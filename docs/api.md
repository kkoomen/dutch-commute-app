# API — NS Reisinformatie API

## Source of truth

The official **NS Reisinformatie API** (NS "Reisinformatie" portal,
`gateway.apiportal.ns.nl`). This is the only allowed data source. Scraping NS
websites or apps is forbidden.

Relevant endpoints (v3):

- `GET /reisinformatie-api/api/v3/trips` — journey advice between two stations;
  returns trips with legs, planned/actual times, and cancellation info.
- `GET /reisinformatie-api/api/v3/departures` — live departures from one
  station; returns trains with category/number, route, planned/actual times,
  and cancellation info.
- `GET /reisinformatie-api/api/v3/stations` — station list (for a station
  picker/search, optional).

**Endpoint choice is an open decision** for the widget lookup:

- `trips` matches the user's origin → destination directly, but returns
  journeys (possibly with transfers) rather than a single train.
- `departures` gives raw trains at the origin station; the route must be
  matched to the destination, but it's closer to "what train do I take".

Primary recommendation: `trips`, matching the user's exact configured journey.
Finalize during development; the networking layer must make swapping easy.

## Authentication

- API key in the `Ocp-Apim-Subscription-Key` header.
- The key is read from the **`NS_API_KEY` environment variable** at build/run
  time (see `development.md` for plumbing).
- **Never hard-code the key. Never commit it.** It must not appear in source,
  git history, or generated files.
- v3 also supports OAuth2 client credentials as an alternative — not needed
  unless the API key stops working.

## Request parameters (trips)

| Parameter | Value |
|-----------|-------|
| `fromStation` | origin station code, e.g. `ASDZ` (Amsterdam Zuid) |
| `toStation` | destination station code, e.g. `UT` (Utrecht Centraal) |
| `dateTime` | ISO-8601 date/time of the approximate departure (Europe/Amsterdam) |
| `searchForArrivalDeparture` | `departure` |
| `lang` | `nl` or `en` (UI language; decide during development) |

Station codes are NS codes (e.g. `ASD` Amsterdam Centraal, `ASDZ` Amsterdam
Zuid, `UT` Utrecht Centraal). The app stores station codes, not free text.

## Models (key fields)

Domain models: `JourneyConfig`, `Trip`, `Train`, `TrainStatus`.

DTOs mirror the v3 response shapes. Key fields relied on (exact names verified
against the NS OpenAPI spec when implementing):

- **Trip / leg**: `name` (e.g. `"IC 1234"`), `direction`, `plannedDeparture`,
  `actualDeparture`, `plannedArrival`, `actualArrival`, `cancelled`, and
  `messages` (user-visible info, e.g. delay explanations).
- Time fields are ISO-8601 strings in `Europe/Amsterdam`.

Only fields needed for display and status derivation are decoded. Unknown
fields are ignored (don't build a full client library).

## Errors

| Case | Handling |
|------|----------|
| 401 / 403 | Invalid or missing API key — surface as "API not configured" |
| 404 | Bad station code — treat as config error |
| 429 | Rate limited — back off; widget shows last known/unavailable |
| 5xx | NS API failure — same graceful degradation |
| Network failure / timeout | Last known status or "unavailable" |
| Decoding failure | Log, degrade gracefully; never crash |

All errors funnel into one `NSAPIError` enum so the app and widget handle them
uniformly. No retry storms from the widget; respect system refresh cadence.

## Mock-data strategy

- **Fixtures**: bundled JSON files in the test target capturing realistic
  v3 responses: on-time train, delayed train, cancelled train, no trains,
  missing/null fields.
- **Transport injection**: `NSAPIClient` takes a transport (protocol or
  `URLProtocol` mock) so tests substitute fixtures without real network.
- **Never** hit the live API in unit tests; tests must run without
  `NS_API_KEY`.
- Optionally, a `MockNSAPIClient` with canned responses for UI previews and
  widget previews (`#Preview` / `PreviewProvider`).

## Rate limits & fairness

Check NS portal limits when the key is provisioned. The widget must not fetch
more often than necessary: one request per timeline generation, refreshed at
system cadence plus one refresh after the shown train departs.
