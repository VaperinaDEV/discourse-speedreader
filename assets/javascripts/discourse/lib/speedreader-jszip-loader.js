// Dynamically loads JSZip from a CDN, same safe pattern as pdf.js in
// speedreader-pdf.js. Not vendored locally on purpose: files under
// assets/javascripts/discourse/ are picked up by Discourse's Ember build
// as ES modules, and a minified UMD bundle placed there can break the
// whole plugin's JS build (and therefore every page on the site).

const JSZIP_SRC = "https://cdnjs.cloudflare.com/ajax/libs/jszip/3.10.1/jszip.min.js";

let jsZipLoadPromise = null;

export function loadJSZip() {
  if (window.JSZip) return Promise.resolve(window.JSZip);
  if (jsZipLoadPromise) return jsZipLoadPromise;

  jsZipLoadPromise = new Promise((resolve, reject) => {
    const script = document.createElement("script");
    script.src = JSZIP_SRC;
    script.onload = () => resolve(window.JSZip);
    script.onerror = () => {
      jsZipLoadPromise = null;
      reject(new Error("jszip-load-failed"));
    };
    document.head.appendChild(script);
  });

  return jsZipLoadPromise;
}
