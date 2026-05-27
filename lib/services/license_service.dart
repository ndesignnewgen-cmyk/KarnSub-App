import 'free_quota_service.dart';

/// Offline monthly license key system — no backend required.
///
/// Key format: KARN-MMYY-CCCC  (14 chars displayed, 8 meaningful)
///   MMYY = 2-digit month + 2-digit year  (e.g. "0526" = May 2026)
///   CCCC = 4-char FNV-1a checksum of MMYY + embedded secret
///
/// Key grants PRO for the entire calendar month encoded in MMYY.
/// After the month ends isPro() returns false automatically — no server needed.
///
/// To generate keys: dart run tool/gen_pro_key.dart MM YYYY [count]
class LicenseService {
  static const _alpha = '23456789ABCDEFGHJKLMNPQRSTUVWXYZ';

  static Future<bool> isPro() => FreeQuotaService.isPro();
  static Future<DateTime?> proExpiry() => FreeQuotaService.proExpiry();

  /// Validate and activate a key. Returns an [ActivationResult].
  static Future<ActivationResult> activateWithKey(String key) async {
    final clean = key.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
    final body = clean.startsWith('KARN') ? clean.substring(4) : clean;
    if (body.length != 8) return ActivationResult.invalid;
    final serial = body.substring(0, 4);
    if (body.substring(4) != _checksum(serial)) return ActivationResult.invalid;

    final expiry = _expiryFromSerial(serial);
    if (expiry == null) return ActivationResult.invalid;
    if (!DateTime.now().isBefore(expiry)) return ActivationResult.expired;

    await FreeQuotaService.activatePro(expiry: expiry);
    return ActivationResult.success;
  }

  // ── internal ──────────────────────────────────────────────────────────────

  /// Parse MMYY → exclusive expiry (start of the following month).
  static DateTime? _expiryFromSerial(String serial) {
    if (serial.length != 4) return null;
    final month = int.tryParse(serial.substring(0, 2));
    final year = int.tryParse(serial.substring(2, 4));
    if (month == null || year == null) return null;
    if (month < 1 || month > 12) return null;
    final fullYear = 2000 + year;
    return month == 12
        ? DateTime(fullYear + 1, 1, 1)
        : DateTime(fullYear, month + 1, 1);
  }

  static String _checksum(String serial) {
    const salt = [0x4B, 0x53, 0x50, 0x52, 0x4F, 0x37, 0x21, 0x5A];
    int h = 0x811C9DC5;
    for (int i = 0; i < serial.length; i++) {
      h ^= serial.codeUnitAt(i);
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

enum ActivationResult { success, invalid, expired }
