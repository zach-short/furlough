# Brief: the living hourglass

Asked for by Zach on 2026-09-07 after seeing the restyle on his phone. The hero hourglass
should mean something, animate, and be one of several: the header pages through every
managed app, and each app's hourglass is coloured by its status. Present the directions below
(a mockup board is the right form; Zach chooses visually), get his pick, then build.

## What the app can actually know

The design has to be honest about the Screen Time API.

| Fact | Known? | How |
|---|---|---|
| Window start and end, remaining window time | Exactly, every second | `Rule.windows`, `Policy.status(of:)` gives `.open(until:)`, `Countdown` already ticks |
| Whether the app is open now, closed, exhausted, blocked all day, unconfigured, bricked | Exactly | `TargetStatus` |
| Budget used so far | No | DeviceActivity only fires threshold callbacks. Today there are two per target: the 5-minute warning (`eventWillReachThresholdWarning`) and exhaustion. |
| Budget used, in quarters | Possible | Register three more events per target at 25 / 50 / 75 % of the budget (a new name scheme such as `mark:<uuid>:<quarter>`, so the monitor's "stale threshold" guard is not confused), record `quarters[targetID] = n` in `RuntimeState` keyed by day. Cost: 3 events per target on the one "day" activity; callbacks can arrive minutes late or twice, which the day-keyed state absorbs. |
| Budget used, exact minutes | Only inside a `DeviceActivityReport` extension view | The data never reaches the app; the report view is slow to appear and cannot be styled from outside. Not for the hero. Fine for a later "today" detail card if ever wanted. |

## Direction A: window glass

The sand is time. The top bulb holds the remaining window; level is
`(windowEnd − now) / (windowEnd − windowStart)`, the stream runs while the window is open,
and the top empties exactly at close. Exact, honest, animates every second with the
countdown. Budget shows beside it, not in it: the sub line ("30 min budget · 5 min left" once
the warning fires) and an amber tint on the glass after the 5-minute warning.

Variations: A1 plain drain; A2 four etched ticks on the top bulb that dim as the window's
quarters pass; A3 the flip, where the glass turns over at window start (sand jumps to the
top) and settles when it closes.

## Direction B: budget glass

The sand is budget, in quarters, via the extra thresholds. The stream runs only while the
app is open in a window; the level steps down a quarter at each callback with a settle
animation; after the 5-minute warning the last grains run with a faster amber pulse;
exhausted means every grain at the bottom, ember, still. This is what Zach described
("1/2 hours remaining"). Coarse, and it trusts the monitor's timing, but it reads as usage.

Variations: B1 quarters only; B2 quarters plus a thin inner "wick" that estimates within the
current quarter from elapsed open time (clearly a guess, so keep it faint); B3 the bottom
mound grows in four visible layers, one per quarter, so the history of the day is legible.

## Direction C: hybrid

Top bulb is the window (exact, drains continuously, from A). The bottom mound's colour
carries the budget: sand light while plenty is left, amber after the 5-minute warning,
ember when exhausted; optional quarter marks on the base if the extra thresholds are added.
Both facts in one object, each at the precision the API allows.

## Colour by status (the same in every direction)

| Status | Glass and glow | Sand | Motion |
|---|---|---|---|
| Open now | Moss glow, cream glass | Sand gradient, stream running | Stream, slow glow pulse |
| Coming soon (opens later today) | Amber glow, low | All sand in the top, still | Glow breathes; a grain drops when under 10 minutes to open |
| Used up today (opens tomorrow) | Ember glow, dim | All sand in the bottom | Still |
| Always blocked | Faint grey, no glow | Grey sand in the bottom, or no sand | Still |
| Needs a schedule | Pending yellow outline | Empty glass | Still; outline pulses once on appear |
| Bricked | Ember glow | Sand frozen mid-stream (the stream stops dead) | Still. A cube glyph at the base |
| 5 minutes left | Amber | Last grains | Pulse quickens to about 1.2 s |

Reduce Motion: no pulse, no stream particles, levels still change with a plain crossfade.

## Header layouts

- **H1 horizontal paging (recommended).** `ScrollView(.horizontal)` with
  `.scrollTargetBehavior(.paging)` and `.scrollTargetLayout()`, one page per target in the
  existing group order (open first), `scrollPosition(id:)` bound to state. The page indicator
  is a row of tiny hourglasses in their status colours instead of dots, so the strip itself is
  a status summary. Tapping a page opens that app's rule editor. The list below stays.
- **H2 thumbnail strip.** One big hero plus a horizontal strip of small coloured hourglasses,
  one per app; tapping one swaps the hero with a matched-geometry move. Better when there are
  many apps, since the strip is denser than paging.
- **H3 vertical deck.** The hero is a stack; the front card is expanded and the others peek
  below it as thin status bars; drag down to bring the next forward. Most dramatic, hardest to
  make feel native inside the main scroll view; only if Zach wants the flourish.

## Implementation notes for whoever builds it

- Generalise `HourglassView(isOpen:)` in `Shared/UI/Hourglass.swift` to a small state value
  (`sandLevel: Double` 0…1, `isRunning: Bool`, `tint: Color`, `glow: Double`, `frozen: Bool`)
  so the same view serves the hero, the row chips (12 pt), the widget and the Live Activity.
  Make `sandLevel` `Animatable`; the top-sand and bottom-mound paths take the level as a
  parameter instead of the current open/closed scale trick.
- The hero countdown is already `Countdown` (`TimelineView`, 1 s). Drive the sand level from
  the same clock so the two never disagree.
- For B or C's quarters: `Monitoring.register` adds the events; `MonitorExtension` handles
  the new name; `RuntimeState` gains the day-keyed quarter map; `Policy.status` or a sibling
  exposes it. Keep the invariant that every callback is idempotent.
- Bricked, blocked-all-day and unconfigured pages still get the full hourglass treatment so
  paging never shows an empty page.
- Fonts: the system app name cannot be set in Bricolage (see HANDOFF, "Known API facts"), so
  the page title is the nickname in the display face when one exists, else the system name at
  `.xxxLarge`.
