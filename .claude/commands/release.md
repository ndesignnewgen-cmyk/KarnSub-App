---
description: Build, copy, and ship KarnSub (web APK + Play AAB) end-to-end
---

# /release — KarnSub Release Agent

Ship a new build of KarnSub. Follow these steps exactly. Stop and report if any
step fails.

## Context (KarnSub project facts)
- Flutter project root: `C:/Users/Nou/Desktop/annie-kaydee/subtitle_app`
- Website repo (separate): `C:/Users/Nou/Desktop/annie-kaydee/website` (branch `gh-pages`)
- Two build flavours from ONE codebase:
  - **Web / self-distributed APK** (default = full slip/QR payment): `flutter build apk --release --target-platform android-arm64`
  - **Google Play AAB** (hides slip/QR, redeem-key only): `flutter build appbundle --release --dart-define=PLAY_STORE=true`
- NEVER embed the user's Gemini API key (BYOK). The only intentional embedded key is the Tenor v1 demo key `LIVDSRZULELA`.
- `lib/utils/sfx_mapper.dart` was hand-edited by the user — do NOT revert it.

## Steps
1. **Version**: if `$ARGUMENTS` contains a version (e.g. `1.1.3`), bump `version:` in `pubspec.yaml` (and the `+N` build number +1). Otherwise just +1 the build number.
2. **Analyze**: run `flutter analyze --no-pub lib/` and grep for `" error "`. If there are errors, STOP and fix or report.
3. **Build web APK**: `flutter build apk --release --target-platform android-arm64`
4. **Build Play AAB**: `flutter build appbundle --release --dart-define=PLAY_STORE=true`
5. **Copy artifacts**:
   - APK → `C:/Users/Nou/Desktop/KarnSub_v<version>.apk`
   - APK → `C:/Users/Nou/Desktop/annie-kaydee/website/KarnSub.apk`
   - AAB → `C:/Users/Nou/Desktop/KarnSub_PlayStore_v<version>.aab`
6. **Push web**: in the website repo, `git add KarnSub.apk` (+ any site changes), commit with a clear message ending in the Co-Authored-By line, then `git push origin gh-pages`.
7. **Report**: APK/AAB sizes, version, what changed, and a 1-line test instruction.

## 🎮 Live office sync (Star-Office-UI pixel dashboard)
If the Star-Office-UI dev dashboard is set up, drive the on-screen character to
match the real build. Run this at each phase (writes the office state.json):

```
python "C:/Users/Nou/Desktop/Star-Office-UI/set_state.py" <state> "<detail>"
```
Phase → state mapping:
- Start of /release        → `executing "Release: starting build…"`
- During analyze           → `syncing  "flutter analyze…"`
- During APK/AAB build     → `executing "Building APK + AAB…"`
- During copy + git push   → `syncing  "Pushing to gh-pages…"`
- Success (end)            → `idle     "Shipped v<version> ✓"`
- On ANY failure           → `error    "<short reason>"`

Valid states: idle, writing, receiving, replying, researching, executing, syncing, error.
If running set_state.py is blocked, fall back to writing
`C:/Users/Nou/Desktop/Star-Office-UI/state.json` directly as
`{"state":"...","detail":"...","progress":0,"updated_at":"<ISO now>"}`.
This is best-effort — never fail the release just because the office sync fails.

## Notes
- Builds are long — run them in the background and wait for completion.
- Confirm the website folder is `annie-kaydee/website` (NOT inside subtitle_app).
