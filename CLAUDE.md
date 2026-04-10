# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

PDF Tool is a native macOS PDF utility app for a non-technical user (John's wife). It provides 11 tools (Merge, Split, Rotate, Compress, Extract Pages, OCR, Annotate, Fill Form, Convert, Print, Protect/Unlock) in a two-column NavigationSplitView layout.

**Platform:** macOS 14.0+ (Sonoma), Apple Silicon native
**Language:** Swift 5.10+, SwiftUI
**Frameworks:** PDFKit, Vision (OCR), AppKit, UniformTypeIdentifiers
**Distribution:** Ad-hoc signed .app copied directly to /Applications (no Developer account, no notarization, no DMG)

## Build & Run

This is an Xcode project. Build with:
```bash
xcodebuild -scheme "PDF Tool" -configuration Debug build
```

Ad-hoc signing for distribution:
```bash
codesign --force --deep --sign - "/path/to/PDF Tool.app"
```

## Specification

The complete spec lives in `docs/requirements.txt` (v4 spec + patch addendum). When the spec patch conflicts with the base spec, the patch takes precedence.

## Architecture Principles

- **PDFKit is the foundation.** Do not reimplement scrolling, text selection, zoom, find, form interaction, or print — PDFKit provides all of these. Build on PDFKit, not around it.
- **Two-column NavigationSplitView:** 200pt fixed sidebar (tool list + SF Symbols) with detail panel. Window starts at 960x660, min 800x540, remembers size/position.
- **Shared PDFView component:** Used by Annotate and Fill Form. It's an NSViewRepresentable wrapping PDFKit's PDFView. Must release document reference in dismantleNSView on tool switch to prevent memory leaks.
- **Thread safety rule:** CPU-heavy work (OCR, thumbnails, file I/O) runs on background tasks. PDFDocument mutations on a *live displayed* document must be on the main actor. Creating a separate PDFDocument in the background, processing it, and writing to disk is fine — this is the pattern for Merge, Split, Compress, Extract.
- **Atomic writes:** All file output uses temp file + rename. No partial files on interruption.
- **No network:** Entitlements must not include `com.apple.security.network.client` or `com.apple.security.network.server`. No URLSession, no WKWebView, no analytics.

## Key Design Rules

- Use only native macOS system controls and semantic colors. No custom hex colors or fonts. Must look correct in light and dark mode automatically.
- Never show Swift error types or system error codes to the user. All errors are plain English with a suggested action.
- Never silently overwrite files. Always show Replace/Save as Copy/Cancel confirmation.
- Default output location: same folder as input. Filename pattern: `[original]_[tool].pdf`.
- After operation: output opens in Preview, PDF Tool stays in background.
- Password-protected PDFs: inline password field (not modal dialog) in the file row/panel.
- Recent files: per-tool, last 5, stored in UserDefaults, shown below drop zone when no file is loaded.

## Build Priority Order

1. App shell (window, sidebar, panel switching with placeholders)
2. Shared widgets (drop zone, file list row, progress button, status banner)
3. Merge (validates full UI pattern end-to-end)
4. Split, Rotate, Compress, Extract Pages
5. Shared PDFView component
6. Annotate
7. Fill Form
8. OCR
9. Convert (native Image conversions first, then Word/Excel with bundled Python)
10. Print
11. Protect/Unlock
12. Preferences, menu bar, app registration, packaging

## OCR Notes

- Uses Apple Vision framework exclusively. No third-party dependencies.
- Languages populated dynamically from Vision at runtime (not hardcoded).
- Text layer uses invisible text in page content stream via Core Graphics (not PDF annotations).
- Vision coordinates (bottom-left, normalized) must map against the page's crop box bounds, accounting for non-zero origin.
- Acceptance: text selectable in Preview, Cmd+F finds words at correct position, Spotlight indexes content, copy yields correct reading order.

## Convert (Word/Excel) Notes

- Requires bundled standalone Python environment with pdf2docx and openpyxl.
- John runs a setup shell script once before building. Claude Code writes the script and Swift subprocess code.
- PYTHONHOME and PYTHONPATH must point only to the bundled directory (no system Python interaction).
- These sub-modes live under a collapsed "Advanced" disclosure group.

## Compress Notes

- Must use macOS Quartz filter mechanism (same as Preview's "Reduce File Size").
- Must preserve bookmarks, internal links, hyperlinks, metadata, and fonts. Abort if preservation can't be guaranteed.
- Four presets: Screen (72dpi), eBook (150dpi), Printer (300dpi, default), Prepress (300dpi + color preservation).

## Out of Scope (v1)

Cloud sync, collaborative annotation, form creation, digital signatures, Windows/Linux, auto-updates.
