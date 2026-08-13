# AGENTS.md — TravelScreen

## Project context

TravelScreen is a native iOS app (Swift / SwiftUI / WidgetKit) that answers one
question at a glance from the Lock Screen: **"Does my train run, and is it
delayed?"**

The user configures their daily journey — origin, destination, weekdays, and an
approximate departure time. A Lock Screen widget then shows the next matching
train with its live status, e.g.:

```
🚆 IC 1234
Utrecht → Amsterdam
18:42 · On time
```

Live data comes from the official NS Reisinformatie API. No scraping, no
unofficial sources.

## Goals

- Lock Screen widget shows the user's relevant upcoming train: route, departure
  time, train information, and status (on time / delayed +N min / cancelled).
- Minimal configuration: origin, destination, days, approximate departure time.
- Correct live status from the official NS API.
- Simple, focused, maintainable codebase.

## Non-goals

- No maps, ticketing, push notifications, or complex trip planning UI.
- No scraping of NS websites or apps.
- No over-engineering: keep networking, models, app state, persistence, and
  widget code small and clearly separated.

## Architecture (summary — see `docs/architecture.md`)

- Two targets: the app (`TravelScreen`) and a widget extension
  (`TravelScreenWidget`).
- Layers: networking (`NSAPIClient`), models (Codable DTOs + small domain
  models), app state + persistence (App Group shared container), widget
  (TimelineProvider).
- Journey configuration lives in the shared container so both the app and the
  widget can read it.
- Status derivation and journey selection are pure functions, unit-testable
  without network access.

## Behavior (summary — see `docs/behavior.md`)

- User configures a journey: origin, destination, weekdays, approximate
  departure time.
- The app finds the relevant upcoming train; the widget shows route, departure
  time, train information, and status.
- Status: on time / delayed (+N min) / cancelled.

## API (summary — see `docs/api.md`)

- Official NS Reisinformatie API v3 (`/trips`, `/departures`).
- API key is read from the `NS_API_KEY` environment variable, supplied via
  git-ignored local configuration. **Never hard-code or commit the API key.**
- Unit tests use bundled JSON fixtures; never hit the live API in tests.

## Development conventions

- Follow current Swift and Apple platform practices (modern Swift concurrency,
  SwiftUI, WidgetKit).
- Keep code readable and small; one clear responsibility per file.
- No dependencies without a clear reason — Foundation, SwiftUI, and WidgetKit
  should suffice.
- Update `docs/` in the same change whenever behavior or architecture changes.
- Prefer simple solutions; avoid unnecessary features or over-engineering.

## Testing expectations

- Unit tests for: API decoding (fixtures), status mapping (on time / delayed /
  cancelled), journey selection, and edge cases (no trains, last train of day,
  crossing midnight, missing fields, nulls).
- Tests are deterministic: mocked API responses and injected clocks, no real
  network.
- Before finishing work: run the full test suite, then report results and any
  limitations.

## Rules for future work

1. Never commit `NS_API_KEY` or any other secret. Keys live only in
   git-ignored local configuration.
2. Use only the official NS Reisinformatie API. Never scrape NS websites or
   apps.
3. Keep the app and widget simple; question any new feature or dependency
   before adding it.
4. When behavior or architecture changes, update the relevant docs in the same
   change.
5. Run tests before finishing; report limitations honestly.
6. Widgets must degrade gracefully: no network → show last known status or
   "unavailable", never crash.
