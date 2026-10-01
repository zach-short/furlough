# Furlough

A personal iOS and Mac app blocker with no unblock button, and two ways to use it.

**Rules** are the everyday half. Pick the apps and websites that eat your time. Give each one a daily minute budget (say 30 minutes) and, if you want, allowed windows (say 8:00 to 10:00 PM, or 5:00 PM to 4:00 AM for a weekend night). Windows can be the same every day or different per day of the week (until midnight on school nights, until 2 AM on weekends). With no windows an app is open all day, up to its budget. Outside the windows, or once the budget is spent, iOS shields the app. The only way to loosen a rule is to wait: loosening edits take effect 24 hours after you make them, and you can cancel them in the meantime. Tightening edits apply instantly.

**The Anchor** is the other half, and it is not a footnote to the first. It is a separate list that you lock in one tap from anywhere, or turn inside out so that the whole device is shielded and the list is what stays open. There is no delay and no code. By default the only thing that lifts it is holding your phone to a physical NFC tag that you paired. Any NTAG sticker works, including the one that came with another blocking product. The Anchor can drop on a schedule, up to three tags can release it, and it crosses to every device you have linked through your own iCloud. Furlough on a Mac can drop an anchor that only the phone's tag will lift.

Either half works on its own, and neither needs the other.

Furlough is built on Apple's Screen Time API (FamilyControls, ManagedSettings, DeviceActivity) and Core NFC, in Swift and SwiftUI, with no third-party dependencies. The iOS app runs on iPhone and iPad. An iPad has no tag reader, so it can be anchored but cannot lift an anchor. The Mac app is a separate native target that enforces on its own, because Apple's Screen Time API does not exist on macOS.

Furlough for Mac is a download at [furloughapp.com](https://furloughapp.com/#download), signed with a Developer ID and notarized by Apple, so nothing has to be built to run it. Furlough for iPhone is [on the App Store](https://apps.apple.com/app/id6810006594). To build from source, to run a fork or a build ahead of what has shipped, see [Install from Xcode](#install-from-xcode).

## How it works

| Piece | What it does |
|---|---|
| `Furlough` (app) | Screen Time authorization, the app picker, per-app rules and the pending-change queue. On every launch it registers the DeviceActivity schedules again and re-applies shields from persisted state, so nothing can drift. |
| `FurloughMonitor` | A DeviceActivity monitor extension. iOS wakes it at window edges, at midnight, when an app's daily usage reaches its budget, and at the Anchor's drop and lift times. Each callback derives the shields again from shared state. It also posts the notifications listed below. |
| `FurloughShield` | Draws the block screen: why the app is blocked and when it opens next. |
| `FurloughWidgets` | The home-screen widget with an Anchor button, the Live Activity shown while a window is open, the Anchor's own Live Activity, and the Drop Anchor control for Control Center. The activity for the next window is requested ahead of time, so it reaches the Lock Screen with the phone locked and Furlough closed. |
| `FurloughReport` | A DeviceActivityReport extension. iOS hands usage history to a report extension and nowhere else, so on a phone where the app cannot read Screen Time data itself, this extension draws the "Where the time goes" page. It has no App Group and writes no state. |
| `Shared/Core` | Models, the pure rules engine (`Policy`), App Group persistence, and the shield reconciler. It is compiled into every target. |

The home screen pages through every managed app. Each page has a living hourglass: the top bulb is the app's current window and drains with the countdown, and the mound turns amber at the "5 minutes left" warning and ember once the budget is spent. The glass is coloured by status everywhere it appears: in the rows, the widget, the Live Activity and the Dynamic Island.

Rules for each app live in an App Group, so the app, the monitor, the shield and the widgets all read the same state. Apple never tells the app which apps you picked, because the tokens are opaque. SwiftUI can still render each app's real icon and name, and you can give each one a nickname that shows on the shield, the widget and notifications.

Furlough has nine kinds of notification, and each has its own switch under Settings > Notifications: a window opening, a window closing in five minutes, five minutes of budget left, a budget spent, the Anchor dropping, a timed Anchor lifting, a queued loosening landing in an hour (while there is still time to cancel it), a queued loosening landing, and a weekly digest on Monday at 9 AM. The four that mark a moment of temptation (a window opening or closing, five minutes left, and a spent budget) carry a Drop anchor button.

Settings on the phone and the foot of the sidebar on the Mac carry the record: days in a row with no budget spent, how long apps were held shut this week and how much of that the Anchor held, loosenings cancelled against loosenings landed, and the longest the Anchor has ever held. It is kept for 60 days. It is not a scoreboard. A streak that broke says so, and the phone cannot see how much of a budget you used, only whether it ran out, so the record does not claim to.

Settings also has "Where the time goes", a page that ranks the last fortnight app by app and suggests rules. The app reads Screen Time data itself when that access is granted, which needs iOS 26.4 or newer and the `com.apple.developer.family-controls.app-and-website-usage` entitlement. On a phone where the access is refused, the `FurloughReport` extension draws the ranking instead.

### The commitment device

- Adding an app is instant. Nothing is enforced until you save its first rule, and that first rule is always tighter than nothing, so it applies instantly too.
- The + button asks Application or Website first, in a small popover. On the phone, Application goes straight to Apple's picker, which holds apps, categories and websites alike. Website opens a sheet where you type an address. A typed site gets its hours enforced but no daily budget, and iOS shows its own "Website Not Allowed" page instead of Furlough's shield. A site that needs a budget has to come from Apple's picker, which buries websites three levels down, so the sheet also offers a short guide (open a category, scroll past its apps, tap Add Website) before it opens the picker. On the Mac, Application lists the apps on the Mac and Website asks for a host.
- Shrinking a window, removing a window, taking a day off a window, or lowering a budget applies instantly.
- An app with no windows is open all day, up to its budget. Giving it a first window applies instantly, because it is then open less than before. Removing its last window reopens the whole day, so that waits out the delay.
- Extending a window, adding a window, adding a day to a window, raising a budget, or removing an app is queued for the loosening delay. Pending changes are listed in the app and can be cancelled. Each one shows the rule you have now beside the one waiting to replace it, so the cost of the change is readable while there is still time to take it back.
- Each app has a worth, in one of four tiers, and the tier scales its delay. Essential waits a quarter of the base, Useful the base itself, Idle twice it, and Hazard four times. With the default 24 hours that runs from 6 hours for Messages to 4 days for TikTok, and no tier waits less than an hour. A new app is Useful until you say otherwise, and Furlough suggests a tier for the apps and sites it recognises.
- Moving an app toward Hazard lengthens its delay, so it applies the moment you save. Moving it toward Essential shortens the delay, which is itself a loosening: it queues behind the delay that app has today. Marking TikTok essential and reopening it in the same save therefore still waits the full four days.
- Blocking an app that is worth keeping says so before you save, and blocking an Essential one asks twice. The warning names the actual cost: blocking Messages stops codes texted to you from arriving, and blocking an authenticator stops you signing in anywhere. Furlough has no emergency unblock, so this is the last cheap moment to change your mind. Apps that Furlough exists to block are never questioned.
- Your first week is gentler. For seven days after you first allow Screen Time access, a loosening waits one hour instead of the full delay. Everything else is real from the first minute: the windows, the budgets and the shields. Only the price of a mistake is lower, so nothing you try while you are still learning the app can lock you out for a day. The week starts when you allow access, ends on a date fixed at that moment, and cannot be extended. It is granted once per install, so turning Screen Time access off and on again does not buy another. Onboarding says it is coming and Settings counts it down, so the first delay that is real is never a surprise. The Anchor gets no first week.
- An edit can be taken back for 15 minutes. Right after a rule lands, the editor offers to put it back exactly as it was. This is not an unblock and cannot be used as one: it restores the rule that was already in force, so if an app was shut before the edit, undoing puts it back to shut. It helps someone who mistyped a budget and does nothing for someone who wants out. There is no count to spend and nothing to hoard.
- Before you save, the editor says what the rule will do: when today's window opens and closes, when the budget runs out, and what changing your mind will cost, both while the first week runs and after it ends. Most early trouble comes from a rule whose meaning was not visible.
- A window can run past midnight. Set 5:00 PM to 4:00 AM and the row says so, marked +1 and counted as 11 h. Furlough stores it as the two windows it really is, the evening and the early morning on the day after, because the rules engine and Screen Time both work a day at a time, and it reads the pair back as the one row you wrote. Pick weekends and Monday morning opens too, because Sunday night is one of the nights you asked for. The budget resets at midnight, so those small hours get a fresh one. The editor says both under the windows.
- When setting up an app, "Use windows from another app" copies another app's windows, days and budget into the editor, so a second app can get the same rule in two taps.
- "Apply these windows to other apps" goes the other way. Pick any of the other apps and sites and they all get this rule in one save, along with the app you wrote it on. Each is judged on its own, so it lands now where it is tighter and waits out the delay where it is looser.
- "Visualize windows" opens the week as a seven-column, 24-hour grid that you edit directly. Drag a window to move it within its day, drag its top or bottom edge to resize it, tap empty track to add one, and use the context menu to delete one. Edits snap to 15 minutes. The day's name opens that day's exact times, and "Apply to other days" there adds the same hours to any other days, on top of what they have.
- Raising the delay is instant. Lowering it loosens every app at once, so it waits out the longest delay in play, which is the slowest tier you have set and not the base.
- While anything is shielded, iOS is told to deny deleting apps, so the app cannot be removed as a shortcut.
- Moving the clock forward does not buy time. Every save records the wall clock alongside the machine's own count of seconds since it booted, which nothing in Settings can change. When the wall clock has run further ahead than that count, by more than ten minutes so that an ordinary correction is ignored, every queued loosening is held. Tightening changes still apply, the Pending screen says "The clock moved forward. Changes wait until it is back.", and the activity log records it. Setting the clock back releases them, on the phone and on the Mac alike. The gap that is left is a reboot, which starts the machine's count again from zero: a reboot followed by a clock change looks like an ordinary first reading.
- Moving the time zone does not buy time either. A zone change moves neither of those numbers, because the same instant is the same moment everywhere, but it re-reads every window against different local hours, so a 10 PM window would open at 9 AM the moment the zone was set to Tokyo. Instead Furlough keeps honouring the zone you left for the base loosening delay. Every rule is decided under both zones and the stricter answer wins, and the day a budget was spent on stays the old zone's day, so it does not refill at a midnight that only the setting brought. The Pending screen names the new zone, the zone Furlough is keeping and the time the hold ends, the activity log records the move, and the hold lapses on its own. Changing the clocks for daylight saving is not a zone change and holds nothing.

### The Anchor

- The Anchor holds its own list of apps, sites and categories, chosen with the same picker. An app can be in the Anchor and have windows too.
- The whole phone can be anchored. The Anchor screen has a scope. Chosen apps is the list above. Everything except turns the list inside out: the list is what stays open, and everything else on the phone is shielded while anchored. The allowlist starts as every app you tiered Essential, so Messages and your authenticator stay reachable unless you take them off it, and taking an Essential app off warns exactly as anchoring it singly does. What is on the list keeps its own windows and budget. Switching scope starts the list again, because a list that means "held" under one scope would mean "let through" under the other, and the screen says so before it switches.
- Setting it up starts with what you already block. The first time you choose apps, the Anchor offers every app and site that has a rule, all checked, with All and None and a row for each. Add them in one tap, or go on to Apple's picker for anything else. After that, "Change apps" opens the picker with the list filled in.
- Tap Anchor in the app and, by default, it asks you to hold up your tag before it locks. That is the same ritual as lifting it, so the two ends of the anchor feel like one gesture. Turn off "Require the tag to anchor" under Tags and tapping Anchor shields the list immediately, with no tag. A device with no tag reader always locks at once. Anchoring is tightening either way, so it is never delayed. A haptic and a short chime confirm a lock and a release, and one switch under Tags ("Haptic and sound on anchor and unanchor") turns both off.
- While the anchor holds, the Anchor page shrinks to one glowing mark, a line saying what is held and since when, and up to three buttons that appear only when they are true right now: the held apps, a linked device, and the time it lifts. Tapping the mark starts the tag scan that lifts it. A Live Activity shows the hold on the Lock Screen. A timed hold counts down to its lift and a tag-only hold counts up from its drop. The activity has no button, because the only button that could belong there is a release.
- The anchor can be dropped from anywhere. The medium widget has an Anchor button, Control Center has a Drop Anchor control, and Spotlight and Shortcuts have the same action, so "at 10 PM, drop anchor" is one automation away. The shortcut can also name a time of day for the anchor to lift. The notifications that mark a moment of temptation carry a Drop anchor button, and a Focus Filter can drop the anchor when a Focus turns on, on the Mac as well as the phone. None of these can release it: that stays in the app, behind the tag.
- The anchor can lift on a timer. On the Anchor screen, "Lifts by itself" with a time makes the next drop a timed one: it lifts at that time, or sooner with the tag. Off, only the tag lifts it, as ever. A timed drop needs at least 15 minutes, because that is the shortest wake iOS will schedule.
- The anchor can drop on a schedule. The Anchor screen's schedule drops the anchor by itself at a time of day on the days you choose, holding until the tag unless you give that drop a lift time. The case it was built for is 10 PM on school nights with only the tag in the morning. Adding a drop time, adding a day, or making a hold longer applies at once. Removing a drop time, taking a day off it, or making a hold shorter is a loosening: it waits out the delay, shows in Pending, and can be cancelled until it lands, because a schedule that can be deleted at 9:59 PM is not a commitment. Furlough tells you when a scheduled anchor drops and when a timed one lifts.
- Unanchor opens the NFC reader, and only a tag you paired releases the anchor, instantly. This is the one unblock in Furlough, and it exists only for the Anchor. Rule-based targets never get one.
- While anchored, the list and the paired tags cannot be changed, so nothing can loosen under the lock. Anchoring is refused until a tag is paired, so there is always a way back.
- "Forget tag" on the Anchor screen unpairs a tag after a confirmation. It is offered only while the anchor is off, because forgetting the last tag while anchored would leave no way back, so the button is hidden and the model refuses it. Anchoring stays refused until a new tag is paired.
- When the anchor is off, each app falls back to its windows and budget, or to nothing if it has no rule. Anchoring an app that is already outside its window changes nothing visible.
- Pairing reads the tag's hardware identifier and writes nothing, so any NTAG sticker works, or the tag from a Brick if you already own one. Up to three tags can be paired, so a tag can live at each place you do.
- Anchoring something Essential warns first, and asks again before it drops. Anchoring is never delayed and only a paired tag lifts it, so a tag in another room means Messages stays gone until you find it. The warning can only name anchored apps that Furlough also has a rule for, because the anchor may hold apps it has never been given a name for.

#### Across devices

Each device joins the link from its own Devices screen (Settings > Devices, after four short things to know), and nothing crosses to or from a device that has not. Once on the link, dropping the anchor on the iPhone locks every linked device, dropping it on the Mac locks the iPhone, and scanning the tag on the iPhone releases all of them. The Anchor's state (down or not, since when, until when) travels through your own iCloud key-value store, with no account of Furlough's and no server. So does the roster: one small entry per device, under the name you gave it.

Each device keeps its own list, because a Screen Time token means nothing off the phone that minted it and a bundle identifier means nothing on it. What goes on one list can cross to the others by name, as described below, so anchoring YouTube on the iPhone puts YouTube on the Mac's list too. The Mac and the iPad have no tag reader, so they can be anchored but never release. The Mac refuses to drop until an iPhone is on the link with it, so it can never lock itself with no tag to lift it. It refuses for the same reason when it is signed out of iCloud or has iCloud Drive off, since no tag could reach it then either. Both devices say so on the Anchor screen and do not fail quietly. Nothing that is already holding is lifted by the link. A device that cannot reach iCloud keeps its last state, and a Mac hears of a drop within about half a minute of it reaching iCloud. Any device can be taken off the link from any other, except while the anchor is down: taking one off then would either leave it locked with no way back or let it go, and the Anchor exists to prevent both.

What you add can cross too. Three settings under Devices, each Always, Ask or Never, control it. "Block the website too" (Always by default) links the site an app is also at, such as youtube.com for YouTube, onto the app's row as soon as Furlough knows the app's name, so blocking one blocks both. Taking the site back off is free for a quarter of an hour and a loosening after that. "Send what I add" (Ask by default) tells the other devices the name of what you add, never a token and never a rule of yours, and each blocks what it can find under that name: the Mac blocks the app if it has one and the site either way, and the iPhone blocks the site at once and the app through Apple's picker. Its first rule follows the name. "Take what my other devices add" (Ask by default) is the receiving end's own say. On the phone a picked app can only cross, or be paired with its site, once Furlough has seen it: right away with Screen Time data access, otherwise the first time the shield covers it.

Both settings cover the Anchor's list as well as your rules, and they say which half a name came from. Put something on the Anchor's list and the others are told it is anchored, not merely blocked: each puts it on its own list, so it goes away the next time any of them drops. Anchoring is the bigger fact, so it asks in its own right under Ask (agreeing to send a thing's hours is not agreeing to this), and the card appears on the Anchor screen and not under Devices, on the half it is about. Nothing crosses under the everything-except scope, where the list is what stays open and sending it would say the opposite of what it means, and nothing lands on a device whose anchor is down, because nothing changes a list under a lock. Something already blocked on the receiving device still lands: there is nothing new to block, and its place on that device's Anchor list is the whole of the message. On the phone an arriving app needs Apple's picker as ever, unless Screen Time data access is on, in which case Furlough matches the name to the token itself and puts it on the list with no picker at all. Taking something back off a list never crosses, so the link only ever tightens.

#### The escape

The one escape that always exists is Apple's own: iOS Settings > Screen Time > Apps with Screen Time Access > Furlough > off. That revokes access, and iOS clears every shield and the delete-protection flag. Furlough cannot prevent it, and it documents it on purpose.

## Furlough on the Mac

Apple's Screen Time API does not exist on the Mac: FamilyControls, ManagedSettings and DeviceActivity are marked unavailable for both native macOS and Mac Catalyst, so nothing built on them can shield anything there. `FurloughMac` is a native Mac app that shares the rules engine and the look and enforces on its own.

| On the phone | On the Mac |
|---|---|
| An app is an opaque Screen Time token | An app is its bundle identifier, picked from the apps on the Mac |
| A website is a token | A website is a host, typed in (`youtube.com` also covers `m.youtube.com`) |
| iOS shields a blocked app | Furlough asks it to quit the moment it launches or the window closes, and shows a floating card saying when it opens next. An app that has run for at least a minute gets 45 seconds to answer a "Save changes?" dialog, counted down on the card, before it is force-quit. One that has only just launched has nothing to save and goes after 2 seconds, so relaunching does not buy more time. |
| iOS shields a blocked site | Furlough reads every window's front tab in Safari and the Chromium browsers (Chrome, Arc, Brave, Edge, Vivaldi, Opera, Dia) through Apple Events, and sends each one that shows a blocked site to its shield page. The page draws the same hourglass in the status that site is in. This covers every running browser, including those that are not in front. With the optional web filter installed, a system extension also refuses the connection itself, from any app: Firefox, a site saved to the Dock as an app, anything that loads a blocked site outside a browser. Those get the floating card instead of the shield page. |
| iOS counts usage toward the budget | Furlough counts seconds while the app or site is in front and the Mac is not idle. "5 minutes left" and the spent-budget notice arrive as notifications. |
| The home-screen widget | A desktop widget with the same card: Edit Widgets on the desktop or in Notification Center, then add Furlough. |
| The Live Activity and Dynamic Island | A menu bar item: Furlough's own hourglass, drawn at the level this moment has reached and redrawn as the sand moves, with the countdown and every app's status one click away in its menu. ActivityKit does not exist on the Mac, so like a Live Activity's glass it is a redrawn still and not an animation. |
| The Anchor | Its own list of apps and sites, chosen from what is on the Mac, or everything except a list, with the same scope as the phone. Drop anchor locks the Mac and, through iCloud, every linked device. Anchored apps are quit and anchored sites go to the shield page. There is no tag reader here, so the Mac never releases: scanning the tag on the iPhone releases all of them. |
| Escape: iOS Settings > Screen Time > turn Furlough off | Escape: Force Quit. Quit is refused while anything is blocked, and logging out and shutting down are always allowed. Force Quit lifts every app block and tab redirect at once, but a launchd agent reopens Furlough about ten seconds later, so it buys nothing worth having. The web filter keeps its last list until the next window edge or until Furlough is back, whichever comes first. Furlough opens at login. |

Windows per weekday, budgets, the pending list and the loosening delay are the same code as the phone, and so are "Visualize windows", "Use windows from another app" and "Apply these windows to other apps". The window opens on the phone's hero (design/HOURGLASS.md, header H1): one page per app with the living hourglass, the countdown, and how much of today's budget is used, which the Mac knows because it counts the minutes itself. A strip of tiny status hourglasses under it turns the pages and is a status summary in itself. Clicking a page opens that app's rule, which shows the same hero at the top. The sidebar groups apps the way the phone's home screen does. Rules and lists are per device. What syncs is the Anchor's state and the names of what you add or anchor, where the Devices settings say so.

The Mac keeps its rules in an App Group container shared with the widget (`X9V4L6HR2R.com.zachshort.furlough`, under `~/Library/Group Containers`). The first launch of a build that has the widget moves the older store there, and nothing is lost.

macOS asks once per browser whether Furlough may control it, the first time Furlough reads that browser while a website has a rule. Refusing means that browser is not enforced. Settings > Web shows the status, and System Settings > Privacy & Security > Automation is where to change it. Firefox is not scriptable this way, so on its own the tab reader does not reach it.

The web filter is the optional second layer of web enforcement. Settings > Web installs it, and Furlough offers it once, the first time a website is added to block. It is not part of onboarding, since it can do nothing before some host is blocked, and anyone who only blocks applications is never asked. The filter is a network content filter that macOS runs as a system extension. It sees every connection the Mac opens and refuses the ones to a blocked site, whatever app opened them. macOS asks twice, once to allow the extension under System Settings > General > Login Items & Extensions and once to let it filter, and it can be switched off there at any time. Settings > Web says so when it has been, and the tab reader keeps enforcing regardless. The filter reads a site's name off the connection (the name the app asked for, or the one in the TLS hello), and while anything is blocked it refuses nameless QUIC connections so the browser falls back to the kind it can read. It blocks nothing past the moment the rules say a status could change, so a list left behind by a force quit lapses on its own.

Getting the Mac app is a download and needs no build. [Download Furlough for Mac](https://furloughapp.com/#download) is a disk image for Apple silicon on macOS 15 or newer, signed with a Developer ID and notarized, so it opens on a Mac that has never seen Xcode and Gatekeeper asks for no detour. [Releasing the Mac app](#releasing-the-mac-app) is how that image is made.

Open the image and drag Furlough onto the Applications folder beside it. It has to live in `/Applications`: macOS loads a system extension from nowhere else, and the login item and the watchdog agent both point there. The first launch is onboarding, a choice between starting with the Anchor or with Rules. The web filter is offered later, the first time a website is added to block. A new version is the same drag over the top. The filter that is already installed is recognised as a replacement and not read as a first install, so the next launch puts it back by itself.

Building it instead, to change it or to fork it, takes three commands:

```bash
xcodebuild -project Furlough.xcodeproj -scheme FurloughMac -configuration Release \
  -destination 'platform=macOS,arch=arm64' -allowProvisioningUpdates -allowProvisioningDeviceRegistration \
  -derivedDataPath build/DerivedDataMac build
rm -rf /Applications/Furlough.app && ditto build/DerivedDataMac/Build/Products/Release/Furlough.app /Applications/Furlough.app
open /Applications/Furlough.app
```

Or open the project in Xcode, pick the `FurloughMac` scheme and My Mac, and press Run. `/Applications` is where a build has to land too, for the same two reasons. Without a paid developer account, five lines have to come out of `project.yml` first: see [Building the Mac app without a developer account](#building-the-mac-app-without-a-developer-account).

`scripts/furlough mac` runs those three commands and stamps a rising build number over `CURRENT_PROJECT_VERSION`. The stamp matters to the web filter and is more than bookkeeping: see [Releasing the Mac app](#releasing-the-mac-app).

## Requirements

Everything below is for building Furlough. Running the Mac app needs none of it, because the [download](#furlough-on-the-mac) is a finished, notarized app.

- A paid Apple Developer account, because Family Controls is not available to Personal Teams. The Mac app on its own can be built without one: see [Building the Mac app without a developer account](#building-the-mac-app-without-a-developer-account).
- Xcode 26.6, the version `project.yml` names, which itself needs macOS 26.2 or newer. The deployment targets are iOS 18.0 and macOS 15.0.
- A physical iPhone. The Screen Time API does not work in the Simulator.
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) 2.46: `brew install xcodegen`

## Install from Xcode

```bash
xcodegen generate
open Furlough.xcodeproj
```

`project.yml` is the source of truth. `Furlough.xcodeproj` is generated and gitignored, so never edit it by hand, and run `xcodegen generate` again after adding or removing a file. A new file that is not in the project compiles nothing and fails nothing.

1. In Xcode, select the `Furlough` scheme and your iPhone as the run destination.
2. Signing is automatic under team `X9V4L6HR2R`. On first build Xcode registers the five iOS bundle IDs (the app, `.monitor`, `.shield`, `.widgets` and `.report`) and turns on the capabilities each one lists in `project.yml`: Family Controls (development), App Groups, NFC Tag Reading and the iCloud key-value store.
3. Press Run. On the phone, tap "Allow Screen Time access", then Allow on the iOS prompt.
4. Tap + to pick apps and websites. Open each one and set its budget, and windows if you want them. With no windows it is open all day, up to the budget. Turn off "Same every day" to give each window its own days. Save.
5. For the Anchor, open the Anchor card, choose apps, and pair a tag by holding the phone to it. Then Anchor locks and Unanchor asks for the tag.

Building a fork means replacing this repository's identifiers with yours. Search for `com.zachshort` and `X9V4L6HR2R`. The places that matter are these:

- `project.yml`: `DEVELOPMENT_TEAM`, the bundle IDs, the App Groups and the iCloud identifier. XcodeGen writes each target's `Info.plist` and `.entitlements` file from it.
- `Shared/Core/Furlough.swift`: `appGroupID`, `macAppGroupID` and `bundleID`.
- The watchdog label, in `FurloughMac/Model/Watchdog.swift` and in the file name and `Label` of the plist under `FurloughMac/Resources/LaunchAgents`.
- The web filter's identifier and Mach service name in `FurloughMacFilter/FilterXPC.swift`, and its `NEMachServiceName` in `project.yml`.
- For a notarized release only, the two hand-written `-DeveloperID.entitlements` files and `scripts/archive-mac.sh`.

Then run `xcodegen generate` again. The Mac group carries the team ID in front of it because macOS will not accept a `group.` prefix without a registered Mac, and the service name has to start with that group.

To build from the command line with the phone connected, use its UDID (see the next section for where to find it):

```bash
xcodebuild -project Furlough.xcodeproj -scheme Furlough -configuration Debug \
  -destination 'platform=iOS,id=<UDID>' -allowProvisioningUpdates \
  -derivedDataPath build/DerivedData build
xcrun devicectl device install app --device <UDID> build/DerivedData/Build/Products/Debug-iphoneos/Furlough.app
```

`scripts/furlough phone` does the whole sequence for the connected phone: build, install, launch, and a check that the phone reports the build it was given. To check that the iOS app builds with no phone attached, use `-destination 'generic/platform=iOS'`.

## Installing on another phone

Any iPhone on iOS 18 or later can run Furlough from this Mac. Development signing under the paid team covers it, and nothing in the project is tied to one device.

1. On the phone: Settings > Privacy & Security > Developer Mode, turn it on, and restart when asked.
2. Plug the phone into the Mac and unlock it. Tap Trust on the phone when it asks about the computer.
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
   The UDID is the `00008xxx-...` value from `xcrun devicectl device info details --device <identifier>`, not the CoreDevice identifier that `list devices` prints first. Or open the project in Xcode, pick the phone as the run destination, and press Run.
5. Install and launch:
   ```bash
   xcrun devicectl device install app --device <UDID> build/DerivedData/Build/Products/Debug-iphoneos/Furlough.app
   xcrun devicectl device process launch --device <UDID> com.zachshort.furlough
   ```
6. On the phone, go through onboarding and allow Screen Time access. Authorization is per phone and per Apple account, and it has to be an adult account, because Furlough asks for individual authorization and not the parent-approved kind.

Limits to know about:

- A paid membership allows 100 iPhones per year. Removing a device does not free its slot until the membership year rolls over.
- A development build keeps running for a year, then needs reinstalling.
- Development-signed builds only install over a cable. TestFlight, ad hoc and the App Store all need the Family Controls distribution entitlement (see [Known limits of the Screen Time API](#known-limits-of-the-screen-time-api)).
- Whoever gets the app should know there is no unblock button, and that the only escape is iOS Settings > Screen Time > Apps with Screen Time Access > Furlough > off.

## If a shield gets stuck

1. Open Furlough and tap Settings > Diagnostics > "Re-apply enforcement now". This registers every schedule again and re-applies shields from saved state.
2. Check Settings > Diagnostics > "Activity log" to see what the monitor extension has been doing.
3. If that does not help, go to iOS Settings > Screen Time > Apps with Screen Time Access, turn Furlough off, then reopen Furlough and allow access again. Your rules are kept, and only the shields are reset.

## Repository layout

| Path | What is in it |
|---|---|
| `Furlough/` | The iOS app: `Model/` (`AppModel`, `Monitoring`, `TagScanner`, `UsageReader`), `Views/`, fonts, sounds and assets. |
| `FurloughMonitor/`, `FurloughShield/`, `FurloughWidgets/`, `FurloughReport/` | The four iOS extensions described above. |
| `FurloughMac/` | The Mac app and its own enforcement: `Model/Enforcer.swift`, `Browsers.swift`, `Watchdog.swift`, `WebFilter.swift`, the views, `Resources/Shield.html` and the watchdog agent plist. |
| `FurloughMacFilter/` | The Mac web filter, a network system extension. |
| `FurloughMacWidgets/` | The Mac desktop widget. |
| `Shared/Core/` | Pure Foundation code compiled into every target: models, `Policy`, `SharedStore`, the Anchor, the device link, the record. It has no SwiftUI import, because the monitor extension has a hard memory limit. |
| `Shared/UI/`, `Shared/Intents/`, `Shared/LiveActivity/`, `Shared/Usage/` | The SwiftUI both apps draw (theme, hourglass, week grid), the App Intents and Focus Filter, the Live Activity code, and the usage collector and cards. |
| `Tests/Core/` | Swift Testing suites over `Shared/Core`. |
| `protocol/` | The device-link contract as JSON Schema, test vectors and tables, for a port to another platform. See `protocol/README.md`. |
| `design/` | The design spec and briefs, the App Store listing and screenshot board under `store/`, and the printable tag holder under `anchor-puck/`. |
| `site/` | The Astro marketing site. See `site/README.md`. |
| `scripts/` | `furlough` and the build, release and App Store scripts. |
| `release-notes.json`, `project.yml` | The one copy of the release notes, and the XcodeGen project definition. |

The project has nine targets: two apps (`Furlough`, `FurloughMac`), six extensions (`FurloughMonitor`, `FurloughShield`, `FurloughWidgets`, `FurloughReport`, `FurloughMacFilter`, `FurloughMacWidgets`) and the `FurloughCoreTests` bundle. Every decision about what is shielded goes through `Policy.decide`, and every monitor callback, app activation and edit ends in a reconcile that recomputes the shields from stored state, so nothing toggles state incrementally.

## Commands

`scripts/furlough` is the front door for everything below. Run it with no arguments for a menu, and pass extra arguments straight through. `scripts/furlough shell` prints the lines for `~/.zshrc` that make `furlough` work from any directory.

| Command | What it does |
|---|---|
| `phone` | Build Debug and run it on the connected iPhone. |
| `mac` | Build the Mac app and put it in `/Applications`. |
| `mac-check`, `mac-release` | Say what this Mac still needs for a Mac release, then sign, notarize and build the DMG. |
| `test` | Run the rules-engine tests here, with no phone. |
| `gen`, `open` | Regenerate the Xcode project, and open it. |
| `version` | Show the marketing version, or bump it by the rules below. |
| `archive`, `beta` | Cut and audit a Release build, and upload it to TestFlight. |
| `submit`, `status`, `review` | Send a build to Beta App Review, and read what App Store Connect says of builds and of the version under review. |
| `shots`, `shots-up`, `store`, `resubmit` | Render and upload App Store screenshots, finish the store record, and resubmit after a rejection. |
| `deploy` | Build the site and push it to Cloudflare Pages. |
| `puck` | Render the anchor puck and zip it for whoever is printing it. |

The App Store Connect commands read an API key from `~/.appstoreconnect/private_keys/`. The key file stays out of this repository.

## Tests

The rules engine has its own tests. `Shared/Core` is plain Foundation and builds for macOS, so the whole of it is tested on the Mac with no phone and no host app: windows, budgets, per-weekday days, tightening versus loosening, the pending queue, the widget's summary, and decoding state written by older builds. The suites in `Tests/Core` also run every fixture in `protocol/fixtures` against the real code. `ShieldReconciler.swift` is left out of the test bundle because it imports ManagedSettings.

```bash
xcodebuild test -project Furlough.xcodeproj -scheme FurloughCoreTests -destination 'platform=macOS,arch=arm64'
```

`scripts/furlough test` runs the same command. Read the result from the line that begins "Test run with", which is where Swift Testing reports. A line that says "Executed 0 tests" is XCTest describing an empty bundle and means nothing here. Every change to `Shared/Core` gets tests in a new file in `Tests/Core` named for the feature.

## Testing builds

Debug builds, which are what Xcode and the commands above produce, add Settings > About > Testing > "Reset everything". After a confirmation it forgets every app, rule, pending change and the Anchor with its tag, lifts every shield, hands Screen Time access back to iOS, and returns to onboarding, so the whole first run (the grant, the first week it starts, the usage step) can be walked again. Use it to start over after trying a week-long delay or a five-minute budget. What it keeps is the notification permission, which iOS only ever asks about once. The Mac app has the same button and it goes the same distance. It also forgets today's counted minutes, takes the login item and the watchdog agent back off, and returns to its own onboarding. What it keeps there is the web filter system extension and the per-browser Automation permissions, which the app cannot ask for again from the inside and which macOS would make you approve again by hand.

It is compiled out of Release builds, so a build you mean to live with keeps its promise of no unblock button. A Release build that should carry it, such as a TestFlight round where wiping the setup on the phone is the point, has to ask by name:

```bash
TESTING_TOOLS=1 scripts/archive.sh
```

```bash
xcodebuild -project Furlough.xcodeproj -scheme FurloughMac -configuration Release -derivedDataPath build/DerivedDataMac SWIFT_ACTIVE_COMPILATION_CONDITIONS='$(inherited) TESTING_TOOLS' build
```

TestFlight and the App Store are the same binary (a build is promoted, not rebuilt), so a build made this way still keeps the section put away. It shows only after five taps on the Version row (Settings > About on the phone, Help > About on the Mac), and "Hide these buttons" puts it back. `scripts/archive.sh` checks the flag both ways: it refuses to ship a plain archive that carries the testing code, and refuses a `TESTING_TOOLS=1` archive that does not. A build made with the flag must never be the one submitted for review. See `Shared/Core/TestingTools.swift`.

## Versioning

`MARKETING_VERSION` lives once, in `project.yml`'s base settings, and every target's Info.plist reads it through `$(MARKETING_VERSION)`. It is always three numbers, such as `1.2.0` and never `1.2`, so that one version cannot be written down two ways.

`CURRENT_PROJECT_VERSION` is not the version. `scripts/archive.sh` stamps each build with a UTC timestamp, which always rises and is never reused. The build number says when, and the marketing version says what.

Which number moves:

| | When | Examples |
|---|---|---|
| PATCH `1.1.0` to `1.1.1` | Nothing new to learn. Something that was wrong now works. | A crash, a wrong label, a spinner that never stops, a slow screen, more rows in the companion or utility tables. |
| MINOR `1.1.1` to `1.2.0` | Something new to find. Anything that changes what you can say or where you can say it. | A new screen or setting, a new way in (widget, Control Center, an intent, a Focus filter), a new field in the setup file that older builds ignore, a new platform. |
| MAJOR `1.x.y` to `2.0.0` | Something you would want to be told before you update. | Stored state an older build can no longer read, the delay or the Anchor or the escape hatch changing meaning, a device or OS version dropped. |

This app has two rules that the general ones do not:

- A change to what `Policy.decide` shields is never a patch, even when it is a fix. If a build can block or unblock something the one before it could not, the minor moves, so that a person whose phone behaved differently this morning can see the reason in the version number.
- One version is one batch. The version is bumped when a build is cut for other people, at `furlough beta`, and not on every merge to `main`, and the batch it covers stops there. Do not put a second day of feature work out under a version string that has already shipped. Version 1.1 broke this rule and 1.2.0 exists to correct it: see below.

Every bump needs an entry in `release-notes.json` first:

```bash
scripts/version.sh minor
```

It refuses a version that is not three numbers, one that does not rise, and one the notes have no entry for, then rewrites the single line in `project.yml`. `scripts/version.sh` on its own says where things stand, and `scripts/archive.sh` runs `--check` before it archives, so a build cannot be cut whose `What's new` screen would not mention the version it is running. Neither commits anything. `patch-notes.md` is the runbook for writing the notes themselves.

### The notes

`release-notes.json` at the root of the repository is the one copy. Both apps bundle it as a resource and read it through `Shared/Core/ReleaseNotes.swift`. It appears as `What's new` under Settings > About on the phone and under Help on the Mac, and the site imports the same file at build time for `furloughapp.com/releases`. There is no second copy to keep in sync, and `Tests/Core/ReleaseNotesTests.swift` holds the file to its shape and to `project.yml`.

The file is ordered newest first. Each entry is a version, a date, a channel (`appstore`, `testflight` or `unreleased`), a headline, a paragraph, and the changes. Each change has a `kind` (`new`, `better`, `fixed`), a `platform` (`both`, `iphone`, `mac`), a title and a sentence or two. Write them for somebody who uses Furlough and does not read this repository: what changed and what it means, not which file moved.

### What the versions so far were

- 1.0 and 1.1 were written without the patch component. `release-notes.json` records them padded, as `1.0.0` and `1.1.0`, and `Version` compares numerically, so `1.1` and `1.1.0` are the same version and a build of either finds its own notes.
- 1.1 carried four builds across two days of feature work under one version string, which is what "one version is one batch" now forbids. The second day (Settings becoming a menu, the usage step offering the Anchor, and the fixes beside them) is 1.2.0, split back out on 2026-09-12. Those changes did go out on 11 September, inside the last three 1.1 builds, and the 1.2.0 entry says so. 1.1.0 is dated 2026-09-10, the day of the only build that carried exactly what it lists.
- A platform's `What's new` list holds only the versions that changed something on that platform. When the running version is missing from it, the app says "You are on 1.2.0, which changed nothing on the Mac" (or the iPhone) instead of letting the list start at an older version that would read as the one you are on. `ReleaseNotes.bundleRelease()` is where that sentence comes from. Most of 1.2.0 is iPhone work: two of its 17 changes are for the Mac.
- 1.2.0 is on the App Store, released 2026-09-15. It is the same version record as 1.0: submitted 2026-09-09, rejected under Guideline 2.1 for want of a hardware demo video, answered, renamed to 1.2.0, and approved. Everything before it went to TestFlight only, which is what the channel on each entry says.
- 1.3.0 adds iPad support, the week grid edited by dragging, the Anchor's schedule on the Mac and the smaller anchored page. Its entry still has the channel `unreleased`. Builds of it have gone to TestFlight, and the signed Mac download on the site is 1.3.0.

## Known limits of the Screen Time API

- Windows must be at least 15 minutes and, as stored, cannot cross midnight. A night is kept as two windows, one either side of midnight, and each half needs its own 15 minutes.
- iOS allows 20 monitored activities, and one is the daily budget tracker. That leaves 19 for every distinct window across all apps plus every distinct Anchor drop time, lift time and timed lift. The editors check the count before you save.
- The monitor extension can fire a few minutes late, and threshold callbacks occasionally fire twice. Every callback is idempotent, so this is harmless.
- Anchoring "Everything except" a list shields every app and website that iOS lets a shield cover, through `.all(except:)` on the app and website category shields, plus the web content filter for every browser. iOS keeps some of its own apps outside every shield, so those stay reachable however the anchor is set. The site's Anchor help page records which, as they are confirmed on a phone. Websites off the list are blocked by the content filter as well as the shield, so a browser other than Safari shows iOS's own "Website Not Allowed" page, and an app on the list that loads web content inside itself may be blocked from doing so. A category cannot be excepted from a shield over everything, so the allowlist holds apps and sites only, and picking a category in the picker puts its apps on the list one by one.
- Distributing outside Xcode (TestFlight, App Store) needs the Family Controls distribution entitlement, requested per bundle ID, which can take weeks. `~/Projects/archive/furlough/testflight-deployment/DEPLOYMENT.md` (outside this repository) has the request and everything else the App Store wants.

## Releasing the Mac app

The Mac app is not an App Store app and cannot become one. It is unsandboxed, drives browsers through Apple Events, terminates other processes, installs a launchd agent and carries a system extension, and the Mac App Store requires the sandbox without exception. Its road is a Developer ID signature plus notarization, in a disk image served from a site you own. Nothing in App Store Connect is involved.

```bash
scripts/furlough mac-check      # what this Mac still needs, and where to get it
scripts/furlough mac-release    # build, sign, notarize, staple, and make the DMG
```

`scripts/archive-mac.sh` is the whole recipe, and its header is the long version. It does what `xcodebuild -exportArchive` cannot: it signs by hand, inside out (the web filter, then the widget, then the app), because Xcode 26's Direct Distribution cannot sign an app that embeds a system extension. Before any of that it runs the same promise checks the phone's archive does, against the Mac binary: the control string first, then no testing-only code, then no split debug binary. Afterwards it reads the entitlements back off the signature. An entitlement that a profile does not grant is dropped silently at signing, and the one that matters here, `content-filter-provider-systemextension`, which a Developer ID system extension needs and a development build must not have, would otherwise leave a filter that refuses to load on somebody else's Mac with nothing in the app to say why.

Three things have to exist on the Mac doing the release. The certificate can only be made by the Account Holder.

1. A Developer ID Application certificate: Xcode > Settings > Accounts > your Apple ID > Manage Certificates > + > Developer ID Application.
2. Two Developer ID provisioning profiles from developer.apple.com > Profiles > + > Developer ID: one for `com.zachshort.furlough.mac` with the Network Extension capability and iCloud, and one for `com.zachshort.furlough.mac.filter` with Network Extension. Save them as `~/.furlough/signing/FurloughMac.provisionprofile` and `~/.furlough/signing/FurloughMacFilter.provisionprofile` (`FURLOUGH_SIGNING` moves that directory).
3. The App Store Connect key that notarization authenticates with, the same one TestFlight uses, at `~/.appstoreconnect/private_keys/`.

`mac-check` decodes each profile and does not trust its file name, and it prints exactly which of the three is missing.

The script leaves the finished DMG in `build/mac-release/`. To publish it, copy it into `site/public/downloads/` and update `macDownloadURL` and `macVersion` in `site/src/site.ts`. That downloads folder keeps only the latest DMG.

Every Mac build stamps a build number, and it is more than bookkeeping. macOS compares a system extension's `CFBundleVersion` when it is asked to replace one, and `CURRENT_PROJECT_VERSION` is `1` in `project.yml`. `scripts/furlough mac` and `mac-release` both stamp a UTC timestamp over it. The app also records which build's extension macOS accepted, so replacing `/Applications/Furlough.app`, which is what every install and every update is, is recognised as a replacement and not read as "no filter was ever installed", and the next launch puts the filter back by itself. A filter switched off in System Settings, or one you were asked about and declined, is left exactly as it is.

## Building the Mac app without a developer account

The signed [download](#furlough-on-the-mac) is the ordinary way onto a Mac, and it is the whole app. This section is the other way: building it yourself, from this repository, without paying Apple for a membership first.

The Mac app is the half of Furlough that never touches the Screen Time API, so nothing it does needs Family Controls. With five lines out of `project.yml` it does not need an Apple Developer account either. Rules, windows, budgets, the quitting of blocked apps, the tab reader and its shield page, and the menu bar hourglass all work under an ad-hoc signature.

You need macOS 26.2 or newer, Xcode 26.6 (the version `project.yml` names, which requires that macOS), and Homebrew.

1. Install XcodeGen. The Xcode project file is not in the repository. It is generated from `project.yml`:
   ```bash
   brew install xcodegen
   ```
2. Clone the repository, and run everything below from inside the `furlough` folder it makes:
   ```bash
   git clone https://github.com/zach-short/furlough.git
   ```
3. Open `project.yml` and delete five lines, all inside the `FurloughMac:` target. These are the parts Apple grants only to a paid account. Four of them are under `entitlements:`:
   ```yaml
   com.apple.developer.ubiquity-kvstore-identifier: $(TeamIdentifierPrefix)com.zachshort.furlough
   com.apple.developer.system-extension.install: true
   com.apple.developer.networking.networkextension:
     - content-filter-provider
   ```
   and the fifth is in the `dependencies:` block at the end of that same target:
   ```yaml
   - target: FurloughMacFilter
   ```
   Leave everything else alone. Do not touch the `.entitlements` files: XcodeGen writes those from `project.yml`.
4. Generate the Xcode project:
   ```bash
   xcodegen generate
   ```
5. Build it:
   ```bash
   xcodebuild -project Furlough.xcodeproj -scheme FurloughMac -configuration Release \
     -destination 'platform=macOS,arch=arm64' -derivedDataPath build/DerivedDataMac \
     DEVELOPMENT_TEAM= CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual build
   ```
6. Put it in `/Applications`. It has to live there for the login item to point at it:
   ```bash
   ditto build/DerivedDataMac/Build/Products/Release/Furlough.app /Applications/Furlough.app
   ```
7. Open it:
   ```bash
   open /Applications/Furlough.app
   ```
8. Say yes to the permission prompts. macOS asks once per browser whether Furlough may control it, and that is how sites get blocked. Refusing means that browser is not enforced. You can change it later under System Settings > Privacy & Security > Automation.

Two things are missing from a build made this way, since both ride on entitlements that only a paid team can grant. The download has them, which is the reason to prefer it unless you mean to change the code.

- The web filter. The tab reader is then the whole of web enforcement, so Safari and the Chromium browsers are covered, and Firefox, a site saved to the Dock as an app, and anything else that loads a site outside a scriptable browser are not.
- The Anchor's lock. It crosses between devices on the iCloud key-value store, which needs the first entitlement removed above, so nothing crosses at all. A Mac refuses to drop an anchor unless an iPhone is on the link, because only that phone's tag could ever release one, and in this build none ever will be. Drop anchor therefore stays refused. Nothing can get stuck: that refusal is the guard against a lock with no way back, and it is doing its job.

## The site

The marketing site in `site/` is an Astro site, built and run with bun (never npm). It is deployed to Cloudflare Pages by direct wrangler upload, not through git, with `scripts/furlough deploy` or `bun run deploy` inside `site/`, and it serves furloughapp.com, including the Mac download and a releases page built from `release-notes.json`. `site/README.md` has the rest.

## Where to read next

- `CLAUDE.md` holds the working rules for sessions in this checkout, and `AGENT-PRACTICES.md` is the process standard behind them.
- `HANDOFF.md` is the record of what is true: the environment, the settled decisions, the code map, the enforcement invariants and a numbered account of every step of work.
- `PASSOFF.md` is the board of what is next.
- `design/DESIGN.md` is the look ("Ember Glass"), and `design/HOURGLASS.md` is the living hourglass.
- `protocol/README.md` is the device-link contract, and `patch-notes.md` is the runbook for the release notes.
