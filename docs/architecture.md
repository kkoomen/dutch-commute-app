# Architecture

## Targets

- **TravelScreen** — the app. Configures the journey, writes it to the shared
  container, and triggers widget reloads.
- **TravelScreenWidget** — the WidgetKit extension. Reads the journey
  configuration, fetches live data, and renders the Lock Screen widget.

Both targets share an App Group so configuration can flow from app to widget.
(Exact group identifier, e.g. `group.<bundle-id>.travelscreen`, is decided
when the Xcode project is created.)

## Layers

```
┌────────────────────────────┐
│ SwiftUI views (app)        │  config form, journey preview
├────────────────────────────┤
│ App state / persistence    │  JourneyConfig store (App Group)
├────────────────────────────┤
│ Domain logic               │  TrainStatus, JourneySelection (pure)
├────────────────────────────┤
│ Models                     │  Codable DTOs ↔ domain models
├────────────────────────────┤
│ Networking                 │  NSAPIClient (URLSession)
├────────────────────────────┤
│ NS Reisinformatie API      │
└────────────────────────────┘

┌────────────────────────────┐
│ Widget views               │  accessoryInline / accessoryRectangular
├────────────────────────────┤
│ TimelineProvider           │  fetches via NSAPIClient, builds entries
├────────────────────────────┤
│ Domain logic + Models      │  shared with app target
└────────────────────────────┘
```

- **Networking** (`NSAPIClient`): thin URLSession wrapper for the NS API.
  Injectable transport so tests can substitute mocked responses.
- **Models**: Codable DTOs mirroring the NS API response shapes, plus small
  domain models (`Train`, `TrainStatus`, `JourneyConfig`). Domain models are
  what the UI and widget render.
- **Domain logic**: two pure functions, the heart of the app:
  - `selectRelevantTrip(config:trips:) -> Trip?` — picks the next trip matching
    the configured weekdays and approximate departure time.
  - `status(of:trip:) -> TrainStatus` — derives on time / delayed (+N min) /
    cancelled from planned vs. actual times and cancellation flags.
- **Persistence**: `JourneyConfig` (origin, destination, weekdays, approximate
  departure time) stored in the App Group shared container (UserDefaults or a
  small JSON file — decided during development). The app triggers
  `WidgetCenter.shared.reloadAllTimelines()` whenever config changes.
- **Widget**: TimelineProvider fetches live data in `getTimeline`, builds one
  entry per relevant train, and schedules the next refresh after the train's
  departure. Entries carry the rendered data so views stay dumb.

## Data flow

1. User saves a journey in the app → `JourneyConfig` written to shared
   container → widget timelines reloaded.
2. Widget timeline generation: read config → query NS API (trips for the
   configured route and day) → select relevant upcoming train → derive status →
   render entry.
3. Timeline policy: refresh again shortly after the shown train's departure so
   the next train takes over.

## Key decisions

- **One widget, one journey.** The widget shows the single configured journey.
  Supporting multiple journeys is an explicit future decision, not a design goal.
- **Widget fetches live data itself.** The timeline provider performs the
  network request so status is fresh without opening the app.
- **Time zone.** NS times are in `Europe/Amsterdam`. Times are displayed in
  that zone; all time math happens on a fixed `TimeZone`/`Calendar` so tests
  are deterministic.

## Open decisions (resolve during development)

- Exact NS endpoint for the widget lookup (`/trips` vs. `/departures` — see
  `api.md`).
- Shared container format (UserDefaults vs. JSON file).
- How the API key reaches the widget process (see `development.md`).
- Which station picker: curated list vs. search over the NS stations endpoint.
