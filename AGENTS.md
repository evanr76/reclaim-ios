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

## Reclaim API scope (personal key)

Probed 2026-07-12. The personal API key is **scope-limited** vs the web session:
- ✅ `GET/POST /api/tasks*`, `GET /api/timeschemes`, `GET /api/moment`,
  `GET /api/moment/next`, planner **action** POSTs that already work
  (done/prioritize/snooze/onDeck-patch).
- ❌ **403**: `?instances=true`, `/api/events`, `/api/planner/*` reads,
  `/api/habits`, `/api/daily-habits`, `/api/hours`, `/api/users/current/settings`,
  `/api/moment/current`.

Consequences: no full calendar / per-task scheduled times / Today timeline, and
**habits are unavailable**. The "Now & Next" banner uses `/api/moment` (current)
+ `/api/moment/next` (next) — the only scheduling data we can read. Re-probe
start/stop + log-work + reindex-by-due before building Phase 3.

## Apple Watch app (ReclaimWatch)

- watchOS target (single, modern) embedded in the iOS app; compiles the shared
  `ReclaimKit` sources directly (NOT as a module — watch files must not
  `import ReclaimKit`). iOS-only bits (ActivityKit) are `#if`-guarded out.
- **Token bridge:** iPhone pushes the API token to the watch via
  `WCSession.updateApplicationContext(["reclaimToken": …])` (PhoneConnectivity);
  the watch stores it in its own Keychain (WatchModel/WCSessionDelegate) and
  fetches Up Next tasks directly from the API. Sign-out on the phone clears it.
- **Build requirement:** a watch-embedding scheme won't build without the
  matching **watchOS simulator runtime** installed (`xcodebuild -downloadPlatform
  watchOS`), even for device builds. `scripts/install-device.sh` (generic iOS)
  embeds the watch app; it auto-installs to a paired watch via the Watch app.
- Verified in a watchOS simulator with the `#if DEBUG && targetEnvironment(simulator)`
  `RECLAIM_TOKEN` env fallback in WatchModel. Complication is deferred.

## On-device intelligence (iOS 26+, Apple Foundation Models)

All AI runs on-device via the Foundation Models framework — no server, no data
leaves the device, and nothing touches the Reclaim API contract. Everything is
gated on `ReclaimIntelligence.isAvailable` (iOS 26 + Apple Intelligence enabled +
model downloaded) and degrades gracefully; the app is fully usable without it.

- **AI task capture** (`Views/TaskCaptureView.swift`, `sparkles` toolbar button):
  type/dictate/paste free text → `@Generable ParsedTask` via guided generation →
  editable review → add. **Multi-turn refinement** reuses one `LanguageModelSession`
  so "make it 2 hours" / "due Friday" keep context.
- **Smart duration/priority** come from the same parse as *suggestions* — never
  auto-applied. **Due dates are only pre-filled when the note explicitly states
  one** (Reclaim schedules by priority; we never fabricate a deadline).
- **Snap-to-task** (`Intelligence/VisionOCR.swift`, `CameraPicker.swift`): photo →
  Vision `VNRecognizeTextRequest` → text → same parse pipeline.
- **Daily briefing** (`Intelligence/DailyBriefing.swift`): generated in-app after
  refresh (staleness-gated to ~3h/day), cached in the App Group, rendered by the
  `ReclaimBriefingWidget`. The widget can't run the model (memory), so it only reads.
- **Spotlight semantic search** (`Intelligence/ReclaimTaskEntity.swift`): tasks are
  an `IndexedEntity`, re-indexed on every `publishSnapshot()` via `indexAppEntities`
  (iOS 18+); the `EntityQuery` reads the App Group snapshot (no token needed).
- Architecture note: all FoundationModels/Vision code lives in the **app target**,
  never in `ReclaimKit` — the watch target compiles ReclaimKit sources directly and
  watchOS has no FoundationModels. `SharedStore` only gained a plain `Briefing` cache.

## Follow-ups: iOS 27 SDK (needs Xcode 27 beta; currently on Xcode 26.6 / SDK 26.5)

- Replace Vision OCR with the model-native `OCRTool` + **direct image input** to the
  model (drop the `VisionOCR`/`CameraPicker` plumbing).
- Adopt **App Intents 2.0**: `LongRunningIntent` showing progress as a Live Activity;
  **View Annotations** ("mark *that* one done"); streaming intent responses; `@UnionValue`.
- Foundation Models: bigger on-device model, on-device fine-tuning, per-request tool
  control via `GenerationOptions`.

## Follow-ups: macOS 27 version (Foundation Models is macOS 26+)

Port the same on-device features to the desktop app (`reclaim-desktop`):
- AI task capture + multi-turn refinement (reuse the `@Generable` schemas & prompts).
- Snap-to-task via **drag-drop / paste a screenshot** → Vision OCR → parse.
- Daily briefing in the **menu-bar popover** and a macOS (Notification Center) widget.
- macOS **Spotlight** indexing via the same `IndexedEntity`.
- Keep the "suggestions only, never fabricate a due date" rule identical to iOS.

## Known gaps / backlog

- Widget only reflects data as of the app's last refresh (App Group snapshot).
  Could add a live-fetching widget via a shared Keychain access group if desired.
- No interactive widget buttons (iOS 17 AppIntent widgets) — tap opens the app.
- App Group + device signing need a real team (automatic signing provisions it).
- Verified against the API through the shared client (identical to macOS, which
  was probed live); iOS-specific UI verified in the simulator.
- On-device AI verified to **compile & launch**; live model output depends on Apple
  Intelligence being enabled on the device (graceful fallback otherwise).
