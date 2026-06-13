---
description: Quick QA — analyze + release build sanity check (no shipping)
---

# /qa — KarnSub QA Agent

Verify the project is healthy WITHOUT shipping. Use after edits, before /release.

## Steps
1. `flutter analyze --no-pub lib/` → grep for `" error "`. List any errors (with file:line) and offer to fix. Warnings/infos are OK to note but not block.
2. Build the web APK to confirm it compiles: `flutter build apk --release --target-platform android-arm64` (run in background, wait).
3. If `$ARGUMENTS` says `play` or `full`, also build the Play AAB: `flutter build appbundle --release --dart-define=PLAY_STORE=true`.
4. Report: ✅/❌ analyze, ✅/❌ build, APK size, and any errors found.

## 🎮 Live office sync (Star-Office-UI)
If the pixel dashboard is set up, mirror QA progress on the character:
```
python "C:/Users/Nou/Desktop/Star-Office-UI/set_state.py" <state> "<detail>"
```
- Start            → `researching "QA: analyze + build check…"`
- Build running    → `executing  "Building APK…"`
- All passed (end) → `idle       "QA passed ✓ 0 errors"`
- Errors found     → `error      "QA: <n> errors"`

Best-effort only — never block QA if the office sync fails.

## Notes
- Do NOT copy artifacts or push anything — this is a check only.
- If a build fails, show the last ~20 lines of output and pinpoint the cause.
