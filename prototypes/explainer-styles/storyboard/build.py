# PROTOTYPE, throwaway (#664): inline the shared timing and the narration MP3 and the rendered blend MP4 into the storyboard page.
import base64, json
from pathlib import Path
H = Path(__file__).parent
src = (H / "page.src.html").read_text()
timing = json.dumps(json.loads((H.parent / "shared/timing.json").read_text()), ensure_ascii=False)
audio = "data:audio/mpeg;base64," + base64.b64encode((H / "narration.mp3").read_bytes()).decode()
video = "data:video/mp4;base64," + base64.b64encode((H.parent / "out/blend.mp4").read_bytes()).decode()
(H / "index.html").write_text(src.replace("__TIMING__", timing).replace("__AUDIO__", audio).replace("__VIDEO__", video))
(H / "preview.html").write_text('<!doctype html><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">' + (H / "index.html").read_text())
