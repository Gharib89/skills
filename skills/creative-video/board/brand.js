/* The brand strip of creative-video's storyboard page, a classic script loaded before page.js, which calls
   brandPanel and which declares the esc and mediaUrl this one uses. Split from page.js to keep each file
   within the token limit. */

// The brand the video wears, null when it has none: each colour a swatch with its hex, name and basis, each
// face with its role and basis, and the logo with where it came from. Only a hex colour reaches `style`,
// and only an https source becomes a link.
function brandPanel(k) {
  if (!k) return "";
  const hex = (h) => (/^#[0-9a-f]{6}$/i.test(h) ? h : "transparent");
  const source = (s) =>
    /^https:/i.test(s)
      ? `<a href="${esc(s)}" rel="noopener noreferrer">${esc(s)}</a>`
      : esc(s);
  return `<section class="brand panel" data-brand="${esc(k.name)}"><h2>Brand: ${esc(k.name)}</h2>
    <p class="lede">${esc(k.from)}${k.once ? ", used for this video only" : ""}. The directions and the scenes wear these colours and faces.</p>
    <div class="swatches">${k.colours
      .map(
        (c) =>
          `<figure class="swatch"><span class="chip" style="background:${hex(c.hex)}"></span><figcaption><code>${esc(c.hex)}</code> <b dir="auto">${esc(c.name)}</b> <span class="tag">${esc(c.basis)}</span></figcaption></figure>`,
      )
      .join("")}</div>
    <ul class="faces">${k.faces
      .map(
        (f) =>
          `<li><span class="label">${esc(f.role)}</span> <b>${esc(f.family)}</b> <span class="tag${f.was ? " warn" : ""}">${f.was ? `replaces ${esc(f.was)}` : esc(f.basis)}</span></li>`,
      )
      .join("")}</ul>
    <p class="logo">${
      k.logo
        ? `<img alt="${esc(k.name)} logo" src="${esc(mediaUrl(k.logo.file))}"> <span class="label">logo from ${source(k.logo.source)}</span>`
        : '<span class="label">no logo</span>'
    }</p></section>`;
}
