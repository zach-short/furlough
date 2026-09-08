# Furlough

A personal iOS and Mac app blocker with no unblock button.

Pick the apps and websites that eat your time. Give each one a daily minute budget (say 30 minutes) and, if you want, allowed windows (say 8:00–10:00 PM, or 5:00 PM to 4:00 AM for a weekend night), the same every day or different per day of the week (until midnight on school nights, until 2 AM on weekends). With no windows an app is open all day, up to its budget. Outside the windows, or once the budget is spent, iOS shields the app. The only way to loosen a rule is to wait: loosening edits take effect 24 hours after you make them, and you can cancel them in the meantime. Tightening edits apply instantly.

There is also the Anchor: a second set of apps you lock in one tap, from anywhere, and can only unlock by holding your phone to a physical NFC tag you paired. Leave the tag at home and your phone stays anchored until you are back.

Built on Apple's Screen Time API (FamilyControls, ManagedSettings, DeviceActivity) and Core NFC. Swift, SwiftUI, no third-party dependencies.

## How it works

| Piece | What it does |
|---|---|
| `Furlough` (app) | Screen Time authorization, the app picker, per-app rules, the pending-change queue. On every launch it re-registers DeviceActivity schedules and re-applies shields from persisted state, so nothing can drift. |
| `FurloughMonitor` | A DeviceActivity monitor extension. iOS wakes it at window edges, at midnight, and when an app's daily usage reaches its budget. Each callback re-derives the shields from shared state. It also posts the "Window opened", "Window closing", "5 minutes left" and "Time's up" notifications. |
| `FurloughShield` | Draws the block screen: why the app is blocked and when it opens next. |
| `FurloughWidgets` | Home-screen widget and the Live Activity shown while a window is open. |
| `Shared/Core` | Models, the pure rules engine (`Policy`), App Group persistence, and the shield reconciler. Compiled into every target. |

The home screen pages through every managed app. Each page has a living hourglass: the top bulb is the app's current window and drains with the countdown, and the mound turns amber at the "5 minutes left" warning and ember once the budget is spent. The glass is coloured by status everywhere it appears: in the rows, the widget, the Live Activity and the Dynamic Island.

Rules for each app live in an App Group so all four processes read the same state. Apple never tells the app which apps you picked; the tokens are opaque. SwiftUI can still render each app's real icon and name, and you can give each one a nickname that shows on the shield, the widget, and notifications.

Furlough notifies you when a window opens, five minutes before it closes, five minutes before a
budget runs out, and when it is spent. A queued loosening gets two more: one an hour before it
lands, while there is still time to cancel it, and one when it lands.

### The commitment device

- Adding an app is instant. Nothing is enforced until you save its first rule, and that first rule is always "tighter than nothing", so it applies instantly too.
- The **+** button asks **Application** or **Website** first, in a small popover. On the phone both end at Apple's picker, which holds apps, categories and websites alike, but a website is three levels down: **Website** first shows a short sheet with the steps (open a category, scroll past its apps, tap **Add Website**), and the picker repeats them in its footer. On the Mac, Application lists the apps on the Mac and Website asks for a host.
- Shrinking a window, removing a window, taking a day off a window, or lowering a budget applies instantly.
- An app with no windows is open all day, up to its budget. Giving it a first window applies instantly (it is open less than before); removing its last window reopens the whole day, so that waits out the delay.
- Extending a window, adding a window, adding a day to a window, raising a budget, or removing an app is queued for the loosening delay. Pending changes are listed in the app and can be cancelled. Each one shows the rule you have now against the one waiting to replace it, so what the change costs is readable while there is still time to take it back.
- **How much it is worth** puts each app in one of four tiers, and the tier scales its delay: **Essential** waits a quarter of the base, **Useful** the base itself, **Idle** twice it, **Hazard** four times. With the default 24 hours that runs 6 hours for Messages to 4 days for TikTok, and no tier can ever wait less than an hour. A new app is Useful until you say otherwise, and Furlough suggests a tier for the apps and sites it recognises.
- Moving an app toward Hazard lengthens its delay, so it applies the moment you save. Moving it toward Essential shortens the delay, which is itself a loosening: it queues behind the delay that app has *today*. So marking TikTok essential and reopening it in the same save still waits the full four days.
- Blocking an app that is worth keeping says so before you save, and blocking an **Essential** one asks twice. The warning names the actual cost — that blocking Messages stops codes texted to you arriving, that blocking an authenticator stops you signing in anywhere. Furlough has no emergency unblock, so this is the last cheap moment to change your mind. Apps Furlough exists to block are never questioned.
- A window can run past midnight: set 5:00 PM → 4:00 AM and the row says so, marked **+1**, counted as 11 h. Furlough keeps it as the two windows it really is — the evening, and the early morning on the day after — because the rules engine and Screen Time both work a day at a time, and reads it back as the one row you wrote. Pick weekends and Monday morning opens too, because Sunday night is one of the nights you asked for; the budget resets at midnight, so those small hours get a fresh one. The editor says both under the windows.
- When setting up an app, **Use windows from another app** copies another app's windows, days and budget into the editor, so a second app can get the same rule in two taps.
- **Apply these windows to other apps** goes the other way: pick any of the other apps and sites and they all get this rule in one save, along with the app you wrote it on. Each is judged on its own, so it lands now where it is tighter and waits out the delay where it is looser.
- **Visualize windows** opens the week as a seven-column, 24-hour grid. Tap a day to see just its hours, change them, and **Apply to other days** to add the same hours to any other days, on top of what they have.
- Raising the delay is instant. Lowering it loosens every app at once, so it waits out the longest delay in play — the slowest tier you have set, not the base.
- While anything is shielded, iOS is told to deny deleting apps, so the app cannot be removed as a shortcut.
- Moving the clock forward does not buy time. Every save records the wall clock alongside the machine's own count of seconds since it booted, which nothing in Settings can change. When the wall clock has run further ahead than that count — by more than ten minutes, so an ordinary correction is ignored — every queued loosening is held: tightening changes still apply, the Pending screen says **The clock moved forward. Changes wait until it is back.**, and the activity log records it. Setting the clock back releases them, on the phone and on the Mac alike. The gap that is left is a reboot, which starts the machine's count again from zero: a reboot followed by a clock change looks like an ordinary first reading.

### The Anchor

- The Anchor holds its own list of apps, sites, and categories, chosen with the same picker. An app can be in the Anchor and have windows too.
- Tap **Anchor** in the app and everything in the list is shielded immediately, no tag needed. Anchoring is tightening.
- **Unanchor** opens the NFC reader; only the tag you paired releases the anchor, instantly. This is the one unblock in Furlough, and it exists only for the Anchor. Rule-based targets never get one.
- While anchored, the list and the paired tag cannot be changed, so nothing can loosen under the lock. Anchoring is refused until a tag is paired, so there is always a way back.
- **Forget tag** on the Anchor screen unpairs the tag after a confirmation. It is only offered while the anchor is off; forgetting the tag while anchored would leave no way back, so the button is hidden and the model refuses it. Anchoring stays refused until a new tag is paired.
- When the anchor is off, each app falls back to its windows and budget, or to nothing if it has no rule. Anchoring an app that is already outside its window changes nothing visible.
- Pairing reads the tag's hardware identifier; nothing is written, so any NTAG sticker works, or the tag from a Brick if you already own one.
- Anchoring something **Essential** warns first, and asks again before it drops: the anchor is instant, and only the paired tag lifts it, so a tag in another room means Messages stays gone until you find it. The warning can only name anchored apps that Furlough also has a rule for — the anchor may hold apps it has never been given a name for.

The one escape that always exists is Apple's own: **Settings > Screen Time > Apps with Screen Time Access > Furlough > off**. That revokes access and iOS clears every shield and the delete-protection flag. Furlough cannot prevent it, and it documents it on purpose.

## Furlough on the Mac

Apple's Screen Time API does not exist on the Mac: FamilyControls, ManagedSettings and DeviceActivity are marked unavailable for both native macOS and Mac Catalyst, so nothing built on them can shield anything there. `FurloughMac` is a native Mac app that shares the rules engine and the look and enforces on its own:

| On the phone | On the Mac |
|---|---|
| An app is an opaque Screen Time token | An app is its bundle identifier, picked from the apps on the Mac |
| A website is a token | A website is a host, typed in (`youtube.com` also covers `m.youtube.com`) |
| iOS shields a blocked app | Furlough asks it to quit the moment it launches or the window closes, and shows a floating card saying when it opens next. An app that has been open a while gets 45 seconds to answer a "Save changes?" dialog, counted down on the card, before it is force-quit; one that has only just launched has nothing to save and goes at once, so relaunching does not buy more time |
| iOS shields a blocked site | Furlough reads every window's front tab in Safari and the Chromium browsers (Chrome, Arc, Brave, Edge, Vivaldi, Opera, Dia) through Apple Events and sends each one showing a blocked site to its shield page, which draws the same hourglass in the status that site is in — every running browser, not just the one in front |
| iOS counts usage toward the budget | Furlough counts seconds while the app or site is in front and the Mac is not idle; "5 minutes left" and "Time's up" arrive as notifications |
| The home-screen widget | A desktop widget with the same card: **Edit Widgets** on the desktop or in Notification Center, then add Furlough |
| The Live Activity and Dynamic Island | A menu bar item: Furlough's own hourglass, drawn at the level this moment has reached and redrawn as the sand moves, with the countdown and every app's status one click away in its menu. ActivityKit does not exist on the Mac, so like a Live Activity's glass it is a still rather than an animation |
| The Anchor | Nothing: a Mac has no NFC reader |
| Escape: Settings > Screen Time > turn Furlough off | Escape: Force Quit. Quit is refused while anything is blocked; logging out and shutting down are always allowed. Force Quit lifts every block at once, but a launchd agent reopens Furlough about ten seconds later, so it buys nothing worth having. Furlough opens at login |

Windows per weekday, budgets, the pending list and the loosening delay are the same code as the phone, and so are **Visualize windows**, **Use windows from another app** and **Apply these windows to other apps**. The window opens on the phone's hero (design/HOURGLASS.md, header H1): one page per app with the living hourglass, the countdown, and how much of today's budget is used — which the Mac knows because it counts the minutes itself — and a strip of tiny status hourglasses under it that turns the pages and is a status summary in itself. Clicking a page opens that app's rule, which shows the same hero at the top. The sidebar groups apps the way the phone's home screen does. Rules are per device; nothing syncs.

The Mac keeps its rules in an App Group container shared with the widget (`X9V4L6HR2R.com.zachshort.furlough`, under `~/Library/Group Containers`). The first launch of a build that has the widget moves the older store there; nothing is lost.

macOS asks once per browser whether Furlough may control it, the first time Furlough reads that browser while a website has a rule. Refusing means that browser is not enforced; Settings > Browsers shows the status, and System Settings > Privacy & Security > Automation is where to change it. Firefox is not scriptable this way and is not enforced.

Build and install from the command line:

```bash
xcodebuild -project Furlough.xcodeproj -scheme FurloughMac -configuration Release \
  -destination 'platform=macOS,arch=arm64' -allowProvisioningUpdates \
  -derivedDataPath build/DerivedDataMac build
rm -rf /Applications/Furlough.app && ditto build/DerivedDataMac/Build/Products/Release/Furlough.app /Applications/Furlough.app
open /Applications/Furlough.app
```

Or open the project in Xcode, pick the `FurloughMac` scheme and My Mac, and press Run. The app has to live in `/Applications` for the login item to point at it.

## Requirements

- A paid Apple Developer account (Family Controls is not available to Personal Teams).
- Xcode 26 or newer, a physical iPhone. The Screen Time API does not work in the Simulator. The Mac app needs macOS 26.
- [XcodeGen](https://github.com/yonaskolb/XcodeGen): `brew install xcodegen`

## Install from Xcode

```bash
xcodegen generate
open Furlough.xcodeproj
```

1. In Xcode, select the `Furlough` scheme and your iPhone as the run destination.
2. Signing is automatic under team `X9V4L6HR2R`. Xcode registers the four bundle IDs and enables Family Controls (development), App Groups, and NFC Tag Reading on first build.
3. Press Run. On the phone, tap **Allow Screen Time access**, then **Allow** on the iOS prompt.
4. Tap **+** to pick apps and websites. Open each one and set its budget, and windows if you want them; with no windows it is open all day, up to the budget. Turn off **Same every day** to give each window its own days. Save.
5. For the Anchor, open the Anchor card, choose apps, and pair a tag by holding the phone to it. Then **Anchor** locks and **Unanchor** asks for the tag.

Building a fork means replacing my identifiers with yours. Change `DEVELOPMENT_TEAM` and the bundle IDs in `project.yml`, the App Group in each target's `.entitlements`, the watchdog label under `FurloughMac/Resources/LaunchAgents`, and `appGroupID` / `macAppGroupID` in `Shared/Core/Furlough.swift`, then re-run `xcodegen generate`. The Mac group carries the team ID in front of it because macOS will not accept a `group.` prefix without a registered Mac.

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

## Testing builds

Debug builds, which is what Xcode and the commands above produce, add **Settings > Testing > Reset everything**. After a confirmation it forgets every app, rule, pending change and the Anchor with its tag, lifts every shield, and leaves the app as it was right after allowing Screen Time access. Use it to start over after trying a week-long delay or a five-minute budget. It is compiled out of Release builds (`-configuration Release`), so a build you mean to live with keeps its promise of no unblock button. A Debug build of the Mac app has the same button; there it also forgets today's counted minutes, and the app stays set up and running.

The rules engine has its own tests. `Shared/Core` is plain Foundation and builds for macOS, so the whole of it — windows, budgets, per-weekday days, tightening versus loosening, the pending queue, the widget's summary, and decoding state written by older builds — is tested on the Mac with no phone and no host app:

```bash
xcodebuild test -project Furlough.xcodeproj -scheme FurloughCoreTests -destination 'platform=macOS,arch=arm64'
```

## Known limits of the Screen Time API

- Windows must be at least 15 minutes and, as stored, cannot cross midnight. A night is kept as two of them, one either side of midnight, and each half needs its own 15 minutes.
- At most 19 distinct windows across all apps (iOS allows 20 monitored activities, and one is the daily budget tracker).
- The monitor extension can fire a few minutes late, and threshold callbacks occasionally fire twice. Every callback is idempotent, so this is harmless.
- Distributing outside Xcode (TestFlight, App Store) needs the Family Controls distribution entitlement, requested per bundle ID, which can take weeks. `~/Projects/archive/furlough/testflight-deployment/DEPLOYMENT.md` has the request, and everything else the App Store wants.
