---
description: Find & fill missing Lao/Thai translations in i18n.dart
---

# /i18n-check — KarnSub Localization Agent

KarnSub uses a custom i18n map in `lib/i18n/i18n.dart`. Every key must have BOTH
`'lo'` (Lao) and `'th'` (Thai). UI strings are looked up with `tr('key')` /
`tr('key', {params})`.

## Steps
1. Read `lib/i18n/i18n.dart`. Find any entry missing `'lo'` or `'th'` (or with an empty value, or with an obviously-untranslated value like English left in the `'th'`/`'lo'` slot).
2. Grep `lib/` for `tr('...')` / `tr("...")` calls and list any keys used in code but NOT defined in the map (missing keys → would show the raw key to users).
3. For each gap, propose the correct Lao + Thai translation. Keep wording short, natural, and consistent with neighboring entries. Preserve `{param}` placeholders exactly.
4. If `$ARGUMENTS` is `fix`, apply the additions/edits directly. Otherwise just report the list for approval.
5. Do a quick `flutter analyze --no-pub lib/i18n/i18n.dart` after edits.

## Notes
- Lao = `'lo'`, Thai = `'th'`. Match the script — never put Thai text in `'lo'` or vice-versa.
- Many strings use emoji + numbers; keep those intact.
- Don't touch unrelated keys.
