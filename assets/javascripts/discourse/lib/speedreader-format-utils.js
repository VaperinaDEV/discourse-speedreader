// Shared helpers used by more than one format extractor.

/**
 * Splits a flat word list into evenly sized "pages" so formats without a
 * real page concept (txt, md, docx) still get a navigable position list.
 */
export function chunkPages(words, wordsPerChunk = 1000) {
  const pages = [];
  for (let i = 0; i < words.length; i += wordsPerChunk) {
    pages.push({ page: pages.length + 1, index: i });
  }
  if (!pages.length) pages.push({ page: 1, index: 0 });
  return pages;
}

/** Strips tags/scripts/styles from an HTML/XHTML string, returns plain text. */
export function htmlToText(htmlString) {
  const doc = new DOMParser().parseFromString(htmlString, "text/html");
  doc.querySelectorAll("script, style").forEach((el) => el.remove());
  return (doc.body ? doc.body.textContent : doc.textContent) || "";
}

/** First non-empty textContent among a list of (possibly namespaced) tag names. */
export function firstTagText(doc, tagNames) {
  for (const tag of tagNames) {
    const el = doc.getElementsByTagName(tag)[0];
    if (el && el.textContent && el.textContent.trim()) return el.textContent.trim();
  }
  return null;
}
