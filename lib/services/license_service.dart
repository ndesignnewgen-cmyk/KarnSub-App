import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import 'firebase_service.dart';
import 'free_quota_service.dart';

/// PRO license-key system with anti-sharing (single-use) enforcement.
///
/// Key format: KARN-DDDD-RRRR-CCCC  (12 meaningful chars) — UNIQUE, single-use.
///   DDDD = number of days the key grants, zero-padded (e.g. "0030" = 30 days).
///   RRRR = random, so every buyer gets a different key.
///   CCCC = 4-char FNV-1a checksum of DDDD+RRRR (offline anti-forgery).
///
/// PRO runs for [DDDD] days FROM THE MOMENT THE KEY IS REDEEMED (not a fixed
/// calendar month). Redeeming while PRO is still active STACKS — the new days
/// are added on top of the remaining time, so renewing early never loses days.
///
/// On activation the key is CLAIMED in Firestore (claimedKeys/{code}); a second
/// device that enters the same key is rejected → it can't be shared.
///
/// To generate keys: dart run tool/gen_pro_key.dart 30 10   (10 × 30-day keys)
class LicenseService {
  static const _alpha = '23456789ABCDEFGHJKLMNPQRSTUVWXYZ';

  static FirebaseFirestore get _db => FirebaseFirestore.instance;

  static Future<bool> isPro() => FreeQuotaService.isPro();
  static Future<DateTime?> proExpiry() => FreeQuotaService.proExpiry();

  /// Validate and activate a key. Returns an [ActivationResult].
  static Future<ActivationResult> activateWithKey(String key) async {
    final clean = key.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
    final body = clean.startsWith('KARN') ? clean.substring(4) : clean;
    if (body.length != 12) return ActivationResult.invalid;

    final serial = body.substring(0, 4); // DDDD (days)
    final rand = body.substring(4, 8);
    if (body.substring(8) != _checksum(serial + rand)) {
      return ActivationResult.invalid;
    }

    final days = int.tryParse(serial);
    if (days == null || days < 1 || days > 3650) {
      return ActivationResult.invalid;
    }

    // Compute expiry = [days] from now, STACKED on any remaining PRO time.
    final now = DateTime.now();
    final current = await FreeQuotaService.proExpiry();
    final base = (current != null && current.isAfter(now)) ? current : now;
    final expiry = base.add(Duration(days: days));

    // Single-use: claim the key in Firestore so it can't be shared / reused.
    final claim = await _claimKey(body, expiry, days);
    if (claim == _Claim.alreadyUsed) return ActivationResult.alreadyUsed;
    if (claim != _Claim.ok) return ActivationResult.needsInternet;

    await FreeQuotaService.activatePro(expiry: expiry);
    return ActivationResult.success;
  }

  // ── single-use claim (anti-sharing) ─────────────────────────────────────────

  /// Atomically claim [code] in Firestore. First caller wins; everyone after is
  /// rejected. Requires connectivity + Firebase (signs in anonymously if needed
  /// so it works without a Google login). Network/Firebase failure → not ok, so
  /// the key cannot be activated offline (which would bypass anti-sharing).
  static Future<_Claim> _claimKey(String code, DateTime expiry, int days) async {
    if (!FirebaseService.available) return _Claim.noNetwork;
    try {
      var user = FirebaseAuth.instance.currentUser;
      user ??= (await FirebaseAuth.instance.signInAnonymously()).user;
      final ref = _db.collection('claimedKeys').doc(code);
      final ok = await _db.runTransaction<bool>((tx) async {
        final snap = await tx.get(ref);
        if (snap.exists) return false; // already claimed
        tx.set(ref, {
          'claimedAt': FieldValue.serverTimestamp(),
          'days': days,
          'expiry': Timestamp.fromDate(expiry),
          'by': user?.uid,
        });
        return true;
      });
      return ok ? _Claim.ok : _Claim.alreadyUsed;
    } catch (e) {
      debugPrint('[LicenseService] claim failed: $e');
      return _Claim.noNetwork;
    }
  }

  // ── internal ──────────────────────────────────────────────────────────────

  /// FNV-1a checksum over [data] (DDDD+RRRR).
  static String _checksum(String data) {
    const salt = [0x4B, 0x53, 0x50, 0x52, 0x4F, 0x37, 0x21, 0x5A];
    int h = 0x811C9DC5;
    for (int i = 0; i < data.length; i++) {
      h ^= data.codeUnitAt(i);
      h = (h * 0x01000193) & 0xFFFFFFFF;
      h ^= salt[i % salt.length];
      h = (h * 0x01000193) & 0xFFFFFFFF;
    }
    h ^= (h >> 16);
    h = (h * 0x45D9F3B) & 0xFFFFFFFF;
    h ^= (h >> 16);
    return String.fromCharCodes([
      _alpha.codeUnitAt((h >> 20) & 31),
      _alpha.codeUnitAt((h >> 15) & 31),
      _alpha.codeUnitAt((h >> 10) & 31),
      _alpha.codeUnitAt((h >> 5) & 31),
    ]);
  }
}

enum _Claim { ok, alreadyUsed, noNetwork }

enum ActivationResult {
  success,
  invalid,
  expired,
  alreadyUsed, // key already redeemed on another device (anti-sharing)
  needsInternet, // couldn't verify the key — connect to the internet
}
