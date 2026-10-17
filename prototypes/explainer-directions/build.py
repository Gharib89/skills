"""Inline fonts, scene data, audio and dir-*.js into storyboard.html (PROTOTYPE)."""
import base64, glob, json, os, re, sys

HERE = os.path.dirname(os.path.abspath(__file__))
SCRIPT = '/home/ribo/wip/projects/explainer-videos/explainers/dora-core/script.md'
b64 = lambda p: base64.b64encode(open(os.path.join(HERE, p), 'rb').read()).decode()

fonts = ''.join(
    f'@font-face {{ font-family: "{fam}"; font-weight: {w}; font-display: block; src: url(data:font/woff2;base64,{b64(f)}) format("woff2"); }}\n'
    for fam, w, f in [('Google Sans Flex', 400, 'google-sans-flex-latin-400-normal.woff2'),
                      ('Google Sans Flex', 600, 'google-sans-flex-latin-600-normal.woff2'),
                      ('JetBrains Mono', 400, 'jetbrains-mono-latin-400-normal.woff2')])

md = open(SCRIPT).read()
narr, props = {}, {}
for sid in ('hook', 'trails', 'integrate'):
    block = re.search(rf'^## Scene {sid} .*?(?=^## Scene )', md, re.S | re.M).group(0)
    lines = re.findall(r'^\d+\. (.*)$', block.split('### Visual')[0], re.M)
    narr[sid] = [re.sub(r'\{([^|}]*)\|[^}]*\}', r'\1', re.sub(r'\s*\[[^\]]+\]\s*$', '', l)) for l in lines]
    props[sid] = json.loads(re.search(r'```json\n(.*?)```', block, re.S).group(1))['props']

scenes = json.load(open(os.path.join(HERE, 'scenes.json')))
t = 0
for s in scenes:  # film time: the three scenes back to back
    s['start'] = round(t, 3); t += s['duration']
data = {'total': round(t, 3), 'scenes': scenes, 'props': props, 'narration': narr,
        'audio': 'data:audio/mpeg;base64,' + b64('film.mp3')}

# `python3 build.py B` builds preview-B.html with only dir-b.js (parallel builders); no argument builds everything
only = sys.argv[1].upper() if len(sys.argv) > 1 else None
files = [os.path.join(HERE, f'dir-{only.lower()}.js')] if only else sorted(glob.glob(os.path.join(HERE, 'dir-*.js')))
dirs = ''.join(f'<script>\n{open(p).read()}\n</script>\n' for p in files)
html = open(os.path.join(HERE, 'shell.html')).read()
html = html.replace('/*FONTS*/', fonts).replace('/*DATA*/', 'window.DATA = ' + json.dumps(data) + ';').replace('/*DIRS*/', dirs)
def write(name, text):
    tmp = os.path.join(HERE, name + '.tmp'); open(tmp, 'w').write(text); os.replace(tmp, os.path.join(HERE, name))
if not only: write('storyboard.html', html)
print(f'{len(html) / 1e6:.2f} MB, {len(files)} directions, total {t:.2f}s')
# local preview with the skeleton the publish adds
write(f'preview-{only}.html' if only else 'preview.html', '<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover"><style>body{margin:0}[hidden]{display:none!important}</style></head><body>' + html + '</body></html>')
