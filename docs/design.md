# Design

## Brand palette

| Role | Hex | Usage |
|---|---|---|
| Dark background | `#083B4C` | Navigation bars, home-screen widget background |
| Light background | `#4CC9C0` | Page background behind cards and forms |
| Primary | `#19B8B0` | Accent: buttons, selected states, checkmarks, tint |
| Primary pressed | `#12938D` | Primary buttons while pressed |
| White | `#F4FFFF` | Text/icons on dark surfaces |
| Dark text | `#06343F` | Text on light surfaces |

## Where the colors live

- `src/DutchCommute/Design/Palette.swift` — the `Palette` enum (all roles),
  `Color(hex:)`, and the `brandedNavigationBar()` view modifier (dark teal
  bar, white titles).
- `src/DutchCommute/Design/PrimaryButtonStyle.swift` — the filled primary
  button (white label on `primary`, `primaryPressed` while pressed, dimmed
  when disabled).
- Both files are compiled into the app **and** the widget target.
- `LoadingView` — launch screen: `darkBackground` → `lightBackground`
  gradient (bottom to top) with the logo (`LoadingLogo` in the asset
  catalog) centered; shown ~1.2 s on launch (`DutchCommuteApp`).

## Rules

- The app forces light appearance (`.preferredColorScheme(.light)` in
  `RootView`); the palette is light-mode only. Lock Screen accessory widgets
  keep system materials (they follow the wallpaper).
- Status colors (green/orange/red/gray for on time / delayed / cancelled /
  unknown) are semantic and intentionally not part of the palette.
- API data (station names, train names, times) is never recolored.
- Use `Palette.*` tokens, not raw hex, in views.
