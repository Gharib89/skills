// The count-up of a `chart` or `stat` number: its text at a progress `p` from 0
// to 1, as a pure function of `p`, so HyperFrames seeking to any time in any
// order draws the same text. It ends on the number exactly as written, in the
// digits (ASCII, Arabic-Indic or Persian) and the separators it is written in.
// `plain` and `countText` are also written into each scene's script as source
// (compose.mjs), so they stay self-contained: no imports, no outer names but
// each other.

// Seconds a number takes to count up, from its cue.
export const COUNT_SECONDS = 0.9;

// A written number as ASCII digits with `,` and `.` separators, so numbers in
// any of the three scripts compare and parse alike.
export function plain(written) {
  return written
    .replace(/[٠-٩]/g, (c) => c.charCodeAt(0) - 0x660)
    .replace(/[۰-۹]/g, (c) => c.charCodeAt(0) - 0x6f0)
    .replaceAll("٬", ",")
    .replaceAll("٫", ".");
}

export function countText(written, p) {
  const ascii = plain(written);
  const dot = ascii.indexOf(".");
  const places = dot < 0 ? 0 : ascii.length - dot - 1;
  const shown = (parseFloat(ascii.replaceAll(",", "")) * p).toLocaleString(
    "en-US",
    {
      minimumFractionDigits: places,
      maximumFractionDigits: places,
      useGrouping: ascii.includes(","),
    },
  );
  const zero = /[٠-٩]/.test(written)
    ? 0x660
    : /[۰-۹]/.test(written)
      ? 0x6f0
      : 0;
  return shown
    .replace(/\d/g, (d) => (zero ? String.fromCharCode(zero + +d) : d))
    .replaceAll(",", written.includes("٬") ? "٬" : ",")
    .replaceAll(".", written.includes("٫") ? "٫" : ".");
}
