import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

import '../firebase_options.dart';

/// Thin wrapper that initializes Firebase exactly once and reports whether the
/// app is actually wired to a Firebase project.
///
/// The whole Firebase layer is ADDITIVE: if the project isn't configured yet
/// (placeholder [firebase_options.dart]) or init fails for any reason, the app
/// keeps working in local-only mode (license keys, offline quota).
class FirebaseService {
  FirebaseService._();

  static bool _initialized = false;
  static bool _available = false;

  /// True only after a successful [init] against a real Firebase project.
  /// Gate all Auth/Firestore usage and the Google-login UI on this.
  static bool get available => _available;

  /// True when [firebase_options.dart] has real (non-placeholder) values.
  static bool get isConfigured => DefaultFirebaseOptions.isConfigured;

  /// The OAuth 2.0 **Web client ID** from your Firebase project, required by
  /// google_sign_in on Android to return an idToken for Firebase Auth.
  ///
  /// Find it in Firebase Console → Authentication → Sign-in method → Google →
  /// "Web SDK configuration" → Web client ID  (ends with .apps.googleusercontent.com).
  /// Leave as the sentinel to disable Google login until you set it.
  /// (Web client ID from google-services.json oauth_client client_type 3.)
  static const String serverClientId =
      '337269628110-tra9vicp44f4qs7d16mdvehgnrdnluaa.apps.googleusercontent.com';

  static bool get hasServerClientId => serverClientId != kFirebaseUnconfigured;

  /// Initialize Firebase. Safe to call once at startup; never throws.
  static Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    if (!isConfigured) {
      debugPrint('[FirebaseService] Not configured — running local-only mode.');
      return;
    }
    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
      _available = true;
      debugPrint('[FirebaseService] Initialized.');
    } catch (e) {
      _available = false;
      debugPrint('[FirebaseService] init failed, local-only mode: $e');
    }
  }
}
