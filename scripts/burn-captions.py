#!/usr/bin/env python3
"""Burns an SRT into a video as pixels, without libass.

    ./scripts/burn-captions.py IN.MOV captions.srt OUT.mp4

Homebrew's ffmpeg 8.1.2 on this machine is built **without libass**, so neither the
`subtitles` nor the `ass` filter exists and the usual one-liner fails with a filter
parse error. Rather than rebuild ffmpeg from source, each cue is drawn to a
transparent PNG with Pillow and composited with ffmpeg's own `overlay`, gated by
`enable='between(t,start,end)'` — core filters, present in every build.

Why burn in at all rather than ship a sidecar .srt: App Review's player may start
muted and may ignore a caption track, and the narration is the part that explains
what the tag is. See ~/Projects/archive/furlough/demo-video/DEMO-VIDEO.md.
"""

import re
import subprocess
import sys
import tempfile
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

FONT = "/System/Library/Fonts/HelveticaNeue.ttc"
SIZE = 44
# The caption band sits under the phone, which occupies the middle of a portrait frame.
BAND_H = 300
MARGIN_BOTTOM = 70
SIDE = 70
LINE_GAP = 10


def parse_srt(path: Path):
    """[(start_seconds, end_seconds, text)] — blank cues dropped."""
    def secs(t):
        h, m, rest = t.split(":")
        s, ms = rest.split(",")
        return int(h) * 3600 + int(m) * 60 + int(s) + int(ms) / 1000

    cues = []
    for block in re.split(r"\n\s*\n", path.read_text(encoding="utf-8").strip()):
        lines = [l for l in block.splitlines() if l.strip()]
        if len(lines) < 2:
            continue
        stamp = next((l for l in lines if "-->" in l), None)
        if not stamp:
            continue
        a, b = [x.strip() for x in stamp.split("-->")]
        text = " ".join(lines[lines.index(stamp) + 1:]).strip()
        if text:
            cues.append((secs(a), secs(b), text))
    return cues


def wrap(draw, text, font, width):
    words, lines, line = text.split(), [], ""
    for w in words:
        trial = f"{line} {w}".strip()
        if draw.textlength(trial, font=font) <= width or not line:
            line = trial
        else:
            lines.append(line)
            line = w
    if line:
        lines.append(line)
    return lines


def render(cue_text, font, w, out_path):
    img = Image.new("RGBA", (w, BAND_H), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    lines = wrap(d, cue_text, font, w - 2 * SIDE)
    asc, desc = font.getmetrics()
    lh = asc + desc + LINE_GAP
    y = BAND_H - (len(lines) * lh)
    for line in lines:
        x = (w - d.textlength(line, font=font)) / 2
        # Black stroke plus a soft shadow: legible over both the dark table and the
        # bright screen the phone throws when a sheet is up.
        d.text((x + 2, y + 3), line, font=font, fill=(0, 0, 0, 150))
        d.text((x, y), line, font=font, fill=(255, 255, 255, 255),
               stroke_width=4, stroke_fill=(0, 0, 0, 235))
        y += lh
    img.save(out_path)


def main() -> int:
    if len(sys.argv) != 4:
        print(__doc__.strip().splitlines()[2].strip(), file=sys.stderr)
        return 1
    src, srt, dst = Path(sys.argv[1]), Path(sys.argv[2]), Path(sys.argv[3])
    for f in (src, srt):
        if not f.exists():
            print(f"missing: {f}", file=sys.stderr)
            return 1

    probe = subprocess.run(
        ["ffprobe", "-v", "error", "-select_streams", "v:0",
         "-show_entries", "stream=width,height", "-of", "csv=p=0:s=x", str(src)],
        capture_output=True, text=True).stdout.strip()
    # ffprobe's csv writer appends the separator after the last field ("1920x1080x"),
    # so drop the empty tail rather than feeding it to int().
    w, h = (int(x) for x in probe.split("x") if x)
    # ffprobe reports the stored frame; a phone clip carries its rotation in metadata and
    # ffmpeg auto-rotates on decode, so swap to what the filter chain will actually see.
    rot = subprocess.run(
        ["ffprobe", "-v", "error", "-select_streams", "v:0",
         "-show_entries", "stream_side_data=rotation", "-of", "default=nw=1:nk=1", str(src)],
        capture_output=True, text=True).stdout.strip()
    if rot and abs(int(float(rot.splitlines()[0]))) == 90:
        w, h = h, w

    cues = parse_srt(srt)
    if not cues:
        print("no cues in the srt", file=sys.stderr)
        return 1
    font = ImageFont.truetype(FONT, SIZE)
    y_at = h - BAND_H - MARGIN_BOTTOM
    print(f"{src.name}: {w}x{h}, {len(cues)} cues, band at y={y_at}")

    with tempfile.TemporaryDirectory() as tmp:
        tmp = Path(tmp)
        inputs, chain, last = ["-i", str(src)], [], "[0:v]"
        for i, (a, b, text) in enumerate(cues):
            png = tmp / f"{i:04d}.png"
            render(text, font, w, png)
            inputs += ["-i", str(png)]
            tag = f"[v{i}]"
            chain.append(
                f"{last}[{i + 1}:v]overlay=0:{y_at}:enable='between(t\\,{a:.3f}\\,{b:.3f})'{tag}")
            last = tag
        script = tmp / "filter.txt"
        script.write_text(";".join(chain), encoding="utf-8")

        cmd = ["ffmpeg", "-y", *inputs, "-filter_complex_script", str(script),
               "-map", last, "-map", "0:a:0",
               "-c:v", "libx264", "-crf", "20", "-preset", "medium",
               "-pix_fmt", "yuv420p", "-c:a", "aac", "-b:a", "128k",
               "-movflags", "+faststart", str(dst), "-loglevel", "error", "-stats"]
        r = subprocess.run(cmd)
        if r.returncode:
            return r.returncode
    print(f"wrote {dst}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
