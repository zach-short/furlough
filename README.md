# Furlough

A personal iOS and Mac app blocker with no unblock button, and two ways to use it.

**Rules** are the everyday half. Pick the apps and websites that eat your time. Give each one a daily minute budget (say 30 minutes) and, if you want, allowed windows (say 8:00–10:00 PM, or 5:00 PM to 4:00 AM for a weekend night), the same every day or different per day of the week (until midnight on school nights, until 2 AM on weekends). With no windows an app is open all day, up to its budget. Outside the windows, or once the budget is spent, iOS shields the app. The only way to loosen a rule is to wait: loosening edits take effect 24 hours after you make them, and you can cancel them in the meantime. Tightening edits apply instantly.

**The Anchor** is the other half, and it is not a footnote to the first. A separate list you lock in one tap from anywhere — or turn inside out, so the whole device is shielded and the list is what stays open. No delay, no timer, no code: the only thing that lifts it is holding your phone to a physical NFC tag you paired. Any NTAG sticker works, including the one that came with another blocking product. It can drop on a schedule, up to three tags can release it, and it crosses to every device you have linked through your own iCloud, where Furlough on a Mac can drop one that only the phone's tag will lift.

Either half works on its own; neither needs the other.

Built on Apple's Screen Time API (FamilyControls, ManagedSettings, DeviceActivity) and Core NFC. Swift, SwiftUI, no third-party dependencies.

## How it works

| Piece | What it does |
|---|---|
| `Furlough` (app) | Screen Time authorization, the app picker, per-app rules, the pending-change queue. On every launch it re-registers DeviceActivity schedules and re-applies shields from persisted state, so nothing can drift. |
| `FurloughMonitor` | A DeviceActivity monitor extension. iOS wakes it at window edges, at midnight, when an app's daily usage reaches its budget, and at the Anchor's drop and lift times. Each callback re-derives the shields from shared state. It also posts the "Window opened", "Window closing", "5 minutes left", "Time's up", "Anchor dropped" and "Anchor lifted" notifications. |
| `FurloughShield` | Draws the block screen: why the app is blocked and when it opens next. |
| `FurloughWidgets` | Home-screen widget with an Anchor button, the Live Activity shown while a window is open, and the Drop Anchor control for Control Center. The activity for the next window is asked for ahead of time, so it arrives on the Lock Screen by itself, with the phone locked and Furlough closed. |
| `Shared/Core` | Models, the pure rules engine (`Policy`), App Group persistence, and the shield reconciler. Compiled into every target. |

The home screen pages through every managed app. Each page has a living hourglass: the top bulb is the app's current window and drains with the countdown, and the mound turns amber at the "5 minutes left" warning and ember once the budget is spent. The glass is coloured by status everywhere it appears: in the rows, the widget, the Live Activity and the Dynamic Island.

Rules for each app live in an App Group so all four processes read the same state. Apple never tells the app which apps you picked; the tokens are opaque. SwiftUI can still render each app's real icon and name, and you can give each one a nickname that shows on the shield, the widget, and notifications.

Furlough notifies you when a window opens, five minutes before it closes, five minutes before a
budget runs out, and when it is spent. A queued loosening gets two more: one an hour before it
lands, while there is still time to cancel it, and one when it lands.

Settings on the phone and the foot of the sidebar on the Mac carry **the record**: days in a row
with no budget spent, how long apps were held shut this week and how much of that the Anchor
held, loosenings cancelled against loosenings landed, and the longest the Anchor has ever held.
It is kept for 60 days and it is not a scoreboard — a streak that broke says so, and the phone
cannot see how much of a budget you actually used, only whether it ran out, so the record does
not pretend to.

### The commitment device

- Adding an app is instant. Nothing is enforced until you save its first rule, and that first rule is always "tighter than nothing", so it applies instantly too.
- The **+** button asks **Application** or **Website** first, in a small popover. On the phone both end at Apple's picker, which holds apps, categories and websites alike, but a website is three levels down: **Website** first shows a short sheet with the steps (open a category, scroll past its apps, tap **Add Website**), and the picker repeats them in its footer. On the Mac, Application lists the apps on the Mac and Website asks for a host.
- Shrinking a window, removing a window, taking a day off a window, or lowering a budget applies instantly.
- An app with no windows is open all day, up to its budget. Giving it a first window applies instantly (it is open less than before); removing its last window reopens the whole day, so that waits out the delay.
- Extending a window, adding a window, adding a day to a window, raising a budget, or removing an app is queued for the loosening delay. Pending changes are listed in the app and can be cancelled. Each one shows the rule you have now against the one waiting to replace it, so what the change costs is readable while there is still time to take it back.
- **How much it is worth** puts each app in one of four tiers, and the tier scales its delay: **Essential** waits a quarter of the base, **Useful** the base itself, **Idle** twice it, **Hazard** four times. With the default 24 hours that runs 6 hours for Messages to 4 days for TikTok, and no tier can ever wait less than an hour. A new app is Useful until you say otherwise, and Furlough suggests a tier for the apps and sites it recognises.
- Moving an app toward Hazard lengthens its delay, so it applies the moment you save. Moving it toward Essential shortens the delay, which is itself a loosening: it queues behind the delay that app has *today*. So marking TikTok essential and reopening it in the same save still waits the full four days.
- Blocking an app that is worth keeping says so before you save, and blocking an **Essential** one asks twice. The warning names the actual cost — that blocking Messages stops codes texted to you arriving, that blocking an authenticator stops you signing in anywhere. Furlough has no emergency unblock, so this is the last cheap moment to change your mind. Apps Furlough exists to block are never questioned.
- **Your first week is gentler.** For seven days after you first allow Screen Time access, a loosening waits one hour instead of the full delay. Everything else is real from the first minute: the windows, the budgets, the shields. Only the price of a mistake is held down, so nothing you try out while you are still learning what the app does can lock you out for a day. The week starts when you allow access, ends on a date fixed at that moment, cannot be extended, and is granted once per install — turning Screen Time access off and on again does not buy another one. Onboarding says it is coming and Settings counts it down, so the first delay that is real is never a surprise.
- **An edit can be taken back for 15 minutes.** Right after a rule lands, the editor offers to put it back *exactly* as it was. This is not an unblock and cannot be used as one: it restores the rule that was already in force, so if an app was shut before the edit, undoing puts it back to shut. It is no use to anyone who wants out, and every use to someone who mistyped a budget. There is no count to spend and nothing to hoard.
- **Before you save, the editor says what the rule will do**: when today's window opens and closes, when the budget runs out, and what changing your mind will cost — both while the first week runs and after it ends. Most of the trouble a new user gets into is not that they cannot undo a rule, it is that they could not see what the rule meant.
- A window can run past midnight: set 5:00 PM → 4:00 AM and the row says so, marked **+1**, counted as 11 h. Furlough keeps it as the two windows it really is — the evening, and the early morning on the day after — because the rules engine and Screen Time both work a day at a time, and reads it back as the one row you wrote. Pick weekends and Monday morning opens too, because Sunday night is one of the nights you asked for; the budget resets at midnight, so those small hours get a fresh one. The editor says both under the windows.
- When setting up an app, **Use windows from another app** copies another app's windows, days and budget into the editor, so a second app can get the same rule in two taps.
- **Apply these windows to other apps** goes the other way: pick any of the other apps and sites and they all get this rule in one save, along with the app you wrote it on. Each is judged on its own, so it lands now where it is tighter and waits out the delay where it is looser.
- **Visualize windows** opens the week as a seven-column, 24-hour grid. Tap a day to see just its hours, change them, and **Apply to other days** to add the same hours to any other days, on top of what they have.
- Raising the delay is instant. Lowering it loosens every app at once, so it waits out the longest delay in play — the slowest tier you have set, not the base.
- While anything is shielded, iOS is told to deny deleting apps, so the app cannot be removed as a shortcut.
- Moving the clock forward does not buy time. Every save records the wall clock alongside the machine's own count of seconds since it booted, which nothing in Settings can change. When the wall clock has run further ahead than that count — by more than ten minutes, so an ordinary correction is ignored — every queued loosening is held: tightening changes still apply, the Pending screen says **The clock moved forward. Changes wait until it is back.**, and the activity log records it. Setting the clock back releases them, on the phone and on the Mac alike. The gap that is left is a reboot, which starts the machine's count again from zero: a reboot followed by a clock change looks like an ordinary first reading.

### The Anchor

- The Anchor holds its own list of apps, sites, and categories, chosen with the same picker. An app can be in the Anchor and have windows too.
- **Or the whole phone.** The Anchor screen has a scope: **Chosen apps**, which is the list above, or **Everything except**, where the list is what stays open and everything else on the phone is shielded while anchored. The allowlist starts as every app you tiered Essential, so Messages and your authenticator stay reachable unless you take them off it; taking an Essential app off warns exactly as anchoring it singly does. What is on the list keeps its own windows and budget. Switching scope starts the list again, because a list that means "held" under one scope would mean "let through" under the other, and the screen says so before it switches.
- Setting it up starts with what you already block. The first time you choose apps, the Anchor offers every app and site that has a rule, all checked, with **All** / **None** and a row each. Add them in one tap, or go on to Apple's picker for anything else; after that, **Change apps** opens the picker with the list filled in.
- Tap **Anchor** in the app and everything in the list is shielded immediately, no tag needed. Anchoring is tightening.
- **Or drop it from anywhere.** The medium widget has an Anchor button, Control Center has a Drop Anchor control, and Spotlight and Shortcuts have the same action, so "at 10 PM, drop anchor" is one automation away. None of them can release it: that stays in the app behind the tag.
- **Or on a timer.** On the Anchor screen, **Lifts by itself** with a time makes the next drop a timed one: it lifts at that time, or sooner with the tag. Off, only the tag lifts it, as ever. A timed drop needs at least 15 minutes, because that is the shortest wake iOS will schedule.
- **Or on a schedule.** The Anchor screen's schedule drops the anchor by itself at a time of day on the days you choose, holding until the tag unless you give that drop a lift time — 10 PM on school nights and only the tag in the morning is the case it was built for. Adding a drop time, adding a day, or making a hold longer applies at once. Removing a drop time, taking a day off it, or making a hold shorter is a loosening: it waits out the delay, shows in Pending, and can be cancelled until it lands, because a schedule that can be deleted at 9:59 PM is not a commitment. Furlough tells you when a scheduled anchor drops, and when a timed one lifts.
- **Unanchor** opens the NFC reader; only the tag you paired releases the anchor, instantly. This is the one unblock in Furlough, and it exists only for the Anchor. Rule-based targets never get one.
- While anchored, the list and the paired tag cannot be changed, so nothing can loosen under the lock. Anchoring is refused until a tag is paired, so there is always a way back.
- **Forget tag** on the Anchor screen unpairs the tag after a confirmation. It is only offered while the anchor is off; forgetting the tag while anchored would leave no way back, so the button is hidden and the model refuses it. Anchoring stays refused until a new tag is paired.
- When the anchor is off, each app falls back to its windows and budget, or to nothing if it has no rule. Anchoring an app that is already outside its window changes nothing visible.
- Pairing reads the tag's hardware identifier; nothing is written, so any NTAG sticker works, or the tag from a Brick if you already own one.
- Anchoring something **Essential** warns first, and asks again before it drops: the anchor is instant, and only the paired tag lifts it, so a tag in another room means Messages stays gone until you find it. The warning can only name anchored apps that Furlough also has a rule for — the anchor may hold apps it has never been given a name for.
- **Across devices.** Each device joins the link from its own Devices screen — Settings > Devices, after four short things to know — and nothing crosses to or from one that has not. Once on it: drop anchor on the iPhone and every linked device locks; drop it on the Mac and the iPhone locks; scan the tag on the iPhone and all of them release. The Anchor's state — down or not, since when, until when — travels through your own iCloud key-value store, with no account of Furlough's and no server, and so does the roster: one small entry per device, by the name you gave it. Each device keeps its own list, because a Screen Time token means nothing off the phone that minted it and a bundle identifier means nothing on it — but what goes on one list can cross to the others by name, under *Send what I add* below, so anchoring YouTube on the iPhone puts YouTube on the Mac's list too. The Mac and the iPad have no tag reader, so they can be anchored but never release, and the Mac refuses to drop until an iPhone is on the link with it, so it can never lock itself with no key. It refuses for the same reason when it is signed out of iCloud or has iCloud Drive off, since no tag could reach it then either. Both devices say so on the Anchor screen rather than failing quietly. Nothing already holding is lifted by any of it. A device that cannot reach iCloud keeps its last state, and a Mac hears of a drop within about half a minute of it reaching iCloud.

- **What you add can cross too.** Three settings under Devices, each Always, Ask or Never. *Block the website too* (Always by default) links the site an app is also at — YouTube, youtube.com — onto the app's row the moment Furlough knows the app's name, so blocking one blocks both; taking the site back off is free for a quarter of an hour and a loosening after. *Send what I add* (Ask) tells the other devices the name of what you add — never a token, never a rule of yours — and each blocks what it can find under it: the Mac the app if it has one and the site either way, the iPhone the site at once and the app through Apple's picker. Its first rule follows the name. *Take what my other devices add* (Ask) is the receiving end's own say. On the phone a picked app can only cross, or be paired with its site, once Furlough has seen it: right away with Screen Time data access, otherwise the first time the shield covers it.

  Both settings cover the Anchor's list as well as your rules, and they say which half a name came from. Put something on the Anchor's list here and the others are told it is *anchored*, not merely blocked: each puts it on its own list, so it goes away the next time any of them drops. Anchoring is the bigger fact, so it asks in its own right under Ask — agreeing to send a thing's hours is not agreeing to this — and the card appears on the Anchor screen rather than under Devices, on the half it is about. Nothing crosses under the everything-except scope, where the list is what stays *open* and sending it would say the opposite of what it means, and nothing lands on a device whose anchor is down, because nothing changes a list under a lock. Something already blocked on the receiving device still lands: there is nothing new to block, and its place on that device's Anchor list is the whole of the message. On the phone an arriving app needs Apple's picker as ever, unless Screen Time data access is on, in which case Furlough matches the name to the token itself and puts it on the list with no picker at all. Taking something back *off* a list never crosses; the link only ever tightens.

Any device can be taken off the link from any other, except while the anchor is down: taking one off then would either leave it locked with no key or let it go, and both are what the Anchor exists to prevent.

The one escape that always exists is Apple's own: **Settings > Screen Time > Apps with Screen Time Access > Furlough > off**. That revokes access and iOS clears every shield and the delete-protection flag. Furlough cannot prevent it, and it documents it on purpose.

## Furlough on the Mac

Apple's Screen Time API does not exist on the Mac: FamilyControls, ManagedSettings and DeviceActivity are marked unavailable for both native macOS and Mac Catalyst, so nothing built on them can shield anything there. `FurloughMac` is a native Mac app that shares the rules engine and the look and enforces on its own:

| On the phone | On the Mac |
|---|---|
| An app is an opaque Screen Time token | An app is its bundle identifier, picked from the apps on the Mac |
| A website is a token | A website is a host, typed in (`youtube.com` also covers `m.youtube.com`) |
| iOS shields a blocked app | Furlough asks it to quit the moment it launches or the window closes, and shows a floating card saying when it opens next. An app that has been open a while gets 45 seconds to answer a "Save changes?" dialog, counted down on the card, before it is force-quit; one that has only just launched has nothing to save and goes at once, so relaunching does not buy more time |
| iOS shields a blocked site | Furlough reads every window's front tab in Safari and the Chromium browsers (Chrome, Arc, Brave, Edge, Vivaldi, Opera, Dia) through Apple Events and sends each one showing a blocked site to its shield page, which draws the same hourglass in the status that site is in — every running browser, not just the one in front. With the optional web filter installed, a system extension also refuses the connection itself, from any app: Firefox, a site saved to the Dock as an app, anything that loads a blocked site outside a browser. Those get the floating card instead of the shield page |
| iOS counts usage toward the budget | Furlough counts seconds while the app or site is in front and the Mac is not idle; "5 minutes left" and "Time's up" arrive as notifications |
| The home-screen widget | A desktop widget with the same card: **Edit Widgets** on the desktop or in Notification Center, then add Furlough |
| The Live Activity and Dynamic Island | A menu bar item: Furlough's own hourglass, drawn at the level this moment has reached and redrawn as the sand moves, with the countdown and every app's status one click away in its menu. ActivityKit does not exist on the Mac, so like a Live Activity's glass it is a still rather than an animation |
| The Anchor | Its own list of apps and sites, chosen from what is on the Mac, or everything except a list, with the same scope as the phone. **Drop anchor** locks the Mac and, through iCloud, every linked device; anchored apps are quit and anchored sites go to the shield page. No tag reader here, so the Mac never releases: scanning the tag on the iPhone releases all of them |
| Escape: Settings > Screen Time > turn Furlough off | Escape: Force Quit. Quit is refused while anything is blocked; logging out and shutting down are always allowed. Force Quit lifts every app block and tab redirect at once, but a launchd agent reopens Furlough about ten seconds later, so it buys nothing worth having; the web filter keeps its last list until the next window edge or until Furlough is back, whichever comes first. Furlough opens at login |

Windows per weekday, budgets, the pending list and the loosening delay are the same code as the phone, and so are **Visualize windows**, **Use windows from another app** and **Apply these windows to other apps**. The window opens on the phone's hero (design/HOURGLASS.md, header H1): one page per app with the living hourglass, the countdown, and how much of today's budget is used — which the Mac knows because it counts the minutes itself — and a strip of tiny status hourglasses under it that turns the pages and is a status summary in itself. Clicking a page opens that app's rule, which shows the same hero at the top. The sidebar groups apps the way the phone's home screen does. Rules and lists are per device: what syncs is the Anchor's state, and the *names* of what you add or anchor, where the Devices settings say so.

The Mac keeps its rules in an App Group container shared with the widget (`X9V4L6HR2R.com.zachshort.furlough`, under `~/Library/Group Containers`). The first launch of a build that has the widget moves the older store there; nothing is lost.

macOS asks once per browser whether Furlough may control it, the first time Furlough reads that browser while a website has a rule. Refusing means that browser is not enforced; Settings > Web shows the status, and System Settings > Privacy & Security > Automation is where to change it. Firefox is not scriptable this way, so on its own the tab reader does not reach it.

The web filter is the second half, and it is optional. Onboarding offers it and Settings > Web installs it: a network content filter that macOS runs as a system extension, which sees every connection the Mac opens and refuses the ones to a blocked site, whatever app opened them. macOS asks twice, once to allow the extension under System Settings > General > Login Items & Extensions and once to let it filter, and it can be switched off there at any time; Settings > Web says so when it has been, and the tab reader keeps enforcing regardless. The filter reads a site's name off the connection (the name the app asked for, or the one in the TLS hello), and while anything is blocked it refuses nameless QUIC connections so the browser falls back to the kind it can read. It blocks nothing past the moment the rules say a status could change, so a list left behind by a force quit lapses on its own.

Build and install from the command line:

```bash
xcodebuild -project Furlough.xcodeproj -scheme FurloughMac -configuration Release \
  -destination 'platform=macOS,arch=arm64' -allowProvisioningUpdates -allowProvisioningDeviceRegistration \
  -derivedDataPath build/DerivedDataMac build
rm -rf /Applications/Furlough.app && ditto build/DerivedDataMac/Build/Products/Release/Furlough.app /Applications/Furlough.app
open /Applications/Furlough.app
```

Or open the project in Xcode, pick the `FurloughMac` scheme and My Mac, and press Run. The app has to live in `/Applications` for the login item to point at it, and macOS will only load the web filter from there.

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

Building a fork means replacing my identifiers with yours. Change `DEVELOPMENT_TEAM` and the bundle IDs in `project.yml`, the App Group in each target's `.entitlements`, the watchdog label under `FurloughMac/Resources/LaunchAgents`, `appGroupID` / `macAppGroupID` in `Shared/Core/Furlough.swift`, and the web filter's identifier and Mach service name in `FurloughMacFilter/FilterXPC.swift` and its `NEMachServiceName` in `project.yml`, then re-run `xcodegen generate`. The Mac group carries the team ID in front of it because macOS will not accept a `group.` prefix without a registered Mac, and the service name has to start with that group.

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

Debug builds, which is what Xcode and the commands above produce, add **Settings > Testing > Reset everything**. After a confirmation it forgets every app, rule, pending change and the Anchor with its tag, lifts every shield, hands Screen Time access back to iOS, and returns to onboarding, so the whole first run — the grant, the first week it starts, the usage step — can be walked again. Use it to start over after trying a week-long delay or a five-minute budget. What it keeps is the notification permission, which iOS only ever asks about once. The Mac app has the same button and it goes the same distance: it also forgets today's counted minutes, takes the login item and the watchdog agent back off, and returns to its own onboarding. What it keeps there is the web filter system extension and the per-browser Automation permissions, which the app cannot ask for again from the inside and macOS would make you approve again by hand.

It is compiled out of Release builds, so a build you mean to live with keeps its promise of no unblock button. A Release build that should carry it — a TestFlight round where wiping the setup on the phone is the point — has to ask by name:

```bash
TESTING_TOOLS=1 scripts/archive.sh
```

```bash
xcodebuild -project Furlough.xcodeproj -scheme FurloughMac -configuration Release -derivedDataPath build/DerivedDataMac SWIFT_ACTIVE_COMPILATION_CONDITIONS='$(inherited) TESTING_TOOLS' build
```

TestFlight and the App Store are the same binary — a build is promoted, not rebuilt — so a build made this way still keeps the section put away: it shows only after **five taps on the Version row** (Settings > About on the phone, Help > About on the Mac), and **Hide these buttons** puts it back. `scripts/archive.sh` knows about the flag both ways: it refuses to ship a plain archive that carries the testing code, and refuses a `TESTING_TOOLS=1` archive that does not. A build made with the flag must never be the one submitted for review. See `Shared/Core/TestingTools.swift`.

The rules engine has its own tests. `Shared/Core` is plain Foundation and builds for macOS, so the whole of it — windows, budgets, per-weekday days, tightening versus loosening, the pending queue, the widget's summary, and decoding state written by older builds — is tested on the Mac with no phone and no host app:

```bash
xcodebuild test -project Furlough.xcodeproj -scheme FurloughCoreTests -destination 'platform=macOS,arch=arm64'
```

## Known limits of the Screen Time API

- Windows must be at least 15 minutes and, as stored, cannot cross midnight. A night is kept as two of them, one either side of midnight, and each half needs its own 15 minutes.
- At most 19 distinct windows across all apps (iOS allows 20 monitored activities, and one is the daily budget tracker).
- The monitor extension can fire a few minutes late, and threshold callbacks occasionally fire twice. Every callback is idempotent, so this is harmless.
- Anchoring **Everything except** a list shields every app and website iOS lets a shield cover, through `.all(except:)` on the app and website category shields, plus the web content filter for every browser. iOS keeps some of its own apps outside every shield, so those stay reachable however the anchor is set; the site's Anchor help page records which, as they are confirmed on a phone. Websites off the list are blocked by the content filter as well as the shield, so a browser other than Safari shows iOS's own "Website Not Allowed" page, and an app on the list that loads web content inside itself may be blocked from doing so. A category cannot be excepted from a shield over everything, so the allowlist holds apps and sites only; picking a category in the picker puts its apps on the list one by one.
- Distributing outside Xcode (TestFlight, App Store) needs the Family Controls distribution entitlement, requested per bundle ID, which can take weeks. `~/Projects/archive/furlough/testflight-deployment/DEPLOYMENT.md` has the request, and everything else the App Store wants.
