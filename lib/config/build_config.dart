/// Compile-time build flavour switches.
///
/// [kPlayStoreBuild] is FALSE by default, so the normal build you ship from the
/// website is unchanged (full in-app payment: QR + slip upload + WhatsApp).
///
/// For the Google Play build, pass the flag so the in-app PURCHASE UI is hidden
/// (Google policy forbids selling digital goods outside Play Billing — but a
/// "redeem license key" field is allowed). Users get a key from you externally
/// and redeem it inside the app.
///
///   Web / self-distributed APK (default):
///     flutter build apk --release
///
///   Google Play (hides QR/slip, keeps redeem-key only):
///     flutter build appbundle --release --dart-define=PLAY_STORE=true
const bool kPlayStoreBuild = bool.fromEnvironment('PLAY_STORE');
