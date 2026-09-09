# Furlough design spec: Ember Glass

Chosen on 2026-09-07 from the treatments page
(https://claude.ai/code/artifact/15056f39-c30e-4295-addf-4dc8d79108ed, section "Glass").
This file is the source of truth for the app's look.

The brief in one line: clear iOS 26 Liquid Glass over a dark warm room, one ember glow low on
the screen, Bricolage Grotesque for names, Onest for body, Geist Mono for the countdown. The
most native-feeling treatment. Decoration stays disciplined; the boldness goes into the hero
countdown and the glowing hourglass.

## Palette

| Token | Value | Use |
|---|---|---|
| Ground | `#0F0D0B` | Screen background |
| Ember | `#E5563D` | Accent, prominent button tint, destructive text |
| Amber | `#F59E4A` | Highlights, lock-screen eyebrows, glow |
| Cream | `#F5EFE6` | Primary text, countdown |
| Muted | `#B8AFA3` | Secondary text |
| Faint | `#90877B` | Tertiary text, section labels, slider ticks |
| Moss | `#7BC96F` | "Open now" state, tightening banner |
| Pending | `#F2B544` | Pending-change state |
| Glass fill | white 15% → 5% (160° gradient) | Glass controls |
| Glass border | white 50% → 8% → 50% (160°), 1 pt | Glass edge |
| Card fill | white 6%, blur 18 | List cards, form cards |
| Card border | white 12%, 1 pt | Card edge |
| Slider fill | Ember → Amber, horizontal | Budget slider |

Wall (the background behind everything): Ground, plus a radial ember glow with a 58% of width
by 35% of height radius (60% alpha, fading out by 62% radius), plus a faint amber glow at the
top right (14% alpha). A very light noise overlay (about 7%) keeps gradients from banding. The
ember laps the room rather than sitting still: a 103 s orbit about the middle, 70% of the width
by 56% of the height out, with its reach breathing ±20% every 41 s and its pace wobbling every
32 s. The orbit is polar, so the ember always clears the middle of the screen, where the content
sits — at its widest it passes just off each edge. Reduce Motion parks it at x 28% / y 104%.

Shield tint over the wall: Ember at 22% on `.systemUltraThinMaterialDark`.

## Type

Fonts are bundled from Google Fonts (OFL) in `Furlough/Fonts` and registered with
`UIAppFonts` in the app and widget targets. iOS renders the shield itself, so the shield uses
system type.

| Role | Face | Setting |
|---|---|---|
| Display | Bricolage Grotesque Bold, 72 pt optical size (`BricolageGrotesque_72pt-Bold`) | Hero name, rule-editor name, widget and Live Activity names. Tracking -0.025 em. |
| Display, small | Bricolage Grotesque SemiBold, 24 pt optical size | Row names when a display face is wanted at 13–15 pt. |
| Body | Onest Regular / Medium / SemiBold / Bold | Everything readable: rows, fields, buttons, footnotes, top-bar title. |
| Numerals | Geist Mono Medium | Countdowns, budget value, widget times, Dynamic Island. Tabular numerals, tracking -0.02 em, Cream. |
| Labels / eyebrows | Onest Bold, 10–11 pt, uppercase, letter-spacing 0.12–0.14 em | Section headers, "OPEN NOW · UNTIL 10:00 PM", "NEXT". |

Sizes: hero countdown 42 pt, Live Activity countdown 28 pt, widget countdown 22 pt,
budget value 30 pt, hero name 24 pt, row name 13.5 pt, row detail 11.5 pt.

## Components

**Glass.** Icon buttons (36 pt capsule), pills, time chips, the prominent Save button, the
Live Activity card, and widgets are glass. In SwiftUI use `.glassEffect(.regular, in: .capsule)`
or `.glassEffect(.regular, in: .rect(cornerRadius: 20))`, and `.buttonStyle(.glassProminent)`
with an Ember tint for Save. Glass shows a 1 pt gradient border and a soft specular band on
the top 45%.

**Cards.** Corner radius 20, card fill and border as above, blurred. Rows have 10 pt vertical
padding and are separated by the card border color.

**App tiles.** 34 pt (48 pt in the rule-editor header), radius 9 (13 for the large one).
Render the real icon with FamilyControls `Label(token)`.

**Launch.** A returning user opens on the launch colour (Ground, set as the system launch
screen); then the wall, a running hourglass (106 × 140 pt, Amber glow at 60 %, slow pulse)
and the "FURLOUGH" eyebrow fade up over 0.45 s, hold 1 s, and dissolve into Home over
0.55 s. The wall stays put under the dissolve, so only the glass and the name move. A fresh
install goes straight to onboarding, and granting access dissolves onboarding into Home.

**Home.** Top bar: glass gear on the left, "N pending" glass pill (Pending color) and glass
plus on the right. Hero: one page per managed app, paged horizontally in the list's order
and landing on the first open app (design/HOURGLASS.md, Direction C with header H1). Each
page: the living hourglass (74 × 98 pt) on the left with its glow beneath it, then the
eyebrow, the app name in Display, the big line in Geist Mono, and a sub line. Per status:
"OPEN NOW · UNTIL 10:00 PM" in Moss with the countdown and "30 min budget today"; "OPEN ALL
DAY" in Moss with a countdown to midnight and "30 min budget · resets at midnight" for a rule
without windows; "OPEN NOW ·
5 MIN LEFT" in Amber after the budget warning; "NEXT WINDOW" in Amber with a countdown to the
opening; "USED UP TODAY" in Ember with a countdown to the next opening; "ANCHORED · SINCE
6:12 PM" in Ember counting up; "ALWAYS BLOCKED" in Muted and "NEEDS A SCHEDULE" in Pending
with a quiet word ("all day", "not enforced") in place of the countdown. Under the pages, a
row of 11 pt status hourglasses is the page indicator, the current one at 135 %; the strip
is a status summary in itself. Tapping a page opens its rule editor. List sections in this
order: Anchored · Open now · Later today · Tomorrow · Later this week · Always blocked · Needs
a schedule. A row whose rule varies by day shows today's windows ("Today 8:00 PM–midnight"),
and its chip shows the day ("Sat") when the next window is more than a day away. Each row:
tile, name (nickname small and muted beside it), rule line; on the right a status chip with
the 12 pt hourglass in the status colour and the next time.

**The hourglass.** One vector drawing in a 120 × 160 space, coloured by status. The top bulb
is the window: its sand level is the fraction of the current window still ahead, exact, and
it drains with the countdown. The mound's colour is the budget at the precision the API
allows: sand while there is plenty, Amber after the 5-minute warning, Ember once spent.

| Status | Glass and glow | Sand | Motion |
|---|---|---|---|
| Open now | Cream glass, Moss glow | Draining, stream running | Stream, glow pulse 3.4 s |
| 5 minutes left | Amber glass, Amber glow | Draining, mound Amber | Pulse 1.2 s |
| Coming soon (later today) | Cream glass, Amber glow at 55 % | All in the top | Glow breathes 4.2 s; a grain drops every 3.2 s under 10 minutes to open |
| Done for today (opens another day) | Cream glass, Amber glow at 35 % | All in the bottom | Still |
| Used up today | Dim glass, Ember glow at 45 % | All in the bottom, Ember | Still |
| Always blocked | Grey glass, no glow | Grey, a low mound | Still |
| Needs a schedule | Pending outline, no glow | Empty | Outline fades up once on appear |
| Anchored | Cream glass, Ember glow at 90 % | Frozen mid-stream, an Ember anchor across the neck with a Ground rim | Still |

Reduce Motion: no pulse, no grains (the stream is a solid line), levels still change.

**Rule editor.** Header: large tile, name in Display, "Nickname shows on the shield and
widget." Cards: Nickname (text field), Allowed windows (with no windows, one Muted row "No
windows. Open all day, up to the budget."; otherwise a "Same every day" row with an
Ember-tinted toggle; glass time chips with an arrow between, duration on the right; when the
toggle is off, a strip of seven 26 pt round day toggles under each window, Onest Bold 10 pt
initials, Amber fill with Ground text when on, white 7% with a card border when off, and the
days named in Faint on the right; "+ Add window", "Visualize windows" and "Use windows from
another app" in Ember), Daily budget (value in Geist Mono
with a small "MIN" label, hint "across all windows", slider 5–240 in steps of 5 with ticks at
5 / 30 / 60 / 120 / 240, Ember-to-Amber fill, glass knob). Effect banner: Moss tint,
"Tighter than now · applies immediately", or Pending tint with the effective date. Save is
glassProminent Ember with cream text. "Remove from Furlough" is a ghost button in Ember with a
footnote "Removing loosens your rules, so it takes 1 day."

**Week sheet.** Full-height sheet titled "Week". A card holds the grid: day initials across
the top as 9.5 pt eyebrows (today in Amber), hours down a 40 pt gutter in Geist Mono 8.5 pt
Faint every three hours, card-border hairlines at those hours, seven equal columns with
hairlines between and a 7 % Amber tint on today. Each window is a rounded (5 pt) Amber block
at 92 % with its start time in Geist Mono 8 pt Ground at the top and its end at the bottom
when the block is tall enough. Below the card, "Tap a day to see and change its hours" and
an "In words" card with the grouped schedule, one group per line. Tapping a column pushes
the day editor: the weekday name as the title, a card with a 26 pt horizontal 24-hour bar
(white 7 % track, Amber segments, ticks at 6, 12 and 18), the day's window rows without day
strips, "+ Add window", any validation error in Ember, then an "Apply to other days" card
with a day strip where the current day is a Cream, non-interactive circle, a glassProminent
"Apply to Sat, Sun" button, and a footnote that says what it will do or what it just did.

**Shield.** iOS lays it out. We supply: background blur `.systemUltraThinMaterialDark`,
background color Ember at 22%, icon = the hourglass with a transparent background (to be
generated), title cream, subtitle muted, primary button "Close" with cream background and dark
text, no secondary button.

**Lock screen.** Live Activity: glass card, the open hourglass (30 × 40 pt) at the leading
edge, eyebrow "FURLOUGH" in Amber, name in Display, "Open until 10:00 PM" muted, countdown in
Geist Mono on the right. Dynamic Island: the same hourglass at 14 × 18 pt (compact leading)
and 12 × 16 pt (minimal) plus a Geist Mono countdown. Widgets: eyebrows "OPEN NOW" or
"NEXT", name in Display, countdown or next time in Geist Mono, detail line muted, and the
status hourglass (30 × 40 pt) in the bottom right corner of the home-screen sizes.

**Motion.** The hourglass table above. Everything in it runs off one frame clock at 30 fps
that pauses when the state is still. Respect Reduce Motion.

## Imagery

- App icon: `Furlough/Assets.xcassets/AppIcon.appiconset/icon-1024.png` (Higgsfield
  Recraft V4.1 glass hourglass, toned down with Seedream). Candidates in `design/icons`.
- Still to generate, only after Zach approves each: a transparent-background hourglass for
  the shield icon and the home hero, an onboarding hero and empty-state illustration in the
  same style, and short clips for the README.
