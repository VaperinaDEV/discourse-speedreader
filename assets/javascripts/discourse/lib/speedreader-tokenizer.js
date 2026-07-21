// Intelligent word tokenization for RSVP speed reading.
//
// No isolated, punctuation-only "word" ever survives in the output:
// closing-type punctuation (. , ; : ! ? ” ) ]) attaches to the previous
// word, opening-type punctuation (" „ ( [ — dialogue dash) attaches to
// the next word. Line-break hyphenation is rejoined.

const OPEN_RE = /^[„"'‚«(\[]+$/u;
const DASH_RE = /^[—–]+$|^-{1,2}$/;
const PUNCT_ONLY_RE = /^[^\p{L}\p{N}]+$/u;

export function dehyphenate(text) {
  return text
    .replace(/(\p{L})-\s*\n\s*(\p{Ll})/gu, "$1$2")
    .replace(/(\p{L})-\s{2,}(\p{Ll})/gu, "$1$2");
}

export function tokenizeWords(rawText) {
  let text = dehyphenate(rawText || "");
  text = text.replace(/\s+/g, " ").trim();
  if (!text) return [];

  const raw = text.split(" ");
  const out = [];
  let prefix = "";

  for (const tok of raw) {
    if (!tok) continue;

    if (PUNCT_ONLY_RE.test(tok)) {
      if (OPEN_RE.test(tok) || DASH_RE.test(tok)) {
        prefix += tok;
      } else if (out.length > 0) {
        out[out.length - 1] += tok;
      } else {
        prefix += tok;
      }
      continue;
    }

    out.push(prefix + tok);
    prefix = "";
  }

  if (prefix) {
    if (out.length > 0) out[out.length - 1] += prefix;
    else out.push(prefix);
  }

  return out.filter(Boolean);
}

/**
 * Optional "chunking": very short function words (articles, conjunctions)
 * can be grouped with the following word so higher speeds stay readable.
 * The word list is language-specific — pass it in from
 * `SiteSetting.speedreader_chunk_words` (admin-configurable per site/
 * locale) rather than hardcoding a single language here.
 *
 * @param {string[]} words
 * @param {string[]} shortWordsList
 */
export function chunkShortWords(words, shortWordsList = []) {
  if (!shortWordsList.length) return words.slice();
  const shortSet = new Set(shortWordsList.map((w) => w.toLowerCase()));

  const out = [];
  for (let i = 0; i < words.length; i++) {
    const w = words[i];
    const bare = w.toLowerCase().replace(/[^\p{L}]/gu, "");
    if (shortSet.has(bare) && w.length <= 4 && i + 1 < words.length) {
      out.push(w + " " + words[i + 1]);
      i++;
    } else {
      out.push(w);
    }
  }
  return out;
}
