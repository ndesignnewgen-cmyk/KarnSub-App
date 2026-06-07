import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import 'auth_service.dart';
import 'firebase_service.dart';
import 'free_quota_service.dart';

/// Reads the user's PRO subscription from Firestore and mirrors it into the
/// local [FreeQuotaService] cache (so PRO keeps working offline).
///
/// Firestore layout (one doc per user):
///   users/{uid} = {
///     email:       string,         // for the dev to find the buyer
///     displayName: string,
///     proExpiry:   Timestamp|null, // dev sets this when a payment lands
///     createdAt:   Timestamp,
///   }
///
/// Dev workflow when a buyer pays: open Firestore Console → users → find by
/// email → set `proExpiry` to the start of the month AFTER the paid period
/// (e.g. paid for May 2026 → proExpiry = 2026-06-01). The app syncs on next
/// launch / login / manual refresh.
class SubscriptionService {
  SubscriptionService._();

  static const _collection = 'users';
  static const _fieldExpiry = 'proExpiry';
  static const _fieldTrial = 'trialExpiry';

  /// Length of the automatic free trial granted on first sign-in.
  static const trialDays = 7;

  static FirebaseFirestore get _db => FirebaseFirestore.instance;

  /// Called at app startup: if a user is already signed in, pull their expiry.
  /// Never throws — offline / unconfigured just leaves the local cache as-is.
  static Future<void> syncOnLaunch() async {
    final user = AuthService.currentUser;
    if (user == null) return;
    await fetchAndCache(user);
  }

  /// Fetch the user's subscription doc, create it on first login, and mirror
  /// `proExpiry` into the local cache. Returns the cloud expiry (may be null).
  static Future<DateTime?> fetchAndCache(User user) async {
    if (!FirebaseService.available) return null;
    try {
      final ref = _db.collection(_collection).doc(user.uid);
      final snap = await ref.get();

      if (!snap.exists) {
        // First sign-in for this account → grant a one-time free trial.
        final trialExpiry = DateTime.now().add(const Duration(days: trialDays));
        await ref.set({
          'email': user.email,
          'displayName': user.displayName,
          _fieldExpiry: null,
          _fieldTrial: Timestamp.fromDate(trialExpiry),
          'createdAt': FieldValue.serverTimestamp(),
        });
        await FreeQuotaService.syncCloudExpiry(trialExpiry);
        return trialExpiry;
      }

      // Keep email fresh (helps the dev locate the buyer).
      if (snap.data()?['email'] != user.email && user.email != null) {
        await ref.set({'email': user.email}, SetOptions(merge: true));
      }

      // Effective expiry = the later of a paid subscription and the trial.
      final pro = _parseExpiry(snap.data()?[_fieldExpiry]);
      final trial = _parseExpiry(snap.data()?[_fieldTrial]);
      final effective = _latest(pro, trial);
      await FreeQuotaService.syncCloudExpiry(effective);
      return effective;
    } catch (e) {
      debugPrint('[SubscriptionService] fetch failed (offline?): $e');
      return null; // keep whatever is cached locally
    }
  }

  /// Manual refresh from the settings screen. Returns the cloud expiry.
  static Future<DateTime?> refresh() async {
    final user = AuthService.currentUser;
    if (user == null) return null;
    return fetchAndCache(user);
  }

  /// Redeem a verified payment slip: atomically claims [refId] (anti-reuse),
  /// extends the user's PRO by one month, and mirrors it to the local cache.
  /// Returns a [RedeemResult].
  /// Detail of the last redeem failure (for surfacing to the user / debugging).
  static String? lastError;

  static Future<RedeemResult> redeemBySlip({
    required String refId,
    required int amountKip,
    String? bank,
  }) async {
    lastError = null;
    final user = AuthService.currentUser;
    if (user == null) return RedeemResult.notLoggedIn;
    if (!FirebaseService.available) {
      lastError = 'Firebase ບໍ່ພ້ອມ (ບໍ່ໄດ້ຕັ້ງຄ່າ / offline)';
      return RedeemResult.error;
    }

    try {
      // Firestore doc IDs cannot contain '/', be empty, or be over 1500 bytes.
      final safeRefId = refId
          .replaceAll(RegExp(r'[/\\\s]+'), '_')
          .replaceAll(RegExp(r'_+'), '_');
      if (safeRefId.isEmpty) {
        lastError = 'refId ບໍ່ຖືກຕ້ອງ';
        return RedeemResult.error;
      }
      final payRef = _db.collection('payments').doc(safeRefId);
      final userRef = _db.collection(_collection).doc(user.uid);

      final newExpiry = await _db.runTransaction<DateTime?>((tx) async {
        final paySnap = await tx.get(payRef);
        if (paySnap.exists) {
          throw _SlipReused(); // refId already redeemed
        }
        final userSnap = await tx.get(userRef);
        final current = userSnap.exists
            ? _latest(_parseExpiry(userSnap.data()?[_fieldExpiry]),
                _parseExpiry(userSnap.data()?[_fieldTrial]))
            : null;
        // Extend by one month from the later of now and the current expiry.
        final base = (current != null && current.isAfter(DateTime.now()))
            ? current
            : DateTime.now();
        final extended = DateTime(base.year, base.month + 1, base.day,
            base.hour, base.minute, base.second);

        tx.set(payRef, {
          'uid': user.uid,
          'amountKip': amountKip,
          'bank': bank ?? '',
          'createdAt': FieldValue.serverTimestamp(),
        });
        tx.set(
          userRef,
          {
            'email': user.email,
            _fieldExpiry: Timestamp.fromDate(extended),
          },
          SetOptions(merge: true),
        );
        return extended;
      });

      if (newExpiry != null) {
        await FreeQuotaService.activatePro(expiry: newExpiry);
        await FreeQuotaService.syncCloudExpiry(newExpiry);
      }
      return RedeemResult.success;
    } on _SlipReused {
      return RedeemResult.alreadyUsed;
    } catch (e) {
      debugPrint('[SubscriptionService] redeem failed: $e');
      lastError = e.toString();
      return RedeemResult.error;
    }
  }

  /// Returns the later of two nullable dates.
  static DateTime? _latest(DateTime? a, DateTime? b) {
    if (a == null) return b;
    if (b == null) return a;
    return a.isAfter(b) ? a : b;
  }

  /// Accepts a Firestore [Timestamp], an ISO-8601 string, or null.
  static DateTime? _parseExpiry(dynamic raw) {
    if (raw == null) return null;
    if (raw is Timestamp) return raw.toDate();
    if (raw is String) return DateTime.tryParse(raw);
    if (raw is int) {
      // epoch millis fallback
      return DateTime.fromMillisecondsSinceEpoch(raw);
    }
    return null;
  }
}

enum RedeemResult { success, alreadyUsed, notLoggedIn, error }

class _SlipReused implements Exception {}
