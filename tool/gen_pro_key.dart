import 'dart:math';

/// KarnSub PRO Key Generator — UNIQUE single-use, duration-based keys.
///
/// Usage:
///   dart run tool/gen_pro_key.dart 30          → 1 key worth 30 days
///   dart run tool/gen_pro_key.dart 30 10        → 10 unique 30-day keys
///   dart run tool/gen_pro_key.dart 365 5        → 5 unique 1-year keys
///   dart run tool/gen_pro_key.dart verify KARN-0030-RRRR-CCCC
///
/// Key format: KARN-DDDD-RRRR-CCCC  (UNIQUE, single-use)
///   DDDD = days the key grants, zero-padded (e.g. "0030" = 30 days)
///   RRRR = random (makes every key different)
///   CCCC = 4-char FNV-1a checksum of DDDD+RRRR
///
/// PRO runs DDDD days from the moment the customer redeems the key (not a fixed
/// month). Redeeming early stacks on remaining time. Each key works ONCE — it is
/// claimed in Firestore on first activation, so it can't be shared.
/// Keep generated keys private — DO NOT commit them to a public repo.

final _rng = Random.secure();

void main(List<String> args) {
  if (args.isNotEmpty && args[0] == 'verify') {
    print(_verifyKey(args.length > 1 ? args[1] : ''));
    return;
  }

  if (args.isEmpty) {
    print('Usage:');
    print('  dart run tool/gen_pro_key.dart DAYS [count]');
    print('  dart run tool/gen_pro_key.dart verify KARN-DDDD-RRRR-CCCC');
    print('');
    print('Examples:');
    print('  dart run tool/gen_pro_key.dart 30        # 1 key, 30 days');
    print('  dart run tool/gen_pro_key.dart 30 10     # 10 unique 30-day keys');
    print('  dart run tool/gen_pro_key.dart 365 5     # 5 unique 1-year keys');
    return;
  }

  final days = int.tryParse(args[0]);
  if (days == null || days < 1 || days > 3650) {
    print('✗ Invalid DAYS. Must be 1-3650 (e.g. 30, 90, 365).');
    return;
  }
  final count = args.length > 1 ? (int.tryParse(args[1]) ?? 1).clamp(1, 500) : 1;
  final serial = days.toString().padLeft(4, '0');

  print('═══════════════════════════════════════════════════');
  print('  KarnSub PRO — $count unique key(s), $days days each');
  print('  Single-use. Runs $days days from when the customer redeems.');
  print('  Keep these private!');
  print('═══════════════════════════════════════════════════');

  final seen = <String>{};
  for (int i = 0; i < count;) {
    final rand = _randomCode(4);
    if (!seen.add(rand)) continue; // ensure no dupes within this batch
    print('  KARN-$serial-$rand-${_checksum('$serial$rand')}');
    i++;
  }
  print('═══════════════════════════════════════════════════');
}

String _randomCode(int n) => String.fromCharCodes(
    List.generate(n, (_) => _alpha.codeUnitAt(_rng.nextInt(_alpha.length))));

// ── Must match LicenseService exactly ──────────────────────────────────────

const _alpha = '23456789ABCDEFGHJKLMNPQRSTUVWXYZ';
const _salt = [0x4B, 0x53, 0x50, 0x52, 0x4F, 0x37, 0x21, 0x5A];

String _checksum(String data) {
  int h = 0x811C9DC5;
  for (int i = 0; i < data.length; i++) {
    h ^= data.codeUnitAt(i);
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
  if (body.length != 12) return '✗ Invalid key format: $raw';

  final serial = body.substring(0, 4);
  final rand = body.substring(4, 8);
  if (body.substring(8) != _checksum('$serial$rand')) {
    return '✗ Bad checksum: $raw';
  }
  final days = int.tryParse(serial);
  if (days == null || days < 1 || days > 3650) {
    return '✗ Invalid days in serial: $raw';
  }
  return '✓ VALID  $raw\n'
      '         Grants: $days days from activation (single-use)';
}
