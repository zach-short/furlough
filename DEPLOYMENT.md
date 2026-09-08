# Deploying Furlough

Furlough has only ever been installed over a cable, from Xcode, onto phones registered with the
team. TestFlight and the App Store are a different road, and one thing on it is slow enough that
it should be started before anything else. This file is the map; `HANDOFF.md` stays the record of
what the app *is*.

## Where this stands

| | Status |
|---|---|
| Family Controls **distribution** entitlement | **Not requested.** Blocks everything. Start here. |
| Apple Distribution certificate | **Missing.** This Mac has only *Apple Development: Zach Short*. |
| App Store Connect app record | Not created. |
| `PrivacyInfo.xcprivacy` | **Done** — app + all three extensions, verified in the built bundles. |
| Release configuration compiles | **Verified**, clean, from `HEAD`. |
| Build-number scheme | Still `CURRENT_PROJECT_VERSION: 1`. Needs to move per upload. |
| Screenshots, description, privacy policy, support URL | Not started. |
| App Review notes | Drafted below. |

## 1. The entitlement, first, because it is the long pole

`com.apple.developer.family-controls` is granted for *development* automatically — that is why
the cable has worked all along. Distribution is a separate grant that Apple reviews by hand, per
App ID, through a form:

<https://developer.apple.com/contact/request/family-controls-distribution>

Until it lands, there is no distribution provisioning profile that carries the entitlement, so
there is no archive, no TestFlight build, and no App Store submission. Reports of the wait run
from days to several weeks. Nothing else in this file takes that long, so submit the request and
do the rest while it sits.

**Cover the extensions, not just the app.** This is the most common way the request goes wrong,
and it does not look like a rejection: the main App ID is granted, the extension App IDs sit at
"Pending" or never grow a Distribution option, and nothing can be signed for distribution because
the app cannot install without them. Developers report losing weeks to it. Three App IDs carry the
entitlement and every one needs its own coverage — `com.zachshort.furlough`,
`com.zachshort.furlough.monitor`, `com.zachshort.furlough.shield` — so request each explicitly
rather than assuming the app's grant flows down. (`…​.widgets` carries no Family Controls
entitlement and needs nothing.) When approval mail arrives, check the Distribution capability on
all three in the portal before believing it; the portal is known to lag the email.

**An individual account is not a problem here.** The team is `X9V4L6HR2R`, an Individual
membership under Zach's own name, and nothing in Apple's criteria turns on that. What they weigh
is whether Screen Time is genuinely central to the app and whether the data is used for anything
other than the person's own usage management. Self-restriction apps are eligible alongside
parental controls. The two named rejection causes are a vague justification and uncovered
extensions — hence the specific text above, and the paragraph before this one.

The form sits behind an Apple login, so its exact fields are not reproduced here. It asks who you
are and what the app does with the framework. The substance to give it:

> Furlough is a self-restriction tool for a single person's own iPhone. It is not a
> parental-control product: it asks for **individual** Screen Time authorization
> (`AuthorizationCenter.requestAuthorization(for: .individual)`), so the person choosing what to
> block and the person being blocked are the same adult.
>
> The person picks apps, categories and websites with `FamilyActivityPicker`. Each one gets
> allowed windows on chosen weekdays and a daily minute budget. `DeviceActivity` schedules one
> repeating daily activity carrying a usage threshold per target, plus one activity per distinct
> window, and every callback recomputes shields from saved state. `ManagedSettings` applies those
> shields — `shield.applications`, `shield.webDomains`, and `application.denyAppRemoval` while
> anything is shielded, so the app cannot be deleted to escape its own rules. A shield-
> configuration extension draws the block screen.
>
> The point of the app is that loosening a rule is deliberately slow: a tightening applies at
> once, while anything that grants more time — a longer window, a bigger budget, removing an app
> — waits out a delay the person set in advance, and is visible and cancellable while it waits.
> There is no unblock button in a release build, by design.
>
> Nothing leaves the device. Furlough has no network code — no `URLSession`, no accounts, no
> analytics, no third-party SDKs — and the activity tokens, which are opaque and non-reversible,
> are stored only in the app's own App Group container.

Two ordering notes. Some entitlement requests ask you to name the app in App Store Connect, so
create that record (step 3) before filling the form if it asks. And the entitlement is tied to
the App IDs above — renaming a bundle later means requesting again.

## 2. An Apple Distribution certificate

```bash
security find-identity -v -p codesigning
```

says one identity today, *Apple Development*. TestFlight needs *Apple Distribution*. Easiest path
is Xcode: **Settings > Accounts > (your Apple ID) > Manage Certificates > + > Apple Distribution**.
It is per-Mac, takes a minute, and can be done now — it does not wait on the entitlement.

## 3. The App Store Connect record

New app, iOS, bundle `com.zachshort.furlough`, primary language English. Two things to decide
before the form:

- **The name.** "Furlough" alone may already be taken on the App Store; the name is global and
  first-come. Check it early, because the entitlement request may want to reference the record.
- **A privacy policy URL and a support URL.** Both are required, and the privacy policy is
  required even though the answer is "nothing is collected". Two static pages on a domain you
  own is enough, and you already deploy to Vercel.

Age rating: the questionnaire should come out 4+ — no user content, no web browsing of its own,
no ads.

Two things follow from the membership being an Individual one rather than an Organization, and
both are easier to get right now than to undo:

- **The seller name on the listing is your legal name**, "Zach Short", not a company. Changing it
  later means migrating the account to an Organization, which needs a D-U-N-S number.
- **Distributing in the EU requires declaring trader status**, and Apple publishes the trader's
  address, phone number and email on the EU product page. For an individual that is whatever
  address you type, and the default thing to type is your home. Apple explicitly accepts a
  **P.O. Box** for the displayed address; use one unless you are happy for a personal app to
  carry your home address publicly.

## 4. Privacy, which is the easy part

The nutrition label answer is **Data Not Collected**, honestly: no `URLSession`, no analytics, no
third-party dependencies, no account. Auditing for that is in the commit that added
`Shared/PrivacyInfo.xcprivacy`.

The manifest itself declares the two "required reason" APIs Furlough genuinely touches, and
declaring them wrong is a bounced upload (`ITMS-91053`), so they are worth stating plainly:

- `NSPrivacyAccessedAPICategoryUserDefaults` — `1C8F.1` for the App Group suite shared by the app,
  monitor, shield and widgets, and `CA92.1` for the app's own `furlough.wasAuthorized` flag.
- `NSPrivacyAccessedAPICategorySystemBootTime` — `35F9.1`, for `clock_gettime_nsec_np(CLOCK_MONOTONIC)`
  in `Clock.uptime`, which is what stops a forward clock change from releasing a queued loosening.
  The reason permits measuring elapsed time between events in the app, and forbids sending it off
  device; Furlough sends nothing anywhere.

The file is one copy shared by four targets, listed as a resource on each in `project.yml`, and it
lands at the root of `Furlough.app` and each `.appex` — verified in a Release build.

## 5. Build numbers

`CURRENT_PROJECT_VERSION` is still `1`. App Store Connect rejects a second upload that reuses a
build number under the same `MARKETING_VERSION`, and the archive is where it gets baked in, so
pass it at archive time rather than editing `project.yml` for every upload:

```bash
xcodebuild archive … CURRENT_PROJECT_VERSION=$(date -u +%Y%m%d%H%M)
```

A UTC timestamp always rises, never collides, and says when a build was cut. `MARKETING_VERSION`
stays `1.0` in `project.yml` and moves by hand for a real release.

## 6. Archiving and uploading

None of this works before step 1 lands; it is written down so it is ready when it does.

```bash
xcodegen generate

xcodebuild -project Furlough.xcodeproj -scheme Furlough -configuration Release \
  -destination 'generic/platform=iOS' -allowProvisioningUpdates \
  -archivePath build/Furlough.xcarchive \
  CURRENT_PROJECT_VERSION=$(date -u +%Y%m%d%H%M) \
  archive
```

```bash
xcodebuild -exportArchive -archivePath build/Furlough.xcarchive \
  -exportOptionsPlist scripts/ExportOptions.plist \
  -exportPath build/export -allowProvisioningUpdates
```

That leaves `build/export/Furlough.ipa`. Upload it with an App Store Connect API key (create one
under **Users and Access > Integrations**, download the `.p8` once, and keep it out of the repo):

```bash
xcrun altool --upload-app -f build/export/Furlough.ipa -t ios \
  --apiKey <KEY_ID> --apiIssuer <ISSUER_ID>
```

`scripts/ExportOptions.plist` sets `manageAppVersionAndBuildNumber` to false on purpose, so the
number you passed at archive time is the number that reaches App Store Connect.

Then, in App Store Connect: the build appears after processing, TestFlight internal testing needs
no review, and **external** testing needs a Beta App Review — which is where the notes below start
mattering.

## 7. Notes for App Review — paste these

A Screen Time app that deliberately has no unblock button is exactly the kind of thing a reviewer
bounces for being unclear or for trapping the user, and a reviewer who cannot get past onboarding
rejects on that alone. Both TestFlight external review and App Review should get this:

> **What Furlough is.** A self-restriction tool: the person sets rules for their own apps on their
> own iPhone. It is not a parental control app and does not use parent/guardian authorization.
>
> **Signing in.** Screen Time authorization must be granted by an **adult** Apple Account. Furlough
> requests individual authorization, so a child account or a Managed Apple ID will be refused by
> the system, not by us.
>
> **How to see it working.**
> 1. Launch, and on the onboarding screen tap through to **Allow Screen Time access**. Accept the
>    system prompt.
> 2. Tap **+** on the home screen, choose **Application**, and pick any installed app.
> 3. Give it a window that has already passed today, or set the daily budget to its lowest value.
> 4. Save. Leave Furlough and open the app you picked — it is now behind Furlough's block screen.
>
> **There is intentionally no unblock button.** That is the product. Anything that grants more
> time waits out a delay the person chose in advance. The way out is the system's own, is
> documented in onboarding and in the app's Settings screen, and always works:
> **Settings > Screen Time > Apps with Screen Time Access > Furlough > off.** Turning it off lifts
> every shield immediately.
>
> **App deletion is denied while something is shielded** (`application.denyAppRemoval`), so the app
> cannot be uninstalled to escape rules the person set for themselves. The same switch above
> releases it.
>
> **NFC is optional and cannot be tested without hardware.** One feature, the Anchor, blocks a
> chosen set of apps instantly and is released only by scanning a physical NFC tag the person
> paired beforehand. Nothing else in the app depends on it, and it can be skipped entirely.
> Furlough only reads a tag's hardware identifier in the foreground; it never writes to a tag and
> never reads one in the background.
>
> **No account, no network, no data collection.** Furlough has no server and no network code.
> Rules and activity tokens never leave the device.

## 8. Screenshots, and a wrinkle worth knowing early

App Store Connect wants one 6.9-inch iPhone set (1320 × 2868, 1290 × 2796 or 1260 × 2736 portrait)
and scales it down for smaller phones. The wrinkle is that neither device that could produce those
pixels is available here:

- The phone is an iPhone 17 Pro — 6.3 inches, 1206 × 2622. Its screenshots are the right *picture*
  at the wrong *size*.
- A 6.9-inch Simulator is the right size, but **Family Controls does not work in the Simulator**,
  so it cannot show a real target, a real shield, or anything past onboarding.

So the real screens have to come off the 6.3-inch phone and be placed into 1320 × 2868 frames.
Given the app has a look worth showing — the ember wall, the living hourglass, the countdown — the
better answer is composed marketing shots at the full size with the phone captures inside them,
rather than a plain upscale. That is a design task, not a build task, and it can start whenever.

## Open questions

- **The name.** Is "Furlough" free on the App Store? Everything else in the record depends on it.
- **Who is this for?** The app is written for one person, and the README says so. A public listing
  needs a description, and a reviewer needs to believe the app is useful to a stranger. Worth
  deciding whether this ships as a real product or as something quietly available.
- **The Mac app** is out of scope for now. It is non-sandboxed and drives browsers through Apple
  Events, so the Mac App Store is effectively closed to it; Developer ID signing plus notarization
  is its road, and it is a separate one.
