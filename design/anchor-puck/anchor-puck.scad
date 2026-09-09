// Furlough anchor puck — printable cases for an NFC sticker.
//
// Two variants of the same Ø40 x 10 object, both two parts, no supports, no hardware:
//
//   press — a cap that pushes on. Fewest features, tightest tolerance.
//   twist — a cap that drops on and locks with a quarter turn on three lugs.
//
// Both carry the app's anchor mark cut into the tap face. The mark is DEBOSSED because
// that face is printed against the bed: a recess is simply absence in the first layers,
// so it comes out bed-smooth with no supports. Raised would need the lid flipped, which
// puts a 26 mm bridge over the tag pocket.
//
// The sticker's own adhesive holds it to the inside of the cap, so only `lid_t` of
// plastic sits between the tag and the phone.
//
// Print the cap FLAT SIDE DOWN, exactly as modelled. Render one part at a time:
//   openscad -D 'variant="twist"' -D 'part="lid"' -o cap.stl anchor-puck.scad

use <anchor-mark.scad>

/* [Which puck] */
variant = "press"; // [press, twist]
part = "both";     // [body, lid, both]

/* [Tag] */
// Sticker diameter, mm. 25 is the common NTAG215 round.
tag_d = 25;
// Sticker thickness, mm. ~0.3 paper/PET, up to ~1.0 for a ferrite anti-metal tag.
tag_t = 0.6;

/* [Mark] */
// Cut the anchor mark into the tap face.
logo = true;
// Height of the mark, mm. Keep it inside the tag pocket, so under `tag_d`.
logo_h = 20;
// How deep it is cut, mm. Leaves lid_t - logo_depth of plastic at the thinnest.
logo_depth = 0.5;

/* [Shell] */
// Assembled outside diameter, mm.
outer_d = 40;
// Assembled overall height, mm.
height = 10;
// Side wall thickness, mm. 2.0 = five passes of a 0.4 nozzle.
wall = 2.0;
// Bottom thickness, mm.
floor_t = 2.0;
// Plastic between the tag and the phone, mm. Do not exceed 1.5.
lid_t = 1.2;
// 45-degree break on the outside edges, mm.
chamfer = 0.8;
// Recess in the underside for a felt pad or VHB square, mm. 0 = flat bottom.
pad_recess = 0;

/* [Press fit] */
// How deep the cap plugs in, mm. Also the tag cavity depth.
plug_h = 3.0;
// Diametral clearance, cap plug vs body bore. Lower = tighter. Tune by 0.05.
fit_gap = 0.20;
// Cut a fingernail slot in the rim so the cap can be prised back off.
notch = true;

/* [Bayonet] */
// Lugs around the cup. Three self-centres; two is enough if you want a wider grip.
lugs = 3;
// Arc each lug covers, degrees.
lug_arc = 26;
// Lug height, mm.
lug_h = 1.6;
// How far a lug stands proud of the cup wall, mm. Its underside is a 45-degree ramp.
lug_out = 1.2;
// Collar left above a lug, mm.
lug_inset = 0.6;
// Degrees of turn from dropped-in to locked.
lock_arc = 30;
// Clearance in the bayonet channel, mm.
bay_gap = 0.35;
// Cap wall left behind a channel, mm.
skirt_wall = 1.65;
// Height of cup left showing below the cap, mm.
foot_h = 1.6;
// Pin the lug snaps past on the way home. It bites by half this. 0 leaves it out.
detent = 0.4;

/* [Hidden] */
$fn = 180;
eps = 0.01;
mouth = 0.6;             // lead-in chamfer where one part enters the other
seat = 0.2;              // relief so the cap lands on the shoulder, not the rim
notch_w = 8;
notch_h = 1.2;

// press
bore_d = outer_d - 2 * wall;
plug_d = bore_d - fit_gap;
pocket_d = tag_d + 1.0;
body_h = height - lid_t;

// twist
cap_face = lid_t + tag_t + 0.4;              // tap face plus the tag's own recess
skirt_h = height - cap_face - foot_h;
cup_h = foot_h + skirt_h - seat;
cap_h = cap_face + skirt_h;
cup_od = outer_d - 2 * (skirt_wall + bay_gap + lug_out);
lug_od = cup_od + 2 * lug_out;
cap_bore = cup_od + 2 * bay_gap;
slot_od = lug_od + 2 * bay_gap;
cup_bore = cup_od - 2 * wall;
lug_z = cup_h - lug_inset - lug_h;
bay_arc = bay_gap / (lug_od / 2) * 180 / PI;  // clearance, as an angle at the lug
entry_arc = lug_arc + 2 * bay_arc;
run_z0 = cap_face + seat + lug_inset - bay_gap / 2;
run_z1 = run_z0 + lug_h + bay_gap;

echo(str(variant, ": assembled ", outer_d, " x ", height, "mm  tag pocket ", pocket_d,
         "mm  ", lid_t, "mm over the tag"));
assert(plug_h >= tag_t + 0.5, "plug_h leaves no room for the tag — raise it or thin the tag");
assert(bore_d / 2 > pocket_d / 2 + 2, "tag is too wide for this shell — raise outer_d");
assert(!logo || lid_t - logo_depth >= 0.6, "the mark would leave the tap face too thin");
assert(!logo || logo_h <= tag_d, "keep the mark inside the tag pocket");
assert(cup_bore > pocket_d, "bayonet collar has eaten the tag pocket — raise outer_d");
assert(lug_h > lug_out, "a lug needs to be taller than it is proud, or it has no flat top");
assert(entry_arc + lock_arc < 360 / lugs - 10, "channels have left too little wall between them");

// The app's own mark, from Shared/UI/AnchorMark.swift. Cut from the bed side, so it
// prints as absence rather than as an overhang.
module logo_cut() {
    translate([0, 0, -eps])
        linear_extrude(height = logo_depth + eps)
            scale(logo_h)
                anchor_mark();
}

// ---------------------------------------------------------------- press fit

module body() {
    difference() {
        rotate_extrude()
            polygon([
                [0, 0],
                [outer_d/2 - chamfer, 0],
                [outer_d/2, chamfer],
                [outer_d/2, body_h],
                [bore_d/2 + mouth, body_h],
                [bore_d/2, body_h - mouth],
                [bore_d/2, floor_t],
                [0, floor_t],
            ]);

        if (pad_recess > 0)
            translate([0, 0, -eps])
                cylinder(d = outer_d - 6, h = pad_recess + eps);

        if (notch)
            translate([-notch_w/2, bore_d/2 - 1, body_h - notch_h])
                cube([notch_w, wall + 2, notch_h + eps]);
    }
}

module lid() {
    difference() {
        rotate_extrude()
            polygon([
                [0, 0],
                [outer_d/2 - chamfer, 0],
                [outer_d/2, chamfer],
                [outer_d/2, lid_t],
                [plug_d/2, lid_t],
                [plug_d/2, lid_t + plug_h - mouth],
                [plug_d/2 - mouth, lid_t + plug_h],
                [pocket_d/2, lid_t + plug_h],
                [pocket_d/2, lid_t],
                [0, lid_t],
            ]);
        if (logo) logo_cut();
    }
}

// ------------------------------------------------------------------- twist

module cup() {
    difference() {
        union() {
            rotate_extrude()
                polygon([
                    [0, 0],
                    [outer_d/2 - chamfer, 0],
                    [outer_d/2, chamfer],
                    [outer_d/2, foot_h],
                    [cup_od/2, foot_h],
                    [cup_od/2, cup_h - 0.4],
                    [cup_od/2 - 0.4, cup_h],
                    [cup_bore/2, cup_h],
                    [cup_bore/2, floor_t],
                    [0, floor_t],
                ]);

            for (i = [0 : lugs - 1])
                rotate([0, 0, i * 360/lugs + bay_arc])
                    rotate_extrude(angle = lug_arc)
                        polygon([
                            [cup_od/2, lug_z],
                            [lug_od/2, lug_z + lug_out],
                            [lug_od/2, lug_z + lug_h],
                            [cup_od/2, lug_z + lug_h],
                        ]);
        }

        if (pad_recess > 0)
            translate([0, 0, -eps])
                cylinder(d = outer_d - 6, h = pad_recess + eps);
    }
}

// One bayonet channel's cross-section, swept by rotate_extrude.
module channel(z0, z1) {
    polygon([
        [cap_bore/2 - 1, z0],
        [slot_od/2, z0],
        [slot_od/2, z1],
        [cap_bore/2 - 1, z1],
    ]);
}

module cap() {
    difference() {
        rotate_extrude()
            polygon([
                [0, 0],
                [outer_d/2 - chamfer, 0],
                [outer_d/2, chamfer],
                [outer_d/2, cap_h],
                [cap_bore/2 + mouth, cap_h],
                [cap_bore/2, cap_h - mouth],
                [cap_bore/2, cap_face],
                [pocket_d/2, cap_face],
                [pocket_d/2, lid_t],
                [0, lid_t],
            ]);

        for (i = [0 : lugs - 1])
            rotate([0, 0, i * 360/lugs]) {
                rotate_extrude(angle = entry_arc) channel(run_z0, cap_h + eps);
                rotate_extrude(angle = entry_arc + lock_arc) channel(run_z0, run_z1);
            }

        if (logo) logo_cut();
    }

    // The lug rides over this on the way home and has to be turned back past it.
    if (detent > 0)
        for (i = [0 : lugs - 1])
            rotate([0, 0, i * 360/lugs + entry_arc + lock_arc - lug_arc/2])
                translate([lug_od/2, 0, run_z0])
                    cylinder(d = detent, h = run_z1 - run_z0);
}

// ---------------------------------------------------------------- dispatch

if (variant == "twist") {
    if (part == "body") cup();
    else if (part == "lid") cap();
    else { cup(); translate([outer_d + 5, 0, 0]) cap(); }
} else {
    if (part == "body") body();
    else if (part == "lid") lid();
    else { body(); translate([outer_d + 5, 0, 0]) lid(); }
}
