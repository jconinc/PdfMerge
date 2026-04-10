#!/bin/bash
# Setup script for PDF Tool's bundled Python environment
# This downloads a standalone Python build and installs pdf2docx + openpyxl
# Run this once before building the app with Word/Excel conversion support.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
PYTHON_DIR="$PROJECT_DIR/PdfMerge/Python"
PYTHON_VERSION="3.11.7"
ARCH="$(uname -m)"

echo "=== PDF Tool Python Environment Setup ==="
echo "Project: $PROJECT_DIR"
echo "Python dir: $PYTHON_DIR"
echo "Architecture: $ARCH"
echo ""

# Determine download URL for python-build-standalone
if [ "$ARCH" = "arm64" ]; then
    PLATFORM="aarch64-apple-darwin"
elif [ "$ARCH" = "x86_64" ]; then
    PLATFORM="x86_64-apple-darwin"
else
    echo "Error: Unsupported architecture: $ARCH"
    exit 1
fi

RELEASE_TAG="20231219"
DOWNLOAD_URL="https://github.com/indygreg/python-build-standalone/releases/download/${RELEASE_TAG}/cpython-${PYTHON_VERSION}+${RELEASE_TAG}-${PLATFORM}-install_only.tar.gz"

# Clean existing Python environment
if [ -d "$PYTHON_DIR/python" ]; then
    echo "Removing existing Python environment..."
    rm -rf "$PYTHON_DIR/python"
fi

# Download standalone Python
echo "Downloading Python ${PYTHON_VERSION} for ${PLATFORM}..."
TEMP_DIR=$(mktemp -d)
TARBALL="$TEMP_DIR/python.tar.gz"

curl -L -o "$TARBALL" "$DOWNLOAD_URL"

echo "Extracting Python..."
tar xzf "$TARBALL" -C "$PYTHON_DIR"

# Verify extraction
PYTHON_BIN="$PYTHON_DIR/python/bin/python3"
if [ ! -f "$PYTHON_BIN" ]; then
    echo "Error: Python binary not found at $PYTHON_BIN"
    exit 1
fi

echo "Python version: $($PYTHON_BIN --version)"

# Install required packages
echo ""
echo "Installing pdf2docx..."
"$PYTHON_BIN" -m pip install --upgrade pip --quiet
"$PYTHON_BIN" -m pip install pdf2docx --quiet

echo "Installing openpyxl..."
"$PYTHON_BIN" -m pip install openpyxl --quiet

echo "Installing pdfplumber..."
"$PYTHON_BIN" -m pip install pdfplumber --quiet

echo ""
echo "=== Setup Complete ==="
echo "Python: $PYTHON_BIN"
echo "Packages installed: pdf2docx, openpyxl, pdfplumber"
echo ""
echo "You can now build PDF Tool with Word/Excel conversion support."

# Cleanup
rm -rf "$TEMP_DIR"
