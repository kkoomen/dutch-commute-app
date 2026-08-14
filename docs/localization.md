# Localization

All app-owned UI copy is translatable. Station names, train names,
directions, and other data returned by the NS API are **never** translated —
they are shown verbatim.

## How strings work

- English is the development language. Every user-facing string lives in
  `src/DutchCommute/en.lproj/Localizable.strings` with the English text as
  the key and value (`"Cancel" = "Cancel";`).
- SwiftUI `Text`, `Button`, `Label`, `Section`, and `navigationTitle`
  literals are already `LocalizedStringKey`s, so they resolve through the
  strings table automatically.
- Strings used in `String` contexts (status labels, weekday names, transport
  mode names, error messages, widget leg labels, ternary titles) go through
  `String(localized:)` — keys equal the English text, so a missing
  translation falls back to English.
- Interpolated strings use format specifiers in the table, e.g.
  `"Created %@"`, `"+%lld min"`, `"NS API returned HTTP %lld."`. Keep the
  specifier unchanged when translating.
- The table is compiled into **both** the app bundle and the widget
  extension bundle (each is a separate process with its own `Bundle.main`).

## What is deliberately not localized

- Station names, train product names ("IC 1234"), directions, times — all
  API/data values shown verbatim.
- Route strings built from station names (`"Utrecht → Amsterdam"`).

## Adding a language

Dutch (`nl`) is already set up as an example (see
`src/DutchCommute/nl.lproj/Localizable.strings`). To add another language:

1. Create `<lang>.lproj/Localizable.strings` (e.g. `de.lproj/`) with the
   same keys and translated values:
   ```strings
   "Cancel" = "Abbrechen";
   "On time" = "Pünktlich";
   "+%lld min" = "+%lld min";
   "Created %@" = "Erstellt %@";
   ```
   Keep the format specifiers (`%@`, `%lld`) unchanged.
2. In `src/DutchCommute.xcodeproj/project.pbxproj`:
   - add a `PBXFileReference` for the language (name `<lang>`, path
     `<lang>.lproj/Localizable.strings`, `lastKnownFileType =
     text.plist.strings`);
   - add it as a child of the `Localizable.strings` `PBXVariantGroup`;
   - add `<lang>` to the project's `knownRegions`.
   No other project changes are needed — both targets pick the new variant
   up automatically.
3. Verify with `plutil -lint` and `xcodebuild build` (see
   `docs/development.md`).

## Keeping the table in sync

After adding or changing UI copy, run:

```sh
xcrun extractLocStrings -o /tmp/strings src/DutchCommute src/DutchCommuteWidget
```

and reconcile the output with `en.lproj/Localizable.strings` (genstrings
extracts literals; `String(localized:)` call sites must be updated by hand).
A missing key never crashes — the English text is shown as fallback.
