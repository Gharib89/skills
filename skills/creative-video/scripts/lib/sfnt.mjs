// A font file as the joins gate shapes it: HarfBuzz reads an sfnt (TTF or
// OTF) and draws a WOFF2 as nothing but .notdef (harfbuzzjs 1.6.4, measured),
// while Fontsource serves WOFF2. So a WOFF or WOFF2 is unpacked here to its
// tables with Node's own zlib and brotli. A WOFF2's transformed glyf, loca or
// hmtx is left out rather than rebuilt: shaping reads cmap, GDEF, GSUB and
// GPOS, and the gate compares one face's shapes with each other, so outlines
// and advances it lacks are lacking on both sides.
import zlib from "node:zlib";

// An sfnt of `tables`, each `[tag, data]`, its directory sorted by tag. No
// checksums: HarfBuzz reads none.
function pack(flavor, tables) {
  tables.sort(([a], [b]) => (a < b ? -1 : a > b ? 1 : 0));
  const n = tables.length;
  const head = Buffer.alloc(12 + 16 * n);
  const log = Math.floor(Math.log2(n || 1));
  head.writeUInt32BE(flavor, 0);
  head.writeUInt16BE(n, 4);
  head.writeUInt16BE(16 << log, 6);
  head.writeUInt16BE(log, 8);
  head.writeUInt16BE(16 * n - (16 << log), 10);
  let at = head.length;
  const body = tables.map(([tag, data], i) => {
    head.write(tag, 12 + 16 * i, "latin1");
    head.writeUInt32BE(at, 12 + 16 * i + 8);
    head.writeUInt32BE(data.length, 12 + 16 * i + 12);
    const padded = Buffer.concat([
      data,
      Buffer.alloc((4 - (data.length % 4)) % 4),
    ]);
    at += padded.length;
    return padded;
  });
  return Buffer.concat([head, ...body]);
}

function woff(buf) {
  const tables = [];
  for (let i = 0; i < buf.readUInt16BE(12); i++) {
    const at = 44 + 20 * i;
    const offset = buf.readUInt32BE(at + 4);
    const stored = buf.subarray(offset, offset + buf.readUInt32BE(at + 8));
    const length = buf.readUInt32BE(at + 12);
    tables.push([
      buf.toString("latin1", at, at + 4),
      stored.length < length ? zlib.inflateSync(stored) : stored,
    ]);
  }
  return pack(buf.readUInt32BE(4), tables);
}

// WOFF2's known tags, by the index its directory's flags give.
const KNOWN = (
  "cmap head hhea hmtx maxp name OS/2 post cvt  fpgm glyf loca prep CFF  VORG " +
  "EBDT EBLC gasp hdmx kern LTSH PCLT VDMX vhea vmtx BASE GDEF GPOS GSUB EBSC " +
  "JSTF MATH CBDT CBLC COLR CPAL SVG  sbix acnt avar bdat bloc bsln cvar fdsc " +
  "feat fmtx fvar gvar hsty just lcar mort morx opbd prop trak Zapf Silf Glat " +
  "Gloc Feat Sill"
)
  .match(/.{4}\s?/g)
  .map((t) => t.slice(0, 4));

function woff2(buf) {
  let at = 48;
  const base128 = () => {
    let n = 0;
    for (let i = 0; i < 5; i++) {
      const b = buf[at++];
      n = n * 128 + (b & 0x7f);
      if (!(b & 0x80)) return n;
    }
    throw new Error("WOFF2 length runs past 5 bytes");
  };
  const dir = [];
  for (let i = 0; i < buf.readUInt16BE(12); i++) {
    const flags = buf[at++];
    const tag =
      (flags & 63) === 63
        ? buf.toString("latin1", at, (at += 4))
        : KNOWN[flags & 63];
    const version = flags >> 6;
    const length = base128();
    // glyf and loca are transformed at version 0, every other table at 1-3.
    const transformed = ["glyf", "loca"].includes(tag)
      ? version !== 3
      : version !== 0;
    dir.push({ tag, transformed, length: transformed ? base128() : length });
  }
  const data = zlib.brotliDecompressSync(
    buf.subarray(at, at + buf.readUInt32BE(20)),
  );
  let from = 0;
  const tables = [];
  for (const t of dir) {
    if (!t.transformed)
      tables.push([t.tag, data.subarray(from, from + t.length)]);
    from += t.length;
  }
  return pack(buf.readUInt32BE(4), tables);
}

// The sfnt of a font file's bytes, or null when they are no font this reads.
// A WOFF or WOFF2 whose length is not its header's, or that does not unpack,
// is refused, naming the face `name`, since the face a scene draws in has to
// be fixed, not skipped.
export function sfnt(buf, name) {
  if (buf.length < 12) return null;
  const sig = buf.toString("latin1", 0, 4);
  if (sig === "OTTO" || sig === "true" || buf.readUInt32BE(0) === 0x00010000)
    return buf;
  if (sig !== "wOFF" && sig !== "wOF2") return null;
  try {
    // Both headers give the file's whole length at byte 8.
    if (buf.readUInt32BE(8) !== buf.length)
      throw new Error(
        `${buf.length} bytes, its header says ${buf.readUInt32BE(8)}`,
      );
    return sig === "wOFF" ? woff(buf) : woff2(buf);
  } catch (e) {
    throw new Error(
      `${name}: not a whole ${sig === "wOFF" ? "WOFF" : "WOFF2"} (${e.message})`,
    );
  }
}
