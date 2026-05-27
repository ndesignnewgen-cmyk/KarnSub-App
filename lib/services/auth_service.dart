import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

import 'firebase_service.dart';

/// Result of a sign-in attempt.
enum SignInResult { success, cancelled, notConfigured, failed }

/// Google Sign-In → Firebase Auth bridge (google_sign_in 7.x API).
///
/// Everything degrades gracefully when Firebase isn't configured: callers can
/// check [FirebaseService.available] / [canSignIn] first, and methods here
/// no-op or return [SignInResult.notConfigured] instead of throwing.
class AuthService {
  AuthService._();

  static bool _gsiInitialized = false;

  static FirebaseAuth get _auth => FirebaseAuth.instance;

  /// The currently signed-in Firebase user, or null.
  static User? get currentUser =>
      FirebaseService.available ? _auth.currentUser : null;

  /// Stream of auth-state changes (null when signed out / unavailable).
  static Stream<User?> authStateChanges() => FirebaseService.available
      ? _auth.authStateChanges()
      : const Stream<User?>.empty();

  /// True when Google login can be offered (Firebase up + web client ID set).
  static bool get canSignIn =>
      FirebaseService.available && FirebaseService.hasServerClientId;

  static Future<void> _ensureGsiInit() async {
    if (_gsiInitialized) return;
    await GoogleSignIn.instance.initialize(
      serverClientId: FirebaseService.serverClientId,
    );
    _gsiInitialized = true;
  }

  /// Trigger the Google sign-in flow and link it to Firebase Auth.
  static Future<SignInResult> signInWithGoogle() async {
    if (!canSignIn) return SignInResult.notConfigured;
    try {
      await _ensureGsiInit();
      final account = await GoogleSignIn.instance.authenticate(
        scopeHint: const ['email'],
      );
      final idToken = account.authentication.idToken;
      if (idToken == null) {
        debugPrint('[AuthService] No idToken — check serverClientId / SHA-1.');
        return SignInResult.failed;
      }
      final credential = GoogleAuthProvider.credential(idToken: idToken);
      await _auth.signInWithCredential(credential);
      return SignInResult.success;
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) {
        return SignInResult.cancelled;
      }
      debugPrint('[AuthService] GoogleSignInException: ${e.code} ${e.description}');
      return SignInResult.failed;
    } catch (e) {
      debugPrint('[AuthService] sign-in failed: $e');
      return SignInResult.failed;
    }
  }

  /// Sign out of both Google and Firebase.
  static Future<void> signOut() async {
    if (!FirebaseService.available) return;
    try {
      if (_gsiInitialized) await GoogleSignIn.instance.signOut();
    } catch (_) {/* ignore */}
    await _auth.signOut();
  }
}
