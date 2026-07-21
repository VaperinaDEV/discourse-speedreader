// File extractor abstraction for speedreader: supports PDF/TXT/MD and
// provides hooks for DOCX/EPUB via dynamic CDN-loaded libraries.

import { tokenizeWords } from "./speedreader-tokenizer";
import { extractPdf } from "./speedreader-pdf";

async function loadScript(src) {
  return new Promise((resolve, reject) => {
    if (document.querySelector(`script[src="${src}"]`)) return resolve();
    const s = document.createElement("script");
    s.src = src;
    s.onload = resolve;
    s.onerror = reject;
    document.head.appendChild(s);
  });
}

export async function extractFile(file, onProgress) {
  const name = (file.name || "").toLowerCase();
  if (name.endsWith('.pdf')) return extractPdf(file, onProgress);

  if (name.endsWith('.txt') || name.endsWith('.text')) {
    const text = await file.text();
    const words = tokenizeWords(text);
    const pages = words.length ? [{ page: 1, index: 0 }] : [];
    return { words, pages, numPages: 1, title: null, author: null };
  }

  if (name.endsWith('.md')) {
    const raw = await file.text();
    // naive markdown stripper: remove basic markdown punctuation
    const stripped = raw.replace(/[#*_>`~\[\]\(\)\-]/g, ' ');
    const words = tokenizeWords(stripped);
    return { words, pages: [{ page: 1, index: 0 }], numPages: 1, title: null, author: null };
  }

  if (name.endsWith('.docx')) {
    // load mammoth from CDN and extract raw text
    const MAMMOTH = "https://unpkg.com/mammoth@1.4.19/dist/mammoth.browser.min.js";
    try {
      await loadScript(MAMMOTH);
      const arrayBuffer = await file.arrayBuffer();
      // mammoth expects a ArrayBuffer or raw file
      // mammoth.extractRawText is available on the loaded global if present
      // If mammoth isn't available, throw and fallthrough to error
      // eslint-disable-next-line no-undef
      if (window.mammoth && window.mammoth.extractRawText) {
        const result = await window.mammoth.extractRawText({ arrayBuffer });
        const text = result.value || '';
        const words = tokenizeWords(text);
        return { words, pages: [{ page: 1, index: 0 }], numPages: 1, title: null, author: null };
      }
    } catch (e) {
      throw new Error('docx-extraction-failed');
    }
  }

  if (name.endsWith('.epub')) {
    // load epub.js or similar; epub parsing in-browser can be complex — try epub.js
    const EPUBJS = "https://cdnjs.cloudflare.com/ajax/libs/epub.js/0.3.88/epub.min.js";
    try {
      await loadScript(EPUBJS);
      // eslint-disable-next-line no-undef
      if (window.ePub) {
        const arrayBuffer = await file.arrayBuffer();
        const book = window.ePub(arrayBuffer);
        const renderer = book.renderTo(document.createElement('div'));
        // Simple approach: iterate sections and collect text — epub.js API is async
        const textChunks = [];
        const spine = await book.loaded.spine;
        for (const item of spine.spine.items) {
          try {
            const content = await item.load(book.load.bind(book));
            const doc = new DOMParser().parseFromString(content, 'text/html');
            textChunks.push(doc.body.textContent || '');
            item.unload();
          } catch (e) {
            // ignore section errors
          }
        }
        const combined = textChunks.join('\n');
        const words = tokenizeWords(combined);
        return { words, pages: [{ page: 1, index: 0 }], numPages: 1, title: null, author: null };
      }
    } catch (e) {
      throw new Error('epub-extraction-failed');
    }
  }

  throw new Error('unsupported-format');
}
