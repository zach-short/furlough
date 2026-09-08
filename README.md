# Furlough

A personal iOS app blocker with no unblock button.

Pick the apps and websites that eat your time. Give each one allowed windows (say 8:00–10:00 PM), the same every day or different per day of the week (until midnight on school nights, until 2 AM on weekends), and a daily minute budget (say 30 minutes). Outside the windows, or once the budget is spent, iOS shields the app. The only way to loosen a rule is to wait: loosening edits take effect 24 hours after you make them, and you can cancel them in the meantime. Tightening edits apply instantly.

There is also a Brick: a second set of apps you lock in one tap, from anywhere, and can only unlock by holding your phone to a physical NFC tag you paired. Leave the tag at home and your phone stays bricked until you are back.

Built on Apple's Screen Time API (FamilyControls, ManagedSettings, DeviceActivity) and Core NFC. Swift, SwiftUI, no third-party dependencies.

## How it works

| Piece | What it does |
|---|---|
| `Furlough` (app) | Screen Time authorization, the app picker, per-app rules, the pending-change queue. On every launch it re-registers DeviceActivity schedules and re-applies shields from persisted state, so nothing can drift. |
| `FurloughMonitor` | A DeviceActivity monitor extension. iOS wakes it at window edges, at midnight, and when an app's daily usage reaches its budget. Each callback re-derives the shields from shared state. It also posts the "5 minutes left" and "Time's up" notifications. |
| `FurloughShield` | Draws the block screen: why the app is blocked and when it opens next. |
| `FurloughWidgets` | Home-screen widget and the Live Activity shown while a window is open. |
| `Shared/Core` | Models, the pure rules engine (`Policy`), App Group persistence, and the shield reconciler. Compiled into every target. |

The home screen pages through every managed app. Each page has a living hourglass: the top bulb is the app's current window and drains with the countdown, and the mound turns amber at the "5 minutes left" warning and ember once the budget is spent. The glass is coloured by status everywhere it appears: in the rows, the widget, the Live Activity and the Dynamic Island.

Rules for each app live in an App Group so all four processes read the same state. Apple never tells the app which apps you picked; the tokens are opaque. SwiftUI can still render each app's real icon and name, and you can give each one a nickname that shows on the shield, the widget, and notifications.

### The commitment device

- Adding an app is instant. Nothing is enforced until you save its first rule, and that first rule is always "tighter than nothing", so it applies instantly too.
- Shrinking a window, removing a window, taking a day off a window, or lowering a budget applies instantly.
- Extending a window, adding a window, adding a day to a window, raising a budget, or removing an app is queued for the loosening delay (24 hours by default). Pending changes are listed in the app and can be cancelled.
- Windows never cross midnight. "Until 2 AM on Saturday night" is an evening window plus a 12:00–2:00 AM window on Sunday, and the budget still resets at midnight.
- When setting up an app, **Use windows from another app** copies another app's windows, days and budget into the editor, so a second app can get the same rule in two taps.
- **Visualize windows** opens the week as a seven-column, 24-hour grid. Tap a day to see just its hours, change them, and **Apply to other days** to give any other days exactly the same hours.
- Raising the delay is instant. Lowering it waits out the current delay.
- While anything is shielded, iOS is told to deny deleting apps, so the app cannot be removed as a shortcut.

### The Brick

- The Brick holds its own list of apps, sites, and categories, chosen with the same picker. An app can be in the Brick and have windows too.
- Tap **Brick** in the app and everything in the list is shielded immediately, no tag needed. Bricking is tightening.
- **Unbrick** opens the NFC reader; only the tag you paired lifts the brick, instantly. This is the one unblock in Furlough, and it exists only for the Brick. Rule-based targets never get one.
- While bricked, the list and the paired tag cannot be changed, so nothing can loosen under the lock. Bricking is refused until a tag is paired, so there is always a way back.
- When the brick is off, each app falls back to its windows and budget, or to nothing if it has no rule. Bricking an app that is already outside its window changes nothing visible.
- Pairing reads the tag's hardware identifier; nothing is written, so any NTAG sticker or an existing Brick device works.

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
2. Signing is automatic under team `X9V4L6HR2R`. Xcode registers the four bundle IDs and enables Family Controls (development), App Groups, and NFC Tag Reading on first build.
3. Press Run. On the phone, tap **Allow Screen Time access**, then **Allow** on the iOS prompt.
4. Tap **+** to pick apps and websites. Open each one and set its windows and budget. Turn off **Same every day** to give each window its own days. Save.
5. For the Brick, open the Brick card, choose apps, and pair a tag by holding the phone to it. Then **Brick** locks and **Unbrick** asks for the tag.

Or from the command line, with the phone connected:

```bash
xcodebuild -project Furlough.xcodeproj -scheme Furlough -configuration Debug \
  -destination 'platform=iOS,name=Zach’s iPhone' -allowProvisioningUpdates \
  -derivedDataPath build/DerivedData build
xcrun devicectl device install app --device <UDID> build/DerivedData/Build/Products/Debug-iphoneos/Furlough.app
```

## Installing on another phone

Any iPhone on iOS 26 or later can run Furlough from this Mac. Development signing under the paid team covers it; nothing in the project is tied to one device.

1. On the phone: **Settings > Privacy & Security > Developer Mode**, turn it on, and restart when asked.
2. Plug the phone into the Mac and unlock it. Tap **Trust** on the phone when it asks about the computer.
3. Find its identifier:
   ```bash
   xcrun devicectl list devices
   ```
   The phone should show as `available (paired)`. If it says `unavailable`, unplug and replug it, or unlock it.
4. Build for that phone. The first build registers its UDID with the team and refreshes the development profile, which is why `-allowProvisioningUpdates` is there:
   ```bash
   xcodebuild -project Furlough.xcodeproj -scheme Furlough -configuration Debug \
     -destination 'platform=iOS,id=<UDID>' -allowProvisioningUpdates \
     -derivedDataPath build/DerivedData build
   ```
   The UDID is the `00008xxx-…` value from `xcrun devicectl device info details --device <identifier>`, not the CoreDevice identifier that `list devices` prints first. Or open the project in Xcode, pick the phone as the run destination, and press Run.
5. Install and launch:
   ```bash
   xcrun devicectl device install app --device <UDID> build/DerivedData/Build/Products/Debug-iphoneos/Furlough.app
   xcrun devicectl device process launch --device <UDID> com.zachshort.furlough
   ```
6. On the phone, go through onboarding and allow Screen Time access. Authorization is per phone and per Apple account, and it has to be an adult account: Furlough asks for individual authorization, not the parent-approved kind.

Limits to know about:

- A paid membership allows 100 iPhones per year. Removing a device does not free its slot until the membership year rolls over.
- A development build keeps running for a year, then needs reinstalling.
- Development-signed builds only install over a cable. TestFlight, ad hoc, and the App Store all need the Family Controls distribution entitlement (see below).
- Whoever gets the app should know there is no unblock button, and that the only escape is Settings > Screen Time > Apps with Screen Time Access > Furlough > off.

## If a shield gets stuck

1. Open Furlough and tap **Settings > Re-apply enforcement now**. This re-registers every schedule and re-applies shields from saved state.
2. Check **Settings > Activity log** to see what the monitor extension has been doing.
3. If that does not help: **Settings > Screen Time > Apps with Screen Time Access**, turn Furlough off, then reopen Furlough and allow access again. Your rules are kept; only the shields are reset.

## Known limits of the Screen Time API

- Windows must be at least 15 minutes and cannot cross midnight (split them in two).
- At most 19 distinct windows across all apps (iOS allows 20 monitored activities, and one is the daily budget tracker).
- The monitor extension can fire a few minutes late, and threshold callbacks occasionally fire twice. Every callback is idempotent, so this is harmless.
- Distributing outside Xcode (TestFlight, App Store) needs the Family Controls distribution entitlement, requested per bundle ID, which can take weeks.
