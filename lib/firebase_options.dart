// File generated for KarnSub Firebase setup.
//
// ┌─────────────────────────────────────────────────────────────────────────┐
// │ THIS IS A TEMPLATE. The values below are placeholders.                    │
// │                                                                           │
// │ Replace it with your real config by running, from the project root:       │
// │     dart pub global activate flutterfire_cli                              │
// │     flutterfire configure                                                 │
// │ which regenerates this file with your project's real keys.                │
// │                                                                           │
// │ OR fill the fields manually from Firebase Console →                       │
// │   Project settings → Your apps → Android app → "SDK setup".               │
// │                                                                           │
// │ While the sentinel string is still present, the app runs in LOCAL-ONLY    │
// │ mode (license keys still work; Google login is hidden).                   │
// └─────────────────────────────────────────────────────────────────────────┘
//
// ignore_for_file: type=lint
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

/// Sentinel value — while any field still equals this, [DefaultFirebaseOptions]
/// is considered NOT configured and the app stays in local-only mode.
const String kFirebaseUnconfigured = 'REPLACE_WITH_FLUTTERFIRE_CONFIGURE';

class DefaultFirebaseOptions {
  /// True once the placeholders have been replaced with real values.
  static bool get isConfigured =>
      android.apiKey != kFirebaseUnconfigured &&
      android.appId != kFirebaseUnconfigured &&
      android.projectId != kFirebaseUnconfigured;

  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      throw UnsupportedError(
        'KarnSub is Android-only; web Firebase config not set up.',
      );
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not configured for $defaultTargetPlatform.',
        );
    }
  }

  // ── Android ──────────────────────────────────────────────────────────────
  // Values pulled from android/app/google-services.json (project karnsub-92e6e).
  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyBhHhji0ed5fX3etMStSa6YtJflvhV4JJ0',
    appId: '1:337269628110:android:e0f1ee8ddf12fd558ac49f',
    messagingSenderId: '337269628110',
    projectId: 'karnsub-92e6e',
    storageBucket: 'karnsub-92e6e.firebasestorage.app',
  );
}
