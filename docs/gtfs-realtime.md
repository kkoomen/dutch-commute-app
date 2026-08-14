# GTFS-Realtime integration

The app supports live data from GTFS-Realtime feeds (bus, tram, metro,
ferry) alongside the NS train API. See <https://gtfs.org/documentation/realtime/reference/>
for the upstream spec.

## Architecture

```
Views / Widget
      │  only domain types: Departure, ServiceAlert
      ▼
TransitDataService (protocol)          ← another provider can implement this
      │
GTFSTransitDataService
      │
      ├── RealtimeUpdateService        ← joins static + live
      │       ├── GTFSRealtimeClient   ← fetches .pb, decodes (SwiftProtobuf),
      │       │                          maps to plain structs, staleness check
      │       └── GTFSStaticDataService ← parses stops/routes/trips/stop_times
      │                                   (CSV), route_type → TransportMode
      └── GTFSRealtimeFeed             ← feed config (url, max age, features)
```

- **Domain**: `Departure` and `ServiceAlert` are the only types the UI
  consumes. `TransportMode` and `TrainStatus` are reused — no duplicates.
- **Static GTFS** (`GTFSStaticDataService`): loads `stops.txt`,
  `routes.txt`, `trips.txt`, `stop_times.txt`; provides stop/route/trip
  lookups, ordered stop times and trip destinations.
- **GTFS-Realtime** (`Networking/GTFSRealtime/`): `GTFSRealtimeFeed`
  describes a feed; `GTFSRealtimeClient` fetches the `.pb` bytes with
  `URLSession`, decodes them with the generated SwiftProtobuf bindings
  (`GTFSRealtime.pb.swift`) and maps them to plain structs — protobuf
  types never leave this layer. `gtfs-realtime.proto` is the source
  schema; regenerate with:
  ```sh
  protoc --swift_out=src/DutchCommute/Networking/GTFSRealtime \
    src/DutchCommute/Networking/GTFSRealtime/gtfs-realtime.proto
  ```
- **Join** (`RealtimeUpdateService`): upcoming departures of a stop are the
  static stop times joined by `trip_id`/`stop_id`/`stop_sequence` with the
  live updates — delays, `SKIPPED` stops, cancelled trips
  (`TripDescriptor.schedule_relationship == CANCELED`). Alerts become
  `ServiceAlert`s, filtered by their active period.
- **Station picker**: the From/To picker offers NS train stations plus
  GTFS bus/metro/tram stops, each row showing the mode icon and label.
  Static GTFS data is read from the bundle's `gtfs/` resource directory
  when present (`stops.txt`, `routes.txt`, `trips.txt`,
  `stop_times.txt`); without it, only NS train stations are offered.

## Safety

- Malformed feed bytes → `GTFSRealtimeError.malformedFeed`; the service
  degrades to scheduled-only departures.
- Stale feeds: the header timestamp older than the feed's `maxAge` →
  `GTFSRealtimeError.staleFeed` (also degrades to scheduled-only).
- Network failures → scheduled-only.
- Tests never touch live APIs: fixtures are built with the generated
  protobuf types (plus one hand-crafted raw-bytes wire fixture), CSV
  fixtures are inline strings.

## Adding a feed/provider

- A new feed = a new `GTFSRealtimeFeed` entry (url, maxAge, features).
- A new provider = a new `TransitDataService` implementation; the UI does
  not change.
