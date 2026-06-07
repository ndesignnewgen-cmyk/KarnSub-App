import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Lightweight in-app localization (Lao / Thai) without the full intl/arb setup.
///
/// Usage:
///   tr('setup.title')                 // looks up the current UI language
///   I18n.set('th')                    // switch language (persists)
///   ValueListenableBuilder(valueListenable: I18n.lang, ...) // rebuild on change
///
/// `main.dart` wraps MaterialApp in a ValueListenableBuilder on [I18n.lang] so
/// the whole tree re-renders when the language toggles.
class I18n {
  I18n._();

  static const _prefsKey = 'ui_lang';

  /// Current UI language code: 'lo' (default) or 'th'.
  static final ValueNotifier<String> lang = ValueNotifier<String>('lo');

  static bool get isThai => lang.value == 'th';

  static Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final v = prefs.getString(_prefsKey);
      if (v == 'lo' || v == 'th') lang.value = v!;
    } catch (_) {
      // keep default
    }
  }

  static Future<void> set(String code) async {
    final c = (code == 'th') ? 'th' : 'lo';
    lang.value = c;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, c);
    } catch (_) {}
  }

  /// Translate [key] for the current language. Falls back to Lao, then the key.
  /// [params] replaces `{name}` style placeholders, e.g. t('home.deleteBody',
  /// {'name': 'X'}).
  static String t(String key, [Map<String, Object>? params]) {
    final m = _strings[key];
    String s;
    if (m == null) {
      assert(() {
        debugPrint('[i18n] missing key: $key');
        return true;
      }());
      s = key;
    } else {
      s = m[lang.value] ?? m['lo'] ?? key;
    }
    if (params != null) {
      params.forEach((k, v) => s = s.replaceAll('{$k}', '$v'));
    }
    return s;
  }
}

/// Short global helper: `tr('setup.title')` or `tr('home.projectCount', {'n': 3})`.
String tr(String key, [Map<String, Object>? params]) => I18n.t(key, params);

/// All UI strings. Each entry: key -> { 'lo': ..., 'th': ... }.
const Map<String, Map<String, String>> _strings = {
  // ── Common ──────────────────────────────────────────────────────────
  'common.close': {'lo': 'ປິດ', 'th': 'ปิด'},
  'common.cancel': {'lo': 'ຍົກເລີກ', 'th': 'ยกเลิก'},
  'common.save': {'lo': 'ບັນທຶກ', 'th': 'บันทึก'},
  'common.delete': {'lo': 'ລຶບ', 'th': 'ลบ'},
  'app.tagline': {
    'lo': 'ສ້າງຊັບພາສາລາວ ອັດຕະໂນມັດ',
    'th': 'สร้างซับไตเติลอัตโนมัติด้วย AI',
  },

  // ── Language switch (Settings) ──────────────────────────────────────
  'lang.section': {'lo': 'ພາສາແອັບ', 'th': 'ภาษาแอป'},
  'lang.lo': {'lo': 'ລາວ', 'th': 'ลาว'},
  'lang.th': {'lo': 'ໄທ', 'th': 'ไทย'},

  // ── Editor screen (batch 1: tabs, toolbar, common) ──────────────────
  'ed.ok': {'lo': 'ຕົກລົງ', 'th': 'ตกลง'},
  'ed.none': {'lo': 'ບໍ່ມີ', 'th': 'ไม่มี'},
  'ed.tab.text': {'lo': 'ແກ້ຊັບ', 'th': 'แก้ซับ'},
  'ed.tab.timeline': {'lo': 'ໄທມ໌ໄລນ໌', 'th': 'ไทม์ไลน์'},
  'ed.tab.style': {'lo': 'ສໄຕລ໌', 'th': 'สไตล์'},
  'ed.tab.position': {'lo': 'ຕຳແໜ່ງ', 'th': 'ตำแหน่ง'},
  // Image overlay toolbar
  'ed.size': {'lo': 'ຂະໜາດ', 'th': 'ขนาด'},
  'ed.rotate': {'lo': 'ໝຸນ', 'th': 'หมุน'},
  'ed.flip': {'lo': 'ກັບດ້ານ', 'th': 'พลิกด้าน'},
  'ed.deleteImage': {'lo': 'ລຶບຮູບ', 'th': 'ลบรูป'},
  // Clip toolbar
  'ed.cutClip': {'lo': 'ຕັດຄລິບ', 'th': 'ตัดคลิป'},
  'ed.deleteClip': {'lo': 'ລຶບຄລິບ', 'th': 'ลบคลิป'},
  'ed.cut': {'lo': 'ຕັດ', 'th': 'ตัด'},
  'ed.audio': {'lo': 'ສຽງ', 'th': 'เสียง'},
  'ed.deleteAiVoice': {'lo': 'ລຶບສຽງ AI', 'th': 'ลบเสียง AI'},
  'ed.copy': {'lo': 'ກ໊ອບປີ້', 'th': 'ก๊อบปี้'},
  'ed.split': {'lo': 'ຕັດແບ່ງ', 'th': 'ตัดแบ่ง'},
  'ed.deleteSfx': {'lo': 'ລຶບ SFX', 'th': 'ลบ SFX'},
  'ed.transcribe': {'lo': 'ຖອດສຽງ', 'th': 'ถอดเสียง'},
  'ed.merge': {'lo': 'ລວມ', 'th': 'รวม'},
  'ed.duplicate': {'lo': 'ສຳເນົາ', 'th': 'ทำสำเนา'},
  'ed.edit': {'lo': 'ແກ້', 'th': 'แก้'},
  'ed.delete': {'lo': 'ລຶບ', 'th': 'ลบ'},
  'ed.image': {'lo': 'ຮູບ', 'th': 'รูป'},
  'ed.sfxBtn': {'lo': 'SFX', 'th': 'SFX'},
  'ed.autoSfxBtn': {'lo': 'SFX ✨', 'th': 'SFX ✨'},
  'ed.mixerBtn': {'lo': 'ປັບສຽງ', 'th': 'ปรับเสียง'},
  'ed.aiVoice': {'lo': 'ສຽງ AI', 'th': 'เสียง AI'},
  // AI engine picker dialog
  'ed.pickAiTitle': {'lo': 'ເລືອກ AI ຖອດສຽງ', 'th': 'เลือก AI ถอดเสียง'},
  'ed.pickWhisper': {
    'lo': 'OpenAI Whisper (ແນະນຳ, ຖືກຕ້ອງທີ່ສຸດ)',
    'th': 'OpenAI Whisper (แนะนำ, แม่นที่สุด)',
  },
  'ed.pickGroq': {'lo': 'Groq (ໄວທີ່ສຸດ)', 'th': 'Groq (เร็วที่สุด)'},
  'ed.pickGemini': {'lo': 'Gemini (ຮອງຮັບແປພາສາ)', 'th': 'Gemini (รองรับการแปล)'},
  'ed.reTranscribeTitle': {'lo': 'ຖອດສຽງອັດຕະໂນມັດ', 'th': 'ถอดเสียงอัตโนมัติ'},
  'ed.reTranscribeBody': {
    'lo': 'ລະບົບຈະລຶບຂໍ້ຄວາມເກົ່າທັງໝົດແລ້ວຖອດສຽງໃໝ່ທັງໝົດ. ທ່ານຕ້ອງການສືບຕໍ່ຫຼືບໍ່?',
    'th': 'ระบบจะลบข้อความเก่าทั้งหมดแล้วถอดเสียงใหม่ทั้งหมด ต้องการดำเนินการต่อหรือไม่?',
  },
  'ed.reTranscribeYes': {'lo': 'ຖອດສຽງໃໝ່', 'th': 'ถอดเสียงใหม่'},
  // Toasts
  'ed.autoCutOff': {'lo': 'ປິດ AI Auto-Cut ແລ້ວ', 'th': 'ปิด AI Auto-Cut แล้ว'},
  'ed.analyzeFail': {'lo': 'ການວິເຄາະສຽງຫຼົ້ມເຫຼວ: {e}', 'th': 'การวิเคราะห์เสียงล้มเหลว: {e}'},
  'ed.autoCutOn': {
    'lo': 'ເປີດ AI Auto-Cut ⚡ ຕັດຊ່ວງງຽບແລ້ວ!',
    'th': 'เปิด AI Auto-Cut ⚡ ตัดช่วงเงียบแล้ว!',
  },
  'ed.noSpeech': {'lo': 'ບໍ່ພົບຊ່ວງສຽງເວົ້າໃນວິດີໂອ', 'th': 'ไม่พบช่วงเสียงพูดในวิดีโอ'},
  'ed.movePlayhead': {
    'lo': 'ເລື່ອນ playhead ມາໃນຄລິບກ່ອນຕັດ',
    'th': 'เลื่อน playhead มาในคลิปก่อนตัด',
  },
  'ed.clipCut': {
    'lo': 'ຕັດຄລິບແລ້ວ — ກົດເລືອກຄລິບເພື່ອລຶບ ຫຼື trim',
    'th': 'ตัดคลิปแล้ว — กดเลือกคลิปเพื่อลบ หรือ trim',
  },
  'ed.tooShort': {'lo': 'ຊ່ວງສັ້ນເກີນໄປ (ຕ້ອງ ≥0.2 ວິ)', 'th': 'ช่วงสั้นเกินไป (ต้อง ≥0.2 วิ)'},
  'ed.videoCut': {'lo': 'ຕັດວິດີໂອແລ້ວ', 'th': 'ตัดวิดีโอแล้ว'},
  'ed.needOneClip': {'lo': 'ຕ້ອງເຫຼືອຢ່າງໜ້ອຍ 1 ຄລິບ', 'th': 'ต้องเหลืออย่างน้อย 1 คลิป'},
  'ed.importingFont': {'lo': 'ກຳລັງນຳເຂົ້າ...', 'th': 'กำลังนำเข้า...'},
  'ed.importFont': {
    'lo': 'ນຳເຂົ້າ font (.ttf / .otf)',
    'th': 'นำเข้า font (.ttf / .otf)',
  },
  'ed.fontImported': {'lo': 'ນຳເຂົ້າ "{name}" ສຳເລັດ', 'th': 'นำเข้า "{name}" สำเร็จ'},
  'ed.fontImportFail': {'lo': 'ນຳເຂົ້າ font ບໍ່ສຳເລັດ: {e}', 'th': 'นำเข้า font ไม่สำเร็จ: {e}'},
  'ed.aiTrackAdded': {'lo': 'ເພີ່ມ track ສຽງ AI ແລ້ວ ✨', 'th': 'เพิ่ม track เสียง AI แล้ว ✨'},

  // ── Editor screen (batch 2: style tab, dialogs) ─────────────────────
  'ed.default': {'lo': 'ຄ່າລວມ', 'th': 'ค่าเริ่มต้น'},
  'ed.on': {'lo': 'ເປີດ', 'th': 'เปิด'},
  'ed.off': {'lo': 'ປິດ', 'th': 'ปิด'},
  'ed.add': {'lo': 'ເພີ່ມ', 'th': 'เพิ่ม'},
  'ed.clear': {'lo': 'ລ້າງ', 'th': 'ล้าง'},
  'ed.thin': {'lo': 'ບາງ', 'th': 'บาง'},
  'ed.regular': {'lo': 'ທຳມະດາ', 'th': 'ปกติ'},
  'ed.bold': {'lo': 'ໜາ', 'th': 'หนา'},
  'ed.boldest': {'lo': 'ໜາສຸດ', 'th': 'หนาสุด'},
  'ed.start': {'lo': 'ເລີ່ມ', 'th': 'เริ่ม'},
  'ed.end': {'lo': 'ສິ້ນສຸດ', 'th': 'สิ้นสุด'},
  'ed.row1': {'lo': 'ແຖວ 1 (ພາສາຫຼັກ)', 'th': 'แถว 1 (ภาษาหลัก)'},
  'ed.row2': {'lo': 'ແຖວ 2 (ພາສາທີ 2 — ທາງເລືອກ)', 'th': 'แถว 2 (ภาษาที่ 2 — ตัวเลือก)'},
  'ed.subtitleTextHint': {'lo': 'ຂໍ້ຄວາມ subtitle...', 'th': 'ข้อความซับไตเติล...'},
  'ed.translationHint': {'lo': 'ຄຳແປ...', 'th': 'คำแปล...'},
  'ed.egHello': {'lo': 'ເຊັ່ນ: ສະບາຍດີ', 'th': 'เช่น: สวัสดี'},
  'ed.newText': {'lo': 'ຂໍ້ຄວາມໃໝ່', 'th': 'ข้อความใหม่'},
  'ed.previewExample': {'lo': 'ຕົວຢ່າງ: ສະບາຍດີ ລາວ', 'th': 'ตัวอย่าง: สวัสดี'},
  // Section titles
  'ed.font': {'lo': 'ຟອນຕ໌', 'th': 'ฟอนต์'},
  'ed.fontShort': {'lo': 'ຟອນ', 'th': 'ฟอนต์'},
  'ed.textColor': {'lo': 'ສີໂຕໜັງສື', 'th': 'สีตัวอักษร'},
  'ed.weight': {'lo': 'ນ້ຳໜັກ', 'th': 'น้ำหนัก'},
  'ed.weightFull': {'lo': 'ນ້ຳໜັກໂຕໜັງສື', 'th': 'น้ำหนักตัวอักษร'},
  'ed.animation': {'lo': 'ອະນິເມຊັນ', 'th': 'แอนิเมชัน'},
  'ed.karaoke': {'lo': 'ໄລ່ສີ (Karaoke)', 'th': 'ไล่สี (Karaoke)'},
  'ed.wordPop': {'lo': 'ຂະຫຍາຍຄຳ (Word Pop)', 'th': 'ขยายคำ (Word Pop)'},
  'ed.fontSizeLabel': {'lo': 'ຂະໜາດຕົວໜັງສື', 'th': 'ขนาดตัวอักษร'},
  // Animation labels
  'ed.slideUp': {'lo': 'ຂຶ້ນ', 'th': 'ขึ้น'},
  'ed.slideDown': {'lo': 'ລົງ', 'th': 'ลง'},
  'ed.slideLeft': {'lo': 'ຊ້າຍ', 'th': 'ซ้าย'},
  'ed.bounce': {'lo': 'ເດັ້ງ', 'th': 'เด้ง'},
  'ed.typewriter': {'lo': 'ພິມດີດ', 'th': 'พิมพ์ดีด'},
  'ed.slow': {'lo': 'ຊ້າ', 'th': 'ช้า'},
  'ed.normal': {'lo': 'ປົກກະຕິ', 'th': 'ปกติ'},
  'ed.fast': {'lo': 'ໄວ', 'th': 'เร็ว'},
  'ed.animIn': {'lo': 'Animation ຕອນເຂົ້າ', 'th': 'Animation ตอนเข้า'},
  'ed.animOut': {'lo': 'Animation ຕອນອອກ', 'th': 'Animation ตอนออก'},
  'ed.animSpeed': {'lo': 'ຄວາມໄວ Animation', 'th': 'ความเร็ว Animation'},
  // Position
  'ed.vPosition': {'lo': 'ຕຳແໜ່ງແນວຕັ້ງ ({p}%)', 'th': 'ตำแหน่งแนวตั้ง ({p}%)'},
  'ed.top': {'lo': 'ເທິງ', 'th': 'บน'},
  'ed.middle': {'lo': 'ກາງ', 'th': 'กลาง'},
  'ed.bottom': {'lo': 'ລຸ່ມ', 'th': 'ล่าง'},
  'ed.fineTune': {'lo': 'ປັບລະອຽດ', 'th': 'ปรับละเอียด'},
  'ed.subHere': {'lo': 'ຊັບຢູ່ນີ້', 'th': 'ซับอยู่นี่'},
  'ed.subPosition': {'lo': 'ຕຳແໜ່ງ Subtitle', 'th': 'ตำแหน่งซับไตเติล'},
  // Per-segment style
  'ed.segStyle': {'lo': 'ສໄຕລ໌ປະໂຫຍກນີ້', 'th': 'สไตล์ประโยคนี้'},
  'ed.applyAll': {'lo': 'ໃຊ້ກັບທຸກປະໂຫຍກ', 'th': 'ใช้กับทุกประโยค'},
  'ed.appliedAll': {'lo': 'ໃຊ້ກັບທຸກປະໂຫຍກແລ້ວ', 'th': 'ใช้กับทุกประโยคแล้ว'},
  // Templates
  'ed.templates': {'lo': 'ແມ່ແບບ (ກດເดียวสวย)', 'th': 'เทมเพลต (กดทีเดียวสวย)'},
  'ed.templateApplied': {'lo': 'ໃຊ້ແມ່ແບບ {name} ✨', 'th': 'ใช้เทมเพลต {name} ✨'},
  'ed.templateProDialog': {'lo': 'ແມ່ແບບ {name}', 'th': 'เทมเพลต {name}'},
  'ed.styleProDialog': {'lo': 'ສະໄຕລ໌ {name}', 'th': 'สไตล์ {name}'},
  // Dialogs
  'ed.editSubtitle': {'lo': 'ແກ້ Subtitle', 'th': 'แก้ซับไตเติล'},
  'ed.addSubtitle': {'lo': 'ເພີ່ມ Subtitle', 'th': 'เพิ่มซับไตเติล'},
  'ed.noSubtitle': {'lo': 'ຍັງບໍ່ມີ Subtitle', 'th': 'ยังไม่มีซับไตเติล'},
  'ed.setStartTip': {'lo': 'ຕັ້ງເລີ່ມ = ຕຳແໜ່ງປັດຈຸບັນ', 'th': 'ตั้งเริ่ม = ตำแหน่งปัจจุบัน'},
  'ed.setStartAt': {'lo': 'ຕັ້ງເລີ່ມທີ່ {t}', 'th': 'ตั้งเริ่มที่ {t}'},
  // Karaoke / wordpop descriptions
  'ed.preview': {'lo': 'ຕົວຢ່າງ / Preview', 'th': 'ตัวอย่าง / Preview'},
  'ed.karaokeDesc': {'lo': 'ໄຮໄລຣທີລະຄຳຕາມຈັງຫວະ', 'th': 'ไฮไลต์ทีละคำตามจังหวะ'},
  'ed.highlightColor': {'lo': 'ສີໄຮໄລຣ', 'th': 'สีไฮไลต์'},
  'ed.wordPopDesc': {'lo': 'ຄຳທີ່ໄລ່ສີຈະເດັ້ງໃຫຍ່ຂຶ້ນ', 'th': 'คำที่ไล่สีจะเด้งใหญ่ขึ้น'},
  // Bilingual
  'ed.bilingualSub': {'lo': 'ຊັບສອງພາສາ', 'th': 'ซับสองภาษา'},
  'ed.bilingualDesc': {
    'lo': 'ສະແດງ 2 ແຖວ ພ້ອມ style ຕ່າງກັນ',
    'th': 'แสดง 2 บรรทัด พร้อม style ต่างกัน',
  },
  'ed.row2Size': {'lo': 'ຂະໜາດ ແຖວ 2', 'th': 'ขนาด แถว 2'},
  'ed.rowGap': {'lo': 'ໄລຍະຫ່າງ ແຖວ 1 ↔ ແຖວ 2', 'th': 'ระยะห่าง แถว 1 ↔ แถว 2'},
  'ed.row2Style': {'lo': 'Style ແຖວ 2', 'th': 'Style แถว 2'},
  // Translate dialog
  'ed.translateSub': {'lo': 'ແປ Subtitle', 'th': 'แปลซับไตเติล'},
  'ed.pickTransLang': {'lo': 'ເລືອກພາສາທີ່ຕ້ອງການແປ', 'th': 'เลือกภาษาที่ต้องการแปล'},
  'ed.needGeminiTranslate': {
    'lo': 'ກາລຸນາໃສ່ Gemini API Key ໃນ Settings',
    'th': 'กรุณาใส่ Gemini API Key ใน Settings',
  },
  'ed.translateDone': {'lo': 'ແປສຳເລັດ!', 'th': 'แปลสำเร็จ!'},
  'ed.translateFail': {'lo': 'ແປຜິດພາດ: {e}', 'th': 'แปลผิดพลาด: {e}'},
  // Misc toasts
  'ed.syncNotEnough': {
    'lo': 'ກວດຫາສຽງເວົ້າບໍ່ພໍ — ລອງປັບດ້ວຍມື',
    'th': 'ตรวจหาเสียงพูดไม่พอ — ลองปรับด้วยมือ',
  },
  'ed.whisperSync100': {'lo': '⚡️ ຊິງດ້ວຍ Whisper ສຳເລັດ 100%', 'th': '⚡️ ซิงด้วย Whisper สำเร็จ 100%'},
  'ed.syncDone': {'lo': 'ຊິງອັດຕະໂນມັດສຳເລັດ (ປັບ {n} ປ່ອນ)', 'th': 'ซิงอัตโนมัติสำเร็จ (ปรับ {n} ท่อน)'},
  'ed.syncFail': {'lo': 'ຊິງບໍ່ສຳເລັດ', 'th': 'ซิงไม่สำเร็จ'},
  'ed.applyAllDone': {'lo': 'ໃຊ້ກັບທຸກປະໂຫຍກແລ້ວ', 'th': 'ใช้กับทุกประโยคแล้ว'},
  'ed.syncing': {'lo': 'ກຳລັງຊິງ...', 'th': 'กำลังซิง...'},
  'ed.auto': {'lo': 'ອັດຕະໂນມັດ', 'th': 'อัตโนมัติ'},
  'ed.splitColon': {'lo': 'ແບ່ງ:', 'th': 'แบ่ง:'},
  'ed.aiDubbing': {'lo': 'ພາກສຽງ AI (AI Dubbing)', 'th': 'พากย์เสียง AI (AI Dubbing)'},
  'ed.noGeminiSet': {'lo': 'ຍັງບໍ່ໄດ້ຕັ້ງຄ່າ Gemini API Key', 'th': 'ยังไม่ได้ตั้งค่า Gemini API Key'},
  'ed.geminiTtsHint': {
    'lo': 'ກະລຸນາໃສ່ Gemini API Key ໃນໜ້າຕັ້ງຄ່າກ່ອນ ເພື່ອພາກສຽງດ້ວຍ Gemini TTS (30 ສຽງ, ຮອງຮັບພາສາລາວ).',
    'th': 'กรุณาใส่ Gemini API Key ในหน้าตั้งค่าก่อน เพื่อพากย์เสียงด้วย Gemini TTS (30 เสียง รองรับภาษาลาว/ไทย)',
  },
  'ed.pickVoiceTone': {'lo': 'ເລືອກພາສາ ແລະ ໂທນສຽງພາກ:', 'th': 'เลือกภาษาและโทนเสียงพากย์:'},
  'ed.voiceLang': {'lo': 'ພາສາສຽງພາກ:', 'th': 'ภาษาเสียงพากย์:'},
  'ed.langLaoOpt': {'lo': 'ພາສາລາວ (Lao)', 'th': 'ภาษาลาว (Lao)'},
  'ed.langThaiOpt': {'lo': 'ພາສາໄທ (Thai)', 'th': 'ภาษาไทย (Thai)'},
  'ed.langEnOpt': {'lo': 'ພາສາອັງກິດ (English)', 'th': 'ภาษาอังกฤษ (English)'},

  // ── Editor batch 4 (panels, sheets, toasts) ─────────────────────────
  'ed.analyzingWave': {'lo': 'ກຳລັງກວດສອບຄື້ນສຽງ... ⚡', 'th': 'กำลังตรวจสอบคลื่นเสียง... ⚡'},
  'ed.analyzingDeadAir': {
    'lo': 'ກຳລັງວິເຄາະຫາຊ່ວງງຽບ (Dead Air) ຂອງວິດີໂອ',
    'th': 'กำลังวิเคราะห์หาช่วงเงียบ (Dead Air) ของวิดีโอ',
  },
  'ed.aiTrackInfo': {
    'lo': 'ສຽງ AI ຖືກວາງເປັນ track ແຍກໃນ timeline.\nກົດ play ເພື່ອຟັງພ້ອມ video. ກົດທີ່ track ເພື່ອ ປັບສຽງ/ລາກ/ລຶບ ໄດ້.',
    'th': 'เสียง AI ถูกวางเป็น track แยกในไทม์ไลน์\nกด play เพื่อฟังพร้อมวิดีโอ กดที่ track เพื่อ ปรับเสียง/ลาก/ลบ ได้',
  },
  'ed.aiTrackRemoved': {'lo': 'ລຶບ track ສຽງ AI ແລ້ວ', 'th': 'ลบ track เสียง AI แล้ว'},
  'ed.removeAiTrackLabel': {'lo': 'ລຶບ track ສຽງ AI', 'th': 'ลบ track เสียง AI'},
  'ed.mixer': {'lo': '🎚️ ປັບສຽງ (Mixer)', 'th': '🎚️ ปรับเสียง (Mixer)'},
  'ed.mainAudio': {'lo': 'ສຽງຫຼັກ', 'th': 'เสียงหลัก'},
  'ed.rippleMode': {'lo': 'ໂໝດກ້ອນ: ລາກ → ກ້ອນທີຫຼັງເລື່ອນຕາມ', 'th': 'โหมดก้อน: ลาก → ก้อนถัดไปเลื่อนตาม'},
  'ed.singleMode': {'lo': 'ໂໝດດ່ຽວ: ລາກສະເພาะກ້ອນດຽວ', 'th': 'โหมดเดี่ยว: ลากเฉพาะก้อนเดียว'},
  'ed.proAutoEmoji': {'lo': 'Auto ✨ (Emoji + ໄຮໄລ້ຄຳເດັດ)', 'th': 'Auto ✨ (Emoji + ไฮไลต์คำเด็ด)'},
  'ed.autoEdit': {'lo': 'Auto Edit', 'th': 'Auto Edit'},
  'ed.autoEditPro': {'lo': 'Auto Edit ✨ (ຕັດຕໍ່ອັດຕະໂນມັດ)', 'th': 'Auto Edit ✨ (ตัดต่ออัตโนมัติ)'},
  'ed.autoEditStepKaraoke': {'lo': '✨ ກຽມຄຳ + Karaoke...', 'th': '✨ เตรียมคำ + Karaoke...'},
  'ed.autoEditStepEmoji': {'lo': '✨ ໃສ່ emoji + ໄຮໄລ້ຄຳເດັດ...', 'th': '✨ ใส่ emoji + ไฮไลต์คำเด็ด...'},
  'ed.autoEditStepSfx': {'lo': '✨ ໃສ່ສຽງ SFX...', 'th': '✨ ใส่เสียง SFX...'},
  'ed.autoEditStepCut': {'lo': '✨ ຕັດຊ່ວງงຽບ...', 'th': '✨ ตัดช่วงเงียบ...'},
  'ed.autoEditStepProof': {'lo': '✨ ກວດຄຳຜິດ...', 'th': '✨ ตรวจคำผิด...'},
  'ed.autoEditStepFade': {'lo': '✨ ໃສ່ Fade ເຂົ້າ-ອອກ...', 'th': '✨ ใส่ Fade เข้า-ออก...'},
  'ed.autoEditStepZoom': {'lo': '✨ ໃສ່ Zoom ຊ່ວງເນັ້ນ...', 'th': '✨ ใส่ Zoom ช่วงเน้น...'},
  'ed.aePick': {'lo': 'ເລືອກສະເຕັບທີ່ຈະໃຫ້ Auto Edit ເຮັດ', 'th': 'เลือกสเต็ปที่จะให้ Auto Edit ทำ'},
  'ed.aeRun': {'lo': 'ເລີ່ມ Auto Edit', 'th': 'เริ่ม Auto Edit'},
  'ed.aeProofread': {'lo': 'ກວດຄຳຜິດ (Gemini)', 'th': 'ตรวจคำผิด (Gemini)'},
  'ed.aeKaraoke': {'lo': 'ຕັດຄຳ Karaoke', 'th': 'ตัดคำ Karaoke'},
  'ed.aeEmoji': {'lo': 'Emoji + ໄຮໄລ້ຄຳເດັດ', 'th': 'Emoji + ไฮไลต์คำเด็ด'},
  'ed.aeSfx': {'lo': 'SFX ອັດຕະໂນมัด', 'th': 'SFX อัตโนมัติ'},
  'ed.aeFade': {'lo': 'Fade ເຂົ້າ-ອອກ', 'th': 'Fade เข้า-ออก'},
  'ed.aeZoom': {'lo': 'Zoom ຊ່ວງເນັ້ນ', 'th': 'Zoom ช่วงเน้น'},
  'ed.aeCut': {'lo': 'ຕັດຊ່ວງเงียบ', 'th': 'ตัดช่วงเงียบ'},
  'ed.aeBroll': {'lo': 'Auto B-roll (ໂຫຼດเน็ต)', 'th': 'Auto B-roll (โหลดเน็ต)'},
  'ed.autoEditDone': {
    'lo': 'Auto Edit ສຳເລັດ ✨ (emoji + SFX + Karaoke)',
    'th': 'Auto Edit สำเร็จ ✨ (emoji + SFX + Karaoke)',
  },
  'ed.autoEditTitle': {'lo': 'Auto Edit ກຳລັງเรียบเรียง...', 'th': 'Auto Edit กำลังเรียบเรียง...'},
  'ed.autoMeme': {'lo': 'Auto Meme', 'th': 'Auto Meme'},
  'ed.autoMemePro': {'lo': 'Auto Meme ✨ (ໃສ່ GIF ອັດຕະໂນมัด)', 'th': 'Auto Meme ✨ (ใส่ GIF อัตโนมัติ)'},
  'ed.autoMemeTitle': {'lo': 'ກຳລັງຫາ meme GIF...', 'th': 'กำลังหา meme GIF...'},
  'ed.autoMemeStep': {'lo': 'ໃສ່ meme {i}/{n}...', 'th': 'ใส่ meme {i}/{n}...'},
  'ed.autoMemeDone': {'lo': 'ໃສ່ {n} meme GIF ແລ້ວ ✨', 'th': 'ใส่ {n} meme GIF แล้ว ✨'},
  'ed.autoMemeNone': {'lo': 'ບໍ່ພົບ meme ທີ່ເໝາະ — ລອງໃໝ່', 'th': 'ไม่พบ meme ที่เหมาะ — ลองใหม่'},
  'ed.autoBroll': {'lo': 'Auto B-roll', 'th': 'Auto B-roll'},
  'ed.autoBrollPro': {'lo': 'Auto B-roll ✨ (ໃສ່ວິດີໂອ/ຮູບ stock ຕາມເນື້ອຫາ)', 'th': 'Auto B-roll ✨ (ใส่วิดีโอ/ภาพ stock ตามเนื้อหา)'},
  'ed.autoBrollTitle': {'lo': 'AI ກຳລັງເລືອກຈັງຫວະ + ຫາວິດີໂອ/ຮູບ...', 'th': 'AI กำลังเลือกจังหวะ + หาวิดีโอ/ภาพ...'},
  'ed.autoBrollStep': {'lo': 'ກຳລັງໃສ່ B-roll {i}/{n}...', 'th': 'กำลังใส่ B-roll {i}/{n}...'},
  'ed.autoBrollDone': {'lo': 'ໃສ່ {n} B-roll ແລ້ວ ✨', 'th': 'ใส่ {n} B-roll แล้ว ✨'},
  'ed.autoBrollNone': {'lo': 'ບໍ່ພົບຮູບທີ່ເໝາະ — ລອງໃໝ່', 'th': 'ไม่พบภาพที่เหมาะ — ลองใหม่'},
  'ed.coverOn': {'lo': 'ເຕັມຈໍ', 'th': 'เต็มจอ'},
  'ed.coverOff': {'lo': 'ບໍ່ເຕັມຈໍ', 'th': 'ไม่เต็มจอ'},
  'ed.coverOnDone': {'lo': 'ຕັ້ງເຕັມຈໍແລ້ວ', 'th': 'ตั้งเต็มจอแล้ว'},
  'ed.coverOffDone': {'lo': 'ປິດເຕັມຈໍແລ້ວ — ປັບຂະໜາດ/ຍ້າຍໄດ້', 'th': 'ปิดเต็มจอแล้ว — ปรับขนาด/ย้ายได้'},
  'ed.broll': {'lo': 'B-roll ວິດີໂອ', 'th': 'B-roll วิดีโอ'},
  'ed.webBroll': {'lo': 'ຄົ້ນ B-roll web', 'th': 'ค้น B-roll web'},
  'ed.webBrollHelp': {'lo': 'ຄົ້ນວິດີໂອ stock ຟຣີ (Pixabay) — ກົດເພື່ອໃສ່ເຕັມຈໍ', 'th': 'ค้นวิดีโอ stock ฟรี (Pixabay) — กดเพื่อใส่เต็มจอ'},
  'ed.webBrollEmpty': {'lo': 'ພິມຄຳຄົ້ນ (ອັງກິດໄດ້ຜົນດີ) ແລ້ວກົດຄົ້ນຫາ', 'th': 'พิมพ์คำค้น (อังกฤษได้ผลดี) แล้วกดค้นหา'},
  'ed.webBrollInserting': {'lo': 'ກຳລັງດາວໂຫຼດ B-roll...', 'th': 'กำลังดาวน์โหลด B-roll...'},
  'ed.brollPro': {'lo': 'B-roll ວິດີໂອ ✨ (ໃສ່ຄລິບຊ້ອນວິດີໂອ)', 'th': 'B-roll วิดีโอ ✨ (ใส่คลิปซ้อนวิดีโอ)'},
  'ed.brollAdded': {'lo': 'ໃສ່ B-roll ວິດີໂອແລ້ວ — ລາກ/trim ໄດ້', 'th': 'ใส่ B-roll วิดีโอแล้ว — ลาก/trim ได้'},
  'ed.autoEmojiDone1': {
    'lo': 'Auto ✨ ສຳເລັດ — emoji + ໄຮໄລ້ + SFX {n} ຈຸດ',
    'th': 'Auto ✨ สำเร็จ — emoji + ไฮไลต์ + SFX {n} จุด',
  },
  'ed.autoEmojiDone2': {
    'lo': 'Auto ✨ ສຳເລັດ — ໃສ່ emoji + ໄຮໄລ້ຄຳເດັດ',
    'th': 'Auto ✨ สำเร็จ — ใส่ emoji + ไฮไลต์คำเด็ด',
  },
  'ed.autoEmojiFail': {'lo': 'Auto ✨ ບໍ່ສຳເລັດ — ລອງໃໝ່', 'th': 'Auto ✨ ไม่สำเร็จ — ลองใหม่'},
  'ed.aiCutSyncWhisper': {
    'lo': 'AI ຕັດຄຳ + Whisper Sync ສຳເລັດ ({n} ປ່ອນ)',
    'th': 'AI ตัดคำ + Whisper Sync สำเร็จ ({n} ท่อน)',
  },
  'ed.aiCutSync': {'lo': 'AI ຕັດຄຳ + ຊິງ ສຳເລັດ ({n} ປ່ອນ)', 'th': 'AI ตัดคำ + ซิง สำเร็จ ({n} ท่อน)'},
  'ed.aiCutSyncHint': {
    'lo': 'ຊິງ ({n}) ✓ — ໃສ່ Groq key (ຟຣີ) ໃນ Settings ເພື່ອໃຫ້ຕົງສຽງເປ໊ະ',
    'th': 'ซิง ({n}) ✓ — ใส่ Groq key (ฟรี) ใน Settings เพื่อให้ตรงเสียงเป๊ะ',
  },
  'ed.movePlayheadCenter': {
    'lo': 'ເລື່ອນ playhead ໃຫ້ຢູ່ກາງກ້ອນ ກ່ອນຕັດ',
    'th': 'เลื่อน playhead ให้อยู่กลางก้อน ก่อนตัด',
  },
  'ed.cantCutHere': {'lo': 'ຕັດບ່ອນນີ້ບໍ່ໄດ້', 'th': 'ตัดตรงนี้ไม่ได้'},
  'ed.noNextBlock': {'lo': 'ບໍ່ມີກ້ອນຕໍ່ໄປ', 'th': 'ไม่มีก้อนถัดไป'},
  'ed.sfxDeleted': {'lo': 'ລຶບ SFX ແລ້ວ', 'th': 'ลบ SFX แล้ว'},
  'ed.sfxCopied': {'lo': 'ກ໊ອບປີ້ SFX ແລ້ວ', 'th': 'ก๊อบปี้ SFX แล้ว'},
  'ed.movePlayheadSfx': {'lo': 'ເລື່ອນ playhead ມາໃນກ້ອນ SFX ກ່ອນຕັດ', 'th': 'เลื่อน playhead มาในก้อน SFX ก่อนตัด'},
  'ed.sfxSplit': {'lo': 'ຕັດແບ່ງ SFX ແລ້ວ', 'th': 'ตัดแบ่ง SFX แล้ว'},
  'ed.movePlayheadAiTrack': {
    'lo': 'ເລື່ອນ playhead ມາໃນ track ສຽງ AI ກ່ອນຕັດ',
    'th': 'เลื่อน playhead มาใน track เสียง AI ก่อนตัด',
  },
  'ed.aiTrackTrimmed': {'lo': 'ຕັດທ້າຍ track ສຽງ AI ແລ້ວ', 'th': 'ตัดท้าย track เสียง AI แล้ว'},
  'ed.play': {'lo': 'ຟັງ', 'th': 'ฟัง'},
  'ed.sfxAdded': {'lo': 'ເພີ່ມ {title} ແລ້ວ', 'th': 'เพิ่ม {title} แล้ว'},
  'ed.imageAdded': {'lo': 'ໃສ່ຮູບແລ້ວ — ລາກໃນ preview ເພື່ອຍ້າຍ', 'th': 'ใส่รูปแล้ว — ลากใน preview เพื่อย้าย'},
  'ed.webImage': {'lo': 'ຄົ້ນຮູບ web', 'th': 'ค้นรูป web'},
  'ed.webImageHint': {'lo': 'ພິມຄຳຄົ້ນ (ອັງກິດໄດ້ຜົນດີ)', 'th': 'พิมพ์คำค้น (อังกฤษได้ผลดี)'},
  'ed.webImageAi': {'lo': '✨ AI ຄຳຄົ້ນ', 'th': '✨ AI คำค้น'},
  'ed.webImageEmpty': {'lo': 'ບໍ່ພົບຮູບ — ລອງຄຳອື່ນ (ອັງກິດ)', 'th': 'ไม่พบรูป — ลองคำอื่น (อังกฤษ)'},
  'ed.webImageInserting': {'lo': 'ກຳລັງໃສ່ຮູບ...', 'th': 'กำลังใส่รูป...'},
  'ed.webImageHelp': {
    'lo': 'ດຶງຮູບຟຣີ (license ສະອາດ) → ວາງเທິງວິດີໂອ ຕົງເວລານີ້',
    'th': 'ดึงรูปฟรี (license สะอาด) → วางบนวิดีโอ ตรงเวลานี้',
  },
  'ed.webImageFail': {'lo': 'ໂຫຼດຮູບບໍ່ໄດ້ — ລອງຮູບອື່ນ', 'th': 'โหลดรูปไม่ได้ — ลองรูปอื่น'},
  'ed.webSfx': {'lo': 'ຄົ້ນ SFX web', 'th': 'ค้น SFX web'},
  'ed.webSfxHint': {'lo': 'ພິມຄຳຄົ້ນ (ອັງກິດໄດ້ຜົນດີ) ເຊັ່ນ explosion, rain', 'th': 'พิมพ์คำค้น (อังกฤษได้ผลดี) เช่น explosion, rain'},
  'ed.webSfxHelp': {
    'lo': 'ຄົ້ນສຽງເອັບເຟັກ 33,000+ ສຽງ (BBC) → ໃສ່ຕົງເວລານີ້. ▶ ຟັງກ່ອນ',
    'th': 'ค้นเสียงเอฟเฟกต์ 33,000+ เสียง (BBC) → ใส่ตรงเวลานี้. ▶ ฟังก่อน',
  },
  'ed.webSfxEmpty': {'lo': 'ບໍ່ພົບສຽງ — ລອງຄຳອື່ນ (ອັງກິດ)', 'th': 'ไม่พบเสียง — ลองคำอื่น (อังกฤษ)'},
  'ed.webSfxInsert': {'lo': 'ໃສ່', 'th': 'ใส่'},
  'ed.webSfxAdded': {'lo': 'ໃສ່ສຽງແລ້ວ ✓', 'th': 'ใส่เสียงแล้ว ✓'},
  'ed.webSfxFail': {'lo': 'ໂຫຼດສຽງບໍ່ໄດ້ — ລອງສຽງອື່ນ', 'th': 'โหลดเสียงไม่ได้ — ลองเสียงอื่น'},
  'ed.srcMeme2': {'lo': 'ມີມ/UI', 'th': 'มีม/UI'},
  'ed.srcReal': {'lo': 'ສຽງຈິງ (BBC)', 'th': 'เสียงจริง (BBC)'},
  'ed.needFreesound': {
    'lo': 'ໃສ່ Freesound token (ຟຣີ) ໃນ Settings ເພື່ອຄົ້ນສຽງມີມ — ຫຼື ສະຫຼັບໄປ "ສຽງຈິງ (BBC)"',
    'th': 'ใส่ Freesound token (ฟรี) ใน Settings เพื่อค้นเสียงมีม — หรือสลับไป "เสียงจริง (BBC)"',
  },
  'ed.bgMusic': {'lo': 'ເພງ', 'th': 'เพลง'},
  'ed.autoDuck': {'lo': 'ຫຼຸດສຽງເພງຕອນເວົ້າ (Auto-duck)', 'th': 'ลดเสียงเพลงตอนพูด (Auto-duck)'},
  'ed.addBgMusic': {'lo': '+ ເພີ່ມເພງພື້ນຫຼັງ', 'th': '+ เพิ่มเพลงพื้นหลัง'},
  'ed.removeBgMusic': {'lo': 'ລຶບເພງ', 'th': 'ลบเพลง'},
  'ed.bgMusicAdded': {'lo': 'ເພີ່ມເພງແລ້ວ ✓', 'th': 'เพิ่มเพลงแล้ว ✓'},
  'ed.bgMusicRemoved': {'lo': 'ລຶບເພງແລ້ວ', 'th': 'ลบเพลงแล้ว'},
  'ed.bgMusicFail': {'lo': 'ໂຫຼດເພງບໍ່ໄດ້ — ລອງໄຟລ໌ອື່ນ', 'th': 'โหลดเพลงไม่ได้ — ลองไฟล์อื่น'},
  'ed.zoom': {'lo': 'ຊູມ', 'th': 'ซูม'},
  'ed.zoomTitle': {'lo': 'ໃສ່ Zoom ໃຫ້ຄລິບນີ້', 'th': 'ใส่ Zoom ให้คลิปนี้'},
  'ed.zoomIn': {'lo': 'ຊູມເຂົ້າ', 'th': 'ซูมเข้า'},
  'ed.zoomInSub': {'lo': 'ຄ່ອຍໆ ຊູມເຂົ້າ (1.0→1.4)', 'th': 'ค่อยๆ ซูมเข้า (1.0→1.4)'},
  'ed.zoomOut': {'lo': 'ຊູມອອກ', 'th': 'ซูมออก'},
  'ed.zoomOutSub': {'lo': 'ຄ່ອຍໆ ຊູມອອກ (1.4→1.0)', 'th': 'ค่อยๆ ซูมออก (1.4→1.0)'},
  'ed.zoomHold': {'lo': 'ຊູມຄ້າງ', 'th': 'ซูมค้าง'},
  'ed.zoomHoldSub': {'lo': 'ຊູມຄ້າງໄວ້ (1.3x)', 'th': 'ซูมค้างไว้ (1.3x)'},
  'ed.zoomPunch': {'lo': 'Punch-in (ກະແທກ)', 'th': 'Punch-in (กระแทก)'},
  'ed.zoomPunchSub': {'lo': 'ຊູມເຂົ້າແຮງ ເນັ້ນຈຸດ (1.0→1.6)', 'th': 'ซูมเข้าแรง เน้นจุด (1.0→1.6)'},
  'ed.zoomNone': {'lo': 'ລຶບ Zoom', 'th': 'ลบ Zoom'},
  'ed.zoomNoneSub': {'lo': 'ເອົາ zoom ອອກຈາກຄລິບນີ້', 'th': 'เอา zoom ออกจากคลิปนี้'},
  'ed.zoomAdded': {'lo': 'ໃສ່ Zoom ແລ້ວ ✓', 'th': 'ใส่ Zoom แล้ว ✓'},
  'ed.zoomRemoved': {'lo': 'ລຶບ Zoom ແລ້ວ', 'th': 'ลบ Zoom แล้ว'},
  'ed.kf': {'lo': '◆ Keyframe (ຂັ້ນສູງ)', 'th': '◆ Keyframe (ขั้นสูง)'},
  'ed.kfSub': {'lo': 'ກຳນົດ zoom/pan ຫຼາຍຈຸດເອງ', 'th': 'กำหนด zoom/pan หลายจุดเอง'},
  'ed.kfCaptured': {'lo': '◆ ບັນທຶກ keyframe ແລ້ວ', 'th': '◆ บันทึก keyframe แล้ว'},
  'ed.kfDeleted': {'lo': 'ລຶບ keyframe ແລ້ວ', 'th': 'ลบ keyframe แล้ว'},
  'ed.kfHint': {'lo': 'ຈີບຊູມ / ລາກແພນ ເທິງວິດີໂອ → ໃສ່ keyframe ເອງ', 'th': 'จีบซูม / ลากแพน บนวิดีโอ → ใส่ keyframe เอง'},
  'ed.opacity': {'lo': 'ຄວາມໂປ່ງໃສ', 'th': 'ความโปร่งใส'},
  'ed.kfTitle': {'lo': 'Keyframe Zoom / Pan', 'th': 'Keyframe Zoom / Pan'},
  'ed.kfTime': {'lo': 'ເວລາ', 'th': 'เวลา'},
  'ed.kfScale': {'lo': 'ຊູມ', 'th': 'ซูม'},
  'ed.kfAdd': {'lo': '◆ ເພີ່ມ Keyframe ທີ່ຈຸດນີ້', 'th': '◆ เพิ่ม Keyframe ที่จุดนี้'},
  'ed.kfEmpty': {'lo': 'ຍັງບໍ່ມີ keyframe — ເລື່ອນເວລາ ຕັ້ງຊູມ ແລ້ວກົດເພີ່ມ', 'th': 'ยังไม่มี keyframe — เลื่อนเวลา ตั้งซูม แล้วกดเพิ่ม'},
  'common.done': {'lo': 'ແລ້ວ', 'th': 'เสร็จ'},
  'ed.fade': {'lo': 'Fade', 'th': 'Fade'},
  'ed.fadeTitle': {'lo': 'ໃສ່ Fade ໃຫ້ຄລິບນີ້', 'th': 'ใส่ Fade ให้คลิปนี้'},
  'ed.fadeIn': {'lo': 'Fade In (ຈາງເຂົ້າ)', 'th': 'Fade In (จางเข้า)'},
  'ed.fadeInSub': {'lo': 'ຄ່ອຍໆ ສະຫວ່າງຈາກສີດຳ ຕອນເລີ່ມ', 'th': 'ค่อยๆ สว่างจากสีดำ ตอนเริ่ม'},
  'ed.fadeOut': {'lo': 'Fade Out (ຈາງອອກ)', 'th': 'Fade Out (จางออก)'},
  'ed.fadeOutSub': {'lo': 'ຄ່ອຍໆ ມືດເປັນສີດຳ ຕອນຈົບ', 'th': 'ค่อยๆ มืดเป็นสีดำ ตอนจบ'},
  'ed.fadeCut': {'lo': 'Fade ທີ່ຮອຍຕັດ', 'th': 'Fade ที่รอยตัด'},
  'ed.fadeCutSub': {'lo': 'ມືດ→ສະຫວ່າງ ລະຫວ່າງຄລິບນີ້ກັບຄລິບຖັດໄປ', 'th': 'มืด→สว่าง ระหว่างคลิปนี้กับคลิปถัดไป'},
  'ed.fadeNone': {'lo': 'ລຶບ Fade', 'th': 'ลบ Fade'},
  'ed.fadeNoneSub': {'lo': 'ເອົາ fade ອອກຈາກຄລິບນີ້', 'th': 'เอา fade ออกจากคลิปนี้'},
  'ed.fadeAdded': {'lo': 'ໃສ່ Fade ແລ້ວ ✓', 'th': 'ใส่ Fade แล้ว ✓'},
  'ed.shake': {'lo': 'ສັ່ນ', 'th': 'สั่น'},
  'ed.shakeTitle': {'lo': 'ໃສ່ Shake (ສັ່ນຈໍ) ໃຫ້ຄລິບນີ້', 'th': 'ใส่ Shake (สั่นจอ) ให้คลิปนี้'},
  'ed.shakeLight': {'lo': 'ສັ່ນເບົາ', 'th': 'สั่นเบา'},
  'ed.shakeMed': {'lo': 'ສັ່ນກາງ', 'th': 'สั่นกลาง'},
  'ed.shakeStrong': {'lo': 'ສັ່ນແຮງ', 'th': 'สั่นแรง'},
  'ed.shakeNone': {'lo': 'ລຶບ Shake', 'th': 'ลบ Shake'},
  'ed.shakeAdded': {'lo': 'ໃສ່ Shake ແລ້ວ ✓', 'th': 'ใส่ Shake แล้ว ✓'},
  'ed.shakeRemoved': {'lo': 'ລຶບ Shake ແລ້ວ', 'th': 'ลบ Shake แล้ว'},
  'ed.bgBlur': {'lo': 'ພື້ນເບລอ', 'th': 'พื้นเบลอ'},
  'ed.bgBlurOn': {'lo': 'ເປີດພື້ນຫຼັງເບລอ (9:16) ✓', 'th': 'เปิดพื้นหลังเบลอ (9:16) ✓'},
  'ed.bgBlurOff': {'lo': 'ປິດพื้นหลังเบลอ', 'th': 'ปิดพื้นหลังเบลอ'},
  'ed.srcImage': {'lo': 'ຮູບ', 'th': 'รูป'},
  'ed.srcMeme': {'lo': 'Meme GIF', 'th': 'Meme GIF'},
  'ed.needTenorKey': {
    'lo': 'ໃສ່ Tenor API key (ຟຣີ) ໃນ Settings ເພື່ອຄົ້ນ meme GIF',
    'th': 'ใส่ Tenor API key (ฟรี) ใน Settings เพื่อค้น meme GIF',
  },
  'ed.gifNote': {
    'lo': '💡 Meme GIF ຂຍັບ ທັງ preview ແລະ ຕอน export',
    'th': '💡 Meme GIF ขยับ ทั้ง preview และตอน export',
  },
  'ed.imageAddFail': {'lo': 'ໃສ່ຮູບບໍ່ສຳເລັດ: {e}', 'th': 'ใส่รูปไม่สำเร็จ: {e}'},
  'ed.imageDeleted': {'lo': 'ລຶບຮູບແລ້ວ', 'th': 'ลบรูปแล้ว'},
  'ed.imageSize': {'lo': '🖼️ ຂະໜາດຮູບ', 'th': '🖼️ ขนาดรูป'},
  'ed.addingAudio': {'lo': 'ກຳລັງເພີ່ມສຽງ...', 'th': 'กำลังเพิ่มเสียง...'},
  'ed.cantReadAudio': {'lo': 'ບໍ່ສາມາດອ່ານໄຟລ໌ສຽງນີ້ໄດ້', 'th': 'ไม่สามารถอ่านไฟล์เสียงนี้ได้'},
  'ed.audioAdded': {'lo': 'ເພີ່ມສຽງ "{name}" ແລ້ວ', 'th': 'เพิ่มเสียง "{name}" แล้ว'},
  'ed.audioAddFail': {'lo': 'ເພີ່ມສຽງບໍ່ສຳເລັດ: {e}', 'th': 'เพิ่มเสียงไม่สำเร็จ: {e}'},
  // SFX picker
  'ed.sfxTab.funny': {'lo': 'ຕະຫຼົກ/ຕີ', 'th': 'ตลก/ตี'},
  'ed.sfxTab.motion': {'lo': 'ການເຄື່ອນໄຫວ', 'th': 'การเคลื่อนไหว'},
  'ed.sfxTab.general': {'lo': 'ທົ່ວໄປ', 'th': 'ทั่วไป'},
  'ed.sfxTab.mine': {'lo': 'ສຽງຂອງຂ້อย', 'th': 'เสียงของฉัน'},
  'ed.pickFromDevice': {'lo': 'ເລືອກສຽງຈາກເຄື່ອງ', 'th': 'เลือกเสียงจากเครื่อง'},
  'ed.supportFormats': {'lo': 'ຮອງຮັບ MP3, WAV, M4A', 'th': 'รองรับ MP3, WAV, M4A'},
  'ed.noAutoSfx': {
    'lo': 'ບໍ່ພົບຄຳ/emoji ທີ່ກົງ SFX — ລອງກົດ Auto ✨ ກ່ອນ (ໃສ່ emoji ໃຫ້ subtitle) ແລ້ວກົດ SFX ✨ ອີກ',
    'th': 'ไม่พบคำ/emoji ที่ตรง SFX — ลองกด Auto ✨ ก่อน (ใส่ emoji ให้ซับ) แล้วกด SFX ✨ อีกครั้ง',
  },
  'ed.autoSfxTitle': {'lo': 'ໃສ່ SFX ອັດຕະໂນມັດ ✨', 'th': 'ใส่ SFX อัตโนมัติ ✨'},
  'ed.autoSfxBody': {
    'lo': 'ພົບຕຳແໜ່ງທີ່ເໝາະສົມ {n} ຈຸດ.\nທ່ານຕ້ອງການລຶບ SFX ເກົ່າອອກກ່ອນ ຫຼື ວາງທັບໃສ່ເລີຍ?',
    'th': 'พบตำแหน่งที่เหมาะสม {n} จุด\nต้องการลบ SFX เก่าออกก่อน หรือวางทับเลย?',
  },
  'ed.sfxAddedN': {'lo': 'ເພີ່ມ {n} SFX ແລ້ວ', 'th': 'เพิ่ม {n} SFX แล้ว'},
  'ed.mergeWithOld': {'lo': 'ລວມກັບຂອງເກົ່າ', 'th': 'รวมกับของเก่า'},
  'ed.autoSfxPlaced': {'lo': 'ວາງ {n} SFX ອັດຕະໂນມັດແລ້ວ', 'th': 'วาง {n} SFX อัตโนมัติแล้ว'},
  'ed.replaceAll': {'lo': 'ແທນທີ່ໃໝ່ໝົດ', 'th': 'แทนที่ใหม่หมด'},
  'ed.sfxAudioLabel': {'lo': '🔊 ສຽງ {name}', 'th': '🔊 เสียง {name}'},
  // Per-segment style sheet
  'ed.sizeWith': {'lo': 'ຂະໜາດ ({n})', 'th': 'ขนาด ({n})'},
  'ed.karaokeProDialog': {'lo': 'Karaoke ໄລ່ສີ', 'th': 'Karaoke ไล่สี'},
  'ed.subVPosition': {'lo': 'ຕຳແໜ່ງແນວຕັ້ງ ({p}%)', 'th': 'ตำแหน่งแนวตั้ง ({p}%)'},
  // Bilingual / position
  'ed.bilingualProDialog': {'lo': 'ຊັບສອງພາສາ', 'th': 'ซับสองภาษา'},
  // Set start tip
  'ed.setStartTip2': {'lo': 'ຕັ້ງເລີ່ມ = ຕຳແໜ່ງປັດຈຸບັນ', 'th': 'ตั้งเริ่ม = ตำแหน่งปัจจุบัน'},
  // AI dubbing sheet
  'ed.geminiTtsHint2': {
    'lo': 'ກະລຸນາໃສ່ Gemini API Key ໃນໜ້າຕັ້ງຄ່າກ່ອນ ເພື່ອພາກສຽງດ້ວຍ Gemini TTS (30 ສຽງ, ຮອງຮັບພາສາລາວ).',
    'th': 'กรุณาใส่ Gemini API Key ในหน้าตั้งค่าก่อน เพื่อพากย์เสียงด้วย Gemini TTS (30 เสียง รองรับลาว/ไทย)',
  },
  'ed.voiceTones': {'lo': 'ໂທນສຽງພາກ (Gemini Voices):', 'th': 'โทนเสียงพากย์ (Gemini Voices):'},
  'ed.loadingVoices': {'lo': 'ກຳລັງໂຫລດລາຍຊື່ສຽງພາກ...', 'th': 'กำลังโหลดรายชื่อเสียงพากย์...'},
  'ed.male': {'lo': ' (ຊາຍ)', 'th': ' (ชาย)'},
  'ed.female': {'lo': ' (ຍິງ)', 'th': ' (หญิง)'},
  'ed.voiceSpeed': {'lo': 'ຄວາມໄວສຽງພາກ:', 'th': 'ความเร็วเสียงพากย์:'},
  'ed.dubFromTranslation': {
    'lo': 'ພາກສຽງໂດຍໃຊ້ຂໍ້ຄວາມແປ (Translation)',
    'th': 'พากย์เสียงโดยใช้ข้อความแปล (Translation)',
  },
  'ed.sfxAutoSyncTitle': {
    'lo': 'ໃສ່ເອັບເຟັກສຽງອັດສະລິຍະ 💥 (SFX Auto-Sync)',
    'th': 'ใส่เอฟเฟกต์เสียงอัจฉริยะ 💥 (SFX Auto-Sync)',
  },
  'ed.autoSfxDesc': {
    'lo': 'ໃສ່ສຽງ Pop/Ding ໃຫ້ຕົງກັບ Emoji ແລະ ຄຳໄຮໄລຣ໌ອັດຕະໂນມັດ',
    'th': 'ใส่เสียง Pop/Ding ให้ตรงกับ Emoji และคำไฮไลต์อัตโนมัติ',
  },
  'ed.exportFormat': {'lo': 'ຮູບແບບການບັນທຶກ (Export Format):', 'th': 'รูปแบบการบันทึก (Export Format):'},
  'ed.muxVideo': {'lo': 'ພາກສຽງໃສ່ວິດີໂອ (Mux Video)', 'th': 'พากย์เสียงใส่วิดีโอ (Mux Video)'},
  'ed.muxVideoSub': {'lo': 'ລວມສຽງພາກ ແລະ ວິດີໂອເຂົ້າກັນ', 'th': 'รวมเสียงพากย์และวิดีโอเข้าด้วยกัน'},
  'ed.audioOnly': {'lo': 'ບັນທຶກແຍກສະເພາະໄຟລ໌ສຽງ (Audio Only)', 'th': 'บันทึกแยกเฉพาะไฟล์เสียง (Audio Only)'},
  'ed.audioOnlySub': {
    'lo': 'ບັນທຶກເປັນໄຟລ໌ .wav ໄວ້ໃນເຄື່ອງ ເພື່ອໄປຕັດຕໍ່ເອງ',
    'th': 'บันทึกเป็นไฟล์ .wav ไว้ในเครื่อง เพื่อไปตัดต่อเอง',
  },
  'ed.goToSettings': {'lo': 'ໄປທີ່ໜ້າຕັ້ງຄ່າ', 'th': 'ไปที่หน้าตั้งค่า'},
  'ed.startDubbing': {'lo': 'ເລີ່ມພາກສຽງ', 'th': 'เริ่มพากย์เสียง'},
  'ed.preparingSystem': {'lo': 'ກຳລັງກຽມລະບົບ...', 'th': 'กำลังเตรียมระบบ...'},
  'ed.savingAudio': {'lo': 'ກຳລັງບັນທຶກໄຟລ໌ສຽງ...', 'th': 'กำลังบันทึกไฟล์เสียง...'},
  'ed.audioSaveFail': {'lo': 'Terminated. ການບັນທຶກໄຟລ໌ສຽງຫຼົ້ມເຫຼວ: {e}', 'th': 'Terminated. การบันทึกไฟล์เสียงล้มเหลว: {e}'},
  'ed.addingAiTrack': {'lo': 'ກຳລັງເພີ່ມ track ສຽງ AI...', 'th': 'กำลังเพิ่ม track เสียง AI...'},
  'ed.aiTrackFail': {'lo': 'ການສ້າງ track ສຽງ AI ລົ້ມເຫຼວ: {e}', 'th': 'การสร้าง track เสียง AI ล้มเหลว: {e}'},
  'ed.dubDone': {'lo': 'ພາກສຽງສຳເລັດແລ້ວ! ✅', 'th': 'พากย์เสียงสำเร็จแล้ว! ✅'},
  'ed.dubMuxedBody': {
    'lo': 'ສຽງພາກ AI ໄດ້ຖືກລວມເຂົ້າກັບວິດີໂອຮຽບຮ້ອຍແລ້ວ!\nໄຟລ໌ວິດີໂອຖືກບັນທຶກໄວ້ໃນຄັງຮູບເປັນຊື່:\n\n{file}',
    'th': 'เสียงพากย์ AI ถูกรวมเข้ากับวิดีโอเรียบร้อยแล้ว!\nไฟล์วิดีโอถูกบันทึกไว้ในคลังรูปชื่อ:\n\n{file}',
  },
  'ed.dubSavedTitle': {'lo': 'ບັນທຶກສຽງພາກສຳເລັດ! 🎙️', 'th': 'บันทึกเสียงพากย์สำเร็จ! 🎙️'},
  'ed.dubSavedBody': {
    'lo': 'ໄຟລ໌ສຽງພາກ AI ໄດ້ຖືກບັນທຶກສະເພາະແຍກໄວ້ໃນເຄື່ອງຮຽບຮ້ອຍແລ້ວ!\n\nໄຟລ໌ຖືກບັນທຶກໄວ້ໃນໂຟນເດີ Music/SubtitleAI ຂອງເຄື່ອງ:\n\n{file}',
    'th': 'ไฟล์เสียงพากย์ AI ถูกบันทึกแยกไว้ในเครื่องเรียบร้อยแล้ว!\n\nไฟล์ถูกบันทึกไว้ในโฟลเดอร์ Music/SubtitleAI ของเครื่อง:\n\n{file}',
  },
  'ed.saveAsAudioLayer': {'lo': 'ບັນທຶກເປັນ Audio Layer ແທນ 🎵', 'th': 'บันทึกเป็น Audio Layer แทน 🎵'},
  'ed.muxFailBody': {
    'lo': 'ການປະສົມສຽງໃສ່ວິດີໂອໂດຍກົງບໍ່ສຳເລັດ, ແຕ່ໄຟລ໌ສຽງພາກໄດ້ຖືກບັນທຶກແຍກສຳເລັດແລ້ວ! ✅',
    'th': 'การผสมเสียงใส่วิดีโอโดยตรงไม่สำเร็จ แต่ไฟล์เสียงพากย์ถูกบันทึกแยกสำเร็จแล้ว! ✅',
  },
  'ed.audioLayerHint': {
    'lo': '💡 ວິທີໃຊ້: ນຳເຂົ້າໄຟລ໌ສຽງນີ້ເປັນ Audio Layer ແຍກໃນ CapCut ຫຼື TikTok ແລ້ວວາງທັບວິດີໂອໄດ້ເລີຍ!',
    'th': '💡 วิธีใช้: นำเข้าไฟล์เสียงนี้เป็น Audio Layer แยกใน CapCut หรือ TikTok แล้ววางทับวิดีโอได้เลย!',
  },
  'ed.understood': {'lo': 'ເຂົ້າໃຈແລ້ວ 👍', 'th': 'เข้าใจแล้ว 👍'},
  'ed.exportTitle': {'lo': 'ສົ່ງອອກ (Export)', 'th': 'ส่งออก (Export)'},
  'ed.exportVideo': {'lo': 'ວິດີໂອ (ຕິດຊັບ)', 'th': 'วิดีโอ (ฝังซับ)'},
  'ed.exportVideoSub': {'lo': 'burn subtitle ຕິດວິດີໂອ → ບັນທຶກ/ແชร์', 'th': 'ฝังซับติดวิดีโอ → บันทึก/แชร์'},
  'ed.exportSrt': {'lo': 'ໄຟລ໌ SRT (.srt)', 'th': 'ไฟล์ SRT (.srt)'},
  'ed.exportSrtSub': {'lo': 'ສຳລັບ CapCut / YouTube / Premiere', 'th': 'สำหรับ CapCut / YouTube / Premiere'},
  'ed.exportVtt': {'lo': 'ໄຟລ໌ VTT (.vtt)', 'th': 'ไฟล์ VTT (.vtt)'},
  'ed.exportVttSub': {'lo': 'ສຳລັບ web / YouTube', 'th': 'สำหรับ web / YouTube'},
  'ed.subFileSaved': {
    'lo': 'ບັນທຶກ {path} ແລ້ວ — ນຳເຂົ້າໃນ CapCut/YouTube ໄດ້',
    'th': 'บันทึก {path} แล้ว — นำเข้าใน CapCut/YouTube ได้',
  },
  'ed.subFileFail': {'lo': 'ບັນທຶກໄຟລ໌ subtitle ບໍ່ສຳເລັດ: {e}', 'th': 'บันทึกไฟล์ subtitle ไม่สำเร็จ: {e}'},
  'ed.srtQuota': {'lo': ' (ຟຣີ ເຫຼືອ {n} ຄັ້ງມື້ນີ້)', 'th': ' (ฟรี เหลือ {n} ครั้งวันนี้)'},
  'ed.srtQuotaReached': {
    'lo': 'Export ໄຟລ໌ subtitle ຟຣີໝົດແລ້ວ (2 ຄັ້ງ/ວັນ) — ອັບເກຣດ PRO ໃຊ້ບໍ່ຈຳກັດ',
    'th': 'Export ไฟล์ subtitle ฟรีหมดแล้ว (2 ครั้ง/วัน) — อัปเกรด PRO ใช้ไม่จำกัด',
  },
  'ed.writingCaption': {'lo': 'Gemini ກຳລັງຂຽນແคปชั่น...', 'th': 'Gemini กำลังเขียนแคปชั่น...'},
  'ed.captionFail': {'lo': 'ສ້າງບໍ່ສຳເລັດ — ລອງໃໝ່', 'th': 'สร้างไม่สำเร็จ — ลองใหม่'},
  'ed.copyAll': {'lo': 'ຄັດລອกທັງໝົด', 'th': 'คัดลอกทั้งหมด'},
  'ed.caption': {'lo': 'ແคปชั่น', 'th': 'แคปชั่น'},
  'ed.captionHint': {'lo': '💡 ກดຄัดລอก แล้วไปวางในแคปชั่น TikTok/FB ได้เลย', 'th': '💡 กดคัดลอก แล้วไปวางในแคปชั่น TikTok/FB ได้เลย'},

  // ── Settings screen ─────────────────────────────────────────────────
  'set.title': {'lo': 'ຕັ້ງຄ່າ', 'th': 'ตั้งค่า'},
  'set.copied': {'lo': 'ຄັດລອກແລ້ວ', 'th': 'คัดลอกแล้ว'},
  'set.aiKeys': {'lo': 'ກະແຈ AI (API Keys)', 'th': 'คีย์ AI (API Keys)'},
  'set.aiKeysDesc': {
    'lo': 'ໃຊ້ key ຂອງເຈົ້າເອງ (ຟຣີ) — ກົດເພື່ອເປີດ/ໃສ່',
    'th': 'ใช้ key ของคุณเอง (ฟรี) — แตะเพื่อเปิด/ใส่',
  },
  'set.general': {'lo': 'ທົ່ວໄປ', 'th': 'ทั่วไป'},
  'set.keySet': {'lo': 'ໃສ່ແລ້ວ', 'th': 'ใส่แล้ว'},
  'set.keyNotSet': {'lo': 'ຍັງບໍ່ໄດ້ໃສ່', 'th': 'ยังไม่ได้ใส่'},
  'set.required': {'lo': 'ຈຳເປັນ', 'th': 'จำเป็น'},
  'set.recommended': {'lo': 'ແນະນຳ', 'th': 'แนะนำ'},
  'set.optional': {'lo': 'ທາງເລືອກ', 'th': 'ตัวเลือก'},
  'set.geminiSub': {'lo': 'ຖອດສຽງ + ພາກສຽງ + ແປ', 'th': 'ถอดเสียง + พากย์ + แปล'},
  'set.groqSub': {'lo': 'ຈັບເວລາໃຫ້ຕົງສຽງ', 'th': 'จับเวลาให้ตรงเสียง'},
  'set.openaiSub': {'lo': 'Whisper ຖອດສຽງ', 'th': 'Whisper ถอดเสียง'},
  'set.tenorSub': {'lo': 'ຄົ້ນ meme GIF', 'th': 'ค้น meme GIF'},
  'set.fromTenor': {'lo': 'ຈາກ tenor.com (Google)', 'th': 'จาก tenor.com (Google)'},
  'set.howTenor': {'lo': 'ວິທີຂໍ Tenor API Key (ສຳລັບ meme GIF)', 'th': 'วิธีขอ Tenor API Key (สำหรับ meme GIF)'},
  'set.howTenor1': {'lo': 'ໄປ developers.google.com/tenor → Get a key', 'th': 'ไป developers.google.com/tenor → Get a key'},
  'set.howTenor2': {'lo': 'ສ້າງ project ໃນ Google Cloud → ເປີດ Tenor API', 'th': 'สร้าง project ใน Google Cloud → เปิด Tenor API'},
  'set.howTenor3': {'lo': 'ສ້າງ API key → ຄັດລອກ', 'th': 'สร้าง API key → คัดลอก'},
  'set.howTenor4': {'lo': 'ນຳ key ມາວາງໃສ່ຊ່ອງດ້ານເທິງ → ບັນທຶກ', 'th': 'นำ key มาวางในช่องด้านบน → บันทึก'},
  'set.tenorInfo': {
    'lo': 'ໃຊ້ค้น meme GIF จาก Tenor (ฟรี). ไม่ใส่ก็ได้ — ใช้ "ค้นรูป" (Openverse) ได้เลย',
    'th': 'ใช้ค้น meme GIF จาก Tenor (ฟรี) ไม่ใส่ก็ได้ — ใช้ "ค้นรูป" (Openverse) ได้เลย',
  },
  'set.freesoundSub': {'lo': 'ຄົ້ນ SFX ມີມ', 'th': 'ค้น SFX มีม'},
  'set.fromFreesound': {'lo': 'ຈາກ freesound.org', 'th': 'จาก freesound.org'},
  'set.howFs1': {'lo': 'ສະໝັກບັນຊີຟຣີ freesound.org', 'th': 'สมัครบัญชีฟรี freesound.org'},
  'set.howFs2': {'lo': 'ໄປ freesound.org/apiv2/apply → ສ້າງ API key', 'th': 'ไป freesound.org/apiv2/apply → สร้าง API key'},
  'set.howFs3': {'lo': 'ກ໊ອບ "Client secret/Api key" ມາວາງ → ບັນທຶກ', 'th': 'ก๊อป "Client secret/Api key" มาวาง → บันทึก'},
  'set.freesoundInfo': {
    'lo': 'ໃຊ້ຄົ້ນສຽງມີມ/UI (CC0 ບໍ່ຕ້ອງ credit). ບໍ່ໃສ່ກໍໄດ້ — ໃຊ້ "ສຽງຈິງ (BBC)" ໄດ້ເລີຍ',
    'th': 'ใช้ค้นเสียงมีม/UI (CC0 ไม่ต้อง credit) ไม่ใส่ก็ได้ — ใช้ "เสียงจริง (BBC)" ได้เลย',
  },
  'set.saved': {'lo': 'ບັນທຶກແລ້ວ!', 'th': 'บันทึกแล้ว!'},
  'set.signedIn': {
    'lo': 'ເຂົ້າສູ່ລະບົບສຳເລັດ — PRO ຈະຕິດຕາມບັນຊີນີ້',
    'th': 'เข้าสู่ระบบสำเร็จ — PRO จะติดตามบัญชีนี้',
  },
  'set.firebaseNotSet': {
    'lo': 'ຍັງບໍ່ໄດ້ຕັ້ງຄ່າ Firebase — ຕິດຕໍ່ຜູ້ພັດທະນາ',
    'th': 'ยังไม่ได้ตั้งค่า Firebase — ติดต่อผู้พัฒนา',
  },
  'set.signInFailed': {
    'lo': 'ເຂົ້າສູ່ລະບົບບໍ່ສຳເລັດ — ລອງໃໝ່',
    'th': 'เข้าสู่ระบบไม่สำเร็จ — ลองใหม่',
  },
  'set.signedOut': {'lo': 'ອອກຈາກລະບົບແລ້ວ', 'th': 'ออกจากระบบแล้ว'},
  'set.updatedProUntil': {
    'lo': 'ອັບເດດແລ້ວ — PRO ໃຊ້ໄດ້ຮອດ {date}',
    'th': 'อัปเดตแล้ว — PRO ใช้ได้ถึง {date}',
  },
  'set.updatedNoPro': {
    'lo': 'ອັບເດດແລ້ວ — ຍັງບໍ່ມີ PRO ໃນບັນຊີນີ້',
    'th': 'อัปเดตแล้ว — ยังไม่มี PRO ในบัญชีนี้',
  },
  'set.enterKeyFirst': {'lo': 'ກາລຸນາໃສ່ API Key ກ່ອນ', 'th': 'กรุณาใส่ API Key ก่อน'},
  'set.priceMonth': {'lo': '39,000 ກີບ/ເດືອນ', 'th': '39,000 กีบ/เดือน'},
  'set.waMsg': {
    'lo': 'ສະບາຍດີ ຢາກສະມັກ KarnSub PRO (39,000 ກີບ/ເດືອນ).',
    'th': 'สวัสดี อยากสมัคร KarnSub PRO.',
  },
  'set.waFail': {
    'lo': 'ເປີດ WhatsApp ບໍ່ໄດ້ — ໂທ/add: 020 9552 4699',
    'th': 'เปิด WhatsApp ไม่ได้ — โทร/add: 020 9552 4699',
  },
  'set.signInFirst': {
    'lo': 'ກະລຸນາ Sign in ກ່ອນ (ປຸ່ມ Google ດ້ານເທິງ)',
    'th': 'กรุณา Sign in ก่อน (ปุ่ม Google ด้านบน)',
  },
  'set.checkingSlip': {'lo': 'ກຳລັງກວດ slip...', 'th': 'กำลังตรวจ slip...'},
  'set.openingPro': {'lo': 'ກຳລັງເປີດ PRO...', 'th': 'กำลังเปิด PRO...'},
  'set.proSuccess': {'lo': '🎉 ເປີດ PRO ສຳເລັດ! ຂອບໃຈ', 'th': '🎉 เปิด PRO สำเร็จ! ขอบคุณ'},
  'set.slipUsed': {'lo': '❌ slip ນີ້ຖືກໃຊ້ໄປແລ້ວ', 'th': '❌ slip นี้ถูกใช้ไปแล้ว'},
  'set.signInFirst2': {'lo': '❌ ກະລຸນາ Sign in ກ່ອນ', 'th': '❌ กรุณา Sign in ก่อน'},
  'set.errorRetry': {'lo': '❌ ເກີດຂໍ້ຜິດພາດ — ລອງໃໝ່', 'th': '❌ เกิดข้อผิดพลาด — ลองใหม่'},
  'set.firestoreDenied': {
    'lo': 'Firestore ປະຕິເສດ (ຕັ້ງ rules)',
    'th': 'Firestore ปฏิเสธ (ตั้ง rules)',
  },
  'set.autoTopupTitle': {'lo': 'ສະໝັກ PRO ອັດຕະໂນມັດ', 'th': 'สมัคร PRO อัตโนมัติ'},
  'set.transferTo': {'lo': 'ໂອນເຂົ້າ: {name}', 'th': 'โอนเข้า: {name}'},
  'set.account': {'lo': 'ບັນຊີ: {acc}', 'th': 'บัญชี: {acc}'},
  'set.checking': {'lo': 'ກຳລັງກວດ...', 'th': 'กำลังตรวจ...'},
  'set.paidUpload': {
    'lo': 'ຂ້ອຍຈ່າຍແລ້ວ — ອັບໂຫຼດ slip',
    'th': 'ฉันจ่ายแล้ว — อัปโหลด slip',
  },
  'set.slipHint': {
    'lo': 'ຈ່າຍ QR ດ້ານເທິງແລ້ວ ຖ່າຍ/ເລືອກຮູບ slip ມາອັບໂຫຼດ — ລະບົບກວດ ແລ້ວເປີດ PRO ໃຫ້ທັນທີ',
    'th': 'จ่าย QR ด้านบนแล้ว ถ่าย/เลือกรูป slip มาอัปโหลด — ระบบตรวจแล้วเปิด PRO ให้ทันที',
  },
  'set.account.section': {'lo': 'ບັນຊີ', 'th': 'บัญชี'},
  'set.linkPro': {'lo': 'ເຊື່ອມ PRO ກັບບັນຊີ', 'th': 'เชื่อม PRO กับบัญชี'},
  'set.loggedIn': {'lo': 'ເຂົ້າສູ່ລະບົບແລ້ວ', 'th': 'เข้าสู่ระบบแล้ว'},
  'set.loginBenefit': {
    'lo': 'ລ໋ອກອິນ → PRO ຕິດຕາມບັນຊີ ແມ້ປ່ຽນເຄື່ອງ',
    'th': 'ล็อกอิน → PRO ติดตามบัญชี แม้เปลี่ยนเครื่อง',
  },
  'set.updatePro': {'lo': 'ອັບເດດ PRO', 'th': 'อัปเดต PRO'},
  'set.signOut': {'lo': 'ອອກ', 'th': 'ออก'},
  'set.deleteAccount': {'lo': 'ລຶບບັນຊີ', 'th': 'ลบบัญชี'},
  'set.deleteConfirm': {
    'lo': 'ການລຶບບັນຊີຈະລຶບຂໍ້ມູນ PRO ແລະ ບັນຊີຂອງເຈົ້າຖາວອນ ກູ້ຄືນບໍ່ໄດ້. ດຳເນີນຕໍ່ບໍ?',
    'th': 'การลบบัญชีจะลบข้อมูล PRO และบัญชีของคุณถาวร กู้คืนไม่ได้ ดำเนินการต่อหรือไม่?',
  },
  'set.deleteConfirmYes': {'lo': 'ລຶບຖາວອນ', 'th': 'ลบถาวร'},
  'set.accountDeleted': {'lo': 'ລຶບບັນຊີສຳເລັດ', 'th': 'ลบบัญชีสำเร็จ'},
  'set.deleteFailed': {'lo': 'ລຶບບັນຊີບໍ່ສຳເລັດ — ລອງໃໝ່', 'th': 'ลบบัญชีไม่สำเร็จ — ลองใหม่'},
  'set.signInGoogle': {'lo': 'ເຂົ້າສູ່ລະບົບ ດ້ວຍ Google', 'th': 'เข้าสู่ระบบด้วย Google'},
  'set.feat.noWatermark': {'lo': 'ບໍ່ມີ watermark', 'th': 'ไม่มี watermark'},
  'set.feat.bilingual': {'lo': 'ສອງພາສາ', 'th': 'สองภาษา'},
  'set.feat.aiVoice': {'lo': 'ພາກສຽງ AI', 'th': 'พากย์เสียง AI'},
  'set.otherChannels': {
    'lo': 'ຊ່ອງທາງອື່ນ (WhatsApp / License) →',
    'th': 'ช่องทางอื่น (WhatsApp / License) →',
  },
  'set.proUntil': {'lo': 'ໃຊ້ໄດ້ຮອດ {date}', 'th': 'ใช้ได้ถึง {date}'},
  'set.proFull': {'lo': 'ໃຊ້ໄດ້ເຕັມທຸກຟີເຈີ', 'th': 'ใช้ได้เต็มทุกฟีเจอร์'},
  'set.renewPro': {'lo': 'ຕໍ່ອາຍຸ PRO', 'th': 'ต่ออายุ PRO'},
  'set.expiredOn': {'lo': 'ໝົດອາຍຸ {date}', 'th': 'หมดอายุ {date}'},
  'set.expired': {'lo': 'ໝົດ', 'th': 'หมด'},
  'set.renewProPrice': {'lo': 'ຕໍ່ອາຍຸ PRO — {price}', 'th': 'ต่ออายุ PRO — {price}'},
  'set.upgradeFull': {'lo': 'ອັບເກຣດໃຊ້ງານເຕັມ', 'th': 'อัปเกรดใช้งานเต็ม'},
  'set.unlockAll': {'lo': 'ປົດລັອກທຸກຟີເຈີ — {price}', 'th': 'ปลดล็อกทุกฟีเจอร์ — {price}'},
  'set.subscribeQr': {'lo': 'ສະໝັກ PRO — ຈ່າຍ QR', 'th': 'สมัคร PRO — จ่าย QR'},
  'set.redeemKey': {'lo': 'ໃສ່ລະຫັດ PRO (Key)', 'th': 'ใส่รหัส PRO (Key)'},
  'set.haveKey': {'lo': 'ມີລະຫັດແລ້ວ? ໃສ່ Key', 'th': 'มีรหัสแล้ว? ใส่ Key'},
  'set.redeemKeyHint': {
    'lo': 'ໃສ່ລະຫັດ PRO ທີ່ໄດ້ຮັບ (ໃຊ້ໄດ້ຄັ້ງດຽວ — ຕ້ອງຕໍ່ເນັດ)',
    'th': 'ใส่รหัส PRO ที่ได้รับ (ใช้ได้ครั้งเดียว — ต้องต่อเน็ต)',
  },
  'set.activate': {'lo': 'ເປີດໃຊ້', 'th': 'เปิดใช้'},
  'set.keyOk': {'lo': 'ເປີດ PRO ສຳເລັດ ✓', 'th': 'เปิด PRO สำเร็จ ✓'},
  'set.keyInvalid': {'lo': 'ລະຫັດບໍ່ຖືກຕ້ອງ', 'th': 'รหัสไม่ถูกต้อง'},
  'set.keyExpired': {'lo': 'ລະຫັດໝົດອາຍຸແລ້ວ', 'th': 'รหัสหมดอายุแล้ว'},
  'set.keyUsed': {'lo': 'ລະຫັດນີ້ຖືກໃຊ້ໄປແລ້ວ', 'th': 'รหัสนี้ถูกใช้ไปแล้ว'},
  'set.keyNeedNet': {'lo': 'ກວດລະຫັດບໍ່ໄດ້ — ກະລຸນາຕໍ່ອິນເຕີເນັດ', 'th': 'ตรวจรหัสไม่ได้ — กรุณาต่ออินเทอร์เน็ต'},
  'set.buyPro': {'lo': 'ຊື້ KarnSub PRO', 'th': 'ซื้อ KarnSub PRO'},
  'set.buyFast': {
    'lo': 'ວິທີໄວ: ກົດ "ຈ່າຍ QR (Auto)" → scan ຈ່າຍ → ອັບ slip → ເປີດ PRO ທັນທີ',
    'th': 'วิธีเร็ว: กด "จ่าย QR (Auto)" → สแกนจ่าย → อัป slip → เปิด PRO ทันที',
  },
  'set.buyWa': {
    'lo': 'ຫຼື ທາງ WhatsApp: ໂອນ {price} → ສົ່ງ slip + Gmail',
    'th': 'หรือทาง WhatsApp: โอน {price} → ส่ง slip + Gmail',
  },
  'set.loginRequired': {
    'lo': 'ຕ້ອງ login Google ກ່ອນ (ປຸ່ມດ້ານເທິງ)',
    'th': 'ต้อง login Google ก่อน (ปุ่มด้านบน)',
  },
  'set.proNote': {
    'lo': 'PRO {price} — ໝົດເດືອນ ກັບຄືນ FREE ເອງ',
    'th': 'PRO {price} — หมดเดือนกลับเป็น FREE เอง',
  },
  'set.payQrAuto': {'lo': 'ຈ່າຍ QR (Auto)', 'th': 'จ่าย QR (Auto)'},
  'set.groqKeyLabel': {'lo': 'Groq Key (ໃຫ້ຕົງສຽງ)', 'th': 'Groq Key (ให้ตรงเสียง)'},
  'set.groqKeyDesc': {
    'lo': 'ທາງເລືອກ — Whisper ຈັບເວລາທຸກຄຳໃຫ້ຕົງສຽງ (console.groq.com)',
    'th': 'ตัวเลือก — Whisper จับเวลาทุกคำให้ตรงเสียง (console.groq.com)',
  },
  'set.groqHint2': {
    'lo': 'gsk_xxxxxxxxxxxxxxxxxxxx (ໃສ່ ຫຼື ບໍ່ໃສ່ກໍ່ໄດ້)',
    'th': 'gsk_xxxxxxxxxxxxxxxxxxxx (ใส่ หรือไม่ใส่ก็ได้)',
  },
  'set.saveGroqKey': {'lo': 'ບັນທຶກ Groq Key', 'th': 'บันทึก Groq Key'},
  'set.groqInfo': {
    'lo': '💡 ໃສ່ Groq key ແລ້ວ ການຖອດສຽງ/Auto Sync ຈະໃຊ້ Whisper ຈັບເວລາໃຫ້ຕົງສຽງທຸກຄຳ (ຂໍຟຣີໄດ້ທີ່ console.groq.com). ບໍ່ໃສ່ກໍ່ໄດ້ — ຈະໃຊ້ການ sync ແບບປົກກະຕິ.',
    'th': '💡 ใส่ Groq key แล้ว การถอดเสียง/Auto Sync จะใช้ Whisper จับเวลาให้ตรงเสียงทุกคำ (ขอฟรีที่ console.groq.com) ไม่ใส่ก็ได้ — จะใช้การ sync แบบปกติ',
  },
  'set.fromAistudio': {'lo': 'ຈາກ aistudio.google.com', 'th': 'จาก aistudio.google.com'},
  'set.fromOpenai': {'lo': 'ຈາກ platform.openai.com', 'th': 'จาก platform.openai.com'},
  'set.save': {'lo': 'ບັນທຶກ', 'th': 'บันทึก'},
  'set.delete': {'lo': 'ລຶບ', 'th': 'ลบ'},
  // How-to: Gemini
  'set.howGemini': {
    'lo': 'ວິທີຂໍ Gemini API Key (ສຳລັບ AI ພາກສຽງ & ຖອດສຽງລາວ)',
    'th': 'วิธีขอ Gemini API Key (สำหรับ AI พากย์เสียง & ถอดเสียง)',
  },
  'set.howGemini1': {
    'lo': 'ໄປ aistudio.google.com → ລ໋ອກອິນດ້ວຍ Gmail',
    'th': 'ไป aistudio.google.com → ล็อกอินด้วย Gmail',
  },
  'set.howGemini2': {
    'lo': 'ກົດປຸ່ມ "Get API key" (ມຸມຊ້າຍເທິງ) → "Create API key"',
    'th': 'กดปุ่ม "Get API key" (มุมซ้ายบน) → "Create API key"',
  },
  'set.howGemini3': {
    'lo': 'ຄັດລອກ Key (ຂຶ້ນຕົ້ນດ້ວຍ AIzaSy...)',
    'th': 'คัดลอก Key (ขึ้นต้นด้วย AIzaSy...)',
  },
  'set.howGemini4': {
    'lo': 'ນຳເອົາ key ມາວາງໃສ່ຊ່ອງດ້ານເທິງ → ກົດ ບັນທຶກ',
    'th': 'นำ key มาวางในช่องด้านบน → กดบันทึก',
  },
  'set.geminiInfo': {
    'lo': 'Gemini 2.5 Flash — ຖອດສຽງພາສາລາວໄດ້ດີທີ່ສຸດ ແລະ ສາມາດພາກສຽງ AI ໄດ້\n(ມີ Free tier ໃຫ້ໃຊ້ຟຣີ)',
    'th': 'Gemini 2.5 Flash — ถอดเสียงได้ดีที่สุด และพากย์เสียง AI ได้\n(มี Free tier ให้ใช้ฟรี)',
  },
  // How-to: OpenAI
  'set.howOpenai': {
    'lo': 'ວິທີຂໍ OpenAI API Key (ສຳລັບ Whisper ຖອດສຽງ)',
    'th': 'วิธีขอ OpenAI API Key (สำหรับ Whisper ถอดเสียง)',
  },
  'set.howOpenai1': {
    'lo': 'ໄປ platform.openai.com → ລ໋ອກອິນ/ສະໝັກສະມາຊິກ',
    'th': 'ไป platform.openai.com → ล็อกอิน/สมัครสมาชิก',
  },
  'set.howOpenai2': {
    'lo': 'ໄປທີ່ເມນູ "API Keys" ດ້ານຊ້າຍມື',
    'th': 'ไปที่เมนู "API Keys" ด้านซ้าย',
  },
  'set.howOpenai3': {
    'lo': 'ກົດ "Create new secret key" (ອາດຕ້ອງຕື່ມເງິນ 5\$ ກ່ອນ)',
    'th': 'กด "Create new secret key" (อาจต้องเติมเงิน 5\$ ก่อน)',
  },
  'set.howOpenai4': {
    'lo': 'ຄັດລອກ Key (ຂຶ້ນຕົ້ນດ້ວຍ sk-...) ມາວາງໃສ່',
    'th': 'คัดลอก Key (ขึ้นต้นด้วย sk-...) มาวาง',
  },
  'set.openaiInfo': {
    'lo': 'ໃຊ້ໂມເດວ Whisper ຂອງ OpenAI ໃນການຖອດສຽງ\n(ຈ່າຍເງິນຕາມການນຳໃຊ້ຕົວຈິງ)',
    'th': 'ใช้โมเดล Whisper ของ OpenAI ในการถอดเสียง\n(จ่ายตามการใช้งานจริง)',
  },
  // How-to: Groq
  'set.howGroq': {
    'lo': 'ວິທີຂໍ Groq API Key (ສຳລັບຈັບເວລາຄຳສັບໃຫ້ຕົງ)',
    'th': 'วิธีขอ Groq API Key (สำหรับจับเวลาคำให้ตรง)',
  },
  'set.howGroq1': {'lo': 'ໄປ console.groq.com → ລ໋ອກອິນ', 'th': 'ไป console.groq.com → ล็อกอิน'},
  'set.howGroq2': {
    'lo': 'ໄປທີ່ເມນູ "API Keys" ດ້ານຊ້າຍມື',
    'th': 'ไปที่เมนู "API Keys" ด้านซ้าย',
  },
  'set.howGroq3': {'lo': 'ກົດ "Create API Key"', 'th': 'กด "Create API Key"'},
  'set.howGroq4': {
    'lo': 'ຄັດລອກ Key (ຂຶ້ນຕົ້ນດ້ວຍ gsk_...) ມາວາງໃສ່',
    'th': 'คัดลอก Key (ขึ้นต้นด้วย gsk_...) มาวาง',
  },
  'set.groqInfo2': {
    'lo': 'ໃຊ້ຮ່ວມກັບ Gemini ເພື່ອໃຫ້ເວລາຂອງແຕ່ລະຄຳ (Word-level timestamps) ຊັດເຈນຂຶ້ນ (ປັດຈຸບັນໃຊ້ຟຣີ)',
    'th': 'ใช้ร่วมกับ Gemini เพื่อให้เวลาของแต่ละคำ (Word-level timestamps) แม่นขึ้น (ปัจจุบันใช้ฟรี)',
  },

  // ── Home screen ─────────────────────────────────────────────────────
  'home.recentProjects': {'lo': 'ໂປຣເຈກຫຼ້າສຸດ', 'th': 'โปรเจกต์ล่าสุด'},
  'home.tagline': {'lo': 'ສ້າງ subtitle ໄວ ດ້ວຍ AI', 'th': 'สร้างซับไตเติลเร็วด้วย AI'},
  'home.projectCount': {'lo': 'ມີ {n} ໂປຣເຈກ', 'th': 'มี {n} โปรเจกต์'},
  'home.newProject': {'lo': 'ສ້າງໂປຣເຈກໃໝ່', 'th': 'สร้างโปรเจกต์ใหม่'},
  'home.newProjectSub': {
    'lo': 'ອັບໂຫລດ video → AI ສ້າງ subtitle',
    'th': 'อัปโหลดวิดีโอ → AI สร้างซับไตเติล',
  },
  'home.bilingualBadge': {'lo': '2 ພາສາ', 'th': '2 ภาษา'},
  'home.segments': {'lo': 'ປ່ອນ', 'th': 'ท่อน'},
  'home.rename': {'lo': 'ປ່ຽນຊື່', 'th': 'เปลี่ยนชื่อ'},
  'home.duplicate': {'lo': 'ສຳເນົາ', 'th': 'ทำสำเนา'},
  'home.renameTitle': {'lo': 'ປ່ຽນຊື່ໂປຣເຈກ', 'th': 'เปลี่ยนชื่อโปรเจกต์'},
  'home.projectNameHint': {'lo': 'ຊື່ໂປຣເຈກ', 'th': 'ชื่อโปรเจกต์'},
  'home.empty': {'lo': 'ຍັງບໍ່ມີໂປຣເຈກ', 'th': 'ยังไม่มีโปรเจกต์'},
  'home.emptySub': {
    'lo': 'ກົດ "ສ້າງໂປຣເຈກໃໝ່" ເພື່ອເລີ່ມ',
    'th': 'กด "สร้างโปรเจกต์ใหม่" เพื่อเริ่ม',
  },
  'home.deleteTitle': {'lo': 'ລຶບໂປຣເຈກ', 'th': 'ลบโปรเจกต์'},
  'home.deleteBody': {
    'lo': 'ຕ້ອງການລຶບ "{name}" ບໍ?\nຂໍ້ມູນຈະຫາຍໄປຖາວອນ',
    'th': 'ต้องการลบ "{name}" ไหม?\nข้อมูลจะหายไปถาวร',
  },

  // ── Processing screen ───────────────────────────────────────────────
  'lang.name.lo': {'lo': 'ພາສາລາວ', 'th': 'ภาษาลาว'},
  'lang.name.th': {'lo': 'ພາສາໄທ', 'th': 'ภาษาไทย'},
  'proc.preparing': {'lo': 'ກຳລັງກຽມໄຟລ໌...', 'th': 'กำลังเตรียมไฟล์...'},
  'proc.extractAudio': {'lo': 'ດຶງສຽງຈາກວິດີໂອ', 'th': 'ดึงเสียงจากวิดีโอ'},
  'proc.transcribeWith': {'lo': '{engine} ຖອດສຽງ{lang}', 'th': '{engine} ถอดเสียง{lang}'},
  'proc.translateTo': {'lo': 'Gemini ແປເປັນ{lang}', 'th': 'Gemini แปลเป็น{lang}'},
  'proc.whisperAlign': {'lo': 'Whisper ຈັບເວລາໃຫ້ຕົງ', 'th': 'Whisper จับเวลาให้ตรง'},
  'proc.createSubtitle': {'lo': 'ສ້າງ Subtitle', 'th': 'สร้างซับไตเติล'},
  'proc.groqFast': {'lo': 'Groq (ໄວ)', 'th': 'Groq (เร็ว)'},
  'proc.noOpenAiKey': {
    'lo': 'ຍັງບໍ່ໄດ້ໃສ່ OpenAI API Key',
    'th': 'ยังไม่ได้ใส่ OpenAI API Key',
  },
  'proc.noGroqKey': {
    'lo': 'ຍັງບໍ່ໄດ້ໃສ່ Groq API Key',
    'th': 'ยังไม่ได้ใส่ Groq API Key',
  },
  'proc.noGeminiKey': {
    'lo': 'ຍັງບໍ່ໄດ້ໃສ່ Gemini API Key',
    'th': 'ยังไม่ได้ใส่ Gemini API Key',
  },
  'proc.noGeminiKeyTranslate': {
    'lo': 'ບໍ່ພົບ Gemini API Key ສຳລັບການແປພາສາ. ກະລຸນາໃສ່ໃນໜ້າຕັ້ງຄ່າ',
    'th': 'ไม่พบ Gemini API Key สำหรับการแปล กรุณาใส่ในหน้าตั้งค่า',
  },
  'proc.aligning': {'lo': 'ກຳລັງຈັດໃຫ້ຕົງສຽງ...', 'th': 'กำลังจัดให้ตรงเสียง...'},
  'proc.whisperAligning': {
    'lo': 'Whisper ກຳລັງຈັບເວລາ (ໃຫ້ຕົງສຽງ)...',
    'th': 'Whisper กำลังจับเวลา (ให้ตรงเสียง)...',
  },
  'proc.done': {'lo': 'ສຳເລັດແລ້ວ! ✅', 'th': 'สำเร็จแล้ว! ✅'},
  'proc.errorLong': {
    'lo': 'ວິດີໂອຍາວເກີນໄປ ຫຼື ເນັດຊ້າ — ກາລຸນາໃຊ້ວິດີໂອສັ້ນກວ່າ 10 ນາທີ ຫຼື ລອງໃໝ່',
    'th': 'วิดีโอยาวเกินไป หรือเน็ตช้า — กรุณาใช้วิดีโอสั้นกว่า 10 นาที หรือลองใหม่',
  },
  'proc.errorGeneric': {'lo': 'ເກີດຂໍ້ຜິດພາດ: {msg}', 'th': 'เกิดข้อผิดพลาด: {msg}'},
  'proc.notSet': {'lo': 'ຍັງບໍ່ໄດ້ໃສ່', 'th': 'ยังไม่ได้ใส่'},
  'proc.noOpenAiTitle': {
    'lo': 'ຍັງບໍ່ໄດ້ຕັ້ງ OpenAI API Key',
    'th': 'ยังไม่ได้ตั้ง OpenAI API Key',
  },
  'proc.noGeminiTitle': {
    'lo': 'ຍັງບໍ່ໄດ້ຕັ້ງ Gemini API Key',
    'th': 'ยังไม่ได้ตั้ง Gemini API Key',
  },
  'proc.errorTitle': {'lo': 'ເກີດຂໍ້ຜິດພາດ', 'th': 'เกิดข้อผิดพลาด'},
  'proc.goSetOpenAi': {'lo': 'ໄປຕັ້ງ OpenAI API Key', 'th': 'ไปตั้ง OpenAI API Key'},
  'proc.goSetGemini': {'lo': 'ໄປຕັ້ງ Gemini API Key', 'th': 'ไปตั้ง Gemini API Key'},
  'proc.retry': {'lo': 'ລອງໃໝ່', 'th': 'ลองใหม่'},
  'proc.back': {'lo': 'ກັບໄປ', 'th': 'กลับไป'},
  'proc.step.extract': {'lo': 'ດຶງສຽງ', 'th': 'ดึงเสียง'},
  'proc.step.send': {'lo': 'ສົ່ງ', 'th': 'ส่ง'},
  'proc.step.transcribe': {'lo': 'ຖອດສຽງ', 'th': 'ถอดเสียง'},
  'proc.step.create': {'lo': 'ສ້າງ', 'th': 'สร้าง'},

  // ── Setup screen ────────────────────────────────────────────────────
  'setup.title': {'lo': 'ໂປຣເຈກໃໝ່', 'th': 'โปรเจกต์ใหม่'},
  'setup.projectName': {'lo': 'ຊື່ໂປຣເຈກ', 'th': 'ชื่อโปรเจกต์'},
  'setup.nameHint': {
    'lo': 'ເຊັ່ນ: ຄລິບສອນທຳອາຫານ EP.1',
    'th': 'เช่น: คลิปสอนทำอาหาร EP.1',
  },
  'setup.uploadVideo': {'lo': 'ອັບໂຫລດວິດີໂອ', 'th': 'อัปโหลดวิดีโอ'},
  'setup.aspectRatio': {'lo': 'ອັດຕາສ່ວນ', 'th': 'อัตราส่วน'},
  'setup.subtitleStyle': {'lo': 'ສໄຕລ໌ Subtitle', 'th': 'สไตล์ซับไตเติล'},
  'setup.speechLang': {
    'lo': 'ພາສາສຽງໃນວິດີໂອ (Speech Audio)',
    'th': 'ภาษาเสียงในวิดีโอ (Speech Audio)',
  },
  'setup.subtitleLang': {
    'lo': 'ພາສາ Subtitles ທີ່ຕ້ອງການ',
    'th': 'ภาษาซับไตเติลที่ต้องการ',
  },
  'setup.aiEngine': {
    'lo': 'ເຄື່ອງມື AI ຖອດສຽງ (AI Engine)',
    'th': 'เครื่องมือ AI ถอดเสียง (AI Engine)',
  },
  'setup.translationMode': {
    'lo': 'ຮູບແບບການສະແດງຜົນ (Translation Mode)',
    'th': 'รูปแบบการแสดงผล (Translation Mode)',
  },
  'setup.subtitleSplit': {'lo': 'ການແບ່ງ Subtitle', 'th': 'การแบ่งซับไตเติล'},
  'setup.previewLabel': {'lo': 'ຕົວຢ່າງ Subtitle', 'th': 'ตัวอย่างซับไตเติล'},
  'setup.previewText': {
    'lo': 'ນີ້ຄືຕົວຢ່າງ subtitle ຂອງເຈົ້າ',
    'th': 'นี่คือตัวอย่างซับไตเติลของคุณ',
  },
  'setup.pickVideoFirst': {
    'lo': 'ກາລຸນາເລືອກວິດີໂອກ່ອນ',
    'th': 'กรุณาเลือกวิดีโอก่อน',
  },
  'setup.tapToChange': {'lo': 'ແຕະເພື່ອປ່ຽນວິດີໂອ', 'th': 'แตะเพื่อเปลี่ยนวิดีโอ'},
  'setup.tapToPick': {'lo': 'ແຕະເລືອກວິດີໂອ', 'th': 'แตะเลือกวิดีโอ'},
  'setup.videoFormats': {
    'lo': 'MP4, MOV, AVI • ສູງສຸດ 10 ນາທີ',
    'th': 'MP4, MOV, AVI • สูงสุด 10 นาที',
  },
  'setup.createSubtitle': {'lo': 'ສ້າງ Subtitle →', 'th': 'สร้างซับไตเติล →'},
  'setup.manualType': {
    'lo': 'ພິມ subtitle ດ້ວຍຕົນເອງ',
    'th': 'พิมพ์ซับไตเติลเอง',
  },
  'setup.defaultProjectName': {'lo': 'ໂປຣເຈກ', 'th': 'โปรเจกต์'},
  'setup.hint': {'lo': 'ຄຳໃບ້ / ຊື່ສະເພາະ (ທາງເລືອກ)', 'th': 'คำใบ้ / ชื่อเฉพาะ (ตัวเลือก)'},
  'setup.hintHint': {'lo': 'ເຊັ່ນ: KarnSub, ປາກເຊ, ນ້ອງເຄ', 'th': 'เช่น: KarnSub, ปากเซ, ชื่อแบรนด์'},
  'setup.hintDesc': {
    'lo': 'ໃສ່ຊື່ຄົນ/ຍີ່ຫໍ້/ສະຖານທີ່ (ຄັ່ນດ້ວຍ ,) — AI ຈະສະກົດໃຫ້ຖືກ',
    'th': 'ใส่ชื่อคน/แบรนด์/สถานที่ (คั่นด้วย ,) — AI จะสะกดให้ถูก',
  },
  'setup.proofread': {'lo': 'ກວດທານ AI (ແນະນຳ)', 'th': 'ตรวจทาน AI (แนะนำ)'},
  'setup.proofreadDesc': {
    'lo': 'Gemini ກວດສະກົດ + ຄວາມຕໍ່ເນື່ອງ ຫຼັງຖອດສຽງ (ໃຊ້ Gemini key)',
    'th': 'Gemini ตรวจสะกด + ความต่อเนื่อง หลังถอดเสียง (ใช้ Gemini key)',
  },
  'setup.groqTipTitle': {'lo': '⚡ ຢາກໃຫ້ subtitle ຕົງຄຳ 100%?', 'th': '⚡ อยากให้ซับตรงคำ 100%?'},
  'setup.groqTipBody': {
    'lo': 'ໃສ່ Groq API key (ຟຣີ) ໃນ Settings → AI ຈະຈັບເວລາທຸກຄຳໃຫ້ຕົງສຽງເປ໊ະ',
    'th': 'ใส่ Groq API key (ฟรี) ในหน้า Settings → AI จะจับเวลาทุกคำให้ตรงเสียงเป๊ะ',
  },

  // Source/target language option labels
  'lang.opt.th': {'lo': '🇹🇭 ພາສາໄທ', 'th': '🇹🇭 ภาษาไทย'},
  'lang.opt.lo': {'lo': '🇱🇦 ພາສາລາວ', 'th': '🇱🇦 ภาษาลาว'},
  'lang.opt.en': {'lo': '🇬🇧 English', 'th': '🇬🇧 English'},
  'lang.opt.auto': {'lo': '🤖 Auto Detect', 'th': '🤖 Auto Detect'},
  'lang.src.th': {'lo': 'ສຽງເວົ້າພາສາໄທ', 'th': 'เสียงพูดภาษาไทย'},
  'lang.src.lo': {'lo': 'ສຽງເວົ້າພາສາລາວ', 'th': 'เสียงพูดภาษาลาว'},
  'lang.src.en': {'lo': 'English Speech', 'th': 'English Speech'},
  'lang.src.auto': {'lo': 'ກວດຫາອັດຕະໂນມັດ', 'th': 'ตรวจหาอัตโนมัติ'},
  'lang.tgt.lo': {'lo': 'ຊັບພາສາລາວ', 'th': 'ซับลาว'},
  'lang.tgt.th': {'lo': 'ຊັບໄທ', 'th': 'ซับไทย'},
  'lang.tgt.en': {'lo': 'English Sub', 'th': 'English Sub'},

  // Translation modes
  'mode.none': {'lo': 'ບໍ່ແປ', 'th': 'ไม่แปล'},
  'mode.none.sub': {'lo': 'ສະແດງພາສາເດີມ', 'th': 'แสดงภาษาเดิม'},
  'mode.translate': {'lo': 'ແປພາສາ', 'th': 'แปลภาษา'},
  'mode.translate.sub': {'lo': 'ສະແດງຊັບແປ', 'th': 'แสดงซับที่แปล'},
  'mode.bilingual': {'lo': 'ສອງພາສາ', 'th': 'สองภาษา'},
  'mode.bilingual.sub': {'lo': 'Bilingual (2 ແຖວ)', 'th': 'Bilingual (2 บรรทัด)'},

  // AI engines
  'engine.gemini': {'lo': '♊️ Gemini AI', 'th': '♊️ Gemini AI'},
  'engine.gemini.sub': {
    'lo': 'ແນະນຳສຳລັບຊັບລາວ (ແປໂດຍກົງ)',
    'th': 'แนะนำสำหรับซับ (แปลโดยตรง)',
  },
  'engine.groq': {'lo': '⚡️ Groq Whisper', 'th': '⚡️ Groq Whisper'},
  'engine.groq.sub': {'lo': 'ຖອດສຽງໄວສູງສຸດ', 'th': 'ถอดเสียงเร็วที่สุด'},
  'engine.whisper': {'lo': '🧠 OpenAI Whisper', 'th': '🧠 OpenAI Whisper'},
  'engine.whisper.sub': {'lo': 'ຈັບເວລາລະອຽດ', 'th': 'จับเวลาละเอียด'},
  'engine.needKey': {
    'lo': 'ກາລຸນາໃສ່ API Key ໃນໜ້າ Settings ກ່ອນ',
    'th': 'กรุณาใส่ API Key ในหน้า Settings ก่อน',
  },

  // Word split
  'split.none': {'lo': 'ບໍ່ແບ່ງ', 'th': 'ไม่แบ่ง'},
  'split.word': {'lo': 'ຄຳ', 'th': 'คำ'},

  // Pro dialog
  'pro.dialogBody': {
    'lo': 'ຟີເຈີນີ້ສຳລັບ PRO ເທົ່ານັ້ນ\nສະມັກ PRO 39,000 ກີບ/ເດືອນ ໃນໜ້າ "ຕັ້ງຄ່າ"',
    'th': 'ฟีเจอร์นี้สำหรับ PRO เท่านั้น\nสมัคร PRO ในหน้า "ตั้งค่า"',
  },
  'pro.upgrade': {'lo': 'Upgrade PRO', 'th': 'อัปเกรด PRO'},
};
