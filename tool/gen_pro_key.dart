/// KarnSub PRO Monthly Key Generator
///
/// Usage:
///   dart run tool/gen_pro_key.dart 05 2026        → key for May 2026
///   dart run tool/gen_pro_key.dart 05 2026 3      → keys for May, Jun, Jul 2026
///   dart run tool/gen_pro_key.dart verify KARN-0526-XXXX
///
/// Key format: KARN-MMYY-CCCC
///   MMYY = 2-digit month + 2-digit year (e.g. "0526" = May 2026)
///   CCCC = 4-char FNV-1a checksum
///
/// All buyers of the same month receive the same key (no backend needed).
/// Keep this file and the generated keys private — DO NOT commit to public repo.

void main(List<String> args) {
  if (args.isNotEmpty && args[0] == 'verify') {
    final key = args.length > 1 ? args[1] : '';
    final result = _verifyKey(key);
    print(result);
    return;
  }

  if (args.length < 2) {
    print('Usage:');
    print('  dart run tool/gen_pro_key.dart MM YYYY [count]');
    print('  dart run tool/gen_pro_key.dart verify KARN-MMYY-XXXX');
    print('');
    print('Examples:');
    print('  dart run tool/gen_pro_key.dart 05 2026        # key for May 2026');
    print('  dart run tool/gen_pro_key.dart 05 2026 3      # May, Jun, Jul 2026');
    return;
  }

  final startMonth = int.tryParse(args[0]);
  final year = int.tryParse(args[1]);
  if (startMonth == null || year == null ||
      startMonth < 1 || startMonth > 12 ||
      year < 2024 || year > 2099) {
    print('✗ Invalid month/year. Month: 01-12, Year: 2024-2099');
    return;
  }
  final count = args.length > 2 ? (int.tryParse(args[2]) ?? 1).clamp(1, 24) : 1;

  print('═══════════════════════════════════════');
  print('  KarnSub PRO Monthly Keys');
  print('  Keep these private! One key per month.');
  print('═══════════════════════════════════════');

  for (int i = 0; i < count; i++) {
    final month = ((startMonth - 1 + i) % 12) + 1;
    final y = year + ((startMonth - 1 + i) ~/ 12);
    final mm = month.toString().padLeft(2, '0');
    final yy = (y % 100).toString().padLeft(2, '0');
    final serial = '$mm$yy';
    final key = 'KARN-$serial-${_checksum(serial)}';
    final lastDay = _lastDay(month, y);
    print('  ${_monthName(month)} $y  →  $key  (valid 01/$mm/$y – $lastDay/$mm/$y)');
  }

  print('═══════════════════════════════════════');
  if (count == 1) {
    final mm = startMonth.toString().padLeft(2, '0');
    final yy = (year % 100).toString().padLeft(2, '0');
    print(
        '  Verify: dart run tool/gen_pro_key.dart verify KARN-$mm$yy-${_checksum('$mm$yy')}');
  }
}

// ── Must match LicenseService exactly ──────────────────────────────────────

const _alpha = '23456789ABCDEFGHJKLMNPQRSTUVWXYZ';
const _salt = [0x4B, 0x53, 0x50, 0x52, 0x4F, 0x37, 0x21, 0x5A];

String _checksum(String serial) {
  int h = 0x811C9DC5;
  for (int i = 0; i < serial.length; i++) {
    h ^= serial.codeUnitAt(i);
    h = (h * 0x01000193) & 0xFFFFFFFF;
    h ^= _salt[i % _salt.length];
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

String _verifyKey(String raw) {
  final clean = raw.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
  final body = clean.startsWith('KARN') ? clean.substring(4) : clean;
  if (body.length != 8) return '✗ Invalid key format: $raw';
  final serial = body.substring(0, 4);
  if (body.substring(4) != _checksum(serial)) return '✗ Bad checksum: $raw';

  final month = int.tryParse(serial.substring(0, 2));
  final year = int.tryParse(serial.substring(2, 4));
  if (month == null || year == null || month < 1 || month > 12) {
    return '✗ Invalid MMYY in serial: $raw';
  }
  final fullYear = 2000 + year;
  final mm = month.toString().padLeft(2, '0');
  final lastDay = _lastDay(month, fullYear);
  final expiresStr = month == 12
      ? '01/01/${fullYear + 1}'
      : '01/${(month + 1).toString().padLeft(2, '0')}/$fullYear';

  final now = DateTime.now();
  final expiry = month == 12
      ? DateTime(fullYear + 1, 1, 1)
      : DateTime(fullYear, month + 1, 1);
  final status = now.isBefore(expiry) ? '✓ VALID' : '✗ EXPIRED';

  return '$status  $raw\n'
      '         Month: ${_monthName(month)} $fullYear  '
      '(01/$mm/$fullYear – $lastDay/$mm/$fullYear)\n'
      '         Expires: $expiresStr';
}

// ── helpers ─────────────────────────────────────────────────────────────────

String _monthName(int m) {
  const names = [
    '', 'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December'
  ];
  return names[m];
}

String _lastDay(int month, int year) {
  final last = DateTime(year, month + 1, 0).day;
  return last.toString().padLeft(2, '0');
}
