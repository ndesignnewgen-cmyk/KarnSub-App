/// Merchant payment details for the auto PRO top-up (QR + slip verify).
///
/// ⚠️ EDIT THESE before release:
///   • [merchantAccount] / [merchantName] — what the slip must be paid TO.
///     The slip verifier matches these against the uploaded transfer slip.
///   • [qrAssetPath] — your bank QR image bundled in assets (see pubspec).
class PaymentConfig {
  PaymentConfig._();

  /// Monthly PRO price in Lao Kip. The slip amount must be ≥ this.
  static const int priceKip = 39000;

  /// Account NUMBER the customer transfers to (BCEL / LAPNet).
  static const String merchantAccount = '040120001591394001';

  /// Account holder NAME — primary match on the slip, because slips often MASK
  /// the account number (e.g. 040-12-00-xxxxx394-001). The verifier matches the
  /// name OR the visible account digits.
  static const String merchantName = 'BOUNPASONG CHANTHAVONG';

  /// Bundled QR image (your bank's receive QR). Put the file at this path and
  /// declare `assets/` in pubspec.yaml. Falls back to a placeholder if missing.
  static const String qrAssetPath = 'assets/pay/qr.png';

  /// Accept slips dated within this many days (avoids reusing very old slips).
  static const int slipMaxAgeDays = 7;
}
