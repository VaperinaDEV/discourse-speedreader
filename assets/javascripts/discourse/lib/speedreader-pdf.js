// Client-side PDF processing: loads pdfjs-dist and reconstructs page text
// using POSITION-AWARE joining (see pageTextFromContent below) rather than
// naively joining every text run with a space — without this, accented
// letters sometimes arrive as separate text runs due to font encoding
// (e.g. "ELS" + "Ő" instead of "ELSŐ" in Hungarian PDFs), and get
// misread as their own "word".
//
// Errors thrown here are plain English strings meant to be caught by the
// calling UI component and mapped to a localized message, e.g.:
//   catch (e) { this.flash(I18n.t("speedreader.errors.pdfjs_load_failed")); }

import { tokenizeWords } from "./speedreader-tokenizer";

const PDFJS_SRC = "https://cdnjs.cloudflare.com/ajax/libs/pdf.js/3.11.174/pdf.min.js";
const PDFJS_WORKER_SRC = "https://cdnjs.cloudflare.com/ajax/libs/pdf.js/3.11.174/pdf.worker.min.js";

let pdfjsLoadPromise = null;

function loadPdfJs() {
  if (window.pdfjsLib) return Promise.resolve(window.pdfjsLib);
  if (pdfjsLoadPromise) return pdfjsLoadPromise;

  pdfjsLoadPromise = new Promise((resolve, reject) => {
    const script = document.createElement("script");
    script.src = PDFJS_SRC;
    script.onload = () => {
      window.pdfjsLib.GlobalWorkerOptions.workerSrc = PDFJS_WORKER_SRC;
      resolve(window.pdfjsLib);
    };
    script.onerror = () => reject(new Error("Failed to load the pdf.js library."));
    document.head.appendChild(script);
  });

  return pdfjsLoadPromise;
}

function pageTextFromContent(content) {
  let text = "";
  let lastItem = null;

  for (const item of content.items) {
    if (!item.str) {
      if (item.hasEOL) text += "\n";
      lastItem = null;
      continue;
    }

    if (lastItem) {
      const fontSize = Math.hypot(lastItem.transform[0], lastItem.transform[1]) || 10;
      const sameLine = Math.abs(item.transform[5] - lastItem.transform[5]) < fontSize * 0.4;

      if (!sameLine) {
        text += "\n";
      } else {
        const prevEndX = lastItem.transform[4] + (lastItem.width || 0);
        const gap = item.transform[4] - prevEndX;
        if (gap > fontSize * 0.14) text += " ";
      }
    }

    text += item.str;
    lastItem = item.hasEOL ? null : item;
    if (item.hasEOL) text += "\n";
  }

  return text;
}

/**
 * @param {File} file
 * @param {(ratio: number, page: number, total: number) => void} [onProgress]
 * @returns {Promise<{ words: string[], pages: {page:number, index:number}[], numPages: number, title: string|null, author: string|null }>}
 */
export async function extractPdf(file, onProgress) {
  const pdfjsLib = await loadPdfJs();
  const buf = await file.arrayBuffer();
  const pdf = await pdfjsLib.getDocument({ data: buf }).promise;
  const numPages = pdf.numPages;

  let meta = null;
  try { meta = await pdf.getMetadata(); } catch (e) { /* no-op */ }

  const words = [];
  const pages = [];

  for (let p = 1; p <= numPages; p++) {
    const page = await pdf.getPage(p);
    const content = await page.getTextContent();
    const pageWords = tokenizeWords(pageTextFromContent(content));

    if (pageWords.length) {
      pages.push({ page: p, index: words.length });
      for (const w of pageWords) words.push(w);
    }

    if (onProgress) onProgress(p / numPages, p, numPages);
  }

  return {
    words,
    pages,
    numPages,
    title: meta?.info?.Title?.trim() || null,
    author: meta?.info?.Author?.trim() || null,
  };
}
