// The canned backend tests select with EXPLAINER_VIDEO_BACKEND: the real one's
// exports, answering from fixtures and logging each call as one JSON line to
// $EXPLAINER_VIDEO_FAKE_LOG, so a test asserts on what setup asked for.
//   EXPLAINER_VIDEO_FAKE_PRESENT  comma-separated commands `which` finds
// The family `ubuntu` answers with its real, non-OFL licence.
import fs from 'node:fs';
import path from 'node:path';

const log = (call) => fs.appendFileSync(process.env.EXPLAINER_VIDEO_FAKE_LOG, JSON.stringify(call) + '\n');

export async function npmCi(dir, env) {
  log({ call: 'npmCi', dir, onnxruntime: env.ONNXRUNTIME_NODE_INSTALL ?? null });
  fs.mkdirSync(path.join(dir, 'node_modules'), { recursive: true });
  fs.writeFileSync(path.join(dir, 'node_modules', '.package-lock.json'), '{}');
  return 0;
}

export async function ensureChrome(nodeDir, home) {
  log({ call: 'ensureChrome', nodeDir, home });
  fs.mkdirSync(path.join(home, '.cache', 'hyperframes', 'chrome'), { recursive: true });
  fs.writeFileSync(path.join(home, '.cache', 'hyperframes', 'chrome', 'chrome-headless-shell'), 'x'.repeat(1000));
  return 0;
}

export async function fontMeta(id) {
  log({ call: 'fontMeta', id });
  return { id, license: id === 'ubuntu' ? 'UFL-1.0' : 'OFL-1.1', weights: [400, 600], subsets: ['latin'], styles: ['normal'] };
}

export async function download(url, file) {
  log({ call: 'download', url });
  fs.writeFileSync(file, 'woff2');
}

export function which(cmd) {
  return (process.env.EXPLAINER_VIDEO_FAKE_PRESENT ?? '').split(',').includes(cmd) ? `/usr/bin/${cmd}` : null;
}
