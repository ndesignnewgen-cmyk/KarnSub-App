# KarnSub Pro Editor — ແຜນພັດທະນາທັງໝົດ

> ສ້າງ: 2026-10-09 · ສະຖານະ: **ແຜນ (ຍັງບໍ່ເລີ່ມ)**
> ໜ້າຕາທີ່ອອກແບບໄວ້ (8 ໜ້າຈໍ): https://claude.ai/artifact/Cuofcc2jtQXqJEoJamyvag
> ແຮງບັນດານໃຈ: OpenCut classic (MIT) — ເອົາແຕ່ **ແນວຄິດ/ການອອກແບບ**, ບໍ່ copy code (ຄົນລະພາສາ: TS/React vs Flutter/Kotlin)

---

## 1. ເປົ້າໝາຍ ແລະ ຫຼັກການ

**ຕຳແໜ່ງ:** ບໍ່ແມ່ນ "CapCut ລາວ" ແຕ່ແມ່ນ **"ແອັບທີ່ເຮັດຄລິບພາສາລາວໄວທີ່ສຸດ"** — ຕັດຕໍ່ໄດ້ພໍ ຈົນຜູ້ໃຊ້ບໍ່ຕ້ອງໜີໄປ CapCut,
ແລະ ຊະນະດ້ວຍສິ່ງທີ່ CapCut ບໍ່ມີ (ຊັບລາວ AI, ແປໄທ→ລາວ, ສຽງ AI ລາວ, ຟອນ/ຕັດຄຳລາວ, ຈ່າຍ QR ລາວ).

**ຫຼັກການ 6 ຂໍ້:**
1. **ວັດແທກກ່ອນສ້າງ** — ໄລຍະ P (ຕົ້ນແບບ) ຕ້ອງຜ່ານກ່ອນ ຈຶ່ງລົງທຶນໄລຍະອື່ນ.
2. **Project ເກົ່າຂອງຜູ້ໃຊ້ຫ້າມເສຍ** — ທຸກການປ່ຽນ model ຕ້ອງມີ migration + backup.
3. **Preview = Export** — engine ດຽວກັນວາດທັງສອງ (ສິ່ງທີ່ເຫັນ ຄືສິ່ງທີ່ໄດ້).
4. **ອອກເປັນຂັ້ນໆ** — ທຸກໄລຍະອອກ test APK ກ່ອນ → ຜູ້ໃຊ້ຢືນຢັນ → ຈຶ່ງອອກ Play Store.
5. **Android ກ່ອນ** — iOS ບໍ່ມີ native code ເລີຍ (AppDelegate 13 ແຖວ); ເປັນໂຄງການແຍກພາຍຫຼັງ.
6. **ບໍ່ສ້າງສິ່ງທີ່ບໍ່ມີຄົນໃຊ້** — ໄລຍະ 4–5 ເລືອກເຮັດຕາມຄຳຂໍຂອງຜູ້ໃຊ້ແທ້.
7. **ວິທີໃຊ້ຄ້າຍ CapCut (ຜູ້ໃຊ້ຄຸ້ນມືທັນທີ)** — playhead ຢູ່ກາງຈໍ ແລະ timeline ເລື່ອນຜ່ານ; ແຖບເຄື່ອງມືລຸ່ມປ່ຽນຕາມສິ່ງທີ່ເລືອກ (+ ປຸ່ມ ‹ ກັບຄືນ);
   "+" ທ້າຍວິດີໂອຫຼັກ; ແທຣັກຮອງເປັນເສັ້ນບາງ; ແຖບເທິງ ✕ · 1080P ▾ · ສົ່ງອອກ; undo/redo ຢູ່ແຖວລຸ່ມ preview; ທ່າມືຄືກັນ (pinch-zoom, ລາກມືຈັບ trim, ກົດຄ້າງລາກ).
   ⚠️ ເອົາແຕ່ວິທີໃຊ້ — icon, ສີ, ໂລໂກ້, template, ສະຕິກເກີ ຕ້ອງເປັນຂອງ KarnSub (ບໍ່ copy ຊັບສິນຂອງ CapCut).

### ເປົ້າໝາຍຄວາມລື່ນ (ວັດໃນມືຖືລະດັບກາງ ເຊັ່ນ Helio G85 / Snapdragon 680, RAM 4–6 GB)

| ຕົວວັດ | ເປົ້າໝາຍ |
|---|---|
| Preview 1080p, 3 ຊັ້ນ (ວິດີໂອ + PiP + ຂໍ້ຄວາມ/ຊັບ) | ≥ 30 fps, ບໍ່ຕົກ frame ເກີນ 2% |
| ປ່ຽນ clip ລະຫວ່າງຫຼິ້ນ | ບໍ່ມີ frame ດຳ / ບໍ່ສະດຸດ |
| ລາກ timeline (scrub) | ເຫັນພາບປ່ຽນພາຍໃນ 100 ms |
| ກົດປຸ່ມ / ລາກ clip ເທິງ timeline | UI 60 fps (frame ≤ 16 ms) |
| ສົ່ງອອກ 45 ວິ 1080p30, 3 ຊັ້ນ | ≤ 60 ວິ |
| ເປີດ project 5 ນາທີ, 7 ແທຣັກ | ≤ 1.5 ວິ |

---

## 2. ສະພາບປັດຈຸບັນ (ກວດຈາກ code 2026-10-09)

| ສ່ວນ | ສະພາບ | ຜົນ |
|---|---|---|
| `lib/screens/editor_screen.dart` | **14,372 ແຖວ**, `setState` 154 ບ່ອນ, `RepaintBoundary` 0 | ແກ້ຍາກ, ທຸກ setState rebuild ທັງໜ້າ → ກະຕຸກ |
| Model (`subtitle_style_model.dart`) | ອີງຊັບເປັນຫຼັກ: `clips` + `removedRanges` + `splitPointsMs` + `imageOverlays` + zoom/fade/shake ແຍກກັນ | ບໍ່ແມ່ນ timeline ຫຼາຍແທຣັກແທ້ |
| Undo (`ProjectSnapshot`) | copy ທັງ list ທຸກຄັ້ງ | ໃຊ້ RAM ຫຼາຍເມື່ອ project ໃຫຍ່ |
| ບ່ອນເກັບ project (`storage_service.dart`) | **ທຸກ project ຢູ່ໃນ SharedPreferences string ດຽວ**; parse ຜິດ → `return []` | ⚠️ ຄວາມສ່ຽງສູນເສຍທຸກ project; ຊ້າເມື່ອໃຫຍ່ |
| `ClipPlayer.kt` | ExoPlayer playlist ແບບ gapless → Flutter Texture | ✅ ພື້ນຖານດີ, ໃຊ້ຕໍ່ໄດ້ |
| `VideoExporterGl.kt` | GPU: decoder → OES texture → GL → encoder; overlay ເປັນ Bitmap | ✅ ພື້ນຖານຂອງ engine ໃໝ່ |
| `MainActivity.kt` (3,129 ແຖວ) | method channel ທັງໝົດ + CPU export pipeline (fallback) | ຕ້ອງແຍກໄຟລ໌ຄືກັນ |
| ຄວາມສາມາດທີ່ມີແລ້ວ | AI ຊັບ/ແປ, Auto-Cut, SFX, B-roll, TTS, keyframe overlay, zoom/fade/shake, ເພງ+duck, blur bg | ✅ ຈຸດແຂງ — ຕ້ອງຮັກສາໄວ້ທັງໝົດ |

---

## 3. ພາບລວມໄລຍະ

```
T  ແຕະໃຫ້ຕົງ (Tap Sync) — ເຮັດກ່ອນໄດ້, ບໍ່ຂຶ້ນກັບ model ໃໝ່  ~3 ອາທິດ   → v1.3.x  (ລາຍລະອຽດ: TAP_SYNC_PLAN.md)
P  ຕົ້ນແບບ engine preview (ຕັດສິນ GO / NO-GO)        ~2 ອາທິດ
0  ຄວາມປອດໄພ + ແບ່ງ code + ປັບຄວາມລື່ນ UI            ~3 ອາທິດ   → v1.4 (ຜູ້ໃຊ້ບໍ່ເຫັນຕ່າງ ແຕ່ລື່ນຂຶ້ນ)
1  Model timeline ໃໝ່ + migration + undo ແບບ command  ~3 ອາທິດ   → (ລວມກັບ 2)
2  Timeline ຫຼາຍແທຣັກ + ການແກ້ໄຂພື້ນຖານ              ~4 ອາທິດ   → v1.5
3  Engine render ດຽວ (preview = export) + proxy        ~5 ອາທິດ   → v1.6
4  ຄວາມສາມາດສ້າງສັນ (text, shape, mask, blend, speed, bezier) ~5 ອາທິດ → v1.7
5  Transition, ຟິວເຕີ, ປັບແສງສີ, reverse, freeze      ~4 ອາທິດ   → v1.8
X  (ຂະໜານ, ທາງເລືອກ) ສົ່ງອອກເປັນ CapCut draft        ~2 ອາທິດ
```
ລວມປະມານ **6–7 ເດືອນ** (ຄາດຄະເນ — ຈະປັບຫຼັງໄລຍະ P).

---

## 4. ລາຍລະອຽດແຕ່ລະໄລຍະ

### ໄລຍະ P — ຕົ້ນແບບ engine preview (GO / NO-GO)

**ເປົ້າໝາຍ:** ພິສູດວ່າ native GL compositor ສະແດງຫຼາຍຊັ້ນໄດ້ລື່ນໃນມືຖືແທ້ ກ່ອນລົງທຶນຫຼາຍເດືອນ.

ວຽກ:
- [ ] Branch ໃໝ່ `proto/preview-engine` (ບໍ່ແຕະ code ທີ່ໃຊ້ງານ)
- [ ] `PreviewEngine.kt`: ExoPlayer 2 ຕົວ (ຫຼັກ playlist + PiP) → SurfaceTexture → GL ລວມເປັນ 1 frame → Flutter `Texture`
- [ ] ຂໍ້ຄວາມ/ຊັບ: Flutter ວາດເປັນຮູບ (ຮອງຮັບການປະສົມສະຫຼະລາວຖືກຕ້ອງ) → ສົ່ງເປັນ texture, cache ໄວ້ຈົນກວ່າຂໍ້ຄວາມປ່ຽນ
- [ ] ໜ້າທົດສອບງ່າຍໆ: ຫຼິ້ນ / ຢຸດ / scrub / ສະແດງ fps ແລະ frame ທີ່ຕົກ
- [ ] ທົດສອບ **ຢ່າງໜ້ອຍ 3 ເຄື່ອງ**: ລຸ້ນຕ່ຳ (RAM 3–4 GB), ລຸ້ນກາງ, ລຸ້ນດີ

**ເງື່ອນໄຂ GO:** ລຸ້ນກາງ ≥ 30 fps ກັບ 3 ຊັ້ນ, scrub ≤ 100 ms, ບໍ່ crash 10 ນາທີ.
**ຖ້າ NO-GO:** ຫຼຸດເປົ້າ (PiP 1 ຊັ້ນ, preview 720p) ຫຼື ເລືອກທາງ X (CapCut draft) ແທນ.

### ໄລຍະ 0 — ຄວາມປອດໄພ + ແບ່ງ code + ຄວາມລື່ນ UI

ຄວາມປອດໄພ:
- [ ] Commit ວຽກທີ່ຄ້າງ (ຕອນນີ້ມີ 6 ໄຟລ໌ modified + `sticker_service.dart` ໃໝ່)
- [ ] **ຍ້າຍບ່ອນເກັບ project**: 1 ໄຟລ໌ JSON ຕໍ່ 1 project (`<appDocs>/projects/<id>.json`) + ດັດຊະນີ; ຂຽນແບບ atomic (temp → rename); ອ່ານ SharedPreferences ເກົ່າຄັ້ງດຽວແລ້ວຍ້າຍ
- [ ] parse ຜິດ → ເກັບໄຟລ໌ເສຍໄວ້ `*.corrupt` + ຂ້າມສະເພາະ project ນັ້ນ (ບໍ່ໃຫ້ຫາຍທັງໝົດ)
- [ ] ໃສ່ `schemaVersion` ໃນ JSON ທຸກ project

ແບ່ງ `editor_screen.dart` (ບໍ່ປ່ຽນພຶດຕິກຳ):
```
lib/editor/
  editor_screen.dart          ← ໂຄງຫຼັກ + state ລວມ (ເປົ້າ < 800 ແຖວ)
  state/editor_controller.dart← ChangeNotifier: selection, playhead, mode
  preview/preview_view.dart
  preview/overlay_gestures.dart
  timeline/timeline_view.dart
  timeline/track_row.dart
  timeline/painters.dart      ← _RulerPainter, _WaveformPainter, _TimeRulerPainter, _OnsetPainter
  toolbar/main_toolbar.dart
  panels/  (subtitle_style, sfx, overlay, zoom_fade_shake, audio_mixer, keyframe, auto_tools…)
```
ຄວາມລື່ນ:
- [ ] Playhead + ເວລາ ໃຊ້ `ValueNotifier` ແທນ `setState` ທັງໜ້າ
- [ ] `RepaintBoundary` ຄອບ preview, timeline, toolbar ແຍກກັນ
- [ ] Timeline ໃຊ້ `CustomPainter` + ວາດສະເພາະສ່ວນທີ່ເຫັນ
- [ ] ວັດ: Flutter DevTools (profile mode) ກ່ອນ/ຫຼັງ ໃນເຄື່ອງລຸ້ນກາງ

ແບ່ງ `MainActivity.kt`: ຍ້າຍແຕ່ລະກຸ່ມ method ໄປໄຟລ໌ຂອງມັນ (Audio, Export, Media, Thumbnail).

**ສຳເລັດເມື່ອ:** `flutter analyze` ສະອາດ, ທົດສອບມືຕາມ checklist (ຂໍ້ 6) ຜ່ານໝົດ, project ເກົ່າເປີດໄດ້ຄືເກົ່າ.

### ໄລຍະ 1 — Model timeline ໃໝ່ + migration + undo

Model ໃໝ່ (Dart, ຮ່າງ):
```dart
class Timeline { List<Track> tracks; int durationMs; CanvasSpec canvas; }
class Track { String id; TrackKind kind; bool muted, locked, hidden; List<Element> elements; }
enum TrackKind { mainVideo, video, text, subtitle, sticker, shape, audio, sfx, music, voice }

sealed class Element {
  String id; int startMs; int durationMs;          // ຕຳແໜ່ງເທິງ timeline
  Transform transform; List<Keyframe> keyframes;  // x, y, scale, rotate, opacity
  List<EffectRef> effects; BlendMode blend; MaskSpec? mask;
}
class VideoElement extends Element { String src; int trimInMs; SpeedSpec speed; double volume; bool reversed; }
class ImageElement / TextElement / SubtitleElement / ShapeElement / AudioElement extends Element {...}
class Transition { String fromId, toId; String type; int durationMs; }
```
Migration (schemaVersion 1 → 2):

| ເກົ່າ | ໃໝ່ |
|---|---|
| `videoPath` / `clips[]` + `removedRanges` + `splitPointsMs` | ແທຣັກ `mainVideo` ທີ່ມີ `VideoElement` ຕາມລຳດັບ (ຕັດຊ່ວງທີ່ຖືກລຶບອອກ) |
| `segments[]` | ແທຣັກ `subtitle` (ຮັກສາ style/karaoke/bilingual ທັງໝົດ) |
| `imageOverlays[]` (+ keyframes) | ແທຣັກ `video`/`sticker` ຕາມປະເພດ |
| `zoomEffects` / `fadeEffects` / `shakeEffects` | `effects` ຂອງ element ຫຼັກທີ່ກວມຊ່ວງນັ້ນ |
| `sfxBlocks` / `bgMusicPath` / `aiVoicePath` | ແທຣັກ `sfx` / `music` / `voice` (ຮັກສາ volume, mute, duck) |

- [ ] Migration ເປັນ pure function + unit test ກັບ project ຕົວຢ່າງແທ້ຫຼາຍແບບ
- [ ] ເກັບ JSON v1 ໄວ້ເປັນ backup ຢ່າງໜ້ອຍ 2 ເວີຊັນ
- [ ] Undo/redo ແບບ **command** (add/remove/move/trim/split/update-prop) + ລວມຫຼາຍ command ເປັນ 1 ຂັ້ນ (batch)
- [ ] ບໍລິການ AI ທັງໝົດ (ຊັບ, Auto-Cut, Auto SFX, B-roll, Hook) ປ່ຽນໄປຂຽນລົງ model ໃໝ່

### ໄລຍະ 2 — Timeline ຫຼາຍແທຣັກ + ການແກ້ໄຂພື້ນຖານ  → v1.5

- [ ] UI timeline ຫຼາຍແທຣັກ (ໜ້າຈໍ 1 ໃນການອອກແບບ): ປ້າຍແທຣັກ, mute/lock/hide
- [ ] ລາກ element ຂ້າມແທຣັກ, trim ດ້ວຍມືຈັບ, ແຍກ (split) ທີ່ playhead
- [ ] Snap (ຂອບ clip, playhead, bookmark), Ripple edit (ເປີດ/ປິດໄດ້)
- [ ] ເລືອກຫຼາຍອັນ, ສຳເນົາ/ວາງ, duplicate, ລຶບ
- [ ] Bookmark ເທິງ ruler
- [ ] ເພີ່ມ PiP ວິດີໂອ (ຈຳກັດ **2 ຊັ້ນ** ໃນລຸ້ນຕ່ຳ, 3 ໃນລຸ້ນກາງຂຶ້ນໄປ — ກວດຈຳນວນ decoder ຕອນເປີດແອັບ)
- [ ] Preview ໃຊ້ `PreviewEngine` ຈາກໄລຍະ P

### ໄລຍະ 3 — Engine render ດຽວ + proxy  → v1.6

- [ ] `RenderGraph`: Dart ສົ່ງ "ສິ່ງທີ່ຕ້ອງວາດທີ່ເວລາ t" (ຊັ້ນ, transform, effect) ໄປ native
- [ ] Compositor GL ດຽວ ໃຊ້ທັງ preview (Texture) ແລະ export (encoder Surface) — ຂະຫຍາຍຈາກ `VideoExporterGl.kt`
- [ ] Shader: transform, opacity, blend mode, mask (ໄລຍະ 4 ຕໍ່ຍອດ)
- [ ] ຂໍ້ຄວາມ/ຊັບ: ວາດໃນ Flutter → texture cache (ຮັບປະກັນການສະແດງຜົນພາສາລາວຖືກ)
- [ ] **Proxy**: ວິດີໂອ > 720p ສ້າງສຳເນົາ 540p ໃນພື້ນຫຼັງ ສຳລັບແກ້ໄຂ; export ໃຊ້ຕົ້ນສະບັບ
- [ ] Thumbnail filmstrip cache ລົງ disk
- [ ] Scrub: ລາກ = seek keyframe ໃກ້ສຸດ (ໄວ), ປ່ອຍ = seek ແນ່ນອນ
- [ ] ໜ້າສົ່ງອອກ (ໜ້າຈໍ 8): 720p–4K, 24/30/60 fps, ຄຸນນະພາບ, HEVC, .srt ນຳ, % + ເວລາທີ່ເຫຼືອ
- [ ] ເກັບ CPU pipeline ເກົ່າໄວ້ເປັນ fallback 1–2 ເວີຊັນ ແລ້ວຈຶ່ງລຶບ

### ໄລຍະ 4 — ຄວາມສາມາດສ້າງສັນ  → v1.7

- [ ] Text layer ອິດສະຫຼະ + ພື້ນຫຼັງ/ເງົາ/ຂອບ + animation (ໜ້າຈໍ 4)
- [ ] ຮູບຊົງ: ສີ່ຫຼ່ຽມ, ວົງມົນ, ຫຼາຍຫຼ່ຽມ, ດາວ, ລູກສອນ + ເສັ້ນຂອບ
- [ ] Mask 10 ແບບ + ຂອບນຸ້ມ + ກັບດ້ານ (ໜ້າຈໍ 3) — ອີງການອອກແບບ `masks/` ຂອງ OpenCut
- [ ] Blend mode 6+ ແບບ + ຄວາມທຶບ
- [ ] ຄວາມໄວ: ຄົງທີ່ 0.1×–10× + ເສັ້ນໂຄ້ງ (preset Montage/Hero/Bullet/Flash) + ຮັກສາ pitch (Media3 Sonic) (ໜ້າຈໍ 2)
- [ ] Keyframe ທຸກ property + ເສັ້ນ Bezier + preset ຂອງຂ້ອຍ + copy/paste keyframe (ໜ້າຈໍ 5)
- [ ] ພື້ນຫຼັງ: ສີ / gradient / blur (ມີແລ້ວ)
- [ ] ນຳເຂົ້າ SRT / ASS ເປັນແທຣັກຊັບ

### ໄລຍະ 5 — Transition + ຟິວເຕີ + ປັບແສງສີ  → v1.8

- [ ] Transition 8+ ແບບ (Dissolve, ເລື່ອນ 4 ທິດ, Zoom, ໝູນ, Glitch, Flash) + ໄລຍະເວລາ + ໃຊ້ກັບທຸກ clip (ໜ້າຈໍ 6)
- [ ] ຟິວເຕີ (LUT) + ຄວາມແຮງ; ປັບແສງສີ: ຄວາມສະຫວ່າງ, contrast, ຄວາມອີ່ມ, ອຸນຫະພູມ, ເງົາ, vignette + ເລື່ອນປຽບທຽບກ່ອນ/ຫຼັງ (ໜ້າຈໍ 7)
- [ ] Reverse (render ເປັນໄຟລ໌ໃນພື້ນຫຼັງ), Freeze frame

### ທາງ X (ຂະໜານ, ທາງເລືອກ) — ສົ່ງອອກເປັນ CapCut draft

ໃຫ້ຜູ້ໃຊ້ສ້າງຊັບລາວໃນ KarnSub ແລ້ວເປີດຕໍ່ໃນ CapCut. ໃຊ້ຄວາມຮູ້ຮູບແບບ draft JSON ຈາກໂຄງການ AI CapCut Editor.
⚠️ ຍັງບໍ່ໄດ້ທົດລອງວ່າ CapCut ມືຖືນຳເຂົ້າ draft ຈາກພາຍນອກໄດ້ບໍ — ຕ້ອງກວດກ່ອນ.

---

## 5. ຟີເຈີ Free / PRO (ຮ່າງ — ລໍຖ້າຕັດສິນ)

| Free | PRO |
|---|---|
| Timeline ຫຼາຍແທຣັກ, ແຍກ/trim/ສຳເນົາ, ຂໍ້ຄວາມ, ຮູບຊົງ, transition ພື້ນຖານ 3 ແບບ, export 720p/1080p (ມີ watermark ຕາມເດີມ) | PiP ຫຼາຍຊັ້ນ, mask, blend, ຄວາມໄວແບບເສັ້ນໂຄ້ງ, bezier, transition/ຟິວເຕີທັງໝົດ, 2K/4K/60fps, ບໍ່ມີ watermark |

---

## 6. ການທົດສອບ (ທຸກໄລຍະ)

- `flutter analyze` + unit test (migration, command undo, retime math)
- Checklist ມື (ເຄື່ອງລຸ້ນກາງ): ສ້າງ project ໃໝ່ → AI ຊັບ → Auto-Cut → ເພີ່ມ SFX/ເພງ/B-roll → keyframe → undo/redo 20 ຄັ້ງ → ສົ່ງອອກ → ເປີດ project ເກົ່າ (v1.3.0) → ປິດ/ເປີດແອັບ
- ວັດຕົວເລກຕາມຕາຕະລາງເປົ້າໝາຍ (ຂໍ້ 1) ແລະ ບັນທຶກໄວ້ທຸກເວີຊັນ
- Test APK → ຜູ້ໃຊ້ທົດສອບ → ຢືນຢັນ → Play Store (closed testing ກ່ອນ)

## 7. ຄວາມສ່ຽງ

| ຄວາມສ່ຽງ | ໂອກາດ | ວິທີຮັບມື |
|---|---|---|
| Migration ທຳລາຍ project ເກົ່າ | ກາງ | backup v1, unit test, ຂ້າມສະເພາະ project ເສຍ |
| Decoder ບໍ່ພໍສຳລັບ PiP | ສູງ (ລຸ້ນຕ່ຳ) | ກວດ decoder, ຈຳກັດຊັ້ນ, proxy |
| GL ຕ່າງກັນແຕ່ລະຍີ່ຫໍ້ (Mali/Adreno/PowerVR) | ກາງ | ທົດສອບ 3+ ເຄື່ອງ, fallback CPU pipeline |
| ຂໍ້ຄວາມລາວສະແດງຜິດໃນ native | ກາງ | ວາດຂໍ້ຄວາມໃນ Flutter ແລ້ວສົ່ງເປັນ texture |
| ໃຊ້ເວລາເກີນຄາດ | ສູງ | gate ທີ່ໄລຍະ P, ອອກເປັນຂັ້ນ, ຕັດໄລຍະ 4–5 ໄດ້ |
| ແອັບໜັກຂຶ້ນ / ກິນແບັດ | ກາງ | proxy, ປິດ engine ເມື່ອອອກຈາກ editor |

## 8. ສິ່ງທີ່ຕ້ອງຕັດສິນໃຈ (ເຈົ້າຂອງແອັບ)

1. ມືຖືທົດສອບ 3 ເຄື່ອງ: ລຸ້ນໃດແດ່ (ໃຫ້ກົງກັບລູກຄ້າແທ້)?
2. PiP ສູງສຸດຈັກຊັ້ນ?
3. ຈະເຮັດທາງ X (CapCut draft) ຂະໜານບໍ?
4. ແບ່ງ Free / PRO ຕາມຕາຕະລາງຂໍ້ 5 ບໍ?
5. iOS: ເຮັດຫຼັງ v1.8 ຫຼື ບໍ່ເຮັດ?

---

## ບັນທຶກຄວາມຄືບໜ້າ

| ວັນທີ | ໄລຍະ | ສິ່ງທີ່ເຮັດ |
|---|---|---|
| 2026-10-09 | — | ສ້າງແຜນ + ອອກແບບ 8 ໜ້າຈໍ |
| 2026-10-09 | — | ປັບການອອກແບບເປັນວິທີໃຊ້ແບບ CapCut (10 ໜ້າຈໍ) + ເພີ່ມແຜນ Tap Sync (ໄລຍະ T) |
