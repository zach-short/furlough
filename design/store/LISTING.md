# Furlough 1.0: the App Store listing

Every App Store Connect field for version 1.0, ready to paste. Character counts were taken with
`printf '%s' "…" | wc -m` against the limits on Apple's own pages, not from memory:
[product page](https://developer.apple.com/app-store/product-page/) (name 30, subtitle 30,
promotional text 170, keywords 100, commas with no spaces),
[platform version information](https://developer.apple.com/help/app-store-connect/reference/app-information/platform-version-information/)
(description 4000 plain text, what's new 4000, copyright is `year Name` with the symbol added
automatically), [screenshot specifications](https://developer.apple.com/help/app-store-connect/reference/screenshot-specifications/)
(1 to 10 images, no alpha channel, a 6.9-inch set removes the 6.5-inch requirement).

Decisions taken with Zach on 2026-09-08: this ships as **a real product**, distributed
**worldwide except the EU**, on a **domain still to be bought**, in **Productivity**.

Choices left to taste are marked **PICK ONE**. Everything else is final.

---

## App name

**PICK ONE.**

**A, recommended** (8 chars)

```
Furlough
```

**B** (21 chars)

```
Furlough: App Blocker
```

A is the reserved name and the one the site and the app icon carry. It is recommended because
Apple indexes the **name and the subtitle together** for search, and the subtitle below already
contains "App blocker". B buys no term that A does not already have, and costs the clean
name on the icon's caption and in the search results row. Take B only if you want the words in
the largest type on the product page.

---

## Subtitle

**30 chars, exactly at the limit.**

```
App blocker. No unblock button
```

Carries the search term and the one true thing in the same breath. No full stop at the end,
because that character is the thirty-first.

**Alternatives, both under the limit:**

- `App and website blocker` (23): broader term coverage, loses the hook.
- `No unblock button` (17): purest, worst for search.

---

## Promotional text

**145 chars of 170.** Editable later without a new build.

```
An app blocker with no unblock button. Tightening a rule applies at once. Anything that gives you more time waits out a delay you set in advance.
```

**Read this before pasting it.** Promotional text renders **above** the description, so it, not
the description's opening, is what a browsing reader sees first. The two are written to survive
that: the promo text states the rule, the description's first line restates it in different words
and keeps going. If the repetition bothers you, leave promotional text **empty** and the
description's own opening takes the position instead. That is a legitimate choice, not a gap.

---

## Description

**3850 chars of 4000.** Plain text, no HTML, which is what Apple accepts.

The first three rendered lines are the whole first paragraph: no unblock button, and rules that
only loosen after a delay. Nothing above them is spent on setup.

```
Furlough is an app blocker with no unblock button. Rules tighten the moment you save them and only loosen after a delay you set in advance. When you want back in, there is nothing to tap.

Pick the apps and websites that eat your time, from Apple's own picker. Give each one a daily budget in minutes and, if you want, the hours it is allowed: eight to ten on school nights, later on weekends, different every day if you like. With no hours set, an app is open all day up to its budget. Outside its hours, or once the budget is spent, iOS shields it until it is due to open again.

THE DELAY

A shorter window, a smaller budget, a day taken off: those apply the moment you save. A longer window, a bigger budget, removing an app: those wait. The wait is a delay you chose beforehand, 24 hours by default. While it waits, the change sits in a list that shows the rule you have now against the one queued to replace it, and you can cancel it right up until it lands.

Each app also gets a tier that scales its delay. Essential waits a quarter of the base, Useful the base itself, Idle twice, Hazard four times. Moving an app toward Essential shortens its future delays, which is itself a loosening, so that waits too.

Blocking something you need is warned about before you save it, by name: blocking a messaging app stops codes texted to you from arriving, blocking an authenticator stops you signing in anywhere. Since there is no emergency unblock, that warning is the last cheap moment to change your mind.

THE SHIELD

The block screen says which app is closed and when it opens next. That is the whole conversation. No snooze, no code to type, no one more minute. While anything is shielded, iOS is told to refuse app deletion, so an app cannot be deleted to get out of a rule you set for yourself.

THE ANCHOR

A second list of apps and sites you lock in one tap, from anywhere. The only thing that releases it is holding your iPhone to an NFC tag you paired beforehand. You supply the tag, and any NTAG sticker works. Leave it at home and your phone stays anchored until you are back. The Anchor is optional and nothing else in Furlough depends on it.

WEBSITES

A site picked from Apple's picker behaves like an app: it gets hours and a daily budget and wears Furlough's shield. A site typed in by name is handled by the system's own web filter instead. That kind gets hours but no daily budget, and iOS shows its own block page rather than Furlough's.

THE WAY OUT

There is one, it is Apple's, and it always works: Settings, Screen Time, Apps with Screen Time Access, Furlough, off. It lifts every shield at once and re-enables app deletion. Furlough cannot prevent it and documents it in the app on purpose. Everything else here assumes you would rather not.

ALSO IN THE APP

A home screen widget and a Live Activity counting down the open window. Notifications when a window opens, five minutes before it closes, five minutes before a budget runs out, and when it is gone. A seven-day grid for drawing hours across the week. One app's rule copied onto any number of others in a single save. A window that runs past midnight, kept as the one row you wrote. Setting the clock forward does not buy time: queued changes are held while the clock runs ahead of the device's own count, and released when it is set back.

PRIVACY

No account, no server, no analytics, no third-party code. There is no networking in the app at all. Apple's Screen Time API is built so Furlough is never told which apps you picked. Rules stay on the iPhone that made them and are not synced anywhere.

REQUIREMENTS

iPhone, iOS 26 or later. Screen Time access, which iOS grants only to an adult Apple Account. Furlough asks for individual authorization: the person setting the rules and the person kept to them are the same person. It is not a parental control app.
```

**What it deliberately does not say**, so nobody re-adds it later:

- No sync, no account, no cloud. The PRIVACY paragraph says rules stay on one iPhone.
- **No usage dashboard.** In-app reading of your own Screen Time history needs Apple's App &
  Website Usage data access, which customers get on EU devices only. Everywhere else the report
  extension shows one card at a time. A description promising a usage screen would be false for
  most of the audience, so usage is not mentioned at all. The reviewer is told about it instead;
  see App Review notes.
- The WEBSITES paragraph keeps the two kinds of website apart rather than flattening them. The
  typed kind genuinely has no daily budget and genuinely wears iOS's page, not Furlough's.
- The Anchor paragraph says **you supply the tag**.

---

## Keywords

**95 chars of 100.** Commas, no spaces after them, as Apple specifies.

```
screen time,focus,distraction,website,block,limit,restrict,habit,discipline,willpower,scrolling
```

No app name or company name appears here (guideline 2.3.7 forbids other people's, and Apple
already indexes your own). "Furlough", "app", and "blocker" are all omitted on purpose: they are
in the name and subtitle, which are indexed alongside keywords, so repeating them wastes budget.
No competitor is named anywhere.

**Swap available, 87 chars:** replace `discipline,willpower` with `self control` if you want the
higher-intent phrase. It is a common English phrase rather than a trademark, but it is also the
name of a long-standing blocker on other platforms, which is the only reason it is not the
default.

---

## What's New in This Version

**461 chars of 4000.** Apple does not require this field for a first version. Fill it in anyway:
it is the only place the product page names what shipped.

```
First release.

Per-app daily budgets and allowed hours, set per weekday. Tightening applies at once; anything that gives you back time waits out a delay you set in advance and can be cancelled while it waits. Four utility tiers that scale that delay. The Anchor: a second list of apps locked in one tap and released only by an NFC tag you paired. A home screen widget, a Live Activity, and notifications at every edge. No account, no server, no unblock button.
```

---

## URLs

**The domain is `furloughapp.com`** (Zach, 2026-09-08). These are final text; what is outstanding
is the deploy. `site/` is a written Astro project with `/privacy` and `/support` in it, and it
builds them to `dist/privacy/index.html` and `dist/support/index.html`, so the clean paths below
work on any host. Privacy policy and support URLs are both **required** fields.

| Field | Value | Status |
|---|---|---|
| Support URL (required) | `https://furloughapp.com/support` | live once `site/` is deployed |
| Marketing URL (optional) | `https://furloughapp.com` | live once `site/` is deployed |
| Privacy Policy URL (required) | `https://furloughapp.com/privacy` | live once `site/` is deployed |

Apple requires the protocol in the field, so keep the `https://`. No trailing slashes.

**`site/astro.config.mjs` now sets `site`, fixed 2026-09-08.** Without it `Astro.site` was
undefined, so `Base.astro` emitted no `<link rel="canonical">` at all and resolved the `og:image`
against a build-time URL rather than the public origin. Verified in a rebuild: all three pages
carry a canonical, and `og:image` is `https://furloughapp.com/icon-1024.png`.

Astro writes the canonical in its trailing-slash form (`https://furloughapp.com/privacy/`). The
App Store fields above are the slashless form, which every static host redirects to it. Either
is accepted; do not mix them within one field.

Once the listing is public, set `appStoreURL` in `site/src/site.ts`, which is currently `null`.
The Apple ID is already known, so the value is:

```
https://apps.apple.com/app/id6810006594
```

---

## Categories

**Primary: Productivity. Secondary: Utilities.**

Productivity is where blockers of this kind sit, so it is where the people looking for one
already browse. It is a crowded chart, but the intent match is exact and chart rank matters less
than search for an app nobody has heard of yet.

Utilities as secondary because Furlough is, mechanically, a system tool: it schedules, shields
and counts, and it has no content of its own.

**Health & Fitness was considered and rejected.** The audience is real and the chart is less
crowded, but the whole description would have to lean toward wellbeing language to make sense
beside the apps already there, and that is the register this listing is written against.
Guideline 2.3.5 asks for the most appropriate category, and a blocker that never mentions health
is not it.

---

## Age rating

**Lands at 4+.** Answers to the current questionnaire, which Apple groups into in-app controls,
content descriptors, and chance-based activities:

| Question | Answer |
|---|---|
| Parental Controls | **No** |
| Age Assurance | No |
| Unrestricted Web Access | No |
| User-Generated Content | No |
| Social Media | No |
| Messaging and Chat | No |
| Advertising | No |
| Profanity or Crude Humor | None |
| Horror/Fear Themes | None |
| Alcohol, Tobacco, or Drug Use or References | None |
| Medical or Treatment Information | None |
| Health or Wellness Topics | None |
| Mature or Suggestive Themes | None |
| Sexual Content or Nudity | None |
| Graphic Sexual Content and Nudity | None |
| Cartoon or Fantasy Violence | None |
| Realistic Violence | None |
| Prolonged Graphic or Sadistic Realistic Violence | None |
| Guns or Other Weapons | None |
| Gambling | No |
| Simulated Gambling | None |
| Contests | None |
| Loot Boxes | No |

Two of these are worth knowing the reasoning for, because both look arguable and neither is:

- **Parental Controls: No.** The question asks whether the app lets a parent monitor, manage or
  restrict *a child's* access. Furlough restricts the account holder's own device and requests
  individual authorization. Answering Yes would put the listing at odds with the App Review notes,
  which say plainly that this is not a parental control app.
- **Health or Wellness Topics: None.** The question asks about self-care or lifestyle
  recommendations. Furlough suggests a utility tier for apps it recognises and warns before you
  block something you need. Both are advice about a rule, not about a person, and neither is
  health guidance.

Guideline 2.3.8 also requires the screenshots themselves to suit a 4+ rating. The six frames are
app UI and typography; nothing in them raises it.

---

## Accessibility Nutrition Labels (iPhone)

Apple's bar, from the
[overview page](https://developer.apple.com/help/app-store-connect/manage-app-accessibility/overview-of-accessibility-nutrition-labels):
a feature may be claimed only if **users can complete all of the app's common tasks using it**.
Common tasks are the primary functionality plus onboarding, settings and finding help. Guideline
2.3 applies, and App Review can ask for a label to be corrected.

**Answer Yes to "Does your app support any of the above features on iPhone?"**, then check only
what is listed as ready below. Answering No suppresses every label, including the two the app has
genuinely earned. The labels are metadata: they can be revised later without a new build, and
Apple asks that they be kept up to date.

### Ready to claim now

| Feature | Evidence |
|---|---|
| **Dark Interface** | The app is dark by construction. `Ember.ground` is `#0F0D0B` and there is no light appearance to fall out of. |
| **Reduced Motion** | Honoured deliberately at both of the app's continuous animations: `Shared/UI/Theme.swift:108-140` parks the drifting ember at a resting point and pauses its `TimelineView`, and `Shared/UI/Hourglass.swift:348-358` stops the living hourglass. Nothing else animates continuously. |
| **Sufficient Contrast** | Every palette token now clears 4.5:1 against both the ground and the card fill. `Ember.faint` was the one failure at 3.80:1 and was raised on 2026-09-08; see the table below. |

### Do not claim: no such content

**Captions** and **Audio Descriptions**. Furlough has no audio and no video anywhere, so there is
nothing to caption or describe. Leave both unchecked.

### The contrast measurements

Measured against `Ember.ground` and against the card fill (white at 6%, which resolves to
`#1D1C1A`). WCAG AA for normal text is 4.5:1.

| Token | On ground | On card | |
|---|---|---|---|
| `cream` `#F5EFE6` | 16.97:1 | 14.90:1 | pass |
| `sandLight` `#FFD59A` | 14.07:1 | 12.35:1 | pass |
| `pending` `#F2B544` | 10.59:1 | 9.30:1 | pass |
| `moss` `#7BC96F` | 9.63:1 | 8.45:1 | pass |
| `amber` `#F59E4A` | 9.12:1 | 8.00:1 | pass |
| `muted` `#B8AFA3` | 8.96:1 | 7.86:1 | pass |
| `ember` `#E5563D` | 5.29:1 | 4.65:1 | pass |
| **`faint` `#90877B`** | **5.48:1** | **4.81:1** | **pass, raised from `#7E766B` (4.33:1 / 3.80:1)** |

`Ember.faint` was the one failure. It carries small secondary text, including the unselected
weekday letters in the rule editor's day strip at 10 pt (`Furlough/Views/RuleEditorView.swift:749`),
where 3.80:1 was well under the bar.

**Fixed 2026-09-08**: raised to `#90877B`, the same hue at a higher value, chosen for margin over
the threshold rather than the minimum that clears it. It stays clearly below `muted` (7.86:1 on
card), so the tertiary tone still reads as tertiary. The token is duplicated across the design
system, so all eight definitions moved together: `Shared/UI/Theme.swift`, `design/DESIGN.md`,
`site/src/styles/global.css`, `site/src/lib/hourglass.ts`, `design/store/board.html`,
`design/hourglass-board.html` and `FurloughMac/Resources/Shield.html`.

### Blocked on a device pass

These three cannot be settled from source. Each needs the feature switched on and the common tasks
walked on the phone: onboarding and Screen Time access, adding an app, writing a rule, the week
grid, the pending list, Settings, and the Anchor.

| Feature | What source says, and what is unresolved |
|---|---|
| **VoiceOver** | Partly built already: labels and values on the budget slider, the day strip, the week grid, the add-website steps and the add-choice buttons, and the hourglass correctly `accessibilityHidden(true)` with the status carried in adjacent text. But only 8 `accessibilityLabel` calls exist across the app, and much of the UI is custom-drawn. Walk it before claiming. |
| **Voice Control** | Follows from the same work: every control needs a name that can be spoken. Custom `Button` labels built from shapes rather than text are the risk. |
| **Larger Text** | Better than it looks. `EmberFont` uses `Font.custom(_:size:)`, which scales with Dynamic Type relative to body, so the text does grow. The open question is whether the layouts survive it at the largest accessibility sizes: the hero, the seven-column week grid, and the 26 pt fixed-size day circles are where it would break first. |
| **Differentiate Without Color Alone** | Looks genuinely satisfied and should be confirmed by eye. Status is never carried by hue alone: the hourglass changes fill level and shape as well as colour, every row carries `RowCopy.detail` text, and the day strip separates on and off by fill brightness with the chosen days also spelled out in words beside it. |

---

## Copyright

**15 chars.** Apple adds the © symbol itself, so do not type one.

```
2026 Zach Short
```

The legal name, because the membership is an Individual one. Changing it later means migrating to
an Organization, which needs a D-U-N-S number.

---

## Territories

**Worldwide except the European Union.**

This reaches the UK, Canada, Australia and everywhere else without triggering the EU trader
declaration, which would publish an address, a phone number and an email on the EU product page.
Territories can be widened at any time afterwards, with no new build and no new review, so
nothing is being closed off here. If the EU is added later, Apple accepts a P.O. Box for the
displayed address.

---

## App Review notes

Adapted from section 8 of `~/Projects/archive/furlough/testflight-deployment/DEPLOYMENT.md`, with
three additions the drafted version predates: the usage step that now sits inside onboarding, the
fact that Family Controls does not run in the Simulator, and the report extension. Guideline
2.3.1 requires every feature to be described here with specificity, and an empty usage screen a
reviewer did not expect is the kind of thing that comes back as "the app did not work".

```
WHAT FURLOUGH IS

A self-restriction tool: one person sets rules for the apps on their own iPhone. It is not a parental control app and does not use parent or guardian authorization. Furlough requests individual Screen Time authorization, AuthorizationCenter.requestAuthorization(for: .individual), so the person choosing what to block and the person being blocked are the same adult.

BEFORE YOU START

Screen Time authorization must be granted by an ADULT Apple Account. A child account or a Managed Apple ID will be refused by the system, not by us.

Family Controls does not function in the Simulator. Furlough cannot shield anything there and cannot be evaluated past onboarding. Please review on a physical iPhone running iOS 26 or later.

HOW TO SEE IT WORKING

1. Launch. On the onboarding screen tap "Allow Screen Time access" and accept the system prompt. A "Where your time went" step follows it; tap "Skip for now" at the bottom to reach the home screen.
2. Tap + on the home screen, choose "Application", and pick any installed app.
3. Give it a window that has already passed today, or set the daily budget to its lowest value.
4. Save. Leave Furlough and open the app you picked. It is now behind Furlough's block screen.

THERE IS INTENTIONALLY NO UNBLOCK BUTTON

That is the product. Anything that grants more time waits out a delay the person chose in advance, and is visible and cancellable in the app while it waits. Tightening a rule applies immediately.

The way out is the system's own, is documented inside the app during onboarding and again in Settings, and always works:

Settings > Screen Time > Apps with Screen Time Access > Furlough > off.

Turning it off lifts every shield immediately. The person is never trapped.

APP DELETION IS DENIED WHILE SOMETHING IS SHIELDED

Furlough sets application.denyAppRemoval while any shield is active, so the app cannot be uninstalled as a way around rules the person set for themselves. The Screen Time switch above releases it along with the shields.

THE USAGE STEP AND THE REPORT EXTENSION

The "Where your time went" step reviews the last fortnight of Screen Time history and suggests a rule per app. It has two paths, chosen at runtime. Where Apple grants the App & Website Usage data access capability, the app reads the fortnight itself and draws a scrolling list. Everywhere else, only the DeviceActivityReport extension ever sees a number, so the cards are remote views stepped through one at a time and "Apply" hands off to the picker rather than writing a rule directly, because nothing can be returned out of that sandbox.

On a review device outside the EU the second path is the expected one, and on a device with little Screen Time history the step may have nothing to show. Both are correct behaviour, not a failure. The step is skippable and nothing else in the app depends on it.

Note that requesting the App & Website Usage capability makes the Screen Time authorization prompt all-or-nothing. That wording comes from iOS, not from us.

NFC IS OPTIONAL AND CANNOT BE TESTED WITHOUT HARDWARE

One feature, the Anchor, blocks a chosen set of apps instantly and is released only by scanning a physical NFC tag the person paired beforehand. The person supplies the tag; any NTAG sticker works. Nothing else in the app depends on it and it can be skipped entirely. Furlough reads only a tag's hardware identifier, in the foreground, on the person's own action. It never writes to a tag and never reads one in the background.

WEBSITES

A website chosen from Apple's picker is shielded like an app. A website typed in by hostname is handled by the system's own web content filter, which shows iOS's own "Website Not Allowed" page rather than Furlough's shield. Both are intended.

NO ACCOUNT, NO NETWORK, NO DATA COLLECTION

Furlough has no server, no accounts and no network code at all: no URLSession, no analytics, no third-party SDKs. Rules and the opaque activity tokens never leave the device. The privacy answer is Data Not Collected, and the bundle carries a privacy manifest declaring the two required-reason APIs the app touches (UserDefaults for its App Group, and system boot time for measuring elapsed time between events).

There are no demo credentials because there is nothing to sign in to.
```

**Sign-in required: No.** There is no account, so leave the demo account fields empty.

**Contact:** Zach Short, `zmshort@wm.edu`.

---

## Screenshots

**There is no caption field.** App Store Connect takes images only; the headline and the line
under it are drawn into the PNG by `design/store/board.html`, which composes six 1320 × 2868
frames. So "captions" below means the text baked into each frame.

Apple wants 1 to 10 images with no alpha channel. A 6.9-inch set removes the 6.5-inch
requirement, which is what the 1320 × 2868 canvas is for. Guideline 2.3.3: screenshots must show
the app **in use**, not title art or a splash screen; text and image overlays around a real
capture are explicitly allowed, which is exactly what the board does.

**This is the other blocker.** `design/store/raw/` holds only a README, so all six frames are
currently falling back to drawn placeholders. Family Controls does not run in the Simulator, so
the captures have to come off the phone: take them on the iPhone, convert, and drop them in as
`01.png` through `06.png`. Then `scripts/store-shots.sh` re-renders and flattens to JPEG.

| # | Eyebrow | Headline | Line under it | Change needed |
|---|---|---|---|---|
| 1 | The rule | No unblock button. | Pick the apps that eat your time. Furlough shields them when the time is gone. | none |
| 2 | Budgets | Thirty minutes. Then it's gone. | Give every app a daily budget. Spend it whenever you like. | none |
| 3 | Windows | Open only when you said so. | Eight to ten on school nights. Later on weekends. Your call, once. | none |
| 4 | The delay | Loosening waits a day. | Tightening is instant. Loosening waits out the delay you set. You can cancel it while it waits. | **rewrite, see below** |
| 5 | The Anchor | Locked till you tap the tag. | One tap locks. Only the NFC tag you paired releases it. Leave the tag at home. | **rewrite, see below** |
| 6 | The shield | Nothing to tap but Close. | The block screen says which app, and when it opens next. That is the whole conversation. | none |

Frames 1, 2, 3 and 6 are already right and match the site.

---

## Found while writing this, not fixed

Per the handoff, wording problems belong here rather than in a quiet edit.

1. **`design/store/board.html:191` contains an em dash, in shipped pixels.**
   `Tightening is instant. Every loosening lands 24 hours later &#8212; and you can cancel it.`
   The other two em dashes in the file are in a `<title>` and a CSS comment and never render into
   a frame; this one does.

2. **The same line overclaims, which is a 2.3 problem as well as a voice one.** "Every loosening
   lands 24 hours later" is only true at the default base and only for the Useful tier. A Hazard
   app waits four days. The replacement in the table above drops the number rather than trying to
   explain the tiers in a screenshot.

3. **`design/store/board.html` frame 5 does not say the tag is user-supplied.** "Only a physical
   NFC tag unlocks" reads as though one is included. The replacement says "the NFC tag you
   paired", and swaps "unlocks" for "releases", which is the verb the app itself uses.

4. **`design/store/raw/README.md` is out of date and will cause a missing frame.** It says
   "`01.png` … `05.png`, matching the five frames" and "the five frames in `../board.html`".
   There are **six**. Anyone following it drops five files and ships frame 6 as a placeholder.

5. **`design/store/board.html` frame 6's placeholder shield says "Netflix opens at 5:00 PM" and
   "You get 1 hour per day."** The app's real shield says "Instagram is closed" and "Opens
   tomorrow at 8:00 PM". Only matters if a placeholder ever ships, which it must not, but the mock
   is the wrong voice to be checking the layout against.

6. **`site/src/pages/privacy.astro` understates what the app now reads.** It says Screen Time
   "usage is reported only as anonymous 'a limit was reached' signals". That was true before
   `FurloughReport`. The report extension reads real per-app history, and on a device with App &
   Website Usage data access the app reads it directly. Nothing leaves the phone either way, so
   the *conclusion* still holds, but the sentence as written is no longer accurate and a privacy
   policy is the wrong page to be loose on.

7. **`site/src/site.ts` has `appStoreURL: null`.** Value to set once the listing is public is in
   the URLs section above.

---

## What still blocks a submission

Neither of these is copy, and neither can be finished from this machine.

1. **Real screenshots.** Six captures off the iPhone into `design/store/raw/` as `01.png` to
   `06.png`, then `scripts/store-shots.sh`. Apple requires the app in use, and the Simulator
   cannot produce it.
2. **A deploy of `site/` to `furloughapp.com`.** The domain is decided and the URLs are final;
   the privacy policy and support fields are required and both are currently unreachable.

An App Preview video is optional and none is assumed.
