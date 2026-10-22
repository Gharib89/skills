// Maintainer only: the headless shell real-render.mjs renders through, wrapped
// with Chrome flags HyperFrames has no option for (it reads the shell's path
// from PRODUCER_HEADLESS_SHELL_PATH).
import fs from "node:fs";
import path from "node:path";

// Under load the screenshot route's anti-aliased edge pixels (a diagram link's
// arrowhead) differed between renders of one composition: 4 of 10 renders of
// the diagram slice, none of 10 with these flags (#917). They hold raster to one
// thread, redraw whole tiles and copy through memory; HyperFrames' beginframe
// route adds the checker-imaging and threaded-animation switches, its
// screenshot route leaves them out.
export const RASTER_FLAGS = [
  "--num-raster-threads=1",
  "--disable-partial-raster",
  "--disable-zero-copy",
  "--disable-checker-imaging",
  "--disable-threaded-animation",
];

// The headless shell setup put under HyperFrames' cache in `home`.
export function headlessShell(home) {
  const root = path.join(
    home,
    ".cache/hyperframes/chrome/chrome-headless-shell",
  );
  const versions = fs.existsSync(root) ? fs.readdirSync(root) : [];
  // newest first, as HyperFrames reads its own cache
  versions.sort((x, y) => y.localeCompare(x, "en", { numeric: true }));
  for (const v of versions) {
    const bin = path.join(
      root,
      v,
      "chrome-headless-shell-linux64",
      "chrome-headless-shell",
    );
    if (fs.existsSync(bin)) return bin;
  }
  throw new Error(`headless shell not found under ${root}`);
}

// A script in `dir` that runs `real` with its own arguments, then `flags`; a
// later switch wins, so the flags stand over HyperFrames' own. Returns its path.
export function shellWith(dir, flags, real) {
  const file = path.join(dir, "headless-shell.sh");
  const quote = (s) => `'${s.replaceAll("'", "'\\''")}'`;
  fs.writeFileSync(
    file,
    `#!/bin/sh\nexec ${quote(real)} "$@" ${flags.map(quote).join(" ")}\n`,
    { mode: 0o755 },
  );
  return file;
}
