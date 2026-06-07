import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import 'api_config.dart';
import 'payment_config.dart';

/// Result of reading a bank-transfer slip with Gemini Vision.
class SlipResult {
  final bool ok;
  final String? error; // user-facing reason when !ok
  final int amountKip;
  final String refId; // unique transaction reference from the slip
  final String? toAccount;
  final String? bank;
  final DateTime? date;

  SlipResult({
    required this.ok,
    this.error,
    this.amountKip = 0,
    this.refId = '',
    this.toAccount,
    this.bank,
    this.date,
  });

  SlipResult.fail(String reason) : this(ok: false, error: reason);
}

/// Reads a payment slip image with Gemini Vision and validates it against the
/// merchant config (amount ≥ price, correct destination account, fresh date).
/// Uniqueness (anti-reuse) is enforced separately in SubscriptionService.
class SlipVerifyService {
  static const _model = 'gemini-2.5-flash';
  static String get _endpoint =>
      'https://generativelanguage.googleapis.com/v1beta/models/$_model:generateContent';

  /// Read + validate a slip. Returns a [SlipResult]; check `.ok`.
  static Future<SlipResult> verifySlip(File image) async {
    final apiKey = await ApiConfig.getApiKey();
    if (apiKey == null || apiKey.isEmpty) {
      return SlipResult.fail('ບໍ່ພົບ Gemini API Key — ໃສ່ໃນໜ້າຕັ້ງຄ່າກ່ອນ');
    }

    final bytes = await image.readAsBytes();
    if (bytes.isEmpty) return SlipResult.fail('ອ່ານໄຟລ໌ຮູບບໍ່ໄດ້');

    final mime = _guessMime(image.path);
    final prompt =
        'You are reading a Lao bank money-transfer slip (BCEL One / LDB / JDB / '
        'U-Money etc). Extract these fields and return ONLY compact JSON:\n'
        '{"amount": <number in kip, digits only>, '
        '"refId": "<transaction id / reference / ref no / ໝາຍເລກອ້າງອີງ>", '
        '"toAccount": "<receiver name AND account number, e.g. \\"BOUNPASONG '
        'CHANTHAVONG 040-12-00-xxxxx394-001\\". Include BOTH the beneficiary '
        'name (ຜູ້ຮັບເງິນ / ໂອນເຂົ້າ) and any account digits even if masked>", '
        '"bank": "<bank name>", '
        '"date": "<ISO 8601 date if visible, else empty>", '
        '"isRealSlip": <true only if this looks like a genuine bank app '
        'screenshot/slip; false if it is a photo of paper, a generic image, '
        'or clearly not a transfer slip>, '
        '"tamperScore": <integer 0-100, how likely the image was EDITED/'
        'photoshopped: 0 = clean genuine screenshot, 100 = obvious edit. Look '
        'for mismatched fonts, misaligned text, inconsistent number spacing, '
        'blurry patches over numbers, color/compression artifacts around the '
        'amount or name>, '
        '"tamperReason": "<short reason in Lao if tamperScore is high, else empty>"}\n'
        'Rules: amount = transferred amount as integer (strip commas, "LAK", "₭", '
        '"ກີບ"). refId is the unique transaction code. For toAccount, prefer the '
        'RECEIVER/beneficiary (not the sender). Be strict on tamperScore — if the '
        'amount/name/account digits look retouched, raise it. If a field is '
        'missing use "" (0 for amount). Return JSON only, no markdown.';

    try {
      final res = await http
          .post(
            Uri.parse('$_endpoint?key=$apiKey'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'contents': [
                {
                  'parts': [
                    {
                      'inline_data': {'mime_type': mime, 'data': base64Encode(bytes)}
                    },
                    {'text': prompt},
                  ]
                }
              ],
              'generationConfig': {'temperature': 0.0},
            }),
          )
          .timeout(const Duration(seconds: 45));

      if (res.statusCode != 200) {
        return SlipResult.fail('ກວດ slip ບໍ່ສຳເລັດ (Gemini ${res.statusCode})');
      }

      final json = jsonDecode(res.body) as Map<String, dynamic>;
      final text = (json['candidates']?[0]?['content']?['parts']?[0]?['text']
              as String?) ??
          '';
      final data = _extractJson(text);
      if (data == null) return SlipResult.fail('ອ່ານ slip ບໍ່ໄດ້ — ລອງຮູບໃໝ່');

      final amount = _toInt(data['amount']);
      final refId = (data['refId'] ?? '').toString().trim();
      final toAccount = (data['toAccount'] ?? '').toString().trim();
      final bank = (data['bank'] ?? '').toString().trim();
      final date = DateTime.tryParse((data['date'] ?? '').toString());
      final isRealSlip = data['isRealSlip'] != false; // default true if absent
      final tamperScore = _toInt(data['tamperScore']);
      final tamperReason = (data['tamperReason'] ?? '').toString().trim();

      // ── Anti-fraud: reject obviously fake / edited slips first ─────────────
      if (!isRealSlip) {
        return SlipResult.fail(
            'ຮູບນີ້ບໍ່ແມ່ນ slip ໂອນເງິນຈິງ — ກະລຸນາ screenshot ຈາກແອັບທະນາຄານ');
      }
      if (tamperScore >= 55) {
        return SlipResult.fail(
            'ກວດພົບ slip ອາດຖືກແກ້ໄຂ ❌${tamperReason.isNotEmpty ? ' ($tamperReason)' : ''} — '
            'ກະລຸນາສົ່ງ slip ຈິງ. ຖ້າແມ່ນ slip ຈິງ ໃຫ້ສະໝັກທາງ WhatsApp');
      }

      // ── Validate ──────────────────────────────────────────────────────────
      if (refId.isEmpty) {
        return SlipResult.fail('ບໍ່ພົບເລກອ້າງອີງໃນ slip — ລອງຮູບຊັດກວ່າ');
      }
      if (amount < PaymentConfig.priceKip) {
        return SlipResult.fail(
            'ຈຳນວນເງິນບໍ່ພໍ ($amount ກີບ < ${PaymentConfig.priceKip} ກີບ)');
      }
      // Match the destination. Slips often MASK the account number
      // (040-12-00-xxxxx394-001), so accept any of:
      //   • the holder name appears on the slip, OR
      //   • the full account digits appear, OR
      //   • the last 4 + first 4 digits appear (covers masked numbers).
      final acctDigits = toAccount.replaceAll(RegExp(r'[^0-9]'), '');
      final wantDigits = PaymentConfig.merchantAccount.replaceAll(RegExp(r'[^0-9]'), '');
      final nameUp = toAccount.toUpperCase();
      final wantNameUp = PaymentConfig.merchantName.toUpperCase();
      // Compare against the WHOLE slip text too (toAccount may only hold the name
      // while digits sit elsewhere) — so also scan the raw model fields.
      final firstName = wantNameUp.split(' ').first;
      bool digitsMatch() {
        if (wantDigits.length < 6 || acctDigits.length < 4) return false;
        final last4 = wantDigits.substring(wantDigits.length - 4);
        final first4 = wantDigits.substring(0, 4);
        return acctDigits.contains(wantDigits) ||
            (acctDigits.contains(last4) && acctDigits.contains(first4));
      }
      final matchesAccount = wantDigits.length < 4 || // not configured → skip
          nameUp.contains(wantNameUp) ||
          nameUp.contains(firstName) ||
          digitsMatch();
      if (!matchesAccount) {
        return SlipResult.fail('ບັນຊີ/ຊື່ປາຍທາງບໍ່ກົງ — ກວດໃຫ້ໂອນເຂົ້າບັນຊີທີ່ຖືກຕ້ອງ');
      }
      // Freshness (only when the date was readable).
      if (date != null) {
        final age = DateTime.now().difference(date).inDays;
        if (age > PaymentConfig.slipMaxAgeDays) {
          return SlipResult.fail('slip ເກົ່າເກີນໄປ (${age} ມື້) — ໃຊ້ slip ໃໝ່');
        }
      }

      return SlipResult(
        ok: true,
        amountKip: amount,
        refId: refId,
        toAccount: toAccount,
        bank: bank,
        date: date,
      );
    } catch (e) {
      debugPrint('[SlipVerify] $e');
      return SlipResult.fail('ເຊື່ອມຕໍ່ Gemini ບໍ່ໄດ້ — ກວດເນັດແລ້ວລອງໃໝ່');
    }
  }

  static int _toInt(dynamic v) {
    if (v is int) return v;
    if (v is double) return v.round();
    if (v is String) {
      final digits = v.replaceAll(RegExp(r'[^0-9]'), '');
      return int.tryParse(digits) ?? 0;
    }
    return 0;
  }

  /// Pull the first {...} JSON object out of a possibly markdown-wrapped reply.
  static Map<String, dynamic>? _extractJson(String text) {
    final start = text.indexOf('{');
    final end = text.lastIndexOf('}');
    if (start < 0 || end <= start) return null;
    try {
      return jsonDecode(text.substring(start, end + 1)) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  static String _guessMime(String path) {
    final p = path.toLowerCase();
    if (p.endsWith('.png')) return 'image/png';
    if (p.endsWith('.webp')) return 'image/webp';
    if (p.endsWith('.heic')) return 'image/heic';
    return 'image/jpeg';
  }
}
