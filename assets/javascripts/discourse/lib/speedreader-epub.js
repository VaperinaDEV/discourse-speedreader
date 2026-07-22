import { tokenizeWords } from "./speedreader-tokenizer";
import { loadJSZip } from "./speedreader-jszip-loader";
import { chunkPages, htmlToText, firstTagText } from "./speedreader-format-utils";

function resolvePath(basePath, relativePath) {
  if (relativePath.startsWith("/")) return relativePath.slice(1);
  const baseParts = basePath.split("/").slice(0, -1);
  const relParts = relativePath.split("/");
  for (const part of relParts) {
    if (part === "." || part === "") continue;
    else if (part === "..") baseParts.pop();
    else baseParts.push(part);
  }
  return baseParts.join("/");
}

/**
 * @param {File} file
 * @param {(ratio: number, chapter: number, total: number) => void} [onProgress]
 */
export async function extractEpub(file, onProgress) {
  const JSZip = await loadJSZip();
  const zip = await JSZip.loadAsync(file);

  // 1. META-INF/container.xml points at the .opf (package document)
  const containerEntry = zip.file("META-INF/container.xml");
  if (!containerEntry) throw new Error("not-an-epub-file");
  const containerXml = await containerEntry.async("text");
  const containerDoc = new DOMParser().parseFromString(containerXml, "application/xml");
  const opfPath = containerDoc.querySelector("rootfile")?.getAttribute("full-path");
  if (!opfPath) throw new Error("epub-missing-opf");

  // 2. The .opf lists every file (manifest) and the reading order (spine)
  const opfEntry = zip.file(opfPath);
  if (!opfEntry) throw new Error("epub-missing-opf");
  const opfXml = await opfEntry.async("text");
  const opfDoc = new DOMParser().parseFromString(opfXml, "application/xml");

  const manifest = {};
  Array.from(opfDoc.getElementsByTagName("item")).forEach((item) => {
    manifest[item.getAttribute("id")] = item.getAttribute("href");
  });

  const spineIds = Array.from(opfDoc.getElementsByTagName("itemref")).map((el) =>
    el.getAttribute("idref")
  );

  const title = firstTagText(opfDoc, ["dc:title", "title"]);
  const author = firstTagText(opfDoc, ["dc:creator", "creator"]);

  // 3. Walk the spine in order, extract plain text from each XHTML chapter
  const words = [];
  const pages = [];
  let chapterNum = 0;

  for (const id of spineIds) {
    const href = manifest[id];
    if (!href) continue;
    const fullPath = resolvePath(opfPath, decodeURIComponent(href));
    const chapterEntry = zip.file(fullPath);
    if (!chapterEntry) continue;

    const html = await chapterEntry.async("text");
    const chapterWords = tokenizeWords(htmlToText(html));

    chapterNum++;
    if (chapterWords.length) {
      pages.push({ page: chapterNum, index: words.length });
      for (const w of chapterWords) words.push(w);
    }
    if (onProgress) onProgress(chapterNum / spineIds.length, chapterNum, spineIds.length);
  }

  if (words.length < 20) throw new Error("no-text-found");
  if (!pages.length) pages.push({ page: 1, index: 0 });

  return { words, pages, numPages: spineIds.length || pages.length, title, author };
}
