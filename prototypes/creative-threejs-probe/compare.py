"""compare.py: per-pair frame differences from .md5 files, and blank-frame checks."""
import sys, pathlib, subprocess

out = pathlib.Path(sys.argv[1])

def md5s(name):
    p = out / "seq" / f"{name}.md5"
    return {l.split()[1]: l.split()[0] for l in p.read_text().splitlines()}

for comp in ["Opaque", "DreiClock"]:
    for gl in ["angle", "vulkan", "swangle"]:
        a, b = md5s(f"{comp}-{gl}-1"), md5s(f"{comp}-{gl}-2")
        diff = sum(1 for k in a if a[k] != b.get(k))
        print(f"{comp:10} {gl:8} differing frames run1 vs run2: {diff}/{len(a)}")

# cross-backend: Opaque angle vs vulkan vs swangle
for x, y in [("angle", "vulkan"), ("angle", "swangle"), ("vulkan", "swangle")]:
    a, b = md5s(f"Opaque-{x}-1"), md5s(f"Opaque-{y}-1")
    print(f"Opaque {x} vs {y}: {sum(1 for k in a if a[k] != b.get(k))}/{len(a)} differ")

# blank or text-less frames: count bright (text) pixels per ArabicText frame, and 3D/background pixels per TransparentHeavy frame
def stats(png):
    r = subprocess.run(["ffmpeg", "-v", "error", "-i", str(png), "-f", "rawvideo", "-pix_fmt", "rgb24", "-"], capture_output=True)
    px = r.stdout
    n = len(px) // 3
    bright = sum(1 for i in range(0, len(px), 3 * 7) if px[i] > 200 and px[i + 1] > 200 and px[i + 2] > 200)
    bg = sum(1 for i in range(0, len(px), 3 * 7) if abs(px[i] - 0x20) < 6 and abs(px[i + 1] - 0x28) < 6 and abs(px[i + 2] - 0x40) < 6)
    return bright, bg, n // 7

for gl in ["angle", "vulkan", "swangle"]:
    d = out / "seq" / f"ArabicText-{gl}-1"
    s = [stats(p)[0] for p in sorted(d.glob("*.png"))]
    print(f"ArabicText {gl}: frames with no white text pixels: {sum(1 for v in s if v == 0)}/{len(s)}; min {min(s)} max {max(s)}")
    d = out / "seq" / f"TransparentHeavy-{gl}-1"
    st = [stats(p) for p in sorted(d.glob("*.png"))]
    nobg = sum(1 for _, bg, n in st if bg < n * 0.5)
    print(f"TransparentHeavy {gl}: frames with background under half the frame: {nobg}/{len(st)}")
