# Behavior

## My journeys (home)

1. The home screen lists all journeys as cards: route, times, days, and the
   **absolute creation time** (e.g. "Created 14 Aug 2026, 02:30").
2. Default order: **most recently created first**. The user can reorder by
   dragging the grip on the left of each card; the manual order is persisted
   and wins over the creation-time sort.
3. "+" adds a new journey; tapping a card opens that journey; swipe deletes.
4. Editing a journey keeps its `id` and `createdAt`; only route/times/days
   change.

## Configuration flow (app)

1. User taps "+" on My journeys.
2. Picks **origin** and **destination** stations (NS station codes under the
   hood) and opens **Travel options** (a full-height modal): a **multi-
   select** of transport modes — Train, Bus, Metro, Tram, Ferry — shown as
   icon tiles, **all selected by default** (at least one is required), plus
   an optional **via station**. A blue checkmark closes it; the selected
   modes are shown on the "Travel options" row and the via station appears
   as a **readonly row between From and To** (tapping either reopens the
   modal). Autocomplete kicks in after **2 non-whitespace characters** and
   queries the station list only after the user **hasn't typed for
   500 ms**; the station list itself is fetched at most once per app
   session.
3. Picks **days of the week** (e.g. Mon–Fri).
4. Sets **departure and return times**: tapping the Depart or Return row
   opens a bottom sheet with a **wheel picker** for the preferred time.
   Every wheel change (debounced ~350 ms) makes one cached `trips` request
   for that leg at today's preferred time and the ~5 returned departures
   are shown as-is; picking one sets the journey time (the preferred time
   itself is never stored; results are cached 2 minutes per
   from-to-time key) — see `docs/api.md`. Until a time is picked the row
   shows **"Tap to set"**
   (no default). Saving requires both times to be set. On error or empty
   results the sheet offers Retry and a manual DatePicker fallback.
5. Saves. The config is stored in the shared container and widget timelines
   are reloaded.

The app may show a quick preview of the train that would be shown right now —
nice-to-have, not required.

## Widget display

The widget (`JourneyWidget`) shows the **next upcoming leg** of the active
journey (outbound leg before the departure time, return leg after it) with
this fixed three-line structure:

```
🚆 Utrecht Centraal
Outbound 08:11
On time
```

- **Line 1**: train icon + destination name (the configured destination of
  the leg: `to` for Outbound, `from` for Return).
- **Line 2**: leg kind (`Outbound` / `Return`) + departure time (actual when
  delayed, else planned).
- **Line 3**: status — `On time` / `+X min` / `Cancelled`.

## Widget sizes

The widget supports these families with the same three-line structure:

- `systemSmall` (2×2 grid cells)
- `systemMedium` (4×2)
- `systemLarge` (4×4)
- `systemExtraLarge` (iPad, 4×4)
- `accessoryRectangular` (Lock Screen, three lines)
- `accessoryCircular` (Lock Screen square 1×1: train icon + status)
- `accessoryInline` (Lock Screen, condensed single line)

`accessoryCorner` is watchOS-only and not supported.
Status strings:

| State     | Display              |
|-----------|----------------------|
| On time   | `18:42 · On time`    |
| Delayed   | `18:42 · +8 min`     |
| Cancelled | `Cancelled`          |

If no relevant train exists (e.g. configured days don't include today, or no
train matches the approximate time), the widget shows a short "no train" state.

If live data is unavailable (no network, API failure), the widget shows last
known status if recent, otherwise an "unavailable" state. It must never show
stale data as if it were fresh.

## Status derivation rules

Given a trip from the NS API, derive status:

1. If the trip's train is **cancelled** → `.cancelled`.
2. Else if **actual departure** exists and is later than **planned departure**
   → `.delayed(minutes)`, where minutes = actual − planned (rounded to whole
   minutes, floor).
3. Else → `.onTime`.

Rule order matters: a cancelled train's actual times may be absent or
misleading, so cancellation is checked first. These rules live in a pure
function (`status(of:)`) with no I/O.

## Train selection rules

Given the config and the API response, pick the train to show:

1. Only consider trips on a configured weekday (today's day must be in the
   user's selected days; if not, show the "no train" state).
2. Among trips departing at or after the configured approximate departure
   time, pick the earliest.
3. If none departs at or after the approximate time, the next train of the day
   after the last configured departure is *not* shown — show "no train"
   instead (the commute window is over). *(Exact rule confirmed during
   development — the key requirement is determinism and tests.)*

## Adding the widget

The "Add to lock screen" button at the bottom of "My journey" opens a sheet
with instructions (press and hold the Lock Screen → Customize → Add Widget →
Travel Screen). There is no public API to add a widget programmatically, so
the app guides the user instead. The widget appears in the gallery after the
app has run once.

## Refresh behavior

- Widget timeline refreshes happen at system discretion; entries schedule a
  refresh shortly after the shown train's departure so the next train appears.
- Config changes in the app trigger `WidgetCenter.shared.reloadAllTimelines()`.
- Optional (iOS 17+): an interactive "Refresh" button on the widget for
  on-demand updates — only if it stays simple.

## Edge cases

- Train runs reverse direction of the configured journey (e.g. user travels
  Amsterdam → Utrecht, next relevant train is Utrecht → Amsterdam) — show the
  actual route with direction of travel.
- Crossing midnight: a train departing 00:15 belongs to the next day's
  schedule; treat days consistently in `Europe/Amsterdam`.
- DST transitions: all time math in `Europe/Amsterdam`, never the device's
  local zone.
- Missing fields in API responses (null actual times, missing messages):
  never crash; degrade to on-time-with-planned-time or unavailable.
