// Text of a PDF (PDFKit), for personal_mcp.py. Only called by it.
//   docs_text.js pdf <path>   -> {"text": "...", "pages": N} | {"locked": true} | {"error": "..."}
ObjC.import("Foundation");
ObjC.import("PDFKit");
function run(argv) {
  try {
    const url = $.NSURL.fileURLWithPath(argv[1]);
    const doc = $.PDFDocument.alloc.initWithURL(url);
    if (!doc || doc.isNil()) return JSON.stringify({ error: "not a readable PDF" });
    if (doc.isLocked) return JSON.stringify({ locked: true, pages: doc.pageCount });
    const s = doc.string;
    return JSON.stringify({ text: s && !s.isNil() ? ObjC.unwrap(s) : "", pages: doc.pageCount });
  } catch (e) {
    return JSON.stringify({ error: String(e.message || e) });
  }
}
