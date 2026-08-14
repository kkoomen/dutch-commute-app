# Architecture

## Targets

- **TravelScreen** — the app. Configures the journey, writes it to the shared
  container, and triggers widget reloads.
- **TravelScreenWidget** — the WidgetKit extension. Reads the journey
  configuration, fetches live data, and renders the Lock Screen widget
  (accessoryRectangular + accessoryInline).
- **TravelScreenTests** — unit tests.

The app and widget share the App Group `group.com.travelscreen.app`
(entitlements: `TravelScreen/TravelScreen.entitlements`,
`TravelScreenWidget/TravelScreenWidget.entitlements`).

**Shared sources** (compiled into both the app and the widget target):
`Station`, `JourneyConfig`, `TrainLeg`, `NSDTOs`, `TrainStatusMapping`,
`JourneySchedule`, `NSDateParsing`, `NSAPIClient`, `APIKey`, `ConfigStore`.
Widget-only: `TravelScreenWidgetBundle`, `JourneyWidget` (TimelineProvider +
views). App-only: app state, views, tests.

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
- **Persistence**: all `JourneyConfig`s (with `id` + `createdAt`) stored via
  `ConfigStore` in the shared App Group UserDefaults
  (`group.com.travelscreen.app`), readable by both the app and the widget.
  The app triggers `WidgetCenter.shared.reloadAllTimelines()` on
  add/update/delete.
- **Widget** (`JourneyWidget`): TimelineProvider reads the config from the
  shared container, computes the active journey day and the next upcoming
  leg (`JourneySchedule`), fetches that one trip via `NSAPIClient`, and
  renders one entry with the leg + status. Timeline policy refreshes shortly
  after the shown train departs so the next leg takes over. Families:
  accessoryRectangular, accessoryInline.

## Data flow

1. User saves a journey in the app → `JourneyConfig` written to shared
   container → widget timelines reloaded.
2. Widget timeline generation: read config → query NS API (trips for the
   configured route and day) → select relevant upcoming train → derive status →
   render entry.
3. Timeline policy: refresh again shortly after the shown train's departure so
   the next train takes over.

## Key decisions

- **One widget, first journey.** The app supports multiple journeys; the
  widget shows the first (top-most) journey on the user's list. Picking a
  specific journey for the widget is future work.
- **Widget fetches live data itself.** The timeline provider performs the
  network request so status is fresh without opening the app.
- **Time zone.** NS times are in `Europe/Amsterdam`. Times are displayed in
  that zone; all time math happens on a fixed `TimeZone`/`Calendar` so tests
  are deterministic.

## Open decisions (resolve during development)

- Widget lookup strategy on the trips endpoint (one request for the next
  relevant train vs. today's journey shape; see `api.md`).
- Shared container format (UserDefaults vs. JSON file).
- How the API key reaches the widget process (see `development.md`).
- Which station picker: curated list vs. the NS station list (loaded via
  `v2/stations` — only endpoint that serves it on this subscription).
