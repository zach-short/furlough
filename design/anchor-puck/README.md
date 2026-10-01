# Anchor puck: printable NFC tag case

A two-part printed housing for a Ø25 mm NFC sticker. It needs no screws and no glue, and nothing prints with supports. Both parts fit on one plate and use about 9 g of filament at most (the two solid parts weigh 8.5 g in PLA, and infill lowers that), which is roughly 20¢.

Two variants of the same Ø40 × 10 object are set by `variant` in the `.scad`:

| Variant | What it is |
| --- | --- |
| `press` | A cap that pushes on. It has the fewest features, clicks onto a snap bead, and opens with a fingernail. |
| `twist` | A cap that drops on and locks with a quarter turn. It has three lugs and a detent, and there is no tolerance to chase. |

Both carry the app's anchor mark cut into the tap face.

The design follows from one fact about Furlough: pairing reads the tag's hardware UID and never writes to it (`Furlough/Model/TagScanner.swift` reads the identifier and nothing else). Furlough stores nothing on the tag, and the tag needs no battery or firmware and has nothing to service. So the case can be sealed for good, and the electronics are an adhesive sticker. The housing is the only part that needs designing, and this folder is that housing.

## Files

| File | What it is |
| --- | --- |
| [`anchor-puck.scad`](anchor-puck.scad) | The model, in OpenSCAD. Every dimension below is a parameter at the top of the file. |
| [`anchor-mark.scad`](anchor-mark.scad) | The app's anchor mark as a polygon module. Generated, so do not edit it by hand. |
| `mark.json` | The same contours as JSON, read by `render.py` for the face view. Generated with the file above. |
| [`export-mark.swift`](export-mark.swift) | Flattens `AnchorMark.outline` into `anchor-mark.scad` and `mark.json`. |
| [`render.py`](render.py) | Software renderer for the five preview PNGs. |
| `print-instructions.txt` | The plain-language READ ME that goes into the package for a person who prints the puck. |
| `anchor-puck-*.png` | The previews: `assembled`, `exploded`, `face`, `twist` and `lugs`. |

The package script is [`scripts/puck.sh`](../../scripts/puck.sh), outside this folder. It needs `openscad` on the PATH (`brew install --cask openscad`).

## Bill of materials

| Item | Spec | Cost |
| --- | --- | --- |
| NFC sticker | NTAG213, 215 or 216, 25 mm round, 1 mm thick at most, adhesive back | $6 to $12 per pack of ten |
| Filament | PLA or PETG, plain (see the warning below) | about 9 g at most, about 20¢ |
| Ballast (optional) | 2 US quarters, a stack of M8 washers, or sand and a drop of CA glue | pocket change |
| Mount (optional) | 30 mm square of 3M VHB, or a felt pad | about 20¢ |

**The one rule that matters: nothing conductive near the tag.** Do not use metal-filled PLA, carbon-fibre filament or metallic paint, and do not glue an aluminium plate to the back. Any of those detunes or shields a 13.56 MHz tag, and the phone stops seeing it. Plain PLA, PETG, ABS and ASA are effectively invisible to the tag in any colour, including silk finishes.

## Geometry

All sizes are in mm, and the names match the parameters in the `.scad`.

| Parameter | Default | Why |
| --- | --- | --- |
| `outer_d` | 40 | Assembled diameter. Big enough to hit with a thumb, small enough to vanish on a nightstand. |
| `height` | 10 | Assembled height, lid included. On the press variant, 6.2 is the least that works: the floor, the plug and the lid stacked. |
| `wall` | 2.0 | Five passes of a 0.4 nozzle. Stiff enough that the press fit does not splay. |
| `floor_t` | 2.0 | Bottom thickness. |
| `lid_t` | 1.2 | The one that matters most: the plastic between tag and phone. Six layers at 0.2. It is 1.2 instead of 1.0 so the 0.5 mm engraving still leaves 0.7. Do not exceed 1.5. |
| `plug_h` | 3.0 | How deep the cap plugs in. Also the depth of the tag cavity. |
| `fit_gap` | 0.20 | Diametral clearance, plug against bore. Since the bead arrived this only guides the plug in. The bead holds the cap on, not this gap. |
| `bead` | 0.30 | How far the snap ring stands proud of the plug, on the radius. This is the tuning knob. |
| `bead_z` | 1.5 | How far below the rim the bead clicks. It sits near the rim on purpose, so the wall can flare. |
| `tag_d` | 25 | Sticker diameter. The cavity is drawn 1 mm wider. |
| `chamfer` | 0.8 | 45° break on the outside edges, so the puck does not feel printed. |
| `notch` | true | Fingernail slot in the rim, so a press fit can still be opened. |
| `pad_recess` | 0 | Set to 0.8 for a felt-pad or VHB recess in the underside. |

The table leaves out a few parameters. `tag_t` (0.6) is the sticker thickness. `logo`, `logo_h` and `logo_depth` control the mark, and `snap`, `bead_flat` (0.2) and `bead_gap` (0.15) control the snap bead. The bayonet set is listed under the twist variant.

Derived values at the defaults: bore Ø36.0, plug Ø35.8, snap bead Ø36.4 into a Ø36.55 groove, tag cavity Ø26.0 × 3.0 deep, and a Ø36 × 3.8 ballast well left in the body once the plug is home.

```
        ┌──────────────────────────┐  ← tap here
        │▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓│  lid_t 1.2  (all that is between tag and phone)
        │███░░░░░ NFC ░░░░░░░░░████│  cavity Ø26 × 3.0, sticker adhered to the roof
        ├──◄┬──────────────────┬►──┤  bead Ø36.4 clicks into groove Ø36.55
        │   │                  │   │  plug Ø35.8 guides in bore Ø36.0
        │   │   ballast well   │   │  Ø36 × 3.8: coins, washers, sand, or nothing
        │   │                  │   │
        │   └──────────────────┘   │  floor 2.0
        └──────────────────────────┘  ← VHB or felt goes here
        |←────────  40.0  ────────→|
```

## Print settings

- 0.4 nozzle, 0.2 mm layers, PLA at your usual profile.
- 4 perimeters, 20 % infill, 6 top and bottom layers. The tap face is 1.2 mm, so give it enough solid layers to close over the engraving.
- No supports and no brim. Both parts are designed so there is nothing to bridge.
- Lid (the cap in the twist variant): flat face down, exactly as it is modelled. The tap face becomes the first layer, which is smooth off the bed, and the cavity opens upward. Do not flip it.
- Body (the cup in the twist variant): open side up, as modelled.

With `part = "both"`, the default, the file lays the two parts side by side in these orientations, so one export gives one plate.

## The mark

The anchor is debossed, not raised, and that is a printing decision more than a taste one. The tap face is printed against the bed, so a recess is simply absence in the first two or three layers. It needs no supports and no overhangs, and it gets the sharpest edges the nozzle can hold on the smoothest surface of the part. A raised mark on that face would have to hang below the bed. You would print it on supports and ruin the finish, or flip the cap and put a 26 mm bridge over the tag pocket. Emboss is free only on a face that prints upward, and this face does not.

- It is 0.5 mm deep, so the tap face keeps 0.7 mm of its 1.2 over the tag.
- It is 20 mm tall, which puts the thinnest stroke at about 1.6 mm, twice the 0.8 mm floor for a feature to resolve at a 0.4 nozzle.
- It doubles as the tap target, because it shows which face to put the phone on.
- Filled with a paint pen and wiped flat, it reads like an inlay.

`anchor-mark.scad` is generated, not drawn. It is `AnchorMark.outline` from [`Shared/UI/AnchorMark.swift`](../../Shared/UI/AnchorMark.swift) flattened to two contours and 462 points, so the engraving is the app's own mark and not a redraw of it. To regenerate it after the mark changes, run this from the project root. The tool writes `anchor-mark.scad` and `mark.json` into the current directory, which is why the second line changes into this folder first.

```
swiftc -O Shared/UI/AnchorMark.swift design/anchor-puck/export-mark.swift -o /tmp/export-mark
cd design/anchor-puck && /tmp/export-mark
```

Checked on 2026-09-30: the build succeeds, prints `contours 2  points 462`, and writes files identical to the ones checked in. Set `logo = false` for a blank face.

## The fit

A press fit held by friction alone is a lottery you lose on someone else's printer. The plug is 0.2 mm under the bore, and if a machine runs even slightly lean, that gap is only a gap and the cap falls off. The first version fell off. So the cap no longer hangs on friction. A ring around the plug stands 0.30 mm proud, crosses the bore 0.4 mm oversize, and clicks into a groove cut 1.5 mm below the rim.

Both flanks of the bead are at 45° for a printing reason. In the cap the bead's underside overhangs, in the body the groove's ceiling overhangs, and 45° is the steepest either will print unsupported. Symmetric flanks mean the cap pushes on and prises off with about the same force, which is what the fingernail notch is for.

The groove sits near the rim, where the body wall can flare outward. A wall that has to stretch would split: 0.2 mm of radial give at Ø36 is about 1.1 % hoop strain, which is close to the limit of PLA, so the geometry spends that give on bending.

`bead` is the only number worth touching, and both parts change when you change it, so re-export both:

- Clicks on but still pulls off: raise `bead` to 0.40.
- Will not seat with thumb pressure, or the body cracks: drop it to 0.20.
- At 0.10 or below the file stops at an assert, because the bead would never touch the bore.
- PETG takes the click better than PLA, and ABS or ASA take it better still.
- For a permanent closure, run a thin ring of CA glue on the flange ledge. The tag has nothing on it to update, so the case never needs to reopen.

Set `snap = false` for the old friction-only fit, to compare the two.

Field note, 2026-09-16: the one tester so far printed the 0.30 default after the friction-only cap had fallen off, and called it a little too tight. The next package went out at 0.20, half the interference (0.2 mm over the bore instead of 0.4). It did not go out at the numeric midpoint of 0.15, because `fit_gap` absorbs the first 0.1 of any bead and 0.15 would leave only 0.1 mm to hold on. The `.scad` default is still 0.30, and `scripts/furlough puck --bead 0.20` builds the 0.20 package. If 0.20 is right on that printer, the default should follow it.

The bead has one cost: you can no longer test the fit by printing the lid alone. A snap needs both halves, and the body is the slow one.

## Assembly

1. Peel the sticker and press it, centred, onto the flat floor of the lid cavity. Its own adhesive is the only fastener.
2. Optional: drop ballast into the body's well so the puck does not skate across a desk. Use two US quarters, or sand levelled off and wicked with thin CA glue.
3. Press the lid home until the flange sits flat on the rim. On the twist variant, drop the cap on so the lugs pass down the channels, then turn it 30° until the detents click.
4. Optional: add a VHB square on the bottom, or set `pad_recess = 0.8` and inlay a felt pad.

Then pair it in Furlough and test through the closed lid before you glue anything. It should read with the top back edge of the phone within about a centimetre. If it reads only on hard contact, the lid is too thick, the sticker is smaller than 25 mm, or something metal is behind it.

## Mounting on metal

A steel desk, a fridge or a laptop behind the puck will kill the read. One fix is to buy "anti-metal" or ferrite-backed stickers. They are 0.8 to 1.0 mm thick and still fit, because the cavity is 3 mm deep, and `tag_t` should be set to the real thickness. The other is to keep the default, which already puts about 8 mm between the tag and whatever the puck sits on: 6.2 mm of air and the 2.0 mm floor.

## The twist variant

`variant = "twist"` swaps the push fit for a bayonet. The cup carries three lugs, the cap has three L-channels, and it locks in 30° of turn. The outside is the same Ø40 × 10, and the sticker and the mark are the same.

It exists because a press fit is a tolerance problem. The snap bead answers most of that, since it holds on a click and not on a gap, but the bead still has to be sized for a printer, and 0.30 mm is not right everywhere. A bayonet has 0.35 mm of clearance everywhere and nothing to tune, and the joint still ends up tight because the cap lands on a shoulder and not on the fit. It also feels better to close. If you are printing a set for someone else, print this one. The package from `scripts/puck.sh` still lists the press parts first and puts the twist parts in a folder named `twist version (backup)`.

| Feature | Size |
| --- | --- |
| Cup collar | Ø33.6, lugs out to Ø36.0 |
| Cap skirt | bore Ø34.3, channel floor Ø36.7, 1.65 mm of wall behind it |
| Lugs | 3 × 26°, 1.6 mm tall, 1.2 mm proud, undersides ramped at 45° |
| Turn | 30°, with 61.8° of unbroken skirt between channels |
| Detent | a Ø0.4 pin at the end of each channel, which bites 0.2 mm |

The parameters are `lugs`, `lug_arc`, `lug_h`, `lug_out`, `lug_inset`, `lock_arc`, `bay_gap`, `skirt_wall`, `foot_h` and `detent`. Three details are worth knowing if you change any of them:

- The cap seats on the cup's shoulder, not on its rim. There is 0.2 mm of relief above the rim (`seat`), so only one stop engages. Take that out and the two stops fight and the cap rocks.
- A lug's underside is a 45° ramp so it prints without support. Its flat top is the face that bears against the channel, so `lug_h` must stay larger than `lug_out`.
- The channels sweep backwards from each drop-in slot. The cap is printed face down and then flipped onto the cup, which mirrors its handedness. If the channels sweep the obvious way, the finished puck locks anticlockwise, the opposite of how a lid turns.

If the detent is too stiff to turn, drop `detent` to 0.3 or set it to 0. If the cap unscrews itself in a pocket, raise it to 0.5.

## Other shapes

Everything is a parameter, so the same file makes other sizes. The file asserts on impossible sizes and stops, and the checks below were run with OpenSCAD on 2026-09-30.

- Wall plate: `height = 6.5` and `pad_recess = 0.8`, with VHB in the recess. Press variant only. Below 6.2 the file still renders, but the plug meets the floor before the lid seats.
- Keychain fob: `outer_d = 32`, `height = 7` and `tag_d = 20`, which needs a 20 mm sticker. With the default 25 mm sticker the file stops at an assert for any `outer_d` below about 36.5, in both variants. The file has no keyring hole, so add a tab with a Ø4 hole yourself.
- Chunky desk weight: `height = 16` leaves about 10 mm of ballast well (9.8), and a stack of M8 washers in there makes it feel like the metal one.

Furlough pairs up to three tags (`Furlough.maxAnchorTags`), so a set of three is the natural print: desk, bedside, front door.

## Export

To hand the puck to someone who is printing it, build the whole package and do not export by hand. Run this from the project root:

```bash
scripts/furlough puck
```

It calls `scripts/puck.sh`, which renders four STLs and writes `build/puck/furlough-puck.zip`. The zip holds one folder, `Furlough puck`:

- `1 - body.stl` and `2 - lid.stl`, the press variant, in print order.
- `twist version (backup)/1 - cup.stl` and `2 - cap.stl`, the twist variant.
- `READ ME.txt`, a copy of `print-instructions.txt`.
- `source/`, with `anchor-puck.scad` and `anchor-mark.scad`, so the tester can change the fit without asking.

`--bead 0.40` moves the snap bead in the STLs, in the packaged source and in the line the READ ME quotes, so a tester never reads 0.30 in a package that is not 0.30. The zip is then named `furlough-puck-bead0.40.zip`, so two test packages can sit in one folder. `--stl-only` writes the folder and no zip, and `-o DIR` changes the output folder. The script stops on any OpenSCAD error or assert, and it refuses to write an STL that is not a closed solid. It does not commit, tag or upload.

Checked on 2026-09-30 with OpenSCAD 2026.09.10: the script built all four STLs and the zip. The header comment of `scripts/puck.sh` has the full reasoning for each check.

The parts on their own:

```
openscad -D 'variant="press"' -D 'part="body"' -o body.stl anchor-puck.scad
openscad -D 'variant="press"' -D 'part="lid"'  -o lid.stl  anchor-puck.scad
openscad -D 'variant="twist"' -D 'part="body"' -o cup.stl  anchor-puck.scad
openscad -D 'variant="twist"' -D 'part="lid"'  -o cap.stl  anchor-puck.scad
```

Or open the file in OpenSCAD, set `variant` and `part` in the customiser, and choose File → Export → STL.

## Previews

`render.py` draws the PNGs without OpenSCAD or a GPU. It revolves the same profiles the `.scad` extrudes, then rasterises them with a z-buffer and Phong shading. It needs Python 3 with numpy and Pillow. It writes the images to the current directory and reads `mark.json` from there, so run it inside this folder:

```bash
cd design/anchor-puck && python3 render.py
```

It prints one line, such as `assembled done`, as each image finishes. If `mark.json` is missing, it skips the face view.

- `anchor-puck-assembled.png`: the press variant closed.
- `anchor-puck-exploded.png`: body, sticker and lid apart.
- `anchor-puck-face.png`: the tap face seen head-on, with the mark.
- `anchor-puck-twist.png`: cup and cap side by side, with the detent pins.
- `anchor-puck-lugs.png`: the cup alone, to show the lugs.

The script keeps its own copy of the dimensions at the top, and it is older than the snap bead. Its press profile has no bead, so the assembled, exploded and face views show the friction-only press fit. The twist views match the current `.scad`. After a change to `anchor-puck.scad`, update the copied numbers in `render.py` by hand.
