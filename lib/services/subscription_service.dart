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
