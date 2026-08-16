# Testing

## Principles

- **Deterministic.** No real network, no wall clock, no random data. Clocks,
  calendars, and API responses are injected.
- **Fast.** Unit tests only; no live API calls, no `NS_API_KEY` required.
- **Core logic first.** The pure functions (status derivation, journey
  selection) get the most coverage; UI stays thin and is tested via previews
  and manual checks.

## Test areas

### API decoding (`NSAPIClient` / DTOs)

- Decode bundled fixtures for: on-time trip, delayed trip, cancelled trip,
  empty response, malformed/missing fields.
- Assert DTO fields map correctly (name, direction, planned/actual times,
  cancellation).
- Assert decode failures surface as `NSAPIError.decoding`, not crashes.

### Status mapping (`status(of:)`)

- On time: planned == actual → `.onTime`.
- Delayed: actual later than planned → `.delayed(N)` with correct minute
  rounding (floor; e.g. 8:41 delay → `+8 min`).
- Cancelled wins over delays: cancelled flag set even with actual times → `.cancelled`.
- Missing actual times → `.onTime` based on planned time.
- Null/missing fields never crash.

### Journey selection (`selectRelevantTrip(config:trips:)`)

- Picks the earliest trip at/after the configured approximate departure time.
- Weekday filtering: configured days vs. trip date (Europe/Amsterdam).
- No matching day → no train (widget shows "no train" state).
- No trip after the approximate time → no train.
- Reverse-direction trains are selected and displayed with their actual route.
- Crossing midnight and DST transitions.

### Edge cases

- Delay of 0 minutes → on time.
- Very large delays (hours).
- Cancelled train with messages vs. without.
- Multiple trips in response, ties (two trains same minute — pick deterministically, e.g. first in response order).

### GTFS (static + realtime)

- `GTFSRealtimeClientTests`: protobuf fixtures (built with the generated
  types) for trip updates, alerts and vehicle positions; one hand-crafted
  raw-bytes wire fixture; malformed and stale feeds throw.
- `GTFSStaticDataServiceTests`: CSV fixtures (quoted fields, >24h times),
  route-type mapping, station choices (stop-modes + derived), and the
  bundled national dataset parses to 55k+ stops.
- `RealtimeUpdateServiceTests`: scheduled-only fallback, delays applied,
  skipped/cancelled trips, limit, unknown modes skipped, alert filtering.

### Live Activities (`LiveActivityTests`)

- `JourneyConfig` encodes/decodes both settings; defaults are off.
- Eligibility: exactly two train stations (GTFS stops and unknown stops
  are ineligible).
- Decision: disabled/ineligible/no-journey-date → none; full
  mode runs for the whole journey period; near-departure waits until
  1 hour before departure and runs inside the window; a non-active journey
  can run when Live Activity is enabled.
- Toggle behavior through `AppState`: disabling live activity clears
  near-departure; enabling it disables the setting on other journeys;
  settings persist in the shared store.
- Cancellation maps to the activity status; the stale date is 5 minutes
  after the last refresh.

ActivityKit start/update/end itself is not unit-testable (system API) and
push delivery needs a real device + backend — see `docs/live-activities.md`.

## How to run

From Xcode: `Cmd+U` (Test) on the `DutchCommute` scheme.

From the terminal (project/scheme names from the Xcode project):

```sh
xcodebuild test \
  -project DutchCommute.xcodeproj \
  -scheme DutchCommute \
  -destination 'platform=iOS Simulator,name=iPhone 16'
```

## `NS_API_KEY` in tests

Unit tests use fixtures and do **not** need `NS_API_KEY`. If an optional
integration/smoke test hits the live API, it must be explicitly opt-in (e.g.
a separate scheme or `#if` flag) and skipped when the key is absent.

## Fixtures

JSON fixtures live in the test target (e.g. `Tests/Fixtures/`). Each fixture
is a realistic, trimmed v3 response. Keep them small; annotate which scenario
each covers. When the DTOs change, fixtures must be updated in the same change
and all tests re-run.
