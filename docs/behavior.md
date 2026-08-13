# Behavior

## Configuration flow (app)

1. User opens the app.
2. Picks **origin** and **destination** stations (NS station codes under the hood).
3. Picks **days of the week** (e.g. Mon–Fri).
4. Sets an **approximate departure time** (e.g. 08:15).
5. Saves. The config is stored in the shared container and widget timelines
   are reloaded.

The app may show a quick preview of the train that would be shown right now —
nice-to-have, not required.

## Widget display

The Lock Screen widget shows, for the selected journey:

```
🚆 IC 1234
Utrecht → Amsterdam
18:42 · On time
```

- **Line 1**: train category + number (e.g. `IC 1234`), with a small emoji
  indicator (🚆 on time, ⚠️ delayed, ✖️ cancelled).
- **Line 2**: route in the direction of travel (destination first if the train
  runs the reverse of the user's configured direction).
- **Line 3**: departure time + status.

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
