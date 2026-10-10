# KarnSub Pro Editor — ແຜນພັດທະນາທັງໝົດ

> ສ້າງ: 2026-10-09 · ສະຖານະ: **ກຳລັງສ້າງ — ໄລຍະ T,0,1,2 ແລ້ວ; 4–5 ບາງສ່ວນ; P ລໍທົດສອບໃນມືຖື**
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
- [x] ຢູ່ branch `feat/tap-sync` ແຕ່ແຍກອອກຈາກ code ທີ່ໃຊ້ງານ (ເຂົ້າໄດ້ທາງ Settings → "ທົດສອບ engine ໃໝ່" ເທົ່ານັ້ນ)
- [x] `PreviewEngine.kt` (2026-10-10): ExoPlayer 2 ຕົວ (ຫຼັກ + PiP) → OES SurfaceTexture → GL thread ລວມເປັນ 1 frame ຕໍ່ vsync → Flutter `Texture` (compile ຜ່ານ, **ຍັງບໍ່ໄດ້ run ໃນມືຖື**)
- [x] ຂໍ້ຄວາມ: Flutter ວາດ (ພາສາລາວຖືກ) → PNG → texture
- [x] ໜ້າທົດສອບ (`preview_bench_screen.dart`): ຫຼິ້ນ/ຢຸດ/scrub + render fps, video fps, % frame ຊ້າ, seek latency, ເວລາ run — ສີຂຽວ/ແດງຕາມເງື່ອນໄຂ GO
- [ ] ທົດສອບ **ຢ່າງໜ້ອຍ 3 ເຄື່ອງ**: ລຸ້ນຕ່ຳ (RAM 3–4 GB), ລຸ້ນກາງ, ລຸ້ນດີ ← **ລໍມືຖື**

**ເງື່ອນໄຂ GO:** ລຸ້ນກາງ ≥ 30 fps ກັບ 3 ຊັ້ນ, scrub ≤ 100 ms, ບໍ່ crash 10 ນາທີ.
**ຖ້າ NO-GO:** ຫຼຸດເປົ້າ (PiP 1 ຊັ້ນ, preview 720p) ຫຼື ເລືອກທາງ X (CapCut draft) ແທນ.

### ໄລຍະ 0 — ຄວາມປອດໄພ + ແບ່ງ code + ຄວາມລື່ນ UI

ຄວາມປອດໄພ:
- [x] Commit ວຽກທີ່ຄ້າງ (sticker picker commit ແລ້ວ d644ef4)
- [x] **ຍ້າຍບ່ອນເກັບ project** (2026-10-10, `lib/services/project_store.dart`): 1 ໄຟລ໌ JSON ຕໍ່ 1 project (`<appDocs>/projects/<id>.json`) + `index.json`; ຂຽນແບບ atomic (temp → rename) + ເກັບເວີຊັນກ່ອນເປັນ `.bak`; ຂຽນສະເພາະ project ທີ່ປ່ຽນ; save ຕໍ່ຄິວ (ບໍ່ແຂ່ງກັນ); ຍ້າຍຈາກ SharedPreferences ຄັ້ງດຽວ + ເກັບຂໍ້ມູນດິບໄວ້ `legacy_prefs_backup.json`
- [x] parse ຜິດ → ລອງ `.bak` ກ່ອນ, ບໍ່ດັ່ງນັ້ນເກັບໄຟລ໌ເສຍໄວ້ `*.corrupt-*` + ຂ້າມສະເພາະ project ນັ້ນ; ໄຟລ໌ທີ່ບໍ່ຢູ່ໃນ index ກໍຍັງໂຫຼດ; ໄຟລ໌ schema ໃໝ່ກວ່າ = ບໍ່ແຕະ
- [x] ໃສ່ `schemaVersion` ໃນ JSON ທຸກ project (wrapper `{schemaVersion, project}`) — 17 test ໃນ `test/project_store_test.dart`

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
**ເຮັດແລ້ວ (2026-10-10), ແບບທີ່ຕ່າງຈາກຮ່າງ:** ແບ່ງເປັນ `part` files + `extension _X on _EditorScreenState`
ໃນ `lib/screens/editor/` (playback, effects, text_tools, preview, style, timeline, transcript, auto, overlays, export, painters).
ຍ້າຍ code ແບບກົງໂຕດ້ວຍ script (ກວດແລ້ວວ່າທຸກແຖວຢູ່ຄົບ, ບໍ່ຊ້ຳ), `editor_screen.dart` ເຫຼືອ **578 ແຖວ** (fields + initState/build/dispose).
static 6 ອັນຍ້າຍໄປເປັນ top-level. ຂັ້ນຕໍ່ໄປ (ເມື່ອແກ້ສ່ວນໃດ): ຍ້າຍ state ຂອງສ່ວນນັ້ນອອກເປັນ controller/widget ຂອງມັນເອງ.

ຄວາມລື່ນ (⏸ ລໍມືຖືລຸ້ນກາງ — ຕ້ອງວັດກ່ອນ/ຫຼັງດ້ວຍ DevTools ຕາມຫຼັກການ "ວັດແທກກ່ອນສ້າງ"):
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

- [x] Migration ເປັນ pure function + unit test (2026-10-10, `lib/timeline/migrate_v1.dart`): ຊ່ວງທີ່ຕັດ → clip ແຍກໃນແທຣັກຫຼັກ, ທຸກເວລາຍ້າຍຈາກ timeline ເດີມ → timeline ຫຼັງຕັດ (`time_map.dart`); ສິ່ງທີ່ຢູ່ໃນຊ່ວງຕັດທັງໝົດ ເກັບໄວ້ `settings.v1Dropped` (ກູ້ຄືນໄດ້)
- [x] ເກັບ JSON v1 ໄວ້ເປັນ backup: ໄຟລ໌ project ຍັງເປັນ v1 + `.bak` (ProjectStore); v2 ຢູ່ຄຽງຂ້າງ
- [x] Undo/redo (`lib/timeline/timeline_ops.dart`): model ເປັນ immutable → ແຕ່ລະຂັ້ນເກັບແຕ່ reference (element ທີ່ບໍ່ປ່ຽນ share ກັນ, ບໍ່ copy ທັງ list) + batch (ລາກ 1 ຄັ້ງ = 1 ຂັ້ນ) + ຈຳກັດ 100 ຂັ້ນ; ops: add/remove(ripple)/move/trim/split/update/duplicate/tracks/transitions/snap
- [x] **ຂົວ v2 → v1** (`project_v1.dart`): editor ໃໝ່ໃຊ້ preview/export ເກົ່າໄດ້ທັນທີ ຈົນກວ່າ engine ໄລຍະ 3 ມາ; ສິ່ງທີ່ v1 ສະແດງບໍ່ໄດ້ ຖືກລາຍງານ (`lossy`)
- [ ] ບໍລິການ AI ຂຽນລົງ model ໃໝ່ໂດຍກົງ — ຕອນນີ້ຜ່ານຂົວ v1 (AI ຍັງຂຽນ segment v1 ແລ້ວ migrate); ປ່ຽນເມື່ອ editor ເກົ່າຖືກປົດ

Test: 41 (model/ops/history) + 5 (ຂົວ round-trip v1→v2→v1).

### ໄລຍະ 2 — Timeline ຫຼາຍແທຣັກ + ການແກ້ໄຂພື້ນຖານ  → v1.5

**Beta ສ້າງແລ້ວ (2026-10-10):** ໜ້າ "Pro Editor (beta)" ແຍກຕ່າງຫາກ (`lib/pro_editor/`), ເປີດຈາກ Home → ⋮ → "ເປີດໃນ Pro Editor (beta)".
editor ເກົ່າຍັງເປັນຄ່າເລີ່ມຕົ້ນ. ບັນທຶກກັບເປັນ v1 + `timelineV2` (ຜ່ານຂົວ) → editor ເກົ່າ/ສົ່ງອອກ ໃຊ້ project ດຽວກັນໄດ້;
ຖ້າ editor ເກົ່າແກ້ project ຫຼັງຈາກນັ້ນ (fingerprint ປ່ຽນ) → ສ້າງ timeline ໃໝ່ຈາກ v1. Test: 16 (controller) + 10 (ໜ້າຈໍ).
- [x] UI timeline ຫຼາຍແທຣັກ: playhead ກາງຈໍ, ruler, ສີຕາມປະເພດ, mute ທີ່ຫົວແທຣັກຫຼັກ, ກົດຄ້າງ → mute/lock/hide
- [x] ລາກ element ຂ້າມແທຣັກ (ກົດຄ້າງ), trim ດ້ວຍມືຈັບ, ແຍກ (split) ທີ່ playhead
- [x] Snap (ຂອບ element, playhead, bookmark), Ripple edit (ເປີດ/ປິດໄດ້)
- [~] ສຳເນົາ/ວາງ, duplicate, ລຶບ ✅ — ເລືອກຫຼາຍອັນມີໃນ controller ແຕ່ຍັງບໍ່ມີທ່າທາງໃນ UI
- [x] Bookmark ເທິງ ruler
- [x] ເພີ່ມ PiP ວິດີໂອ (Free 1 ຊັ້ນ, PRO 2 ຊັ້ນ) + ຮູບ/ສະຕິກເກີ + ເພງ + ຕໍ່ clip ທ້າຍແທຣັກຫຼັກ (+)
- [ ] Preview ໃຊ້ `PreviewEngine` ຈາກໄລຍະ P — ຕອນນີ້ preview ປະກອບໃນ Flutter (`pro_preview.dart`): ວິດີໂອຫຼັກຫຼິ້ນແທ້, ສະຕິກເກີ/ຊັບ/zoom/fade ສະແດງ, **PiP ວິດີໂອຍັງເປັນກ່ອງແທນ (ບໍ່ຫຼິ້ນ)**
- ຄວາມໄວ, Mask ເທິງວິດີໂອ, ຟິວເຕີ ມີປຸ່ມແຕ່ສະແດງ "ກຳລັງມາ" (ລໍ engine ໃໝ່)

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

**ສ້າງແລ້ວບາງສ່ວນ (2026-10-10) ເທິງ exporter ເກົ່າ:** ຂໍ້ຄວາມ/ຮູບຊົງ/ຮູບທີ່ມີ mask ຖືກວາດເປັນ PNG (`lib/timeline/layer_render.dart`,
ໃຊ້ painter ດຽວກັນທັງ preview ແລະ export → ພາສາລາວສະແດງຖືກ) ແລ້ວສົ່ງເປັນ image overlay ພ້ອມ keyframe. ສ່ວນທີ່ຕ້ອງການ engine ໃໝ່ (ໄລຍະ 3) ຍັງລໍ.
- [x] Text layer ອິດສະຫຼະ + ພື້ນຫຼັງ/ເງົາ/ຂອບ (ໜ້າຈໍ 4); animation ເຂົ້າ/ອອກ 4 ແບບ (ຈາງ, ເລື່ອນຂຶ້ນ, ເລື່ອນຊ້າຍ, ເດັ້ງ) ສ້າງເປັນ keyframe
- [x] ຮູບຊົງ: ສີ່ຫຼ່ຽມ, ວົງມົນ, ຫ້າຫຼ່ຽມ, ດາວ, ລູກສອນ + ເສັ້ນຂອບ
- [~] Mask 7 ແບບ + ຂອບນຸ້ມ + ກັບດ້ານ — **ສະເພາະຮູບ**; mask ເທິງວິດີໂອ ລໍ engine ໃໝ່
- [ ] Blend mode 6+ ແບບ — ລໍ engine ໃໝ່ (ຄວາມທຶບມີແລ້ວຜ່ານ keyframe)
- [ ] ຄວາມໄວ: ຄົງທີ່ + ເສັ້ນໂຄ້ງ + ຮັກສາ pitch — ລໍ engine ໃໝ່
- [x] Keyframe x/y/ຂະໜາດ/ໝູນ/ຄວາມທຶບ + Bezier + preset + copy/paste keyframe (ໜ້າຈໍ 5); ລາກ/ບີບ/ໝູນ layer ເທິງວິດີໂອໂດຍກົງ
- [ ] ພື້ນຫຼັງ: ສີ / gradient / blur (ມີແລ້ວ)
- [ ] ນຳເຂົ້າ SRT / ASS ເປັນແທຣັກຊັບ

### ໄລຍະ 5 — Transition + ຟິວເຕີ + ປັບແສງສີ  → v1.8

- [~] Transition: **ມືດລົງ, Zoom, ສັ່ນ** ໃຊ້ໄດ້ ແລະ ສົ່ງອອກໄດ້ (ແປງເປັນ effect ຂອງ exporter ເກົ່າ) + ໄລຍະເວລາ + ໃຊ້ກັບທຸກ clip (ໜ້າຈໍ 6);
  Dissolve/ເລື່ອນ/Glitch/Flash ສະແດງ "ກຳລັງມາ" — ລໍ engine ໃໝ່
- [ ] ຟິວເຕີ (LUT) + ຄວາມແຮງ; ປັບແສງສີ: ຄວາມສະຫວ່າງ, contrast, ຄວາມອີ່ມ, ອຸນຫະພູມ, ເງົາ, vignette + ເລື່ອນປຽບທຽບກ່ອນ/ຫຼັງ (ໜ້າຈໍ 7)
- [ ] Reverse (render ເປັນໄຟລ໌ໃນພື້ນຫຼັງ), Freeze frame

### ທາງ X (ຂະໜານ, ທາງເລືອກ) — ສົ່ງອອກເປັນ CapCut draft

ໃຫ້ຜູ້ໃຊ້ສ້າງຊັບລາວໃນ KarnSub ແລ້ວເປີດຕໍ່ໃນ CapCut. ໃຊ້ຄວາມຮູ້ຮູບແບບ draft JSON ຈາກໂຄງການ AI CapCut Editor.
⚠️ ຍັງບໍ່ໄດ້ທົດລອງວ່າ CapCut ມືຖືນຳເຂົ້າ draft ຈາກພາຍນອກໄດ້ບໍ — ຕ້ອງກວດກ່ອນ.

---

## 5. ຟີເຈີ Free / PRO (ຕັດສິນແລ້ວ 2026-10-10)

| Free | PRO |
|---|---|
| Timeline ຫຼາຍແທຣັກ, ແຍກ/trim/ສຳເນົາ, ຂໍ້ຄວາມ, ຮູບຊົງ, PiP 1 ຊັ້ນ, transition ພື້ນຖານ 3 ແບບ, export 720p/1080p (ມີ watermark ຕາມເດີມ), ແຕະໃຫ້ຕົງທີລະປະໂຫຍກ | PiP 2 ຊັ້ນ, mask, blend, ຄວາມໄວແບບເສັ້ນໂຄ້ງ, bezier, transition/ຟິວເຕີທັງໝົດ, 2K/4K/60fps, ບໍ່ມີ watermark, ດູດເຂົ້າສຽງ (snap), karaoke ທີລະຄຳ |

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

## 8. ການຕັດສິນໃຈ (ສະຫຼຸບແລ້ວ 2026-10-10 — ເຈົ້າຂອງແອັບມອບໃຫ້ Claude ຕັດສິນ)

1. **ມືຖືທົດສອບ 3 ເຄື່ອງ** — ໃຫ້ກວມ GPU ທັງ 3 ຕະກູນ (PowerVR / Mali / Adreno):
   - **ລຸ້ນຕ່ຳ:** Redmi A3 ຫຼື ເຄື່ອງ Helio G36 (PowerVR, RAM 3–4 GB) — ກໍລະນີຮ້າຍສຸດ
   - **ລຸ້ນກາງ = ເຄື່ອງຕັດສິນ GO/NO-GO:** ເຄື່ອງ Helio G85 (Mali-G52, RAM 4–6 GB) ເຊັ່ນ Redmi 13C / Galaxy A05 — ຊິບທີ່ພົບຫຼາຍທີ່ສຸດໃນມືຖືລາຄາຖືກຢູ່ລາວ
   - **ລຸ້ນດີ:** ມືຖືຂອງເຈົ້າຂອງແອັບເອງ. ຖ້າບໍ່ແມ່ນ Snapdragon ໃຫ້ຢືມເຄື່ອງ Snapdragon (Adreno) ມາທົດສອບເພີ່ມ
   - ⚠️ ກວດຊິບໃນສະເປັກກ່ອນຊື້ທຸກຄັ້ງ (ລຸ້ນດຽວກັນບາງປະເທດໃຊ້ຊິບຕ່າງກັນ)
2. **PiP ສູງສຸດ:** Free 1 ຊັ້ນ, PRO 2 ຊັ້ນ. ເຄື່ອງທີ່ decoder ບໍ່ພໍ ຈຳກັດເປັນ 1 ອັດຕະໂນມັດ. ຈະເປີດ 3 ຊັ້ນໃນເຄື່ອງແຮງ **ສະເພາະເມື່ອ** ຕົວເລກຈາກໄລຍະ P ຜ່ານ (ເລີ່ມແບບລະວັງ ແລ້ວຄ່ອຍເພີ່ມ ດີກວ່າສັນຍາແລ້ວກະຕຸກ)
3. **ທາງ X (CapCut draft): ບໍ່ເຮັດຂະໜານ.** ຍັງບໍ່ຮູ້ວ່າ CapCut ມືຖືນຳເຂົ້າ draft ໄດ້ບໍ, ແລະ ມັນພາຜູ້ໃຊ້ໜີໄປ CapCut ເຊິ່ງຂັດກັບຕຳແໜ່ງຂອງແອັບ. ເກັບໄວ້ເປັນ **ແຜນສຳຮອງ ຖ້າໄລຍະ P ໄດ້ NO-GO** ເທົ່ານັ້ນ
4. **Free / PRO:** ໃຊ້ຕາຕະລາງຂໍ້ 5 ຕາມຮ່າງ. ແຕະໃຫ້ຕົງ: ແຕະທີລະປະໂຫຍກ + ວາງບົດເອງ + ປັບຕາມມື + ເຕືອນ BT = **ຟຣີ**; ດູດເຂົ້າສຽງ (snap) + karaoke ທີລະຄຳ = **PRO**
5. **iOS: ບໍ່ເຮັດກ່ອນ v1.8.** ຕ້ອງຂຽນ native ໃໝ່ທັງໝົດ (ExoPlayer/GL ທີ່ເປັນ Kotlin → AVFoundation/Metal) ແລະ ຕະຫຼາດລາວເປັນ Android ສ່ວນໃຫຍ່. ຫຼັງ v1.8 ຈຶ່ງປະເມີນອີກຄັ້ງຕາມຄຳຂໍຂອງຜູ້ໃຊ້ແທ້
6. **ໂໝດເລີ່ມຕົ້ນຂອງແຕະໃຫ້ຕົງ:** ກົດຄ້າງ (ຈັບຊ່ວງງຽບໄດ້ຖືກ). ແອັບຈື່ໂໝດທີ່ຜູ້ໃຊ້ເລືອກຄັ້ງລ່າສຸດ. ໂໝດ karaoke ທີລະຄຳ ເລີ່ມຕົ້ນເປັນ **ແຕະ** (ຄຳຮ້ອງຕໍ່ເນື່ອງ ບໍ່ມີຊ່ວງງຽບ)

**ລຳດັບເຮັດວຽກ:** ໄລຍະ T (ແຕະໃຫ້ຕົງ) ກ່ອນ → ໄລຍະ P. ຊື້/ຫາເຄື່ອງທົດສອບໄວ້ລະຫວ່າງເຮັດໄລຍະ T.

---

## ບັນທຶກຄວາມຄືບໜ້າ

| ວັນທີ | ໄລຍະ | ສິ່ງທີ່ເຮັດ |
|---|---|---|
| 2026-10-09 | — | ສ້າງແຜນ + ອອກແບບ 8 ໜ້າຈໍ |
| 2026-10-09 | — | ປັບການອອກແບບເປັນວິທີໃຊ້ແບບ CapCut (10 ໜ້າຈໍ) + ເພີ່ມແຜນ Tap Sync (ໄລຍະ T) |
| 2026-10-10 | — | ຕັດສິນທັງ 6 ຂໍ້ທີ່ຄ້າງ (ຂໍ້ 8): ເຄື່ອງທົດສອບ, PiP 1/2, ບໍ່ເຮັດທາງ X, Free/PRO, iOS ຫຼັງ v1.8, ກົດຄ້າງເປັນຄ່າເລີ່ມຕົ້ນ |
| 2026-10-10 | T | ຂຽນ Tap Sync T1–T6 ຄົບ (branch `feat/tap-sync`), 63 test ຜ່ານ — ລໍທົດສອບໃນມືຖືແທ້ ກ່ອນເລີ່ມໄລຍະ P |
| 2026-10-10 | 0 | ບ່ອນເກັບ project ແບບໄຟລ໌ (ປອດໄພ) + ແບ່ງ editor_screen.dart 14,425 → 578 ແຖວ (11 part files); 80 test ຜ່ານ. ຄວາມລື່ນ + ແບ່ງ MainActivity.kt ລໍມືຖືທົດສອບ |
| 2026-10-10 | 1 | Model v2 + migration + undo + ຂົວ v2→v1 (`lib/timeline/`) |
| 2026-10-10 | 2 | Pro Editor (beta) ຫຼາຍແທຣັກ (`lib/pro_editor/`), ເປີດຈາກ Home ⋮ |
| 2026-10-10 | P | ຕົ້ນແບບ PreviewEngine.kt + ໜ້າວັດຜົນ — ລໍມືຖືເພື່ອຕັດສິນ GO/NO-GO. ທັງໝົດ 152 test ຜ່ານ |
| 2026-10-10 | 2 | ຕັດຕໍ່ກ່ອນ ແລ້ວຈຶ່ງເຮັດຊັບ AI ຈາກສຽງທີ່ຕັດແລ້ວ (ແບບ CapCut); ປຸ່ມ "ຕັດຕໍ່ຄລິບ" ໃນ Home; ໜ້າຕາຕາມແບບ 01–02 (filmstrip, ແຖບບາງ, ເຄື່ອງໝາຍ transition) |
| 2026-10-10 | 2 | **ແກ້ບັກສົ່ງອອກ:** ຫຼາຍ clip ສົ່ງອອກຜິດວິດີໂອ → `ExportPlan` (ໄຟລ໌ດຽວ + ຊ່ວງທີ່ຕັດ, ຫຼື merge ກ່ອນ); ຊັບ/SFX/effect ຕິດຕາມ clip ເມື່ອ trim/ລຶບ (`TimelineOps.relink`) |
| 2026-10-10 | 4–5 | ຂໍ້ຄວາມ, ຮູບຊົງ, mask ຮູບ, keyframe + ລາກເທິງວິດີໂອ, animation ເຂົ້າ/ອອກ, transition ມືດ/Zoom/ສັ່ນ — ເທິງ exporter ເກົ່າ. 194 test ຜ່ານ. APK `KarnSub-1.3.0-phase45-TEST.apk` |
