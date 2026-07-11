# Reclaim iOS

A native iOS app for [Reclaim.ai](https://reclaim.ai) — the iPhone companion to
[reclaim-desktop](https://github.com/evanr76/reclaim-desktop). Manage your
Reclaim tasks with bulk operations, quick-add by Siri, and a Home/Lock Screen
widget for your Up Next glance.

Built with SwiftUI (iOS 17+), sharing a self-contained copy of `ReclaimKit`
(the model + API-client layer) with the macOS app.

> [!IMPORTANT]
> **Unofficial project.** Not affiliated with, endorsed by, or supported by
> Reclaim.ai. It uses Reclaim's **undocumented** private API
> (`api.app.reclaim.ai`), which can change or break at any time. Use at your own
> risk. "Reclaim.ai" and its logos are trademarks of their respective owner;
> this app ships a neutral placeholder icon. MIT licensed, no warranty.

## Features

- **Task list** with Active / Overdue / Completed / All filters and search.
- **Up Next section** pinned on top (Reclaim's `onDeck`).
- **Swipe actions** — complete/reopen (leading), delete + Up Next (trailing).
- **Multi-select edit mode → bulk bar**: complete, delete (with confirmation),
  set priority, move in/out of Up Next, snooze, reschedule (presets or a date
  picker).
- **Create & edit** tasks (title, notes, priority, due date, duration).
- **Siri / Shortcuts** — "Add a task to Reclaim" via an App Intent.
- **Widget** — small/medium Home & Lock Screen widget showing Up Next + top
  tasks, fed by a shared App Group snapshot the app writes on each refresh.
- **Auto-refresh** (default hourly, only while open + online) and pull-to-refresh.
- **Keychain**-stored API key.

## Building

Requires Xcode 16+ and [XcodeGen](https://github.com/yonaskolb/XcodeGen)
(`brew install xcodegen`). The Xcode project is generated from `project.yml`
(and gitignored):

```bash
xcodegen generate
open ReclaimIOS.xcodeproj      # then pick a Simulator and ⌘R
```

Signing to run on a device: select your team on all three targets
(app, widget, ReclaimKit) — automatic signing will provision the App Group
`group.io.github.evanr76.reclaimios`.

### Simulator quick-test with a token

A `DEBUG`-only fallback reads `RECLAIM_TOKEN` from the environment, so you can
skip onboarding while testing:

```bash
SIMCTL_CHILD_RECLAIM_TOKEN=<your-key> xcrun simctl launch --console booted io.github.evanr76.reclaimios
```

## Architecture

```
reclaim-ios/
├── project.yml               XcodeGen spec (app + widget + ReclaimKit)
├── ReclaimKit/               Shared model + API client (static library)
│   ├── ReclaimTask/User/Enums.swift, ReclaimAPIClient.swift, KeychainStore.swift
│   └── SharedStore.swift     App Group snapshot for the widget
├── ReclaimIOS/               App target
│   ├── ReclaimIOSApp.swift, ViewModels/, Views/, AppIntents/
│   └── Assets.xcassets, ReclaimIOS.entitlements (App Group)
└── ReclaimWidget/            WidgetKit extension
    ├── ReclaimWidget.swift
    └── ReclaimWidget.entitlements (App Group)
```

The app and widget share code via the `ReclaimKit` **static library** (linked
into both — no framework embedding). The API layer is a copy of the macOS app's,
kept intentionally identical; see [AGENTS.md](AGENTS.md).
