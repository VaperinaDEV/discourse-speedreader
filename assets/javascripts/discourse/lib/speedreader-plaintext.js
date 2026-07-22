import { tokenizeWords } from "./speedreader-tokenizer";
import { chunkPages } from "./speedreader-format-utils";

export async function extractTxt(file) {
  const text = await file.text();
  const words = tokenizeWords(text);
  if (words.length < 20) throw new Error("no-text-found");
  const pages = chunkPages(words);
  return { words, pages, numPages: pages.length, title: null, author: null };
}

function stripMarkdown(md) {
  return md
    .replace(/```[\s\S]*?```/g, " ") // fenced code blocks
    .replace(/`([^`]+)`/g, "$1") // inline code
    .replace(/!\[[^\]]*\]\([^)]*\)/g, " ") // images
    .replace(/\[([^\]]+)\]\([^)]*\)/g, "$1") // links -> link text
    .replace(/^#{1,6}\s+/gm, "") // headers
    .replace(/^>\s?/gm, "") // blockquotes
    .replace(/(\*\*|__)(.*?)\1/g, "$2") // bold
    .replace(/(\*|_)(.*?)\1/g, "$2") // italic
    .replace(/^\s*[-*+]\s+/gm, "") // bullet lists
    .replace(/^\s*\d+\.\s+/gm, "") // numbered lists
    .replace(/^-{3,}$/gm, " ") // horizontal rules
    .replace(/\|/g, " "); // table pipes
}

export async function extractMarkdown(file) {
  const raw = await file.text();
  const text = stripMarkdown(raw);
  const words = tokenizeWords(text);
  if (words.length < 20) throw new Error("no-text-found");
  const pages = chunkPages(words);
  const titleMatch = raw.match(/^#\s+(.+)$/m);
  return {
    words,
    pages,
    numPages: pages.length,
    title: titleMatch ? titleMatch[1].trim() : null,
    author: null,
  };
}
