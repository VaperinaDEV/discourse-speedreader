// File extractor abstraction for speedreader: supports PDF/TXT/MD and
// provides hooks for DOCX/EPUB via dynamic CDN-loaded libraries.

import { tokenizeWords } from "./speedreader-tokenizer";
import { extractPdf } from "./speedreader-pdf";

async function loadScriptWithFallback(urls) {
  for (const url of urls) {
    try {
      await new Promise((resolve, reject) => {
        const s = document.createElement('script');
        s.src = url;
        s.async = true;
        s.onload = () => resolve(url);
        s.onerror = () => {
          s.remove();
          reject(new Error(`load failed: ${url}`));
        };
        document.head.appendChild(s);
      });
      return url;
    } catch (err) {
      console.warn(err);
    }
  }
  throw new Error('All script load attempts failed');
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
    try {
      if (!window.mammoth || !window.mammoth.extractRawText) {
        await loadScriptWithFallback([
          'https://cdn.jsdelivr.net/npm/mammoth@1.11.0/mammoth.browser.min.js',
          'https://cdnjs.cloudflare.com/ajax/libs/mammoth/1.11.0/mammoth.browser.min.js',
          'https://cdn.jsdelivr.net/npm/mammoth/mammoth.browser.min.js'
        ]);
      }
  
      if (window.mammoth && window.mammoth.extractRawText) {
        const arrayBuffer = await file.arrayBuffer();
        const result = await window.mammoth.extractRawText({ arrayBuffer });
        const text = result.value || '';
        const words = tokenizeWords(text);
        return { words, pages: [{ page: 1, index: 0 }], numPages: 1, title: null, author: null };
      } else {
        throw new Error('mammoth-not-available');
      }
    } catch (e) {
      console.error('DOCX extraction error', e);
      throw new Error('docx-extraction-failed');
    }
  }

  if (name.endsWith('.epub')) {
    try {
      if (!window.ePub) {
        await loadScriptWithFallback([
          'https://cdn.jsdelivr.net/npm/epubjs@0.3.88/dist/epub.min.js',
          'https://unpkg.com/epubjs@0.3.88/dist/epub.min.js',
          'https://cdn.jsdelivr.net/npm/epubjs/dist/epub.min.js',
          'https://unpkg.com/epubjs/dist/epub.min.js'
        ]);
      }
  
      if (window.ePub) {
        const arrayBuffer = await file.arrayBuffer();
        const book = window.ePub(arrayBuffer);
        await book.ready;
        const textChunks = [];
  
        const spine = book.loaded && book.loaded.spine;
        if (spine && spine.spine && Array.isArray(spine.spine.items)) {
          for (const item of spine.spine.items) {
            try {
              const content = await item.load(book.load.bind(book));
              const doc = new DOMParser().parseFromString(content, 'text/html');
              textChunks.push(doc.body.textContent || '');
              if (item.unload) item.unload();
            } catch (e) {
              // ignore section errors
              console.warn('epub section error', e);
            }
          }
        } else {
          try {
            const rendition = book.renderTo(document.createElement('div'));
          } catch (e) {
          }
        }
  
        const combined = textChunks.join('\n');
        const words = tokenizeWords(combined);
        return { words, pages: [{ page: 1, index: 0 }], numPages: 1, title: null, author: null };
      } else {
        throw new Error('epub-lib-not-available');
      }
    } catch (e) {
      console.error('EPUB extraction error', e);
      throw new Error('epub-extraction-failed');
    }
  }

  throw new Error('unsupported-format');
}
