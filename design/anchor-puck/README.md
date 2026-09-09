# Anchor puck — printable NFC tag case

A two-part printed housing for a Ø25 mm NFC sticker. No screws, no supports, no glue
required. Both parts come off one plate in well under an hour and use about 20¢ of
filament.

Two variants of the same Ø40 × 10 object, set by `variant` in the `.scad`:

| | | |
| --- | --- | --- |
| `press` | a cap that pushes on | fewest features, tightest tolerance, opens with a fingernail |
| `twist` | a cap that drops on and locks with a quarter turn | three lugs, a detent, no tolerance chasing |

Both carry the app's anchor mark cut into the tap face.

The whole design follows from one fact about Furlough: pairing reads the tag's
**hardware UID and never writes to it**. There is no data on the tag, no battery, no
firmware, and nothing to service — so the case can be sealed forever, and the
electronics are just an adhesive sticker. What the retail version sells is the
housing; this is the housing.

Model: [`anchor-puck.scad`](anchor-puck.scad) (OpenSCAD, every dimension below is a
parameter at the top of the file).

## Bill of materials

| Item | Spec | Cost |
| --- | --- | --- |
| NFC sticker | NTAG213/215/216, 25 mm round, ≤ 1 mm thick, adhesive back | $6–12 per pack of ten |
| Filament | PLA or PETG, **plain** — see the warning below | ~9 g, about 20¢ |
| Ballast (optional) | 2 US quarters, a stack of M8 washers, or sand + a drop of CA | pocket change |
| Mount (optional) | 30 mm square of 3M VHB, or a felt pad | ~20¢ |

**The one rule that matters: nothing conductive near the tag.** No metal-filled PLA,
no carbon-fibre filament, no metallic paint, and no aluminium plate glued to the
back. Any of those detune or shield a 13.56 MHz tag and the phone will stop seeing
it. Plain PLA, PETG, ABS and ASA are all effectively invisible to it, in any colour,
including silk finishes.

## Geometry

All in mm; the names match the parameters in the `.scad`.

| Parameter | Default | Why |
| --- | --- | --- |
| `outer_d` | 40 | Assembled diameter. Big enough to hit with a thumb, small enough to vanish on a nightstand. |
| `height` | 10 | Assembled height, lid included. |
| `wall` | 2.0 | Five passes of a 0.4 nozzle — stiff enough that the press fit doesn't splay. |
| `floor_t` | 2.0 | Bottom. |
| `lid_t` | 1.2 | **The critical one.** Plastic between tag and phone. Six layers at 0.2; 1.2 rather than 1.0 so the 0.5 mm engraving still leaves 0.7. Do not exceed 1.5. |
| `plug_h` | 3.0 | How deep the cap plugs in; also the depth of the tag cavity. |
| `fit_gap` | 0.20 | Diametral clearance, plug vs bore. This is the tuning knob. |
| `tag_d` | 25 | Sticker diameter. The cavity is drawn 1 mm wider. |
| `chamfer` | 0.8 | 45° break on the outside edges so it doesn't feel printed. |
| `notch` | true | Fingernail slot in the rim, so a press fit is still reversible. |
| `pad_recess` | 0 | Set to 0.8 for a felt-pad or VHB recess in the underside. |

Derived: bore Ø36.0, plug Ø35.8, tag cavity Ø26.0 × 3.0 deep, and a Ø36 × 3.8
ballast well in the floor of the body.

```
        ┌──────────────────────────┐  ← tap here
        │▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓│  lid_t 1.2  (all that's between tag and phone)
        │███░░░░░ NFC ░░░░░░░░░████│  cavity Ø26 × 3.0, sticker adhered to the roof
        ├───┬──────────────────┬───┤  plug Ø35.8 into bore Ø36.0
        │   │                  │   │
        │   │   ballast well   │   │  Ø36 × 3.8 — coins, washers, sand, or nothing
        │   │                  │   │
        │   └──────────────────┘   │  floor 2.0
        └──────────────────────────┘  ← VHB or felt goes here
        |←────────  40.0  ────────→|
```

## Print settings

- 0.4 nozzle, 0.2 mm layers, PLA at whatever your usual profile is.
- 4 perimeters, 20 % infill, 6 top and bottom layers — the tap face is 1.2 mm, so give
  it enough solid layers to close over the engraving.
- **No supports, no brim.** Both parts are designed so there is nothing to bridge.
- **Lid: flat face down, exactly as it is modelled.** The tap face becomes the first
  layer — smooth off the bed, and the cavity opens upward. Do not flip it.
- Body: open side up, as modelled.

## The mark

The anchor is **debossed**, not raised, and that is a printing decision rather than a
taste one. The tap face is printed against the bed, so a recess is simply absence in
the first two or three layers: no supports, no overhangs, and the sharpest edges the
nozzle can hold, on the smoothest surface on the part. A raised mark on that same face
would have to hang below the bed — you'd have to lift the part onto supports and ruin
the finish, or flip the cap and put a 26 mm bridge over the tag pocket. Emboss is only
free on a face that prints upward, and this isn't one.

- 0.5 mm deep, so the tap face keeps 0.7 mm of its 1.2 over the tag.
- 20 mm tall, which puts the thinnest stroke at about 1.6 mm — twice the 0.8 mm floor
  for a feature to resolve at a 0.4 nozzle.
- It doubles as the tap target: it tells you which face to put the phone on.
- Fill it with a paint pen and wipe the face flat and it reads like an inlay.

[`anchor-mark.scad`](anchor-mark.scad) is generated, not drawn: it is
`AnchorMark.outline` from [Shared/UI/AnchorMark.swift](../../Shared/UI/AnchorMark.swift)
flattened to two contours and 462 points, so the engraving is the app's own mark and
not a redraw of it. To regenerate after the mark changes:

```
swiftc -O Shared/UI/AnchorMark.swift design/anchor-puck/export-mark.swift -o /tmp/export-mark
cd design/anchor-puck && /tmp/export-mark
```

Set `logo = false` for a blank face.

## The fit

The plug is 0.2 mm under the bore, which is a firm push on a well-tuned printer.
Print the lid on its own first (six minutes) and try it before committing to a set:

- Falls out or rattles → drop `fit_gap` to 0.10.
- Won't seat with thumb pressure → raise to 0.30.
- Want it permanent → a thin ring of CA glue on the flange ledge. You'll never need
  to open it; the tag has nothing on it to update.

## Assembly

1. Peel the sticker and press it, centred, onto the flat floor of the lid cavity.
   Its own adhesive is the only fastener.
2. Optional: drop ballast into the body's well so it doesn't skate across a desk.
   Two US quarters, or sand levelled off and wicked with thin CA.
3. Press the lid home until the flange sits flat on the rim. On the twist variant,
   drop the cap on so the lugs pass down the channels, then turn it 30° until the
   detents click.
4. Optional: VHB square on the bottom, or set `pad_recess = 0.8` and inlay a felt pad.

Then pair it in Furlough and **test through the closed lid before you glue anything.**
It should read with the top back edge of the phone within about a centimetre. If it
only reads on hard contact, the lid is too thick, the sticker is smaller than 25 mm,
or something metal is behind it.

## Mounting on metal

A steel desk, a fridge, or a laptop behind the puck will kill the read. Either buy
"anti-metal" / ferrite-backed stickers (they are 0.8–1.0 mm thick — still fits, the
cavity is 3 mm), or keep the default, which already puts 6 mm of air and plastic
between the tag and whatever it's sitting on.

## The twist variant

`variant = "twist"` swaps the push fit for a bayonet: the cup carries three lugs, the
cap has three L-channels, and it locks in 30° of turn. Same Ø40 × 10 outside, same
sticker, same mark.

It exists because a press fit is a tolerance problem — 0.20 mm is either right or it
isn't, and it changes with filament and nozzle temperature. A bayonet doesn't care:
0.35 mm of clearance everywhere, and the joint still ends up tight because the cap
lands on a shoulder rather than on the fit. It also just feels better to close.

| Feature | Size |
| --- | --- |
| Cup collar | Ø33.6, lugs out to Ø36.0 |
| Cap skirt | bore Ø34.3, channel floor Ø36.7, 1.65 mm of wall behind it |
| Lugs | 3 × 26°, 1.6 mm tall, 1.2 mm proud, undersides ramped at 45° |
| Turn | 30°, with 61.8° of unbroken skirt between channels |
| Detent | a Ø0.4 pin at the end of each channel — it bites 0.2 mm |

Two details worth knowing if you change anything:

- The cap seats on the cup's **shoulder**, not on its rim — there is 0.2 mm of relief
  above the rim (`seat`) so only one stop engages. Take that out and the two stops
  fight and it rocks.
- A lug's underside is a 45° ramp so it prints without support; its flat top is the
  face that bears against the channel, so `lug_h` must stay larger than `lug_out`.
- The channels sweep **backwards** from each drop-in slot. The cap is printed face
  down and then flipped onto the cup, which mirrors its handedness — sweep them the
  obvious way and the finished puck locks anticlockwise, against every instinct
  anyone has about lids.

If the detent is too stiff to turn, drop `detent` to 0.3 or set it to 0. If the cap
unscrews itself in a pocket, raise it to 0.5.

## Other shapes

Everything is a parameter, so:

- **Wall plate** — `height = 6`, `pad_recess = 0.8`, VHB in the recess.
- **Keychain fob** — `outer_d = 32`, `height = 7`; add a Ø4 hole through the flange.
- **Chunky desk weight** — `height = 16` for a 10 mm ballast well; a stack of M8
  washers in there makes it feel like the metal one.

Furlough pairs up to three tags (`Furlough.maxAnchorTags`), so a set of three is the
natural print: desk, bedside, front door.

## Export

```
openscad -D 'variant="press"' -D 'part="body"' -o body.stl anchor-puck.scad
openscad -D 'variant="press"' -D 'part="lid"'  -o lid.stl  anchor-puck.scad
openscad -D 'variant="twist"' -D 'part="body"' -o cup.stl  anchor-puck.scad
openscad -D 'variant="twist"' -D 'part="lid"'  -o cap.stl  anchor-puck.scad
```

Or open the file in OpenSCAD, set `variant` and `part` in the customiser, and
File → Export → STL.
