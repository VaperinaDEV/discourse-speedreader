import { tokenizeWords } from "./speedreader-tokenizer";
import { loadJSZip } from "./speedreader-jszip-loader";
import { chunkPages, firstTagText } from "./speedreader-format-utils";

export async function extractDocx(file) {
  const JSZip = await loadJSZip();
  const zip = await JSZip.loadAsync(file);

  const docEntry = zip.file("word/document.xml");
  if (!docEntry) throw new Error("not-a-docx-file");
  const docXml = await docEntry.async("text");

  const doc = new DOMParser().parseFromString(docXml, "application/xml");
  // Word paragraphs are <w:p>, text runs inside are <w:t>. Join runs within
  // a paragraph directly (no extra spaces — Word already splits runs at
  // formatting boundaries, not at word boundaries), paragraphs with \n so
  // the tokenizer treats them as normal whitespace-separated text.
  const paragraphs = Array.from(doc.getElementsByTagName("w:p"));
  const text = paragraphs
    .map((p) =>
      Array.from(p.getElementsByTagName("w:t"))
        .map((t) => t.textContent)
        .join("")
    )
    .join("\n");

  let title = null;
  let author = null;
  const coreEntry = zip.file("docProps/core.xml");
  if (coreEntry) {
    try {
      const coreXml = await coreEntry.async("text");
      const coreDoc = new DOMParser().parseFromString(coreXml, "application/xml");
      title = firstTagText(coreDoc, ["dc:title", "title"]);
      author = firstTagText(coreDoc, ["dc:creator", "creator"]);
    } catch (e) {
      // metadata is a nice-to-have, never fail extraction because of it
    }
  }

  const words = tokenizeWords(text);
  if (words.length < 20) throw new Error("no-text-found");

  const pages = chunkPages(words);
  return { words, pages, numPages: pages.length, title, author };
}
