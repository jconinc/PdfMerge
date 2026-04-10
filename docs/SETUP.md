# PdfMerge (PDF Tool) - Setup & Install Guide

## What It Is

A native macOS PDF utility with 12 tools: Merge, Split, Rotate, Compress, Extract Pages, OCR, Annotate, Edit Text, Fill Form, Convert, Print, and Protect/Unlock. Built for a non-technical user -- no subscriptions, no cloud, no tracking.

## Requirements

- macOS 14 Sonoma or later
- Xcode 15 or later (for building)
- Apple Silicon or Intel Mac

## Build

1. Clone the repo:
   ```bash
   git clone https://github.com/jconinc/PdfMerge.git
   cd PdfMerge
   ```

2. Open in Xcode:
   ```bash
   open PdfMerge.xcodeproj
   ```

3. Select the **PdfMerge** scheme and **My Mac** as the run destination.

4. In **Signing & Capabilities**, the project uses ad-hoc signing (`-`). If Xcode asks for a team, pick your Apple ID.

5. **Product > Build** (Cmd+B).

6. If you get compile errors (expected after cross-platform authoring), they'll likely be minor -- wrong parameter label or missing import. Fix and rebuild.

## Install

1. **Product > Show Build Folder in Finder** -- navigate to `Build/Products/Debug/PDF Tool.app`.
2. Drag to `/Applications`.
3. Ad-hoc sign for distribution:
   ```bash
   codesign --force --deep --sign - "/Applications/PDF Tool.app"
   ```
4. Double-click to launch.

## Optional: Word/Excel Conversion

Word and Excel conversion requires a bundled Python environment. This is optional -- all other tools work without it.

1. Run the setup script once:
   ```bash
   cd PdfMerge
   ./Scripts/setup_python_env.sh
   ```
   This downloads a standalone Python 3.11 and installs `pdf2docx`, `openpyxl`, and `pdfplumber`.

2. Rebuild the app so the Python environment is bundled inside the .app.

3. The Convert tool's Word/Excel options will now be available under the "Advanced" disclosure group.

## Tools Overview

| Tool | What It Does |
|------|-------------|
| **Merge** | Combine multiple PDFs into one. Drag to reorder. |
| **Split** | Split by range, every N pages, or pick individual pages. |
| **Rotate** | Rotate selected pages 90/180/270 degrees. |
| **Compress** | Reduce file size with 4 presets (Screen, eBook, Printer, Prepress). |
| **Extract Pages** | Pull out specific pages as a new PDF. |
| **OCR** | Add searchable text layer to scanned documents using Apple Vision. |
| **Annotate** | Highlight, underline, strikethrough, freehand, shapes, text notes. |
| **Edit Text** | Click text to replace it. Font matching with 50+ PostScript names. |
| **Fill Form** | Fill interactive PDF form fields. Flatten to lock values. |
| **Convert** | PDF to images, images to PDF, PDF to Word/Excel (requires Python). |
| **Print** | Print with macOS print dialog. |
| **Protect/Unlock** | Add or remove password protection with permission controls. |

## How It Works

- Drop a PDF (or browse) into any tool.
- Configure options, click the action button.
- Output opens in Preview. The app stays in the background.
- Recent files are saved per-tool (last 5).

### Key Behaviors

- **Never silently overwrites** -- always shows Replace / Save as Copy / Cancel.
- **Atomic writes** -- uses temp file + rename, so interrupted operations don't corrupt files.
- **Sandboxed** -- only accesses user-selected files via security-scoped bookmarks.
- **No network** -- zero outbound connections. No analytics, no telemetry.

## Uninstall

1. Delete `PDF Tool.app` from `/Applications`.
2. Reset preferences: `defaults delete com.pdftool.app`
3. Remove from System Settings > Privacy & Security > Accessibility if listed.

## Troubleshooting

### App won't open ("damaged" or "unidentified developer")

This happens because the app isn't notarized. Fix:
```bash
xattr -cr "/Applications/PDF Tool.app"
```
Then try opening again.

### OCR produces no text

- Check the language setting in Preferences > OCR. Vision supports many languages but the right one must be selected.
- Very low-quality scans may not produce results. Try the "Accurate" recognition level.

### Compress says "already well-optimized"

The file is already small. The compressor aborts if the output would be larger than the input.

### Word/Excel conversion not available

Run `./Scripts/setup_python_env.sh` and rebuild. The Python environment must be bundled inside the app.

## Architecture (for developers)

```
PdfMerge/
  App/           -- SwiftUI app entry, commands, constants
  Models/        -- Data types (Tool, PDFFileItem, OutputSettings, etc.)
  Services/      -- Stateless business logic (MergeService, OCRService, etc.)
  Utilities/     -- Extensions and helpers
  Views/
    PDFViewer/   -- NSViewRepresentable wrapping PDFKit's PDFView
    Preferences/ -- Settings window
    Shared/      -- Reusable components (DropZone, FileListRow, etc.)
    Sidebar/     -- Tool navigation
    Tools/       -- One folder per tool (View + ViewModel)
```

Each tool follows the pattern: **ViewModel** (state + logic) + **View** (UI) + **Service** (file operations).
