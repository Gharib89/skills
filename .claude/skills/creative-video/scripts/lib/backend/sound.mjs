// The backend's sound sources: Openverse's audio search and the Kenney packs'
// zips.
import fs from "node:fs";
import path from "node:path";
import { toolPaths } from "../tools.mjs";
import { fromCache } from "./common.mjs";

// Openverse's CC0 audio results for `query` (keyless; `medium` asks for the
// longer clips a bed needs), refused after 30 s: on 2026-10-28 every CC0
// search here hung while the API's stats answered at once.
export async function openverse(query, { medium }) {
  const url = `https://api.openverse.org/v1/audio/?q=${encodeURIComponent(query)}&license=cc0${medium ? "&length=medium" : ""}`;
  let r;
  try {
    r = await fetch(url, { signal: AbortSignal.timeout(30000) });
  } catch (e) {
    throw new Error(
      e.name === "TimeoutError" ? "timed out after 30 s" : e.message,
    );
  }
  if (!r.ok) throw new Error(`HTTP ${r.status}`);
  return (await r.json()).results ?? [];
}

// A Kenney pack's zip unpacked flat into `dir`: its audio files and its
// licence or readme, nothing else.
export async function unzipSounds(zip, dir) {
  const JSZip = fromCache(toolPaths().node)("jszip");
  const archive = await JSZip.loadAsync(fs.readFileSync(zip));
  fs.mkdirSync(dir, { recursive: true });
  for (const f of Object.values(archive.files)) {
    const name = path.posix.basename(f.name);
    if (!f.dir && /\.(ogg|wav|mp3)$|^(licen[cs]e|readme)\.txt$/i.test(name))
      fs.writeFileSync(path.join(dir, name), await f.async("nodebuffer"));
  }
}
