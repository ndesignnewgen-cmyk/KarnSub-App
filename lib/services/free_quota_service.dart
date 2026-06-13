import 'package:shared_preferences/shared_preferences.dart';

/// Manages PRO status and the daily free-export quota.
///
/// PRO is granted by EITHER of two independent sources, whichever lasts longer:
///   • a license key activated on this device  → [_keyExpiryKey]
///   • a cloud (Firestore) subscription synced down → [_cloudExpiryKey]
///
/// [isPro] / [proExpiry] always reflect the LATER of the two, so a logged-in
/// cloud subscriber and an offline key holder both work, and the cloud value
/// can extend (but never shorten) a still-valid local key.
class FreeQuotaService {
  // Local license-key grant (set by LicenseService.activateWithKey).
  // Key name kept as 'pro_expiry_date' for backward compatibility.
  static const _keyExpiryKey = 'pro_expiry_date';
  // Cloud (Firestore) subscription expiry, cached locally for offline use.
  static const _cloudExpiryKey = 'pro_cloud_expiry';

  // Daily FHD (1080p) export quota for free users. HD (720p) is unlimited.
  static const _exportDateKey = 'fhd_export_date';
  static const _exportCountKey = 'fhd_export_count';
  static const int freeFhdPerDay = 3;

  // Daily SRT/VTT subtitle-file export quota for free users.
  static const _srtDateKey = 'srt_export_date';
  static const _srtCountKey = 'srt_export_count';
  static const int freeSrtPerDay = 2;

  /// True if PRO is active (either source) and not yet expired.
  static Future<bool> isPro() async {
    final expiry = await proExpiry();
    if (expiry == null) return false;
    return DateTime.now().isBefore(expiry);
  }

  /// Effective expiry = the LATER of the license-key grant and the cloud grant.
  /// Returns null if neither source has ever granted PRO.
  static Future<DateTime?> proExpiry() async {
    final prefs = await SharedPreferences.getInstance();
    final key = _parse(prefs.getString(_keyExpiryKey));
    final cloud = _parse(prefs.getString(_cloudExpiryKey));
    if (key == null) return cloud;
    if (cloud == null) return key;
    return cloud.isAfter(key) ? cloud : key;
  }

  /// Activate PRO from a license key, valid until [expiry] (exclusive).
  static Future<void> activatePro({required DateTime expiry}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyExpiryKey, expiry.toIso8601String());
  }

  /// Cache the cloud subscription expiry pulled from Firestore.
  /// Pass null to clear it (e.g. subscription revoked or never set).
  static Future<void> syncCloudExpiry(DateTime? expiry) async {
    final prefs = await SharedPreferences.getInstance();
    if (expiry == null) {
      await prefs.remove(_cloudExpiryKey);
    } else {
      await prefs.setString(_cloudExpiryKey, expiry.toIso8601String());
    }
  }

  /// Clear locally cached cloud PRO state (used on sign-out).
  /// A license key activated on this device stays valid unless [includeKey].
  static Future<void> clearCloud({bool includeKey = false}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_cloudExpiryKey);
    if (includeKey) await prefs.remove(_keyExpiryKey);
  }

  /// Remaining free FHD (1080p) exports for today. PRO is unlimited.
  static Future<int> remainingFhdExports() async {
    if (await isPro()) return 999;
    final prefs = await SharedPreferences.getInstance();
    final today = _todayStr();
    final storedDate = prefs.getString(_exportDateKey) ?? '';
    if (storedDate != today) return freeFhdPerDay;
    final used = prefs.getInt(_exportCountKey) ?? 0;
    return (freeFhdPerDay - used).clamp(0, freeFhdPerDay);
  }

  /// Consume one free FHD export for today.
  static Future<void> useFhdExport() async {
    final prefs = await SharedPreferences.getInstance();
    final today = _todayStr();
    final storedDate = prefs.getString(_exportDateKey) ?? '';
    final count = storedDate == today ? (prefs.getInt(_exportCountKey) ?? 0) : 0;
    await prefs.setString(_exportDateKey, today);
    await prefs.setInt(_exportCountKey, count + 1);
  }

  /// Remaining free SRT/VTT subtitle-file exports for today. PRO is unlimited.
  static Future<int> remainingSrtExports() async {
    if (await isPro()) return 999;
    final prefs = await SharedPreferences.getInstance();
    final today = _todayStr();
    final storedDate = prefs.getString(_srtDateKey) ?? '';
    if (storedDate != today) return freeSrtPerDay;
    final used = prefs.getInt(_srtCountKey) ?? 0;
    return (freeSrtPerDay - used).clamp(0, freeSrtPerDay);
  }

  /// Consume one free SRT/VTT export for today.
  static Future<void> useSrtExport() async {
    final prefs = await SharedPreferences.getInstance();
    final today = _todayStr();
    final storedDate = prefs.getString(_srtDateKey) ?? '';
    final count = storedDate == today ? (prefs.getInt(_srtCountKey) ?? 0) : 0;
    await prefs.setString(_srtDateKey, today);
    await prefs.setInt(_srtCountKey, count + 1);
  }

  static DateTime? _parse(String? s) =>
      (s == null || s.isEmpty) ? null : DateTime.tryParse(s);

  static String _todayStr() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }
}
