# API — NS Reisinformatie API

## Source of truth

The **trips operation** of the official NS Reisinformatie API
(`gateway.apiportal.ns.nl`). The official portal documentation is saved as
`docs/trips-api.html`. This is the **only** API surface used by the app.

```
GET /reisinformatie-api/api/v3/trips
```

Note (verified live 2026-08-14): other routes on this subscription —
`/v3/stations`, `/v3/departures`, and all non-trips paths — return
`404 {"statusCode":404,"message":"Resource not found"}`. Everything the app
needs comes from `trips`.

## Authentication

- API key in the `Ocp-Apim-Subscription-Key` header.
- The key comes from the git-ignored `src/.env` (`NS_API_KEY`), bundled into
  the app as a resource and read at runtime by `APIKey.ns` — see
  `development.md`. No build scripts.
- **Never hard-code the key. Never commit it.** It must not appear in source,
  git history, or generated files.

## Request parameters (verified live)

| Parameter | Value used by the app | Notes |
|-----------|----------------------|-------|
| `fromStation` | origin station code, e.g. `ASDZ` | Accepts NS codes or names |
| `toStation` | destination station code, e.g. `UT` | Same |
| `dateTime` | ISO-8601 with offset, e.g. `2026-08-14T08:11:00+02:00` | Europe/Amsterdam; past and future dates both accepted |
| `searchForArrivalDeparture` | `departure` | `arrival` also valid |
| `lang` | `en` | Response text language |

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
`LegDTO` in `TravelScreen/Models/NSDTOs.swift`). Unknown fields are ignored —
no full client library.

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
