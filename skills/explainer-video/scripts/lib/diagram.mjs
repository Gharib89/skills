// The `diagram` component's props at compile, and the columns the composer
// lays its nodes out in: the scene file holds no coordinates.
import { CUE, fail, known, list, named, place, text } from "./props.mjs";

// The grid a frame holds: past it a node's label no longer fits its box.
export const DIAGRAM = { columns: 5, rows: 3 };

// The columns a diagram's nodes stand in, along the reading direction, each
// listing its nodes' indexes in the order written. A node stands one column
// past every node linked to it from earlier in the list, so a link back to an
// earlier node (a reply) never moves one.
export function diagramColumns({ nodes, links }) {
  const index = new Map(nodes.map((n, i) => [n.id, i]));
  const rank = nodes.map(() => 0);
  for (const [i, n] of nodes.entries())
    for (const l of links)
      if (l.to === n.id && index.get(l.from) < i)
        rank[i] = Math.max(rank[i], rank[index.get(l.from)] + 1);
  const columns = Array.from({ length: Math.max(...rank) + 1 }, () => []);
  for (const [i, r] of rank.entries()) columns[r].push(i);
  return columns;
}

// Throws the first reason the props `p` are not a diagram for the scene's
// sentences in spoken form, `said`.
export function checkDiagram(p, said) {
  list("diagram", p.nodes, "nodes", said, [2, Infinity]);
  const ids = p.nodes.map((n) => n.id);
  for (const n of p.nodes) {
    named("diagram", n.id, "an id per node");
    if (ids.indexOf(n.id) !== ids.lastIndexOf(n.id))
      fail(`diagram node id "${n.id}" is used twice`);
    named("diagram", n.label, "a label per node");
    if (n.note !== undefined) text("diagram", n.note, "a note that is text");
    known("a diagram node", n, [...CUE, "id", "label", "note"]);
  }
  list("diagram", p.links, "links", said);
  const seen = new Set();
  for (const l of p.links) {
    for (const end of ["from", "to"]) {
      const n = p.nodes[ids.indexOf(l[end])];
      if (!n)
        fail(
          `diagram link ${end} ${JSON.stringify(l[end])} names no node (${ids.join(", ")})`,
        );
      if (place(l, said) < place(n, said))
        fail(
          `diagram link ${l.from} to ${l.to} lands before node "${n.id}" appears (at ${n.at}${n.on ? ` on "${n.on}"` : ""})`,
        );
    }
    if (l.from === l.to) fail(`diagram link ${l.from} to itself`);
    const key = JSON.stringify([l.from, l.to]);
    if (seen.has(key)) fail(`diagram link ${l.from} to ${l.to} is twice`);
    seen.add(key);
    if (
      l.packets !== undefined &&
      !(Number.isInteger(l.packets) && l.packets >= 1 && l.packets <= 3)
    )
      fail(`diagram link ${l.from} to ${l.to} packets is not 1 to 3`);
    known("a diagram link", l, [...CUE, "from", "to", "packets"]);
  }
  const columns = diagramColumns(p);
  const rows = Math.max(...columns.map((c) => c.length));
  if (columns.length > DIAGRAM.columns || rows > DIAGRAM.rows)
    fail(
      `diagram lays out ${columns.length} columns of up to ${rows} nodes; a frame holds ${DIAGRAM.columns} of up to ${DIAGRAM.rows}`,
    );
}
