// A real PNG built byte by byte, for the logo check's transparency read.
import zlib from "node:zlib";

// An 8-bit PNG `w` pixels wide of its colour type, one row per scanline given
// (a filter byte, then the row's bytes), with a tRNS chunk when one is given.
export const png = (colourType, rows, { w = 1, trns } = {}) => {
  const chunk = (type, data) => {
    const len = Buffer.alloc(4);
    len.writeUInt32BE(data.length);
    return Buffer.concat([len, Buffer.from(type), data, Buffer.alloc(4)]);
  };
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(w, 0);
  ihdr.writeUInt32BE(rows.length, 4);
  ihdr[8] = 8;
  ihdr[9] = colourType;
  return Buffer.concat([
    Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
    chunk("IHDR", ihdr),
    ...(trns ? [chunk("tRNS", Buffer.from(trns))] : []),
    chunk("IDAT", zlib.deflateSync(Buffer.from(rows.flat()))),
    chunk("IEND", Buffer.alloc(0)),
  ]);
};
