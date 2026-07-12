# AGENTS.md — Reclaim iOS

Context file for AI agents. iPhone companion to `reclaim-desktop`.

## What this is

Native **SwiftUI iOS** app (iOS 17+) over the Reclaim.ai REST API: task list +
bulk operations, create/edit, Siri App Intent, and a WidgetKit widget. See
`README.md` for the feature list.

## Project status

- **Code complete.** Project generates via XcodeGen; targets: `ReclaimIOS` (app),
  `ReclaimWidget` (extension), `ReclaimKit` (static library).
- Verify builds against the iOS **Simulator** SDK. NOTE: Xcode 26.x needs its
  matching iOS simulator **platform** installed (`xcodebuild -downloadPlatform
  iOS`) — older runtimes alone won't resolve as build destinations.

## Conventions

- **No third-party deps** beyond XcodeGen (build tool). System frameworks only:
  SwiftUI, Foundation, Security (Keychain), Network, WidgetKit, AppIntents.
- **`ReclaimKit` is a self-contained COPY** of the macOS app's model/API layer
  (`ReclaimTask`, `User`, `Enums`, `ReclaimAPIClient`, `KeychainStore`) — the user
  chose independence from the published macOS repo over a shared package. Keep the
  API client identical to macOS; if you fix a client bug here, port it to
  `reclaim-desktop` too (and vice-versa). Shared types are `public` (library
  boundary).
- **State** in `TaskListViewModel` (`@MainActor @Observable`); views are thin.
  Optimistic complete/delete (skip refetch — Reclaim archive/delete is
  eventually-consistent); other mutations optimistic + refetch.
- **Widget data**: the app writes a small `SharedStore.TaskSnapshot` array to the
  App Group (`group.io.github.evanr76.reclaimios`) after every load; the widget
  reads it (no token/network in the widget). `WidgetCenter.reloadAllTimelines()`
  on each publish.
- **iOS idioms** (vs macOS): `List` + edit-mode multi-select instead of `Table`;
  swipe actions; sheets for create/settings; pushed detail for edit; no menu bar
  / login-item (macOS-only). Widget replaces the macOS menu-bar glance.
- Keychain service id: `io.github.evanr76.reclaimios`.

## Build / verify

```bash
xcodegen generate
xcodebuild -project ReclaimIOS.xcodeproj -scheme ReclaimIOS \
  -destination 'platform=iOS Simulator,name=<device>' \
  CODE_SIGNING_ALLOWED=NO build

# run + inject a token for real data:
xcrun simctl boot <device>; xcrun simctl install booted <path>.app
SIMCTL_CHILD_RECLAIM_TOKEN=<key> xcrun simctl launch --console booted io.github.evanr76.reclaimios
```

A `#if DEBUG` fallback in `TaskListViewModel.init` reads `RECLAIM_TOKEN` from the
environment (simulator testing only).

## Known gaps / backlog

- Widget only reflects data as of the app's last refresh (App Group snapshot).
  Could add a live-fetching widget via a shared Keychain access group if desired.
- No interactive widget buttons (iOS 17 AppIntent widgets) — tap opens the app.
- App Group + device signing need a real team (automatic signing provisions it).
- Verified against the API through the shared client (identical to macOS, which
  was probed live); iOS-specific UI verified in the simulator.
