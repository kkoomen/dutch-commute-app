# Live Activities & push updates

Live Activities are started, updated and ended by the app via ActivityKit
(`LiveActivities/` in the app target; the rendering configuration lives in
the widget extension's `WidgetBundle` as `JourneyLiveActivity`).

## Behavior

- Exactly one journey may have **Show live activity** enabled at a time;
  enabling it disables the setting for other journeys. This is independent
  from **Show on lockscreen**.
- `showsLiveActivity` off → never started; any running activity is ended.
- Both endpoints must be **train stations** (resolved from the picker
  data; GTFS bus/metro/tram stops are ineligible).
- Turning the toggle **on starts the activity immediately**: it is
  requested with the planned departure and a placeholder route name, then
  refreshed with live data as soon as the NS API responds. It never
  blocks on the network fetch to appear.
- `showsNearDeparture` on → an activity **auto-starts** only from
  **1 hour before the next departure** until the journey ends (the
  return departure of that journey date). Off → the full journey period.
  An explicit toggle-on overrides the wait window: the activity starts
  right away and later `apply` runs keep it alive instead of ending it.
- The activity ends when: the journey ends, the journey is deleted,
  deactivated, disabled, or the train is cancelled (shown as cancelled,
  then ended shortly after).
- Content carries a **`staleDate`** (5 minutes after the last refresh) and
  an `isStale` flag; failed refreshes mark the data stale instead of
  claiming freshness.
- While the **app process is alive**, the running activity is refreshed
  with live data every **1 minute** (`LiveActivityManager.refreshInterval`:
  a periodic loop that calls `apply`, fetching the trip from the NS API and
  updating the activity; it sleeps without API calls when no activity is
  running). iOS suspends backgrounded apps, so this cadence is only
  guaranteed while the app runs — an around-the-clock cadence also needs
  the backend push client (see below). The 5-minute `staleDate` is longer
  than the refresh interval, so content is only flagged stale when updates
  actually stop.
- The Lock Screen card follows the **app's appearance setting**
  (System / Light / Dark), shared with the widget extension through the
  App Group. Colors are resolved explicitly per scheme because
  ActivityKit resolves dynamic colors passed to `activityBackgroundTint`
  against the light appearance even on dark devices; the device scheme
  is read from SwiftUI's `colorScheme` environment (`UITraitCollection
  .current` reports light on dark devices in the Live Activity render
  context).
- The card shows: **"From → To"** as the title, the train and its
  **track** on the second line, and departure time + status below.
  `fromName`/`toName`/`track` are part of `ContentState` because the
  outbound and return legs differ and ActivityKit attributes are
  immutable.
- Starts that fail are reported to the user: the app checks
  `ActivityAuthorizationInfo().areActivitiesEnabled` (Live Activities
  globally disabled in Settings) and shows a friendly error in the
  journey view instead of failing silently.

## Scheduling limitation

The automatic "one hour before departure" start happens while the app
process is alive (`LiveActivityManager` schedules a task; `apply` also
runs on app launch and on every journey mutation). iOS provides no API
to start an activity later from a cold state — a backend push cannot
start an activity either. If the app never runs in that window, the
activity simply doesn't appear. (Turning the toggle on is not affected:
that starts the activity immediately.)

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
      "routeName": "IC 1234",
      "fromName": "Utrecht Centraal",
      "toName": "Amsterdam Centraal",
      "track": "4",
      "departureTime": 1723651200,
      "status": "+5 min",
      "isCancelled": false,
      "statusKind": "delayed",  // "onTime" | "delayed" | "cancelled" | "unknown"
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
  (Codable, exact keys). `statusKind` is machine-readable for coloring
  (the `status` string is localized); payloads may omit it — it decodes
  as nil and renders neutral.
- `stale-date` lets the system flag the activity as stale if pushes stop.
- Sending a push before the system budget allows it (frequent pushes are
  rejected) is handled by `stale-date`: the activity degrades visibly
  instead of showing stale data as current.

## When a Live Activity can actually be shown

These are the platform conditions for a Live Activity to appear on the
Lock Screen; all of them are outside the app's control and are the usual
reasons "it doesn't show" even when the toggle is on:

- **Device and OS**: iPhone with iOS 16.1 or later (the project targets
  iOS 17). Live Activities do not exist on iPad — the app supports iPad
  (`TARGETED_DEVICE_FAMILY = 1,2`), where no Live Activity can ever be
  displayed.
- **Global setting**: Settings → Face ID & Passcode → **Live Activities**
  must be on. When it is off, `Activity.request` still succeeds but the
  system never shows the activity; the app now checks
  `ActivityAuthorizationInfo().areActivitiesEnabled` and tells the user
  where to enable it.
- **Setup requirements**: no "Live Activities" capability exists in
  Xcode's Signing & Capabilities. The requirements are
  `NSSupportsLiveActivities` in the app's **and** the widget
  extension's Info.plist (both in place), the Live Activity
  configuration in the widget extension, and — because the app
  requests with `pushType: .token` — the **Push Notifications**
  capability (`aps-environment`) on the app target for device
  builds; without it, `Activity.request` fails on device.
- **Simulator**: Live Activities appear in the Simulator's Dynamic
  Island, but the Simulator has no Lock Screen — verify lock-screen
  rendering on a physical iPhone.
- **Start conditions in the app**: "Show live activity" must be enabled,
  both stops must be train stations, and at least one travel day must be
  configured. "Show on lockscreen" is independent. For automatic starts,
  the app must have run inside the near-departure window when that mode is
  on.
- **Update budget**: iOS throttles frequent updates (roughly one per
  minute with regular pushes; frequent-push mode needs the
  `NSSupportsLiveActivitiesFrequentUpdates` key and capability).

## Troubleshooting: "The Live Activity could not be started"

The app requests the activity with `pushType: .token`; when
`Activity.request` throws on a **physical iPhone** (the Simulator is
more lenient), the journey view shows a friendly alert. On a device
build, the confirmed requirement is the **Push Notifications
capability**:

1. **Push Notifications capability (confirmed fix)** — `pushType:
   .token` fails on device with `com.apple.ActivityKit.ActivityInput
   error 0` when the app lacks `aps-environment`. In Xcode:
   `DutchCommute` target → Signing & Capabilities → "+ Capability" →
   **Push Notifications**, then reinstall. (Free personal teams may
   not support this capability.)
2. **Widget extension plist key** — the widget extension's Info.plist
   must carry `NSSupportsLiveActivities` as well (the app's Info.plist
   carries it too); both are in the project.
3. **Stale install** — after any signing/plist change, delete the app
   from the device and reinstall, otherwise the old profile and
   extension keep failing.
