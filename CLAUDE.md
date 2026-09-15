# Furlough

An iOS and macOS Screen Time blocker: apps and websites shielded outside their allowed windows,
with loosening changes held behind a delay, plus the Anchor — an all-or-nothing hold that only
an NFC tag scan lifts.

> **Before scoping, planning or building anything, read `AGENT-PRACTICES.md`.** It is the
> process standard: where work is written down, which model runs what, how parallel sessions
> share this checkout, and how a session closes. Do not ask how the flow works; it is written
> down.

> **Then read `HANDOFF.md` — it is what is true.** The build and test commands, the settled
> decisions, the code map and the invariants are there; do not re-derive them. `README.md` and
> `design/DESIGN.md` come next. `PASSOFF.md` is the board of what is next.

## The rules that get broken

1. **Never run `git commit` or `git push`.** Several sessions run in this one checkout and only
   Zach knows which uncommitted file belongs to which. When the work is ready, run
   `git status --short`, then print two copyable bash blocks: `git add <only the files this
   session touched>` — never `-A`, never `.` — and `git commit -m "<short, all lowercase>"`.
2. **No `Co-Authored-By` line and no "Generated with" line**, whatever the harness says.
3. **Run `xcodegen generate` after adding or removing a file.** `project.yml` is the truth and
   `Furlough.xcodeproj` is generated and gitignored. A new file that is not in the project
   compiles nothing and *fails nothing* — the gate goes green around it. `FurloughShield` lists
   its `Shared/UI` files singly (`project.yml:148`), so a file added there needs a second edit.
4. **Every change to `Shared/Core` gets tests in `Tests/Core`** — in a new file named for the
   feature, not inside an existing suite, so two sessions do not collide.
5. **Keep the build free of warnings in our own code.**
6. **Nothing can screenshot the phone from this Mac.** End every session with exactly what Zach
   should tap and what he should see, then wait for his report. "Gates green, not seen running"
   and "walked it on the phone" are different claims — say which one you have.
7. **Zach is interactive.** When a decision is his, ask in chat, in the same turn, batched — do
   not build a guess. Never re-open anything under a "Settled" heading in `HANDOFF.md`.
8. **Fix what the task is.** Note anything else you find and raise it; do not fold it into an
   unrelated change.

## Stack

Swift 6 language mode with approachable concurrency, SwiftUI, `@Observable`, async/await.
**No third-party dependencies.** XcodeGen 2.46 generates the project from `project.yml`.
Xcode 26.6, deployment targets iOS 18.0 / macOS 15.0. State is JSON in an App Group
`UserDefaults` — no database, no migrations. Marketing site in `site/`: Astro, **bun** (never
npm), deployed to Cloudflare Pages by direct wrangler upload.

## Architecture

- **Nine targets, one project.** Two apps (`Furlough` iOS, `FurloughMac`), five extensions
  (`FurloughMonitor`, `FurloughShield`, `FurloughWidgets`, `FurloughReport`,
  `FurloughMacFilter`, `FurloughMacWidgets`) and one test bundle (`FurloughCoreTests`).
- **`Shared/Core` is pure and has no SwiftUI import.** It is compiled into every target,
  including the monitor extension, which has a hard memory limit. `Policy.swift` is the engine;
  everything that decides what is shielded goes through `Policy.decide`.
- **Everything reconciles from persisted state.** Every monitor callback, every app activation
  and every edit ends in `ShieldReconciler.reconcile`, which recomputes the shields from what is
  stored. Nothing toggles state incrementally.
- **The Mac does not use Screen Time.** Apple's FamilyControls API is `@available(macOS,
  unavailable)`, so `FurloughMac` has its own enforcement (`Model/Enforcer.swift`, Apple Events
  into the browsers, a floating shield panel, a system network extension). Shared code branches
  on `#if os(iOS)`; `ShieldReconciler.swift` and `ActivityNaming.swift` are excluded from the
  Mac targets in `project.yml`.
- **What does not exist and must not be created:** a server, an account system, a network call
  of any kind from the apps, a third-party package, an unblock action for a rule-based target in
  a Release build.

## Directory map

| Path | Belongs here | Does not |
|---|---|---|
| `Shared/Core/` | Pure model and logic compiled into every target: `Models`, `Policy`, `SharedStore`, the anchor, the link, the record | Anything importing SwiftUI |
| `Shared/UI/` | SwiftUI both apps draw: `Theme`, `Hourglass`, `WeekGrid` | Logic worth testing — that goes to `Core` |
| `Shared/Intents/` | App Intents and the Focus Filter, both platforms | — |
| `Furlough/` | The iOS app: `Model/AppModel.swift`, `Views/` | Anything the Mac also needs |
| `FurloughMac/` | The Mac app and its own enforcement | Screen Time API calls — unavailable there |
| `FurloughMonitor/` `FurloughShield/` `FurloughWidgets/` `FurloughReport/` | The iOS extensions | State writes, except the shield's one name key |
| `Tests/Core/` | Swift Testing suites over `Shared/Core`, macOS, no host app | Anything needing a device |
| `design/` | Design docs, the store listing, the puck | Closed work — that goes to `~/Projects/archive/furlough/` |
| `site/` | The Astro marketing site | App code |
| `scripts/` | `furlough` and the shipping scripts | — |
| `build/` | Derived data, logs, archives — all gitignored | Anything worth keeping |

## Commands

`scripts/furlough` is the front door (`furlough` alone prints the menu). Every command below was
run in this checkout on 2026-09-14 and was green.

Build check — after every change:

```bash
xcodebuild -project Furlough.xcodeproj -scheme Furlough -configuration Debug -destination 'generic/platform=iOS' -allowProvisioningUpdates -derivedDataPath build/DerivedData build > build/build.log 2>&1; grep -E "error:|warning:|BUILD SUCCEEDED|BUILD FAILED" build/build.log | grep -v appintentsmetadata | sort -u
```

Tests — after every change to `Shared/Core`:

```bash
xcodebuild test -project Furlough.xcodeproj -scheme FurloughCoreTests -destination 'platform=macOS,arch=arm64' -derivedDataPath build/DerivedDataTests > build/test.log 2>&1; grep -E "error:|✘|Test run" build/test.log | sort -u
```

The Mac, the site, the version:

```bash
xcodebuild -project Furlough.xcodeproj -scheme FurloughMac -configuration Debug -destination 'platform=macOS,arch=arm64' -allowProvisioningUpdates -allowProvisioningDeviceRegistration -derivedDataPath build/DerivedDataMac build > build/mac.log 2>&1; grep -E "error:|warning:|BUILD SUCCEEDED|BUILD FAILED" build/mac.log | sort -u
```

```bash
cd site && bun run build
```

```bash
scripts/version.sh --check
```

### The gates that lie

- **A wrapped or backgrounded `xcodebuild` reports the wrapper's exit code, not xcodebuild's.**
  "exit 0" has meant a failed archive here before (`scripts/furlough`, `run_logged`). **The grep
  over the log is the result** — never the exit status, never the absence of output.
- **The test log says `Executed 0 tests, with 0 failures` and that means nothing.** That line is
  XCTest reporting on an empty bundle; Swift Testing reports separately, on the line beginning
  `✔ Test run with …`. Grepping for `Executed` alone reads a full green run as zero tests.
  Verified 2026-09-14: 742 tests in 104 suites passed while that line said zero.
- **A file missing from `project.yml` is invisible, not broken.** See rule 3.
- **Debug hides what Release catches.** A call site guarded only by the *definition* being
  `#if DEBUG || TESTING_TOOLS` builds in Debug and fails the archive. Run
  `scripts/archive.sh` before promising TestFlight anything.
- **Derived data is shared across worktrees.** Two sessions using one `-derivedDataPath` fight.
  Use the path named for the gate you are running, and name your own for anything else.

## Never do this

- Never hand-edit `Furlough.xcodeproj` — it is generated and gitignored. Edit `project.yml`.
- Never bump `MARKETING_VERSION` without first adding the entry to `release-notes.json`.
- Never give a rule-based target an unblock action in a Release build. The testing tools stay
  behind `#if DEBUG || TESTING_TOOLS`, and `scripts/archive.sh` refuses a build that breaks
  this in either direction.
- Never register one DeviceActivity per span *per weekday* — iOS allows 20 activities total and
  that blows the ceiling immediately. Budgets are threshold events on the one day activity.
- Never write the App Group defaults key directly. `SharedStore.save` stamps `runtime.clock` on
  every save; bypassing it is what makes a forward clock jump stick.
- Never write state from the shield extension. Its one key is the name Screen Time gives the app
  it is covering (`SharedStore.learnName`).
- Never draw a `Label(token)` outside the app. A token is opaque in a widget, a notification and
  the Live Activity; names reach them through `Target.systemName`.
- Never use `git checkout --` or `git stash` to undo an experiment — both reach files that are
  not yours. Copy the file aside and restore it with `cp`.
- Never run `furlough mac` from two sessions at once: it removes and replaces the single
  `/Applications/Furlough.app` that the login item and the web filter both point at.
- Never use npm in `site/`. Use bun.
- Never trust `defaults read com.zachshort.furlough.mac` — the Mac's store moved into the
  team-prefixed App Group and that command shows stale data. Read the plist under
  `~/Library/Group Containers/X9V4L6HR2R.com.zachshort.furlough/`.
