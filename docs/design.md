# Design

## Brand palette

Every role adapts to the current color scheme (light / dark):

| Role | Light | Dark | Usage |
|---|---|---|---|
| Background | `#F8FAFC` | `#0E0F11` | Page background behind cards and forms |
| Surface | `#FFFFFF` | `#1D2324` | Cards, list rows, sheets |
| Surface secondary | `#D6DBD9` | `#202F2F` | Unselected day toggles, mode tiles |
| Text primary | `#0C0D0F` | `#E1DFDB` | Titles and body text |
| Text secondary | `#606569` | `#8D9193` | Subtitles |
| Text tertiary | `#ACB0B0` | `#525D5E` | Captions, muted labels |
| Primary | `#007572` | `#5ABAB1` | Accent: buttons, selected states, checkmarks, tint |
| Primary pressed | `#00605E` | `#4AA29B` | Primary buttons while pressed |
| On accent | `#FFFFFF` | `#0E0F11` | Text on accent fills |
| Status on time | `#5AA58B` | `#6CB87A` | "On time" status |

## Where the colors live

- `src/DutchCommute/Design/Palette.swift` — the `Palette` enum. Colors are
  dynamic (`UIColor` providers), so they follow the active color scheme
  automatically, in the app and the widget extension.
- `src/DutchCommute/Design/Appearance.swift` — `Appearance` (system / light /
  dark), persisted via `AppStorage("appearance")`.
- `src/DutchCommute/Design/PrimaryButtonStyle.swift` — the filled primary
  button (label on `primary`, `primaryPressed` while pressed, dimmed when
  disabled).

## Appearance toggle

- Defaults to **System**: the app follows the device setting (dark system →
  dark app, light system → light app).
- The home screen's top bar has a sun/moon button (sun in light appearance,
  moon in dark) that opens a menu: System / Light / Dark. The choice is
  persisted and applied via `preferredColorScheme` in `DutchCommuteApp`.
- The widget extension always follows the system setting (it has no access
  to the app's override).

## Rules

- Status colors for delayed / cancelled / unknown are semantic system colors
  (orange / red / gray) — only "on time" uses the brand green.
- API data (station names, train names, times) is never recolored.
- Use `Palette.*` tokens, not raw hex, in views.
- The launch screen always uses the teal splash gradient
  (`splashDark` → `splashLight`), independent of the color scheme.
