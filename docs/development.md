# Development

## Prerequisites

- Xcode 15+ (iOS 17+ SDK; Lock Screen widgets require iOS 16+, App Intents
  interactivity iOS 17+).
- An NS Reisinformatie API subscription (portal: gateway.apiportal.ns.nl) that
  provides an API key.
- No package dependencies: Foundation, SwiftUI, WidgetKit, XCTest only.

## Project setup (one-time)

1. Create the Xcode project `TravelScreen.xcodeproj` (app target
   `TravelScreen`, iOS 17+ deployment target).
2. Add the widget extension target `TravelScreenWidget` (WidgetKit extension,
   Lock Screen widget).
3. Enable the App Group capability on both targets and use a shared group,
   e.g. `group.<your-bundle-id>.travelscreen`.
4. Add a unit test target `TravelScreenTests`.
5. Copy this directory's `docs/` and `AGENTS.md` into the repo root if not
   already there.

### Proposed structure

```
TravelScreen.xcodeproj
TravelScreen/            app target
  App/, Views/, Models/, Networking/, Domain/, Store/
TravelScreenWidget/      widget extension
  Widget/, Timeline/
TravelScreenTests/       unit tests
  Fixtures/              JSON fixtures
docs/                    this documentation
Config/Local.xcconfig    git-ignored, holds NS_API_KEY
```

## `NS_API_KEY` configuration

The key is read from the `NS_API_KEY` environment variable. Recommended
plumbing:

1. Create `Config/Local.xcconfig` (git-ignored):
   ```
   NS_API_KEY = <your-key>
   ```
2. Reference it from the project; add a scheme environment variable
   `NS_API_KEY = $(NS_API_KEY)` to the Run and Test actions so the app
   process (and tests, if ever needed) see it via
   `ProcessInfo.processInfo.environment["NS_API_KEY"]`.
3. For the widget extension process: write the key into the shared App Group
   container from the app at launch (or embed via the same xcconfig + Info.plist
   build-setting pattern). Exact mechanism decided during development — the
   hard rule: **never commit the key**.
4. CI/team members: copy `Config/Local.xcconfig.example` (a placeholder file
   that is committed) to `Config/Local.xcconfig` and fill in the key.

`.gitignore` already excludes `Config/Local.xcconfig` and `*.local.xcconfig`.
Verify with `git status` that no key ever appears in a diff.

## Build & run

```sh
open TravelScreen.xcodeproj
```

Run the app scheme from Xcode. The widget appears in the simulator/device
Lock Screen gallery under the app's name.

## Tests

See `docs/testing.md`:

```sh
xcodebuild test \
  -project TravelScreen.xcodeproj \
  -scheme TravelScreen \
  -destination 'platform=iOS Simulator,name=iPhone 16'
```

## Conventions

- Swift concurrency (`async`/`await`); avoid threads and `DispatchQueue` unless
  needed. `Sendable` where the compiler asks.
- SwiftUI for all UI; no UIKit unless unavoidable.
- Files are small and single-purpose. Names: `NSAPIClient`, `TrainStatus`,
  `JourneyConfig`, `selectRelevantTrip`, `status(of:)`.
- Domain logic has no I/O; networking has no UI; views render models only.
- Keep the widget view code minimal; all logic lives in shared, testable code.
- Format with `swift-format` (Apple's, via Xcode) if available; otherwise keep
  style consistent with the file you're editing.
- Prefer `#Preview` macros over storyboards/xibs.

## Definition of done

- Builds cleanly (no warnings introduced).
- Full test suite passes.
- `NS_API_KEY` not present anywhere in the repo or git history.
- Docs updated if behavior or architecture changed.
- Limitations reported honestly in the summary of the change.
