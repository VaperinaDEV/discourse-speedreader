// Format dispatcher: picks the right extractor by file extension and
// returns a uniform { words, pages, numPages, title, author } shape.
//
// PDF and EPUB/DOCX both rely on a library loaded dynamically from a CDN
// at runtime (never vendored under assets/javascripts/discourse/ — see
// speedreader-jszip-loader.js for why).

import { extractPdf } from "./speedreader-pdf";
import { extractTxt, extractMarkdown } from "./speedreader-plaintext";
import { extractDocx } from "./speedreader-docx";
import { extractEpub } from "./speedreader-epub";

export const SUPPORTED_EXTENSIONS = [".pdf", ".epub", ".docx", ".txt", ".md", ".markdown"];

export async function extractFile(file, onProgress) {
  const name = (file.name || "").toLowerCase();

  if (name.endsWith(".pdf")) return extractPdf(file, onProgress);
  if (name.endsWith(".epub")) return extractEpub(file, onProgress);
  if (name.endsWith(".docx")) return extractDocx(file);
  if (name.endsWith(".txt") || name.endsWith(".text")) return extractTxt(file);
  if (name.endsWith(".md") || name.endsWith(".markdown")) return extractMarkdown(file);

  throw new Error("unsupported-format");
}
