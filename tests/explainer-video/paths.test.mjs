// The per-user directories on each OS, the OS injected (ADR 0014, ADR 0017).
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { userDirs } from '../../skills/explainer-video/scripts/lib/paths.mjs';

test('Linux follows XDG, falling back to ~/.config, ~/.local/share and ~/.cache', () => {
  assert.deepEqual(userDirs({ platform: 'linux', env: {}, home: '/home/u' }), {
    config: '/home/u/.config/explainer-video',
    data: '/home/u/.local/share/explainer-video',
    cache: '/home/u/.cache/explainer-video',
  });
  assert.deepEqual(userDirs({ platform: 'linux', env: { XDG_CONFIG_HOME: '/x/c', XDG_DATA_HOME: '/x/d', XDG_CACHE_HOME: '/x/k' }, home: '/home/u' }), {
    config: '/x/c/explainer-video',
    data: '/x/d/explainer-video',
    cache: '/x/k/explainer-video',
  });
});

test('Linux ignores a relative XDG path, as the XDG spec says', () => {
  assert.equal(userDirs({ platform: 'linux', env: { XDG_CACHE_HOME: 'rel' }, home: '/home/u' }).cache, '/home/u/.cache/explainer-video');
});

test('macOS uses Application Support and Caches, and ignores XDG', () => {
  assert.deepEqual(userDirs({ platform: 'darwin', env: { XDG_CACHE_HOME: '/x/k' }, home: '/Users/u' }), {
    config: '/Users/u/Library/Application Support/explainer-video',
    data: '/Users/u/Library/Application Support/explainer-video',
    cache: '/Users/u/Library/Caches/explainer-video',
  });
});

test('Windows uses APPDATA for config and LOCALAPPDATA for data and cache, with backslashes', () => {
  assert.deepEqual(userDirs({ platform: 'win32', env: { APPDATA: 'C:\\Users\\u\\AppData\\Roaming', LOCALAPPDATA: 'C:\\Users\\u\\AppData\\Local' }, home: 'C:\\Users\\u' }), {
    config: 'C:\\Users\\u\\AppData\\Roaming\\explainer-video',
    data: 'C:\\Users\\u\\AppData\\Local\\explainer-video',
    cache: 'C:\\Users\\u\\AppData\\Local\\explainer-video',
  });
  assert.equal(userDirs({ platform: 'win32', env: {}, home: 'C:\\Users\\u' }).config, 'C:\\Users\\u\\AppData\\Roaming\\explainer-video');
});
