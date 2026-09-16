# The Mac's first run, watched

What this is for: `site/src/pages/mac.astro` names the three permissions macOS asks for but not
the order they arrive in, because nobody has watched the flow. HANDOFF 43 has owed that
walkthrough since 2026-09-14 and says plainly the repair "has not been watched happening on a
Mac". This file is the script for watching it once, properly, so `/mac` can be rewritten from
life instead of from the code.

It produces two things: **an ordered list of what actually appeared**, and **a screenshot of every
prompt** in `/Users/Shared/furlough-walk/`, which is what the copy gets quoted from.

Walk it in a **fresh user account**. Zach's own account has already approved all three
permissions and will not re-prompt — that is the exact failure this exists to avoid.

**Already verified, 2026-09-16, so do not spend the walk on it.** `/mac` is live and 200, and so
is every other page; the homepage, nav, footer and support all point at `/mac/`; the page's one
download link is `/downloads/Furlough-1.2.0.dmg`; and the file served from there is
**byte-identical** to the local build (SHA-256 `1110b6fd…b62f6b`), `accepted / Notarized
Developer ID / Zach Short (X9V4L6HR2R)`, ticket stapled. The one thing that could not be checked
without a browser is **quarantine** — `curl` does not set the attribute that makes Gatekeeper
speak — so the first-open dialog in step 4 is genuinely unknown until you do it.

---

## What is predicted, and what you are checking

Below is the sequence the code says should happen, with the exact macOS wording read off this
Mac's own frameworks on 2026-09-16. **You are confirming or correcting a prediction, not
transcribing from scratch.** For each one, note whether it appeared, *where in the order*, and
anything that differs. Anything that appears which is not on this list is the most valuable
thing you can bring back.

The prediction — and note that the last two do **not** happen at install time, which is the part
the current page gets wrong:

| # | Prompt | When the code says it fires |
|---|---|---|
| 1 | Gatekeeper, "downloaded from the Internet" | First open of the copied app |
| 2 | Notifications | The **Start** button on onboarding's first pane (`MacOnboardingView`) |
| 3 | Background items (login item, then watchdog agent) | `finishOnboarding` — `setLaunchAtLogin` then `setWatchdog`, back to back |
| 4 | System extension approval | Only when the **web filter is installed** — offered after the **first website** is added, not at first run (HANDOFF 36) |
| 5 | Filter permission | Immediately after the extension activates (`WebFilter.enableFilter`) |
| 6 | Automation, once per browser | Only when a **host has a rule** and that browser is running (`Enforcer` → `Browsers`) |

Exact wording to check against, from the system frameworks:

- **System extension** (`SystemExtensions.framework`) — title `"Furlough" would like to use a new
  network extension`, body `You can enable this extension in Login Items & Extensions. Network
  extensions run in the background and can monitor network traffic on your Mac.`, buttons
  `Open System Settings` / `OK`.
- **Filter permission** (`NetworkExtension.framework`) — title `"Furlough" Would Like to Filter
  Network Content`, body `All network activity on this Mac may be filtered or monitored.`,
  buttons `Allow` / `Don't Allow`.
- **Automation** (`TCC.framework`) — `"Furlough" wants access to control "Safari". Allowing
  control will provide access to documents and data in "Safari", and to perform actions within
  that app.`

---

## Step 0 — before you create the account (in your own account)

Two things on this Mac are **system-wide** and a fresh user account does not reset them. Left
alone, they will silently skip the most important prompt in the walk.

1. **The system extension is already activated.** `systemextensionsctl list` shows
   `com.zachshort.furlough.mac.filter (1.2.0/202609141817)` `[activated enabled]`. A second user
   launching the same app gets no approval prompt, because macOS has already approved that
   extension for this machine. **Take it out first:** in Furlough, **Settings > Web > Remove the
   web filter**, confirm, then check it is gone:

   ```bash
   systemextensionsctl list
   ```

   It should report `0 extension(s)`. Your own Mac is unfiltered until you put it back in
   cleanup — the tab reader keeps enforcing Safari and Chrome meanwhile, which is what the
   confirmation dialog says.

2. **`/Applications/Furlough.app` already exists**, and the login item and the watchdog point at
   it. Leave it where it is; the fresh account will be told to replace it with the identical
   build from the DMG, which is harmless because it is the same signed bits.

3. **Log out — do not fast-user-switch.** Fast user switching leaves your Furlough running
   against the same `/Applications` bundle and the same extension, and two enforcers on one
   store is a mess that will make the walk lie. Logging out is one of the three reasons
   `MacAppDelegate` lets Furlough quit while something is shielded.

---

## Step 1 — the account

System Settings > General > Users & Groups > Add User. Make it an **Administrator**.

Administrator, not Standard, on purpose: approving a system extension needs an admin unlock, and
almost everybody installing this is the admin of their own Mac. (If you want to know what a
Standard user hits, that is a second walk — they reach an unlock they cannot clear, and that is
worth a line on the page if so.)

Name it something obvious like `Walkthrough`. Log out, log in as it.

---

## Step 2 — point screenshots at the shared folder

First thing in the new account, open Terminal and paste:

```bash
mkdir -p /Users/Shared/furlough-walk && defaults write com.apple.screencapture location /Users/Shared/furlough-walk && killall SystemUIServer
```

Now every `⌘⇧4` (then Space, then click the dialog, for a clean window shot) lands somewhere the
main account can read it. **Screenshot every prompt, without exception**, including any that is
not on the prediction list.

---

## Step 3 — the download

Go to **https://furloughapp.com/mac/** in Safari. Not to a local file and not to `build/` — the
point is the whole path, Gatekeeper and quarantine included.

Record: does the page load, does the Download button read the right version, and does anything
about the page mislead you *before* you install — now that you are reading it as a stranger would.

Click Download. Open the DMG. Drag Furlough to Applications. Finder will ask to replace the
existing copy; say yes, and **screenshot what it asks**.

> **Also try this, once, deliberately:** before dragging, double-click Furlough **inside the
> mounted disk image**. `WebFilter.isInApplications` is false there, so the filter refuses and
> HANDOFF 36 says the offer sheet "renders its wrong branch". Screenshot whatever it says. This
> is a separate PASSOFF item, not something to fix here — we just want to know how bad it looks,
> because running an app straight from the DMG is a thing people do. Then quit it and do the
> drag properly.

---

## Step 4 — first open

Open Furlough from `/Applications` (not from the DMG).

**Prompt 1 predicted — Gatekeeper.** Expect roughly `"Furlough" is an app downloaded from the
Internet. Are you sure you want to open it?`. Screenshot it and record the exact wording and the
exact buttons — this is the one prompt whose wording I could not read off a framework, so what
you see is the only source.

---

## Step 5 — onboarding

**Prompt 2 predicted — Notifications**, on the **Start** button of the first pane, before the
second pane appears.

Then pick a half and press **Start with the Anchor** / **Start with Rules**.

**Prompt 3 predicted — background items.** `finishOnboarding` registers the login item and the
watchdog agent back to back. Record whether that is **one** notification or **two**, what it
says, and whether it is a banner you can miss or a dialog that stops you.

Record the order numbers you actually saw. If the notifications prompt came after something
else, that alone rewrites the page.

---

## Step 6 — block an application

Sidebar **+** > Application. Pick something harmless that is installed — TextEdit is ideal.
Give it a rule that blocks it now (no windows, zero budget — an always-blocked category-style
rule, or just a window that does not cover the current time).

Then **launch TextEdit** and watch. Expected: it is asked to quit and the shield panel appears.
Screenshot the shield panel. Record how long it took.

This is the "confirm the app blocks something before you claim it works" half, for apps.

---

## Step 7 — block a website, and meet the filter

Sidebar **+** > Website. Add something you can safely visit — `example.com` is the honest choice.
Give it a rule that blocks it now.

**Prompt 4 and 5 predicted.** Adding the first website is what triggers `WebFilterOfferSheet`
(`Config.hasAnyHost`). Take the offer — press **Install the web filter**.

- The **system extension approval** should appear. Screenshot it. Then follow it: record **which
  System Settings pane it lands you in**, whether you had to unlock, and what the toggle is
  called. The code's log line says `General > Login Items & Extensions > Network Extensions` —
  confirm or correct that, because it goes on the page verbatim.
- The **filter permission** should follow immediately. Screenshot it.

Record whether these two arrive back to back or with a gap, and whether anything required a
restart (`activate()` has an `.afterReboot` branch that says `Restart the Mac to finish
installing the web filter.`).

---

## Step 8 — Automation, in two browsers

**Prompt 6 predicted**, once per browser.

1. In **Safari**, open the blocked site. Expect the Automation prompt naming Safari. Screenshot
   it. Allow it. Expect the tab to be redirected to the shield page within about two seconds
   (`Browsers.pollInterval`).
2. In **Google Chrome**, open the same blocked site. Expect a **second, separate** Automation
   prompt naming Chrome. Screenshot it. This is the step that proves the grant is per-browser,
   and it is the permission most likely to be silently missing.

Record the wording of both, and whether the page visibly loads before the shield replaces it —
the code says it will, and if a stranger sees the site for a moment that belongs on the page.

---

## Step 9 — what to bring back

- The screenshots in `/Users/Shared/furlough-walk/`.
- **The order you actually saw**, as a numbered list.
- For each: which System Settings pane it landed in, and whether it needed an unlock.
- Anything that appeared which is not predicted above.
- Anything that looked broken rather than merely unexplained — that is a `FurloughMac` bug and a
  separate item, not something to fold into the copy.

---

## Step 10 — cleanup

In the walkthrough account: nothing to undo, the account goes.

The 1.2.0 DMG is a Release build with no **Reset everything** — `archive-mac.sh` refuses an
archive carrying it — so Furlough will refuse to quit while something is shielded and the
watchdog will reopen it. **Log out**; that is allowed and it stops cleanly.

Back in your own account:

1. Furlough > **Settings > Web > Install the web filter**, and re-approve the extension and the
   filter. Check with `systemextensionsctl list` that it is `[activated enabled]` again.
2. System Settings > Users & Groups > delete the `Walkthrough` account (delete the home folder;
   keep the next walk clean).
3. `/Users/Shared/furlough-walk/` can go once the screenshots have been read.

If the walkthrough account's install changed anything in **your** account's Furlough state, it
should not have — the App Group store is per-user — but the activity log is the place to check.
