# Development

## Prerequisites

- Xcode 15+ (iOS 17+ SDK; Lock Screen widgets require iOS 16+, App Intents
  interactivity iOS 17+).
- An NS Reisinformatie API subscription (portal: gateway.apiportal.ns.nl) that
  provides an API key.
- No package dependencies: Foundation, SwiftUI, WidgetKit, XCTest only.

## Project setup (already done — current layout)

All code lives under `src/`:

```
src/
  DutchCommute.xcodeproj
  DutchCommute/            app target
    App/, Views/, Models/, Networking/, Domain/, Store/
  DutchCommuteTests/       unit tests
    Fixtures/              JSON fixtures
  .env                     git-ignored, holds NS_API_KEY (bundled as resource)
  .env.example             committed template
```

A widget extension target (`DutchCommuteWidget`) exists with the app and
shares the App Group `group.com.dutchcommute.app` (entitlements in both
targets). Bundle id: `com.dutchcommute.app.widget`.

## `NS_API_KEY` configuration

The key lives only in the git-ignored `src/.env` — no build scripts involved:

1. Create `src/.env` (copy from `src/.env.example`):
   ```
   NS_API_KEY="<your-key>"
   ```
2. Xcode copies `src/.env` into the app bundle as a resource (file
   reference `../.env` in the app target's Copy Bundle Resources phase).
3. At runtime, `APIKey.ns` (in `DutchCommute/Networking/APIKey.swift`) parses
   `NS_API_KEY` from the bundled `.env` and hands it to `NSAPIClient`.

Rebuild the app after changing the key. `.gitignore` excludes `src/.env`.
Verify with `git status` that no key ever appears in a diff.

## Build & run

```sh
open src/DutchCommute.xcodeproj
```

Run the app scheme from Xcode.

## Tests

See `docs/testing.md`:

```sh
xcodebuild test \
  -project src/DutchCommute.xcodeproj \
  -scheme DutchCommute \
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
