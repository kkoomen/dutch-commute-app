# API — NS Reisinformatie API

## Source of truth

The **trips operation** of the official NS Reisinformatie API
(`gateway.apiportal.ns.nl`) — `docs/trips-api.html` has the official portal
documentation. This is the only endpoint used for departure times and live
status; the v2 stations operation (`/v2/stations`) provides the autocomplete
station list.

```
GET /reisinformatie-api/api/v3/trips
GET /reisinformatie-api/api/v2/stations (station list, autocomplete only)
```

Note (verified live 2026-08-14): the v3 reisinformatie routes other than
`trips` — `/v3/stations`, `/v3/departures` — return
`404 {"statusCode":404,"message":"Resource not found"}` on this
subscription.

## Authentication

- API key in the `Ocp-Apim-Subscription-Key` header.
- The key comes from the git-ignored `src/.env` (`NS_API_KEY`), bundled into
  the app as a resource and read at runtime by `APIKey.ns` — see
  `development.md`. No build scripts.
- **Never hard-code the key. Never commit it.** It must not appear in source,
  git history, or generated files.

## Request parameters (verified working, live example 2026-08-14)

| Parameter | Value used by the app | Notes |
|-----------|----------------------|-------|
| `fromStation` | station **name**, e.g. `Hoogkarspel` | Names verified working via curl; codes also accepted per the docs |
| `toStation` | station **name**, e.g. `Amsterdam Centraal` | Same |
| `dateTime` | ISO-8601 with offset, e.g. `2026-08-14T17:00:00+02:00` | Must be a **current/recent date** — old dates (e.g. 2000-01-01) return HTTP 400 |
| `searchForArrival` | `false` | Explicit departure search (matches the verified curl) |
| `lang` | `en` | Response text language |

Notes from `docs/trips-api.html`:

- `searchForArrivalDeparture` (a v2 parameter name) is **not** valid on v3
  and a request containing it returns HTTP 400; the v3 equivalents are
  `searchForArrival` / `departure`.
- `maxJourneys` is **not** a trips parameter and must not be sent — a
  request with it returns HTTP 400.

## Departure-time options (setup screen)

The setup screen's time rows (**Depart** / **Return**) are buttons that open
a bottom sheet (`TimePickerSheet`) with a **wheel picker** for the
**preferred time** (starts at the current value when editing, else 08:00):

- **Every wheel change** (debounced ~350 ms) triggers **one regular
  `trips` request** for that leg (`from → to` for depart, `to → from` for
  return) with `dateTime` = **today at the preferred time**
  (Europe/Amsterdam), `fromStation`/`toStation` = names,
  `searchForArrival=false`, `lang=en`.
- Results are **cached for 2 minutes** keyed by
  `<fromCode>-<toCode>-<modes>-<preferredMinute>`
  (`TripsSearchCache`, held by `NSAPIClient`), so scrolling back and forth
  or reopening the sheet within 2 minutes never re-queries the API.
- The response (~5 trips around the requested time) is shown **as-is**:
  the distinct departure minutes-of-day (`leg.origin.plannedDateTime`,
  `NSAPIClient.departureMinutes(of:calendar:)`) are listed, duplicates
  removed, nothing filtered.
- Picking one of the listed departures sets the journey time. The
  preferred time itself is **never stored** — it only seeds the search.
- On error or an empty result the sheet offers Retry plus a manual
  DatePicker fallback, so a journey can still be saved without the API.

## Response keys (verified against a live response)

Times live on the leg's `origin` / `destination` objects — **not** on the leg
itself. The app reads only these keys:

| Path (inside `trips[].legs[]`) | Type | Used for |
|---|---|---|
| `name` | string | Train display, e.g. `"IC 3008"` → "🚆 IC 3008" |
| `direction` | string | Shown as "→ Den Helder" |
| `cancelled` | bool | Full cancellation → status `.cancelled` |
| `origin.plannedDateTime` | string | Planned departure (status derivation) |
| `origin.actualDateTime` | string? | Actual departure; delay = actual − planned, floored to minutes |
| `product.number`, `product.categoryCode` | string | Fallback display name when `name` is missing (e.g. `"IC 1234"`) |
| `destination.plannedDateTime` | string | Arrival context (not displayed yet) |
| `trips[].status` | string | Trip-level status; `"NORMAL"` observed (informational) |

Notes:

- Timestamps are ISO-8601 **without colon in the offset**
  (`2026-08-14T05:41:00+0200`). `NSDateParser` also accepts `+02:00` and `Z`.
- `partCancelled`, `transfers`, `optimal`, `realtime`, per-stop
  `cancelled`/`departureDelayInSeconds`, and `product.longCategoryName` exist
  in the response but are not used for status yet — only `leg.cancelled` is.

Only fields needed for display and status derivation are decoded (`TripDTO`,
`LegDTO` in `DutchCommute/Models/NSDTOs.swift`). Unknown fields are ignored —
no full client library. Tracks come from `origin`/`destination`:
`plannedTrack` / `actualTrack` (actual wins for display; "Spoor X").

Domain models: `JourneyConfig`, `TrainLeg`, `TrainStatus`.

## Errors

| Case | Handling |
|------|----------|
| 400 | Bad request (e.g. unknown station code) — treat as config error |
| 401 / 403 | Invalid or missing API key — surface as "API not configured" |
| 429 | Rate limited — back off; show last known/unavailable |
| 5xx | NS API failure — graceful degradation |
| Network failure / timeout | Last known status or "unavailable" |
| Decoding failure | Log, degrade gracefully; never crash |

All errors funnel into one `NSAPIError` enum (`missingAPIKey`, `invalidURL`,
`httpStatus`, `decoding`, `noTrips`, `network`).

## Mock-data strategy

- **Fixtures**: bundled JSON files in the test target (`trips-on-time.json`,
  `trips-delayed.json`, `trips-cancelled.json`) capturing the real response
  shape: legs with `origin`/`destination` objects, `+0200` timestamps.
- **Never** hit the live API in unit tests; tests run without a key.
- Fixtures must be updated in the same change whenever the DTOs change.
