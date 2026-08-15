# Live Activities & push updates

Live Activities are started, updated and ended by the app via ActivityKit
(`LiveActivities/` in the app target; the rendering configuration lives in
the widget extension's `WidgetBundle` as `JourneyLiveActivity`).

## Behavior

- Only the **active** journey may run a Live Activity.
- `showsLiveActivity` off → never started; any running activity is ended.
- Both endpoints must be **train stations** (resolved from the picker
  data; GTFS bus/metro/tram stops are ineligible).
- `showsNearDeparture` on → the activity runs only from **1 hour before
  the next departure** until the journey ends (the return departure of
  that journey date). Off → the full journey period.
- The activity ends when: the journey ends, the journey is deleted,
  deactivated, disabled, or the train is cancelled (shown as cancelled,
  then ended shortly after).
- Content carries a **`staleDate`** (5 minutes after the last refresh) and
  an `isStale` flag; failed refreshes mark the data stale instead of
  claiming freshness.

## Scheduling limitation

The "one hour before departure" start happens while the app process is
alive (`LiveActivityManager` schedules a task; `apply` also runs on app
launch and on every journey mutation). iOS provides no API to start an
activity later from a cold state — a backend push cannot start an
activity either. If the app never runs in that window, the activity
simply doesn't appear.

## Push updates (backend required — not bundled)

`LiveActivityPushTokenStore` persists per-activity push tokens in the
Keychain. `LiveActivityUpdateClient` is the abstraction for the backend;
the app ships with `NoopLiveActivityUpdateClient`, so **no backend is
faked** — implement the protocol against a real server.

### Required backend endpoints

| Endpoint | Purpose |
|---|---|
| `POST /push-tokens` | Body: `{ "push_token": <base64>, "activity_id": <uuid>, "journey_id": <uuid>, "device": "ios" }` — register a (rotated) token |
| `DELETE /push-tokens/{activity_id}` | Remove the token when the activity ends |

The backend then sends APNs pushes (token from the stored push token,
topic = the app's bundle id). Register the APNs entitlement and a
`.p8`/`.p12` key with Apple to send pushes.

### APNs payload contract

```json
{
  "aps": {
    "timestamp": 1723651200,
    "event": "update",            // "update" | "end"
    "content-state": {
      "departureTime": 1723651200,
      "status": "+5 min",
      "isCancelled": false,
      "lastUpdate": 1723651199,
      "isStale": false
    },
    "stale-date": 1723651500
  }
}
```

- `event: "update"` refreshes the content; `event: "end"` ends the
  activity (with optional `content-state` as the final state).
- `content-state` fields must match `JourneyActivityAttributes.ContentState`
  (Codable, exact keys).
- `stale-date` lets the system flag the activity as stale if pushes stop.
- Sending a push before the system budget allows it (frequent pushes are
  rejected) is handled by `stale-date`: the activity degrades visibly
  instead of showing stale data as current.
