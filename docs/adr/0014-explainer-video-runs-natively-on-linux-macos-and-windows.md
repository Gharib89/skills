# explainer-video runs natively on Linux, macOS and Windows

`explainer-video` runs natively on Linux, macOS and Windows, so every script it ships is Node, never bash, unlike this repo's other skills. Node is already required by HyperFrames (ADR 0012), so it adds no runtime; Python appears only inside the opt-in model adapters (TTS, voice conversion, ACE-Step), run through `uv`, and in `maintainer/` scripts that build what the skill downloads and never run on a user's machine. The owner asked that the skill avoid any OS-specific form (2026-10-15, while settling the style profile format), and a single bash step breaks a Windows run as surely as a hard-coded path.

## Considered Options

- Linux and macOS native, Windows through WSL: lets scripts stay bash, but a Windows owner then needs WSL for a skill whose renderer and voices run natively.
- Portable storage paths only, the rest decided per stage: leaves the language of every later script open, which is the expensive part to change.

## Consequences

- Paths are built with Node's `path` and `os.homedir()`, never a literal separator or `~`.
- Per-user files follow each OS's convention under `explainer-video/`: config (style profiles, settings) in `$XDG_CONFIG_HOME` or `~/.config` on Linux, `~/Library/Application Support` on macOS, `%APPDATA%` on Windows; data (the font store) in `$XDG_DATA_HOME` or `~/.local/share` on Linux, the same Application Support on macOS, `%LOCALAPPDATA%` on Windows.
