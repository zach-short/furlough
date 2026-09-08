# Brief: the living hourglass

Asked for by Zach on 2026-09-07 after seeing the restyle on his phone. The hero hourglass
should mean something, animate, and be one of several: the header pages through every
managed app, and each app's hourglass is coloured by its status.

## Chosen (2026-09-07): Direction C without quarter marks, header H1

Picked from the mockup board `design/hourglass-board.html`
(https://claude.ai/code/artifact/113cbd4e-85ba-46d4-a144-4ad48a204779), which shows every
direction and variation live against one demo day, all seven status colours per direction,
and the three header layouts as working phones. Built the same day:

- `Shared/UI/Hourglass.swift`: `HourglassState` (sand level, mound level, running, frozen,
  glass tint, sand and mound tones, glow colour and strength, pulse, grain, cube) with the
  presets `open(level:warned:)`, `comingSoon(inMinutes:)`, `doneForToday`, `usedUp`,
  `alwaysBlocked`, `unconfigured`, `anchored`, and `HourglassState.of(target, status:,
  runtime:, now:)` mapping a `TargetStatus` to Direction C. `HourglassView(state:phase:)` is a
  pure drawing driven by a clock value; `TopSandShape` and `MoundShape` take the level (both
  `Animatable`); under 40 pt it switches to a bolder chip drawing. `LivingHourglass` wraps it
  in `TimelineView(.animation)` at 30 fps, pauses two seconds after the state goes still, and
  under Reduce Motion drops the pulse and the grains but keeps the level.
- Home: `HeroPager` pages one `HeroPage` per target in the list's order (Anchored, Open now,
  Later today, Tomorrow, Later this week, Always blocked, Needs a schedule), lands on the
  first open app, and `HeroIndicator` is the strip of 11 pt status hourglasses; tapping one
  turns to that page, tapping a page opens the rule editor. Each page ticks once a second and
  derives the sand level and the countdown from the same date.
- Rows: `StatusChip` shows the 12 pt hourglass in the status colour instead of the SF glyph.
- Widget: `Policy.Summary` gained `openStart`, `openWarned` and `nextOpenIsExhausted`; the
  home-screen sizes show the glass bottom right, and the timeline adds an entry every three
  minutes while a window is open so the sand keeps draining between reloads.
- Live Activity: the glass sits at the leading edge of the card and in the Dynamic Island
  (compact, minimal, expanded). ActivityKit cannot animate custom views, so its level is the
  level at the last sync; `windowStart` is now the window's real start and `ContentState`
  carries `warned` (decoded tolerantly).
- Quarter marks were not built: no `mark:` events, no quarter map. The budget shows only
  through the two callbacks that exist: amber at the 5-minute warning, ember when spent.

## Sand, rebuilt (2026-09-08)

Zach's note after living with it: the top sand floated in the middle of the bulb with air on
both sides, and the stream was a dashed line at one speed with nothing happening where it
landed. Rebuilt in `Shared/UI/HourglassGeometry.swift` (pure geometry, no SwiftUI, checked by
a scratch script) and the shapes in `Hourglass.swift`:

- The sand fills the bulb it is in. Both bulbs are walked from the mockup's body path (the
  two Béziers into the neck, solved by bisection into a quarter-unit table of half widths),
  inset one unit so the wall's stroke stays a line; the stroke is now drawn over the sand.
- The top surface is a funnel: a bowl whose depth is 36 % of the width where the sand meets
  the wall, with a shadow at the bottom, shallower as the last of it runs into the neck.
  Through the neck the sand narrows from the neck's width to the stream's 3 units at the
  orifice (y 81), so the charge pours into the stream instead of stopping on a straight
  line above it, which Zach spotted on the phone. The
  pile below is a cone at about 32°, the angle of repose of dry sand, with a rounded tip
  under the stream and a lighter patch of fresh sand there; it spreads to the walls as it
  grows and fills the corners when it reaches them.
- A level is a share of one charge by area, not a height. One charge is the pile at its
  tallest (tip at y 102); the top bulb's level-1 edge is whatever holds the same area (y
  23.85, so a little air under the lid), and tables invert area to edge or tip. The surface
  drops slowly while the bulb is wide and quickly as it narrows, and top plus pile is
  conserved through a window.
- The stream is grains. `HourglassStream` emits 34 a second from the neck at 16 units/s under
  150 units/s² of gravity, each with its own sideways offset and size from a hash of its
  index, the column wandering slowly and spreading a little as it falls, each grain stretched
  along its fall in proportion to its speed. Everything is a function of the phase, so a
  still phase (widgets, the Live Activity) shows a full stream and the Anchor is the stream
  at one fixed phase. Landing grains throw two chips with a 40 % chance, which hop under the
  same gravity, roll on the pile's surface and fade over 0.42 s; a small dust haze shimmers
  where the stream lands. The lone grain of a window minutes away now accelerates, hops once
  and fades. Reduce Motion and the 12 pt chips keep a solid tapering column.
- Grains are one `Path` of ellipses per opacity band, so a frame is four fills at most, and
  nothing here needs `Canvas`, so the widget and shield extensions draw the same picture.

The rest of this file is the brief as presented.

## What the app can actually know

The design has to be honest about the Screen Time API.

| Fact | Known? | How |
|---|---|---|
| Window start and end, remaining window time | Exactly, every second | `Rule.windows`, `Policy.status(of:)` gives `.open(until:)`, `Countdown` already ticks |
| Whether the app is open now, closed, exhausted, blocked all day, unconfigured, anchored | Exactly | `TargetStatus` |
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
| Anchored | Ember glow | Sand frozen mid-stream (the stream stops dead) | Still. A cube glyph at the base |
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
- Anchored, blocked-all-day and unconfigured pages still get the full hourglass treatment so
  paging never shows an empty page.
- Fonts: the system app name cannot be set in Bricolage (see HANDOFF, "Known API facts"), so
  the page title is the nickname in the display face when one exists, else the system name at
  `.xxxLarge`.
