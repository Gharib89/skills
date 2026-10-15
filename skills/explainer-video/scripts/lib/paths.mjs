// The per-user directories explainer-video writes, each OS by its own convention
// (ADR 0014; the cache is ADR 0017's): config holds style profiles and settings,
// data the font store, cache the tool installs. The OS is a parameter so one test
// covers all three; `path.win32` or `path.posix` follows it, never the host's.
import fs from "node:fs";
import os from "node:os";
import path from "node:path";

const NAME = "explainer-video";

export function userDirs({
  platform = process.platform,
  env = process.env,
  home = os.homedir(),
} = {}) {
  if (platform === "win32") {
    const p = path.win32;
    const roaming = env.APPDATA || p.join(home, "AppData", "Roaming");
    const local = env.LOCALAPPDATA || p.join(home, "AppData", "Local");
    return {
      config: p.join(roaming, NAME),
      data: p.join(local, NAME),
      cache: p.join(local, NAME),
    };
  }
  const p = path.posix;
  if (platform === "darwin") {
    const support = p.join(home, "Library", "Application Support", NAME);
    return {
      config: support,
      data: support,
      cache: p.join(home, "Library", "Caches", NAME),
    };
  }
  // The XDG spec has a relative value ignored.
  const xdg = (name, fallback) =>
    p.isAbsolute(env[name] ?? "") ? env[name] : p.join(home, fallback);
  return {
    config: p.join(xdg("XDG_CONFIG_HOME", ".config"), NAME),
    data: p.join(xdg("XDG_DATA_HOME", p.join(".local", "share")), NAME),
    cache: p.join(xdg("XDG_CACHE_HOME", ".cache"), NAME),
  };
}

// The user's videos folder, where delivery copies a finished video. On Linux it
// is XDG's: the variable, else the line xdg-user-dirs writes, else ~/Videos.
export function videosDir({
  platform = process.platform,
  env = process.env,
  home = os.homedir(),
} = {}) {
  if (platform === "win32") return path.win32.join(home, "Videos");
  const p = path.posix;
  if (platform === "darwin") return p.join(home, "Movies");
  if (p.isAbsolute(env.XDG_VIDEOS_DIR ?? "")) return env.XDG_VIDEOS_DIR;
  const config = p.isAbsolute(env.XDG_CONFIG_HOME ?? "")
    ? env.XDG_CONFIG_HOME
    : p.join(home, ".config");
  const file = p.join(config, "user-dirs.dirs");
  const line = fs.existsSync(file)
    ? fs.readFileSync(file, "utf8").match(/^XDG_VIDEOS_DIR="([^"]*)"/m)
    : null;
  const named = line?.[1].replace(/^\$HOME(?=\/|$)/, home);
  return named && p.isAbsolute(named) ? named : p.join(home, "Videos");
}
