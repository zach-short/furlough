"""Software render of the anchor puck, straight from the .scad profiles.

Revolves the same two polygons the OpenSCAD file extrudes, then rasterises them
with a z-buffer and Phong shading. No OpenSCAD, no GPU.
"""
import json
import math
import os
import numpy as np
from PIL import Image

# --- parameters, mirroring anchor-puck.scad -------------------------------
tag_d, tag_t = 25.0, 0.6
outer_d, height = 40.0, 10.0
wall, floor_t, lid_t, plug_h = 2.0, 2.0, 1.2, 3.0
fit_gap, chamfer, mouth = 0.20, 0.8, 0.6

bore_d = outer_d - 2 * wall
plug_d = bore_d - fit_gap
pocket_d = tag_d + 1.0
body_h = height - lid_t

BODY = [(0, 0), (outer_d/2 - chamfer, 0), (outer_d/2, chamfer), (outer_d/2, body_h),
        (bore_d/2 + mouth, body_h), (bore_d/2, body_h - mouth), (bore_d/2, floor_t), (0, floor_t)]
LID = [(0, 0), (outer_d/2 - chamfer, 0), (outer_d/2, chamfer), (outer_d/2, lid_t),
       (plug_d/2, lid_t), (plug_d/2, lid_t + plug_h - mouth), (plug_d/2 - mouth, lid_t + plug_h),
       (pocket_d/2, lid_t + plug_h), (pocket_d/2, lid_t), (0, lid_t)]
TAG = [(0, 0), (tag_d/2, 0), (tag_d/2, 0.3), (0, 0.3)]

GRAPHITE = np.array([0.205, 0.215, 0.235])
ORANGE = np.array([0.78, 0.28, 0.10])


def signed_area(profile):
    n = len(profile)
    return 0.5 * sum(profile[i][0]*profile[(i+1) % n][1] - profile[(i+1) % n][0]*profile[i][1]
                     for i in range(n))


def place(profile, dz=0.0, flip=False):
    """Move a profile up the z axis, optionally flipping it end for end."""
    pts = [(r, (-z if flip else z) + dz) for r, z in profile]
    if flip:
        pts = list(reversed(pts))
    assert signed_area(pts) > 0, "profile wound the wrong way"
    return pts


def revolve(profile, albedo, segments=200):
    """Lathe a profile into triangles. Normals come from the profile segment, so
    edges stay crisp along the profile and smooth around the axis."""
    th = np.linspace(0, 2*math.pi, segments, endpoint=False)
    cos, sin = np.cos(th), np.sin(th)
    tris, norms = [], []
    n = len(profile)
    for j in range(n):
        r0, z0 = profile[j]
        r1, z1 = profile[(j + 1) % n]
        dr, dz = r1 - r0, z1 - z0
        length = math.hypot(dr, dz)
        if length < 1e-9:
            continue
        nr, nz = dz / length, -dr / length          # outward normal in the (r, z) plane
        # ring of vertices at each end of this profile segment
        a = np.stack([r0*cos, r0*sin, np.full(segments, z0)], axis=1)
        b = np.stack([r1*cos, r1*sin, np.full(segments, z1)], axis=1)
        nrm = np.stack([nr*cos, nr*sin, np.full(segments, nz)], axis=1)
        k = np.arange(segments)
        kn = (k + 1) % segments
        # two triangles per quad, with matching per-vertex normals
        tris.append(np.stack([a[k], b[k], b[kn]], axis=1))
        norms.append(np.stack([nrm[k], nrm[k], nrm[kn]], axis=1))
        tris.append(np.stack([a[k], b[kn], a[kn]], axis=1))
        norms.append(np.stack([nrm[k], nrm[kn], nrm[kn]], axis=1))
    V = np.concatenate(tris, axis=0)
    N = np.concatenate(norms, axis=0)
    return V, N, np.tile(albedo, (len(V), 1))


def render(meshes, eye, target, size, ss=2, layer_lines=True, shadow=True, frame=0.86,
           decal=None):
    W, H = size[0]*ss, size[1]*ss
    V = np.concatenate([m[0] for m in meshes], axis=0)
    N = np.concatenate([m[1] for m in meshes], axis=0)
    A = np.concatenate([m[2] for m in meshes], axis=0)

    eye, target = np.array(eye, float), np.array(target, float)
    fwd = target - eye
    fwd /= np.linalg.norm(fwd)
    right = np.cross(fwd, np.array([0, 0, 1.0]))
    right /= np.linalg.norm(right)
    up = np.cross(right, fwd)

    rel = V - eye
    cam = np.stack([rel @ right, rel @ up, rel @ fwd], axis=-1)      # (T,3,3)
    depth = np.maximum(cam[..., 2], 1e-6)
    u, v = cam[..., 0] / depth, cam[..., 1] / depth
    F = min(W * frame / (u.max() - u.min()), H * frame / (v.max() - v.min()))
    cx = W/2 - F * (u.min() + u.max()) / 2
    cy = H/2 + F * (v.min() + v.max()) / 2
    sx = cx + u * F
    sy = cy - v * F

    # background gradient
    g = np.linspace(0, 1, H)[:, None]
    img = (np.array([0.945, 0.953, 0.960])[None, None, :] * (1 - g[..., None])
           + np.array([0.855, 0.870, 0.885])[None, None, :] * g[..., None])
    img = np.repeat(img, W, axis=1)
    zbuf = np.full((H, W), np.inf)
    cover = np.zeros((H, W), bool)
    shade = np.zeros((H, W, 3))

    key = np.array([-0.42, -0.72, 0.85]); key /= np.linalg.norm(key)
    fill = np.array([0.80, -0.35, 0.25]); fill /= np.linalg.norm(fill)
    back = np.array([0.30, 0.85, 0.30]); back /= np.linalg.norm(back)

    xs = sx.astype(np.float64); ys = sy.astype(np.float64)
    for t in range(len(V)):
        x0, x1, x2 = xs[t]; y0, y1, y2 = ys[t]
        area = (x1 - x0)*(y2 - y0) - (x2 - x0)*(y1 - y0)
        if area <= 1e-9:            # back-facing or degenerate
            continue
        lo_x = max(int(math.floor(min(x0, x1, x2))), 0)
        hi_x = min(int(math.ceil(max(x0, x1, x2))) + 1, W)
        lo_y = max(int(math.floor(min(y0, y1, y2))), 0)
        hi_y = min(int(math.ceil(max(y0, y1, y2))) + 1, H)
        if lo_x >= hi_x or lo_y >= hi_y:
            continue
        px = np.arange(lo_x, hi_x) + 0.5
        py = np.arange(lo_y, hi_y) + 0.5
        gx, gy = np.meshgrid(px, py)
        w0 = ((x1 - x0)*(gy - y0) - (gx - x0)*(y1 - y0)) / area
        w1 = ((gx - x0)*(y2 - y0) - (x2 - x0)*(gy - y0)) / area
        inside = (w0 >= 0) & (w1 >= 0) & (w0 + w1 <= 1)
        if not inside.any():
            continue
        b2, b1 = w0, w1
        b0 = 1 - b1 - b2
        invz = b0/depth[t, 0] + b1/depth[t, 1] + b2/depth[t, 2]
        z = 1 / np.maximum(invz, 1e-9)
        sub = zbuf[lo_y:hi_y, lo_x:hi_x]
        win = inside & (z < sub)
        if not win.any():
            continue
        idx = np.where(win)
        bb = np.stack([b0[idx], b1[idx], b2[idx]], axis=-1)
        pos = bb @ V[t]
        nrm = bb @ N[t]
        nrm /= np.maximum(np.linalg.norm(nrm, axis=-1, keepdims=True), 1e-9)
        view = eye - pos
        view /= np.linalg.norm(view, axis=-1, keepdims=True)

        lam = (0.80*np.clip(nrm @ key, 0, None)
               + 0.22*np.clip(nrm @ fill, 0, None)
               + 0.14*np.clip(nrm @ back, 0, None) + 0.16)
        h = key + view
        h /= np.linalg.norm(h, axis=-1, keepdims=True)
        spec = 0.30 * np.clip(np.sum(nrm*h, axis=-1), 0, None)**42
        rim = 0.10 * (1 - np.abs(np.sum(nrm*view, axis=-1)))**3
        alb = A[t].copy()
        if layer_lines:
            band = 1 + 0.05*np.sin(2*math.pi*pos[:, 2]/0.2) * (1 - np.abs(nrm[:, 2]))
            alb = alb[None, :] * band[:, None]
        else:
            alb = np.repeat(alb[None, :], len(lam), axis=0)
        col = alb * lam[:, None] + spec[:, None] + rim[:, None]

        yy = idx[0] + lo_y; xx = idx[1] + lo_x
        zbuf[yy, xx] = z[idx]
        shade[yy, xx] = col
        cover[yy, xx] = True

    def boxblur(a, k):          # separable box blur via running sums
        pad = k // 2
        p = np.pad(a, ((0, 0), (pad, pad)), mode="edge")
        c = np.cumsum(p, axis=1)
        c = np.concatenate([np.zeros((a.shape[0], 1)), c], axis=1)
        return (c[:, k:] - c[:, :-k]) / k

    # A debossed mark on a face: seen near head-on, a 0.5 mm recess reads as a step in
    # shading rather than a step in silhouette, so darken the covered pixels.
    if decal is not None:
        from PIL import ImageDraw
        polys_xy, z_plane, _depth = decal
        mask = Image.new("L", (W, H), 0)
        dr = ImageDraw.Draw(mask)
        order = sorted(polys_xy, key=lambda q: -abs(np.sum(
            np.array(q)[:, 0] * np.roll(np.array(q)[:, 1], -1)
            - np.roll(np.array(q)[:, 0], -1) * np.array(q)[:, 1])))
        for j, poly in enumerate(order):
            w = np.array([[x, y, z_plane] for x, y in poly], float) - eye
            d = np.maximum(w @ fwd, 1e-6)
            pts = list(zip(cx + (w @ right) / d * F, cy - (w @ up) / d * F))
            dr.polygon(pts, fill=255 if j == 0 else 0)
        m = np.asarray(mask, float) / 255.0
        edge = m - boxblur(boxblur(m.T, 5).T, 5)          # thin rim where it steps down
        cut = cover & (m > 0.5)
        shade[cut] *= 0.62
        shade[cover] *= (1 - 0.35 * np.clip(edge, 0, 1))[cover][:, None]

    if shadow:
        # soft contact shadow: the silhouette, nudged down and blurred
        m = cover.astype(np.float64)
        m = np.roll(m, int(0.012*H), axis=0)
        k = max(3, int(0.010*W)) | 1
        for _ in range(3):
            m = boxblur(m, k)
            m = boxblur(m.T, k).T
        img *= (1 - 0.40*np.clip(m, 0, 1))[..., None]

    img = np.where(cover[..., None], shade, img)
    img = np.clip(img, 0, 1)**(1/2.2)
    out = Image.fromarray((img*255 + 0.5).astype(np.uint8))
    return out.resize(size, Image.LANCZOS)


body = revolve(BODY, GRAPHITE)
lid_asm = revolve(place(LID, dz=height, flip=True), GRAPHITE)
render([body, lid_asm], eye=(64, -92, 50), target=(0, 0, 5),
       size=(1400, 1000), frame=0.74).save("anchor-puck-assembled.png")
print("assembled done")

# Build order: the lid sits as it comes off the bed, cavity up, sticker dropped in.
lid_open = revolve(place(LID, dz=height + 12), GRAPHITE)
tag_open = revolve(place(TAG, dz=height + 12 + lid_t), ORANGE)
render([body, tag_open, lid_open], eye=(72, -104, 62), target=(0, 0, 13),
       size=(1400, 1120), frame=0.80, shadow=False).save("anchor-puck-exploded.png")
print("exploded done")

# The mark on the tap face, seen near head-on, where a 0.5 mm recess has no parallax.
LOGO_H = 20.0
if os.path.exists("mark.json"):
    mark = [[(x * LOGO_H, y * LOGO_H) for x, y in poly]
            for poly in json.load(open("mark.json"))]
    render([body, lid_asm], eye=(0, -30, 124), target=(0, 0, 6), size=(1200, 1200),
           frame=0.82, decal=(mark, height, 0.5)).save("anchor-puck-face.png")
    print("face done")
else:
    print("no mark.json here — run export-mark.swift first; skipping the face view")


# --- twist variant --------------------------------------------------------
# The lugs and the bayonet channels are not solids of revolution, but they are
# still lathe work: the profile just changes with the angle. One revolve that
# takes a profile *function* draws both, and the walls at each feature's ends
# fall out of the mesh for free.

seat, foot_h = 0.2, 1.6
bay_gap, lug_out, skirt_wall = 0.35, 1.2, 1.65
lugs, lug_arc, lock_arc = 3, 26.0, 30.0
lug_h, lug_inset = 1.6, 0.6

cap_face = lid_t + tag_t + 0.4
skirt_h = height - cap_face - foot_h
cup_h = foot_h + skirt_h - seat
cap_h = cap_face + skirt_h
cup_od = outer_d - 2 * (skirt_wall + bay_gap + lug_out)
lug_od = cup_od + 2 * lug_out
cap_bore = cup_od + 2 * bay_gap
slot_od = lug_od + 2 * bay_gap
cup_bore = cup_od - 2 * wall
lug_z = cup_h - lug_inset - lug_h
bay_arc = math.degrees(bay_gap / (lug_od / 2))
entry_arc = lug_arc + 2 * bay_arc
run_z0 = cap_face + seat + lug_inset - bay_gap / 2
run_z1 = run_z0 + lug_h + bay_gap


def within(t, a0, a1):
    return (t - a0) % 360.0 <= (a1 - a0)


def cup_profile(t):
    """A lug bulges the collar out between lug_z and lug_z + lug_h, with a 45
    degree ramp underneath. Off a lug the four points collapse onto the wall."""
    r = cup_od/2
    for i in range(lugs):
        a0 = i * 360/lugs + bay_arc
        if within(t, a0, a0 + lug_arc):
            r = lug_od/2
    return [(0, 0), (outer_d/2 - chamfer, 0), (outer_d/2, chamfer), (outer_d/2, foot_h),
            (cup_od/2, foot_h), (cup_od/2, lug_z),
            (r, lug_z + lug_out), (r, lug_z + lug_h), (cup_od/2, lug_z + lug_h),
            (cup_od/2, cup_h - 0.4), (cup_od/2 - 0.4, cup_h),
            (cup_bore/2, cup_h), (cup_bore/2, floor_t), (0, floor_t)]


def cap_profile(t):
    """Inside the skirt: the drop-in channel runs from the rim down to run_z0,
    the turn runs on from there between run_z0 and run_z1."""
    r_rim = r_slot = cap_bore/2
    for i in range(lugs):
        a0 = i * 360/lugs
        if within(t, a0 - entry_arc, a0):
            r_rim = r_slot = slot_od/2
        elif within(t, a0 - entry_arc - lock_arc, a0):
            r_slot = slot_od/2
    return [(0, 0), (outer_d/2 - chamfer, 0), (outer_d/2, chamfer), (outer_d/2, cap_h),
            (r_rim, cap_h), (r_rim, run_z1), (r_slot, run_z1), (r_slot, run_z0),
            (cap_bore/2, run_z0), (cap_bore/2, cap_face),
            (pocket_d/2, cap_face), (pocket_d/2, lid_t), (0, lid_t)]


def revolve_fn(profile_fn, albedo, segments=300, breaks=()):
    """Lathe a profile that varies with the angle. Normals are smoothed around
    the axis but kept flat along the profile, so a feature's end wall stays sharp."""
    th = list(np.linspace(0, 360, segments, endpoint=False))
    for b in breaks:                       # land exactly either side of each edge
        th += [b - 0.03, b + 0.03]
    th = np.array(sorted({round(x % 360, 4) for x in th}))
    S = len(th)
    P = np.array([profile_fn(t) for t in th])            # (S, n, 2)
    rad = np.radians(th)
    V = np.stack([P[:, :, 0] * np.cos(rad)[:, None],
                  P[:, :, 0] * np.sin(rad)[:, None],
                  P[:, :, 1]], axis=-1)                  # (S, n, 3)
    k = np.arange(S)
    kn = (k + 1) % S
    tris, norms = [], []
    for j in range(P.shape[1]):
        a, b = V[:, j, :], V[:, (j + 1) % P.shape[1], :]
        nf = np.cross(b[kn] - a[k], b[k] - a[k])         # outward, per quad
        nf /= np.maximum(np.linalg.norm(nf, axis=1, keepdims=True), 1e-12)
        nv = nf[(k - 1) % S] + nf[k]                     # smooth around the axis only
        nv /= np.maximum(np.linalg.norm(nv, axis=1, keepdims=True), 1e-12)
        tris.append(np.stack([a[k], b[k], b[kn]], axis=1))
        norms.append(np.stack([nv[k], nv[k], nv[kn]], axis=1))
        tris.append(np.stack([a[k], b[kn], a[kn]], axis=1))
        norms.append(np.stack([nv[k], nv[kn], nv[kn]], axis=1))
    Vt = np.concatenate(tris, axis=0)
    return Vt, np.concatenate(norms, axis=0), np.tile(albedo, (len(Vt), 1))


def shift(mesh, dx=0.0, dy=0.0, dz=0.0):
    V, N, A = mesh
    return V + np.array([dx, dy, dz]), N, A


cup_breaks = [i*360/lugs + bay_arc + d for i in range(lugs) for d in (0, lug_arc)]
cap_breaks = [i*360/lugs + d for i in range(lugs) for d in (0, -entry_arc, -entry_arc - lock_arc)]

cup = revolve_fn(cup_profile, GRAPHITE, breaks=cup_breaks)
cap = revolve_fn(cap_profile, GRAPHITE, breaks=cap_breaks)
# the detent pins, each a stubby cylinder standing in its channel
PIN = [(0, 0), (0.4/2, 0), (0.4/2, run_z1 - run_z0), (0, run_z1 - run_z0)]
pins = [shift(revolve(PIN, GRAPHITE, segments=24),
              dx=lug_od/2 * math.cos(math.radians(ang)),
              dy=lug_od/2 * math.sin(math.radians(ang)),
              dz=run_z0)
        for ang in [i*360/lugs - entry_arc - lock_arc + lug_arc for i in range(lugs)]]

render([shift(cup, dx=-22), shift(cap, dx=22)] + [shift(p, dx=22) for p in pins],
       eye=(0, -80, 96), target=(0, 0, 3.5), size=(1500, 940),
       frame=0.94).save("anchor-puck-twist.png")
print("twist done")

render([cup], eye=(30, -54, 46), target=(0, 0, 4.6), size=(1300, 1000),
       frame=0.86).save("anchor-puck-lugs.png")
print("lugs done")
