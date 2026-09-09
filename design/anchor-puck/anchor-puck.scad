// Furlough anchor puck — a printable case for an NFC sticker.
//
// Two parts, no supports, no hardware: a cup (body) and a press-fit cap (lid).
// The sticker's own adhesive holds it to the inside of the lid, so only `lid_t`
// of plastic sits between the tag and the phone.
//
// Print the lid FLAT SIDE DOWN, exactly as modelled here: the tap face is the
// first layer, so it comes off the bed smooth and there is nothing to bridge.
//
// Render one part at a time by setting `part`, then File > Export > Export as STL.
//   openscad -D 'part="body"' -o body.stl anchor-puck.scad
//   openscad -D 'part="lid"'  -o lid.stl  anchor-puck.scad

/* [Tag] */
// Sticker diameter, mm. 25 is the common NTAG215 round.
tag_d = 25;
// Sticker thickness, mm. ~0.3 paper/PET, up to ~1.0 for a ferrite anti-metal tag.
tag_t = 0.6;

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
lid_t = 1.0;
// How deep the lid plugs into the body, mm. Also the tag cavity depth.
plug_h = 3.0;

/* [Fit and finish] */
// Diametral clearance, lid plug vs body bore. Lower = tighter. Tune by 0.05.
fit_gap = 0.20;
// 45-degree break on the outside edges, mm.
chamfer = 0.8;
// Cut a fingernail slot in the rim so the lid can be prised back off.
notch = true;
// Recess in the underside for a felt pad or VHB square, mm. 0 = flat bottom.
pad_recess = 0;

/* [Output] */
part = "both"; // [body, lid, both]

/* [Hidden] */
$fn = 180;
eps = 0.01;

bore_d = outer_d - 2 * wall;
plug_d = bore_d - fit_gap;
pocket_d = tag_d + 1.0;
body_h = height - lid_t;
mouth = 0.6;             // lead-in chamfer at the bore mouth
notch_w = 8;             // fingernail slot width
notch_h = 1.2;           // fingernail slot depth below the rim

echo(str("bore ", bore_d, "mm  plug ", plug_d, "mm  cavity ", pocket_d,
         "mm x ", plug_h, "mm  assembled ", outer_d, " x ", height, "mm"));
assert(plug_h >= tag_t + 0.5, "plug_h leaves no room for the tag — raise it or thin the tag");
assert(bore_d / 2 > pocket_d / 2 + 2, "tag is too wide for this shell — raise outer_d");

module body() {
    difference() {
        rotate_extrude()
            polygon([
                [0, 0],
                [outer_d / 2 - chamfer, 0],
                [outer_d / 2, chamfer],
                [outer_d / 2, body_h],
                [bore_d / 2 + mouth, body_h],
                [bore_d / 2, body_h - mouth],
                [bore_d / 2, floor_t],
                [0, floor_t],
            ]);

        if (pad_recess > 0)
            translate([0, 0, -eps])
                cylinder(d = outer_d - 6, h = pad_recess + eps);

        if (notch)
            translate([-notch_w / 2, bore_d / 2 - 1, body_h - notch_h])
                cube([notch_w, wall + 2, notch_h + eps]);
    }
}

module lid() {
    rotate_extrude()
        polygon([
            [0, 0],
            [outer_d / 2 - chamfer, 0],
            [outer_d / 2, chamfer],
            [outer_d / 2, lid_t],
            [plug_d / 2, lid_t],
            [plug_d / 2, lid_t + plug_h - mouth],
            [plug_d / 2 - mouth, lid_t + plug_h],
            [pocket_d / 2, lid_t + plug_h],
            [pocket_d / 2, lid_t],
            [0, lid_t],
        ]);
}

if (part == "body") body();
else if (part == "lid") lid();
else {
    body();
    translate([outer_d + 5, 0, 0]) lid();
}
