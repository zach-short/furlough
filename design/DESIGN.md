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
| Faint | `#7E766B` | Tertiary text, section labels, slider ticks |
| Moss | `#7BC96F` | "Open now" state, tightening banner |
| Pending | `#F2B544` | Pending-change state |
| Glass fill | white 15% → 5% (160° gradient) | Glass controls |
| Glass border | white 50% → 8% → 50% (160°), 1 pt | Glass edge |
| Card fill | white 6%, blur 18 | List cards, form cards |
| Card border | white 12%, 1 pt | Card edge |
| Slider fill | Ember → Amber, horizontal | Budget slider |

Wall (the background behind everything): Ground, plus a radial ember glow centered at
x 28% / y 104% (60% alpha, fading out by 62% radius), plus a faint amber glow at the top
right (14% alpha). A very light noise overlay (about 7%) keeps gradients from banding.

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

**Home.** Top bar: glass gear on the left, "N pending" glass pill (Pending color) and glass
plus on the right. Hero: hourglass image on the left with an ember glow beneath it, then the
eyebrow ("OPEN NOW · UNTIL 10:00 PM" in Moss when something is open, "NEXT WINDOW" in Amber
otherwise), the app name in Display, the countdown in Geist Mono, and a sub line such as
"30 min budget today". List sections in this order: Open now · Later today · Tomorrow ·
Later this week · Always blocked · Needs a schedule. A row whose rule varies by day shows
today's windows ("Today 8:00 PM–midnight"), and its chip shows the day ("Sat") when the next
window is more than a day away. Each row: tile, name (nickname small and muted beside
it), rule line; on the right a status chip with a lock or hourglass glyph and the next time.

**Rule editor.** Header: large tile, name in Display, "Nickname shows on the shield and
widget." Cards: Nickname (text field), Allowed windows (a "Same every day" row with an
Ember-tinted toggle; glass time chips with an arrow between, duration on the right; when the
toggle is off, a strip of seven 26 pt round day toggles under each window, Onest Bold 10 pt
initials, Amber fill with Ground text when on, white 7% with a card border when off, and the
days named in Faint on the right; "+ Add window" and "Use windows from another app" in
Ember), Daily budget (value in Geist Mono
with a small "MIN" label, hint "across all windows", slider 5–240 in steps of 5 with ticks at
5 / 30 / 60 / 120 / 240, Ember-to-Amber fill, glass knob). Effect banner: Moss tint,
"Tighter than now · applies immediately", or Pending tint with the effective date. Save is
glassProminent Ember with cream text. "Remove from Furlough" is a ghost button in Ember with a
footnote "Removing loosens your rules, so it takes 1 day."

**Shield.** iOS lays it out. We supply: background blur `.systemUltraThinMaterialDark`,
background color Ember at 22%, icon = the hourglass with a transparent background (to be
generated), title cream, subtitle muted, primary button "Close" with cream background and dark
text, no secondary button.

**Lock screen.** Live Activity: glass card, eyebrow "FURLOUGH" in Amber, name in Display,
"Open until 10:00 PM" muted, countdown in Geist Mono on the right. Dynamic Island compact:
hourglass glyph in Amber plus a Geist Mono countdown. Widgets: eyebrows "OPEN NOW" or "NEXT",
name in Display, countdown or next time in Geist Mono, detail line muted.

**Motion.** A slow ember pulse under the hourglass (3.4 s, alternating), and the sand in the
hourglass settles when a window closes. Respect Reduce Motion.

## Imagery

- App icon: `Furlough/Assets.xcassets/AppIcon.appiconset/icon-1024.png` (Higgsfield
  Recraft V4.1 glass hourglass, toned down with Seedream). Candidates in `design/icons`.
- Still to generate, only after Zach approves each: a transparent-background hourglass for
  the shield icon and the home hero, an onboarding hero and empty-state illustration in the
  same style, and short clips for the README.
