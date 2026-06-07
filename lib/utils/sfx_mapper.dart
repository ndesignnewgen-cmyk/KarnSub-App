import 'dart:math';
import '../models/subtitle_style_model.dart';

class SfxMapper {
  static final _rnd = Random();
  static SfxType _rand(List<SfxType> types) => types[_rnd.nextInt(types.length)];

  static SfxType _pop() => _rand([SfxType.pop, SfxType.pop2, SfxType.pop3, SfxType.pop4, SfxType.pop5]);
  static SfxType _swoosh() => _rand([SfxType.swoosh, SfxType.swoosh2]);
  static SfxType _whoosh() => _rand([SfxType.whoosh, SfxType.whoosh2, SfxType.whoosh3, SfxType.whoosh4, SfxType.whoosh5, SfxType.whoosh6, SfxType.whoosh7, SfxType.whoosh8, SfxType.whoosh9, SfxType.whoosh10]);
  static SfxType _punch() => _rand([SfxType.punch, SfxType.punch2, SfxType.punch3, SfxType.punch4, SfxType.punch5]);
  static SfxType _slap() => _rand([SfxType.slap, SfxType.slap2]);
  static SfxType _wow() => _rand([SfxType.wow, SfxType.wow2]);
  static SfxType _camera() => _rand([SfxType.cameraShutter, SfxType.cameraShutter2, SfxType.cameraShutter3]);
  static SfxType _cash() => _rand([SfxType.cashRegister, SfxType.cashRegister2]);
  static SfxType _scratch() => _rand([SfxType.recordScratch, SfxType.recordScratch2]);
  static SfxType _squeak() => _rand([SfxType.squeak, SfxType.squeak2, SfxType.squeak3, SfxType.squeak4, SfxType.squeek]);
  static SfxType _ding() => _rand([SfxType.ding, SfxType.ding2]);
  static SfxType _badumtss() => _rand([SfxType.badumtss, SfxType.badumtss2]);

  /// Map an emoji string → SfxType (used after auto-emoji assigns emoji to segments).
  /// When [strict] is true, an unmatched emoji returns null instead of a generic
  /// Pop — so auto-SFX only adds a sound for emojis with a meaningful match
  /// (avoids spamming Pop everywhere).
  static SfxType? getSfxForEmoji(String emoji, {bool strict = false}) {
    if (emoji.isEmpty) return null;
    // ── ❤️ Love / Heart ──
    if (_has(emoji, ['❤️','🧡','💛','💚','💙','💜','🖤','🤍','🤎','💕','💗','💓','💞','💝','🥰','😍','😘','💋'])) return _pop();
    // ── 🔥 Fire / Hot / Energy ──
    if (_has(emoji, ['🔥','♨️','🌋','💢','😤','🥵'])) return _swoosh();
    // ── 🪄 Magic / Stars / Sparkle ──
    if (_has(emoji, ['🪄','✨','🌟','⭐','💫','🌠','🔮','🎩'])) return SfxType.magic;
    // ── 😂 Laugh / Fun ──
    if (_has(emoji, ['😂','🤣','😆','😄','😁','🤭','😝','🙃'])) return SfxType.laugh;
    // ── 😢 Sad / Cry ──
    if (_has(emoji, ['😢','😭','🥺','😿','💔','😔','😞','🤧'])) return SfxType.cricket;
    // ── 😮 Surprise / Shock ──
    if (_has(emoji, ['😮','😲','🤯','😱','😨','😦','🫢','👀'])) return _wow();
    // ── 💪 Power / Strong ──
    if (_has(emoji, ['💪','⚡','🦁','🐉','👊','🥊','🔱','💥'])) return _punch();
    // ── 🎉 Celebration / Win ──
    if (_has(emoji, ['🎉','🎊','🏆','🥳','🎈','🎆','🎇','🥂','🎖️'])) return SfxType.applause;
    // ── 🌬️ Wind / Nature / Calm ──
    if (_has(emoji, ['🌬️','💨','🌙','🌿','🍃','🌊','🌸','🕊️'])) return _whoosh();
    // ── 💡 Idea / Notification ──
    if (_has(emoji, ['💡','🔔','🔑','📢','📣','💬'])) return _ding();
    // ── 🚀 Speed / Movement ──
    if (_has(emoji, ['🚀','✈️','🏎️','⚡','🏃','💨'])) return _swoosh();
    // ── 🤖 Tech / Digital ──
    if (_has(emoji, ['🤖','💻','📱','🖥️','🔊'])) return _camera();
    if (_has(emoji, ['⌨️'])) return SfxType.typing;
    // ── 💧 Bubble / Water ──
    if (_has(emoji, ['💧','🫧','🌊','🐟','🐸'])) return _pop();
    // ── 🦆 Funny fail / Duck ──
    if (_has(emoji, ['🦆','🤡'])) return SfxType.quack;
    // ── 🎵 Music / Rhythm ──
    if (_has(emoji, ['🎵','🎶','🎸','🎤','🎼','🎹'])) return _ding();
    if (_has(emoji, ['🥁'])) return _badumtss();
    // ── 🐾 Bounce / Animal ──
    if (_has(emoji, ['🦘','🐇','🐰','⛹️','🏀','🪀'])) return SfxType.boing;
    // ── ❌ Error / Stop ──
    if (_has(emoji, ['❌','⚠️','🚫','🛑'])) return SfxType.buzzer;
    if (_has(emoji, ['🔇','📵'])) return _scratch();
    // ── ✅ Correct / Right ──
    if (_has(emoji, ['☑️','✅','✔️'])) return SfxType.correct;
    // ── 👆 Click / Select ──
    if (_has(emoji, ['👆','👉','🖱️','🔗'])) return _pop();
    // ── 💣 Shock / Impact ──
    if (_has(emoji, ['💣','🧨','💥'])) return SfxType.vineBoom;
    // ── 🤬 Swear / Angry ──
    if (_has(emoji, ['🤬','😡','😠'])) return SfxType.beep;
    // ── 👾 Glitch / Tech issue ──
    if (_has(emoji, ['👾','😵‍💫'])) return SfxType.glitch;
    // ── 📯 Airhorn / Hype ──
    if (_has(emoji, ['📯'])) return SfxType.airhorn;
    // ── Generic pop for any unmatched emoji (skipped in strict mode) ──
    return strict ? null : _pop();
  }

  /// Map a word (Lao/Thai/English) → SfxType.
  static SfxType? getSfxForWord(String word) {
    final clean = word.toLowerCase().trim().replaceAll(RegExp(r'[.,!?;:]'), '');
    if (clean.isEmpty) return null;

    // ── Emoji passthrough ──
    final emojiResult = getSfxForEmoji(clean);
    if (emojiResult != null && clean.runes.any((r) => r > 0x1F300)) return emojiResult;

    // ── Lao words ──
    if (['ຮັກ','ຫວານ','ຮ່ວນ','ງາມ','ຄຶດຮອດ'].contains(clean)) return _pop();
    if (['ຮ້ອນ','ແຮງ','ດຸ','ໄຟ','ລຸກ'].contains(clean)) return _swoosh();
    if (['ມະຫັດສະຈັນ','ມາຍາ','ວິເສດ','ສ້າງ','ຈຳລອງ'].contains(clean)) return SfxType.magic;
    if (['ຕົກໃຈ','ຊ໊ອກ','ຫະ','ໂອ້ຍ','ປ໊າດ','ຊ້ວ'].contains(clean)) return _wow();
    if (['ແຂງ','ເຂັ້ມ','ພະລັງ','ສຸດຍອດ','ຈ້ອງ'].contains(clean)) return _punch();
    if (['ຢ້ານ','ຫ້ວ','ໜ້ານ້ຳຕາ','ເສົ້າ','ໃຈຫັກ'].contains(clean)) return SfxType.cricket;
    if (['ຕະຫຼົກ','ຮ່າ','ຮ່າໆ'].contains(clean)) return SfxType.laugh;
    if (['ຄິດອອກ','ວ້າວ','ດີເລີດ','ແຈ່ມ'].contains(clean)) return _ding();
    if (['ສຳເລັດ','ຊະນະ','ເຢ້','ສະຫຼອງ','ລາງວັນ','ຖືກຕ້ອງ','ແມ່ນແລ້ວ'].contains(clean)) return SfxType.correct;
    if (['ໄວ','ແລ່ນ','ຟ້າວ','ດ່ວນ'].contains(clean)) return _swoosh();
    if (['ໃຫຍ່','ຍາວ','ລົມ'].contains(clean)) return _whoosh();
    if (['ຜິດ','ຢຸດ','ຫ້າມ','ຜິດພາດ','ບໍ່ແມ່ນ'].contains(clean)) return SfxType.buzzer;
    if (['ເຊັນເຊີ','ລະບົບ'].contains(clean)) return _camera();
    if (['ນ້ຳ','ຟອງ'].contains(clean)) return _pop();
    if (['ໂດດ','ເດັ້ງ'].contains(clean)) return SfxType.boing;
    if (['ກົດ','ເລືອກ','ຄລິກ','ຕໍ່ໄປ','ພິມ'].contains(clean)) return SfxType.typing;
    if (['ຕີ','ຕໍາ','ດັງ'].contains(clean)) return _slap();
    if (['ເງິນ','ລວຍ','ຂາຍ','ຊື້'].contains(clean)) return _cash();
    if (['ຕາຍ','ລະເບີດ','ຕູມ'].contains(clean)) return SfxType.vineBoom;
    if (['ປາດໂທ້','ຍິ່ງໃຫຍ່'].contains(clean)) return SfxType.airhorn;
    if (['ແປ້ກ','ມຸກແປ້ກ'].contains(clean)) return _badumtss();

    // ── English words ──
    if (['love','heart','sweet','cute','miss'].contains(clean)) return _pop();
    if (['fire','hot','burn','fierce','intense'].contains(clean)) return _swoosh();
    if (['magic','amazing','sparkle','spell'].contains(clean)) return SfxType.magic;
    if (['omg','shock','gasp','what','seriously'].contains(clean)) return _wow();
    if (['power','strong','beast','goat'].contains(clean)) return _punch();
    if (['sad','cry','tears','heartbreak'].contains(clean)) return SfxType.cricket;
    if (['lol','haha','funny','laugh'].contains(clean)) return SfxType.laugh;
    if (['idea','yes'].contains(clean)) return _ding();
    if (['win','success','champion','celebrate'].contains(clean)) return SfxType.applause;
    if (['correct','right','done'].contains(clean)) return SfxType.correct;
    if (['fast','run','speed','go'].contains(clean)) return _swoosh();
    if (['wind','calm','breeze','night'].contains(clean)) return _whoosh();
    if (['error','stop','wrong','fail'].contains(clean)) return SfxType.buzzer;
    if (['click','select','next','type','keyboard'].contains(clean)) return SfxType.typing;
    if (['boom','bang','hit'].contains(clean)) return SfxType.vineBoom;
    if (['money','cash','rich','buy'].contains(clean)) return _cash();
    if (['joke','pun'].contains(clean)) return _badumtss();
    if (['glitch','bug','hack'].contains(clean)) return SfxType.glitch;
    if (['swear','fuck','shit'].contains(clean)) return SfxType.beep;

    return null;
  }

  static bool _has(String s, List<String> emojis) =>
      emojis.any((e) => s.contains(e));
}
