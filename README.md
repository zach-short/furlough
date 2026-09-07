# Furlough

A personal iOS app blocker with no unblock button.

Pick the apps and websites that eat your time. Give each one daily windows (say 8:00–10:00 PM) and a daily minute budget (say 30 minutes). Outside the windows, or once the budget is spent, iOS shields the app. The only way to loosen a rule is to wait: loosening edits take effect 24 hours after you make them, and you can cancel them in the meantime. Tightening edits apply instantly.

Built on Apple's Screen Time API (FamilyControls, ManagedSettings, DeviceActivity). Swift, SwiftUI, no third-party dependencies.

## How it works

| Piece | What it does |
|---|---|
| `Furlough` (app) | Screen Time authorization, the app picker, per-app rules, the pending-change queue. On every launch it re-registers DeviceActivity schedules and re-applies shields from persisted state, so nothing can drift. |
| `FurloughMonitor` | A DeviceActivity monitor extension. iOS wakes it at window edges, at midnight, and when an app's daily usage reaches its budget. Each callback re-derives the shields from shared state. It also posts the "5 minutes left" and "Time's up" notifications. |
| `FurloughShield` | Draws the block screen: why the app is blocked and when it opens next. |
| `FurloughWidgets` | Home-screen widget and the Live Activity shown while a window is open. |
| `Shared/Core` | Models, the pure rules engine (`Policy`), App Group persistence, and the shield reconciler. Compiled into every target. |

Rules for each app live in an App Group so all four processes read the same state. Apple never tells the app which apps you picked; the tokens are opaque. SwiftUI can still render each app's real icon and name, and you can give each one a nickname that shows on the shield, the widget, and notifications.

### The commitment device

- Adding an app is instant. Nothing is enforced until you save its first rule, and that first rule is always "tighter than nothing", so it applies instantly too.
- Shrinking a window, removing a window, or lowering a budget applies instantly.
- Extending a window, adding a window, raising a budget, or removing an app is queued for the loosening delay (24 hours by default). Pending changes are listed in the app and can be cancelled.
- Raising the delay is instant. Lowering it waits out the current delay.
- While anything is shielded, iOS is told to deny deleting apps, so the app cannot be removed as a shortcut.

The one escape that always exists is Apple's own: **Settings > Screen Time > Apps with Screen Time Access > Furlough > off**. That revokes access and iOS clears every shield and the delete-protection flag. Furlough cannot prevent it, and it documents it on purpose.

## Requirements

- A paid Apple Developer account (Family Controls is not available to Personal Teams).
- Xcode 26 or newer, a physical iPhone. The Screen Time API does not work in the Simulator.
- [XcodeGen](https://github.com/yonaskolb/XcodeGen): `brew install xcodegen`

## Install from Xcode

```bash
xcodegen generate
open Furlough.xcodeproj
```

1. In Xcode, select the `Furlough` scheme and your iPhone as the run destination.
2. Signing is automatic under team `X9V4L6HR2R`. Xcode registers the four bundle IDs and enables Family Controls (development), App Groups, and NFC-free capabilities on first build.
3. Press Run. On the phone, tap **Allow Screen Time access**, then **Allow** on the iOS prompt.
4. Tap **+** to pick apps and websites. Open each one and set its windows and budget. Save.

Or from the command line, with the phone connected:

```bash
xcodebuild -project Furlough.xcodeproj -scheme Furlough -configuration Debug \
  -destination 'platform=iOS,name=Zach’s iPhone' -allowProvisioningUpdates \
  -derivedDataPath build/DerivedData build
xcrun devicectl device install app --device <UDID> build/DerivedData/Build/Products/Debug-iphoneos/Furlough.app
```

## If a shield gets stuck

1. Open Furlough and tap **Settings > Re-apply enforcement now**. This re-registers every schedule and re-applies shields from saved state.
2. Check **Settings > Activity log** to see what the monitor extension has been doing.
3. If that does not help: **Settings > Screen Time > Apps with Screen Time Access**, turn Furlough off, then reopen Furlough and allow access again. Your rules are kept; only the shields are reset.

## Known limits of the Screen Time API

- Windows must be at least 15 minutes and cannot cross midnight (split them in two).
- At most 19 distinct windows across all apps (iOS allows 20 monitored activities, and one is the daily budget tracker).
- The monitor extension can fire a few minutes late, and threshold callbacks occasionally fire twice. Every callback is idempotent, so this is harmless.
- Distributing outside Xcode (TestFlight, App Store) needs the Family Controls distribution entitlement, requested per bundle ID, which can take weeks.
