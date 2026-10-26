// probe.mjs <chrome>: does a WebGPU adapter and device exist under each flag set?
import puppeteer from "puppeteer-core";
import http from "node:http";

// WebGPU needs a secure context: serve a blank page from 127.0.0.1.
const server = http
  .createServer((_, res) => res.end("<!doctype html><title>p</title>"))
  .listen(0, "127.0.0.1");
await new Promise((r) => server.once("listening", r));
const url = `http://127.0.0.1:${server.address().port}/`;

const chrome = process.argv[2];
const base = ["--no-sandbox", "--enable-webgl", "--ignore-gpu-blocklist"];
const sets = {
  "HF hardware (gl-egl) + unsafe-webgpu": [
    ...base,
    "--use-gl=angle",
    "--use-angle=gl-egl",
    "--enable-gpu-rasterization",
    "--disable-software-rasterizer",
    "--enable-unsafe-webgpu",
  ],
  "HF hardware + unsafe-webgpu + Vulkan feature": [
    ...base,
    "--use-gl=angle",
    "--use-angle=gl-egl",
    "--enable-gpu-rasterization",
    "--disable-software-rasterizer",
    "--enable-unsafe-webgpu",
    "--enable-features=Vulkan",
  ],
  "ANGLE vulkan + unsafe-webgpu + Vulkan feature": [
    ...base,
    "--use-gl=angle",
    "--use-angle=vulkan",
    "--enable-unsafe-webgpu",
    "--enable-features=Vulkan",
  ],
  "HF software WebGPU (swiftshader vulkan)": [
    ...base,
    "--use-gl=angle",
    "--use-angle=swiftshader",
    "--enable-unsafe-swiftshader",
    "--enable-unsafe-webgpu",
    "--enable-features=Vulkan",
    "--use-vulkan=swiftshader",
  ],
};
for (const [name, args] of Object.entries(sets)) {
  const b = await puppeteer.launch({
    executablePath: chrome,
    headless: "shell",
    args,
  });
  const p = await b.newPage();
  await p.goto(url);
  const r = await p.evaluate(async () => {
    if (!navigator.gpu) return "no navigator.gpu";
    const a = await navigator.gpu.requestAdapter();
    if (!a) return "no adapter";
    let dev = "device ok";
    try {
      await a.requestDevice();
    } catch (e) {
      dev = "device FAIL " + e.message;
    }
    const i = a.info || {};
    return `${i.vendor} | ${i.architecture} | ${i.device} | ${i.description} | ${dev}`;
  });
  console.log(`${name}: ${r}`);
  await b.close();
}
server.close();
