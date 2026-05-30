import '../models/subtitle_style_model.dart';

class SfxMapper {
  /// Map an emoji string → SfxType (used after auto-emoji assigns emoji to segments).
  static SfxType? getSfxForEmoji(String emoji) {
    if (emoji.isEmpty) return null;
    // ── ❤️ Love / Heart ──
    if (_has(emoji, ['❤️','🧡','💛','💚','💙','💜','🖤','🤍','🤎','💕','💗','💓','💞','💝','🥰','😍','😘','💋'])) return SfxType.heart;
    // ── 🔥 Fire / Hot / Energy ──
    if (_has(emoji, ['🔥','♨️','🌋','💢','😤','🥵'])) return SfxType.fire;
    // ── 🪄 Magic / Stars / Sparkle ──
    if (_has(emoji, ['🪄','✨','🌟','⭐','💫','🌠','🔮','🎩'])) return SfxType.magic;
    // ── 😂 Laugh / Fun ──
    if (_has(emoji, ['😂','🤣','😆','😄','😁','🤭','😝','🙃'])) return SfxType.laugh;
    // ── 😢 Sad / Cry ──
    if (_has(emoji, ['😢','😭','🥺','😿','💔','😔','😞','🤧'])) return SfxType.sad;
    // ── 😮 Surprise / Shock ──
    if (_has(emoji, ['😮','😲','🤯','😱','😨','😦','🫢','👀'])) return SfxType.surprise;
    // ── 💪 Power / Strong ──
    if (_has(emoji, ['💪','⚡','🦁','🐉','👊','🥊','🔱','💥'])) return SfxType.power;
    // ── 🎉 Celebration / Win ──
    if (_has(emoji, ['🎉','🎊','🏆','🥳','🎈','🎆','🎇','🥂','🎖️'])) return SfxType.tada;
    // ── 🌬️ Wind / Nature / Calm ──
    if (_has(emoji, ['🌬️','💨','🌙','🌿','🍃','🌊','🌸','🕊️'])) return SfxType.wind;
    // ── 💡 Idea / Notification ──
    if (_has(emoji, ['💡','🔔','🔑','📢','📣','💬'])) return SfxType.ding;
    // ── 🚀 Speed / Movement ──
    if (_has(emoji, ['🚀','✈️','🏎️','⚡','🏃','💨'])) return SfxType.whoosh;
    // ── 🤖 Tech / Digital ──
    if (_has(emoji, ['🤖','💻','📱','⌨️','🖥️','🔊'])) return SfxType.beep;
    // ── 💧 Bubble / Water ──
    if (_has(emoji, ['💧','🫧','🌊','🐟','🐸','🦆'])) return SfxType.bubble;
    // ── 🎵 Music / Rhythm ──
    if (_has(emoji, ['🎵','🎶','🎸','🥁','🎤','🎼','🎹'])) return SfxType.chime;
    // ── 🐾 Bounce / Animal ──
    if (_has(emoji, ['🦘','🐸','🐇','🐰','⛹️','🏀'])) return SfxType.bounce;
    // ── ❌ Error / Stop ──
    if (_has(emoji, ['❌','⚠️','🚫','🛑','🔇','📵'])) return SfxType.glitch;
    // ── 👆 Click / Select ──
    if (_has(emoji, ['👆','👉','🖱️','☑️','✅','🔗'])) return SfxType.click;
    // ── 🥊 Drum / Impact ──
    if (_has(emoji, ['🥊','💥','🪘','🎯','💣','🧨'])) return SfxType.drum;
    // ── Generic pop for any unmatched emoji ──
    return SfxType.pop;
  }

  /// Map a word (Lao/Thai/English) → SfxType.
  static SfxType? getSfxForWord(String word) {
    final clean = word.toLowerCase().trim().replaceAll(RegExp(r'[.,!?;:]'), '');
    if (clean.isEmpty) return null;

    // ── Emoji passthrough ──
    final emojiResult = getSfxForEmoji(clean);
    if (emojiResult != null && clean.runes.any((r) => r > 0x1F300)) return emojiResult;

    // ── Lao words ──
    if (['ຮັກ','ຫວານ','ຮ່ວນ','ງາມ','ຄຶດຮອດ'].contains(clean)) return SfxType.heart;
    if (['ຮ້ອນ','ແຮງ','ດຸ','ໄຟ','ລຸກ'].contains(clean)) return SfxType.fire;
    if (['ມະຫັດສະຈັນ','ມາຍາ','ວິເສດ','ສ້າງ','ຈຳລອງ'].contains(clean)) return SfxType.magic;
    if (['ຕົກໃຈ','ຊ໊ອກ','ຫະ','ໂອ້ຍ','ປ໊າດ','ຕາຍ','ຊ້ວ'].contains(clean)) return SfxType.surprise;
    if (['ແຂງ','ເຂັ້ມ','ພະລັງ','ສຸດຍອດ','ຈ້ອງ'].contains(clean)) return SfxType.power;
    if (['ຕົກໃຈ','ຢ້ານ','ຫ້ວ','ໜ້ານ້ຳຕາ','ສຸດ','ເສົ້າ','ໃຈຫັກ'].contains(clean)) return SfxType.sad;
    if (['ຕົກໃຈ2','ຫ້ວ','ໜ້ານ້ຳຕາ'].contains(clean)) return SfxType.sad;
    if (['ຕະຫຼົກ','ຮ່າ','ຮ່າໆ','ອຸ້ຍ'].contains(clean)) return SfxType.laugh;
    if (['ຄິດອອກ','ວ້າວ','ດີເລີດ','ແຈ່ມ'].contains(clean)) return SfxType.ding;
    if (['ສຸດຍອດ','ສວຍງາມ','ພິເສດ'].contains(clean)) return SfxType.chime;
    if (['ສຳເລັດ','ຊະນະ','ເຢ້','ສະຫຼອງ','ລາງວັນ'].contains(clean)) return SfxType.tada;
    if (['ໄວ','ແລ່ນ','ຟ້າວ','ດ່ວນ'].contains(clean)) return SfxType.swoosh;
    if (['ໃຫຍ່','ຍາວ','ລົມ'].contains(clean)) return SfxType.wind;
    if (['ຜິດ','ຢຸດ','ຫ້າມ','ຜິດພາດ'].contains(clean)) return SfxType.glitch;
    if (['ເຊັນເຊີ','ລະບົບ'].contains(clean)) return SfxType.beep;
    if (['ຕະຫຼົກ','ນ້ຳ','ຟອງ'].contains(clean)) return SfxType.bubble;
    if (['ໂດດ','ເດັ້ງ','ມ່ວນ'].contains(clean)) return SfxType.bounce;
    if (['ກົດ','ເລືອກ','ຄລິກ','ຕໍ່ໄປ'].contains(clean)) return SfxType.click;
    if (['ຕີ','ຕໍາ','ດັງ'].contains(clean)) return SfxType.drum;

    // ── English words ──
    if (['love','heart','sweet','cute','miss'].contains(clean)) return SfxType.heart;
    if (['fire','hot','burn','fierce','intense'].contains(clean)) return SfxType.fire;
    if (['magic','wow','amazing','sparkle','spell'].contains(clean)) return SfxType.magic;
    if (['omg','shock','gasp','what','seriously'].contains(clean)) return SfxType.surprise;
    if (['power','strong','beast','goat'].contains(clean)) return SfxType.power;
    if (['sad','cry','tears','heartbreak'].contains(clean)) return SfxType.sad;
    if (['lol','haha','funny','laugh'].contains(clean)) return SfxType.laugh;
    if (['idea','yes','done'].contains(clean)) return SfxType.ding;
    if (['win','success','champion','celebrate'].contains(clean)) return SfxType.tada;
    if (['fast','run','speed','go'].contains(clean)) return SfxType.swoosh;
    if (['wind','calm','breeze','night'].contains(clean)) return SfxType.wind;
    if (['error','stop','wrong','fail'].contains(clean)) return SfxType.glitch;
    if (['click','select','next'].contains(clean)) return SfxType.click;
    if (['boom','bang','hit'].contains(clean)) return SfxType.drum;

    return null;
  }

  static bool _has(String s, List<String> emojis) =>
      emojis.any((e) => s.contains(e));
}
