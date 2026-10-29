// The joins gate's font reader: a TTF or OTF as it is, a WOFF or WOFF2 unpacked
// to the tables HarfBuzz shapes from, anything else refused.
import { test } from "node:test";
import assert from "node:assert/strict";
import zlib from "node:zlib";
import { sfnt } from "../../skills/creative-video/scripts/lib/sfnt.mjs";

const TABLES = {
  cmap: Buffer.from("cmap table bytes"),
  GSUB: Buffer.from("substitutions"),
  glyf: Buffer.from("glyph outlines, transformed in a woff2"),
  loca: Buffer.from(""),
};

// The tables an sfnt's directory lists, by tag.
function tables(buf) {
  const out = {};
  for (let i = 0; i < buf.readUInt16BE(4); i++) {
    const at = 12 + 16 * i;
    const [offset, length] = [
      buf.readUInt32BE(at + 8),
      buf.readUInt32BE(at + 12),
    ];
    out[buf.toString("latin1", at, at + 4)] = buf.subarray(
      offset,
      offset + length,
    );
  }
  return out;
}

function woff(entries) {
  const dir = Buffer.alloc(20 * entries.length);
  let at = 44 + dir.length;
  const parts = entries.map(([tag, data], i) => {
    const packed = zlib.deflateSync(data);
    const body = packed.length < data.length ? packed : data;
    dir.write(tag, 20 * i, "latin1");
    dir.writeUInt32BE(at, 20 * i + 4);
    dir.writeUInt32BE(body.length, 20 * i + 8);
    dir.writeUInt32BE(data.length, 20 * i + 12);
    const padded = Buffer.concat([
      body,
      Buffer.alloc((4 - (body.length % 4)) % 4),
    ]);
    at += padded.length;
    return padded;
  });
  const head = Buffer.alloc(44);
  head.write("wOFF", 0, "latin1");
  head.writeUInt32BE(0x00010000, 4);
  head.writeUInt16BE(entries.length, 12);
  return Buffer.concat([head, dir, ...parts]);
}

const base128 = (n) => {
  const out = [n & 0x7f];
  for (n >>>= 7; n; n >>>= 7) out.unshift(0x80 | (n & 0x7f));
  return Buffer.from(out);
};
// `entries` as [tag, data, transformed]; cmap, GSUB, glyf and loca are known
// tags (indexes 0, 28, 10, 11), anything else is written out.
function woff2(entries) {
  const known = { cmap: 0, glyf: 10, loca: 11, GSUB: 28 };
  const dir = Buffer.concat(
    entries.map(([tag, data, transformed]) => {
      const glyfLike = tag === "glyf" || tag === "loca";
      const version = glyfLike ? (transformed ? 0 : 3) : transformed ? 1 : 0;
      const flags = Buffer.from([(version << 6) | (known[tag] ?? 63)]);
      return Buffer.concat([
        flags,
        known[tag] === undefined ? Buffer.from(tag, "latin1") : Buffer.alloc(0),
        base128(data.length),
        transformed ? base128(data.length) : Buffer.alloc(0),
      ]);
    }),
  );
  const packed = zlib.brotliCompressSync(
    Buffer.concat(entries.map((e) => e[1])),
  );
  const head = Buffer.alloc(48);
  head.write("wOF2", 0, "latin1");
  head.writeUInt32BE(0x00010000, 4);
  head.writeUInt16BE(entries.length, 12);
  head.writeUInt32BE(packed.length, 20);
  return Buffer.concat([head, dir, packed]);
}

test("a TTF or OTF is read as it is", () => {
  const ttf = Buffer.concat([Buffer.from([0, 1, 0, 0]), Buffer.alloc(8)]);
  assert.equal(sfnt(ttf), ttf);
  const otf = Buffer.concat([Buffer.from("OTTO"), Buffer.alloc(8)]);
  assert.equal(sfnt(otf), otf);
});

test("a WOFF is unpacked to its tables, compressed or stored", () => {
  const got = tables(sfnt(woff(Object.entries(TABLES))));
  for (const [tag, data] of Object.entries(TABLES))
    assert.deepEqual(got[tag], data, tag);
});

test("a WOFF2 is unpacked to its tables, a transformed glyf and loca left out", () => {
  const plain = Object.entries(TABLES).map(([t, d]) => [t, d, false]);
  const got = tables(
    sfnt(woff2([...plain, ["Zzzz", Buffer.from("own tag"), false]])),
  );
  for (const [tag, data] of Object.entries(TABLES))
    assert.deepEqual(got[tag], data, tag);
  assert.equal(got.Zzzz.toString(), "own tag");
  const shaped = tables(
    sfnt(
      woff2([
        ["cmap", TABLES.cmap, false],
        ["glyf", TABLES.glyf, true],
        ["loca", Buffer.alloc(0), true],
        ["GSUB", TABLES.GSUB, false],
      ]),
    ),
  );
  assert.deepEqual(Object.keys(shaped).sort(), ["GSUB", "cmap"]);
  assert.deepEqual(shaped.GSUB, TABLES.GSUB);
});

test("anything else is no font", () => {
  assert.equal(sfnt(Buffer.from("<html>not a font</html>")), null);
  assert.equal(sfnt(Buffer.alloc(2)), null);
});
