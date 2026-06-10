#!/usr/bin/env bash
# Generates the Xcode project from project.yml using XcodeGen.
# Run once after cloning, or after changing project.yml.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# ── Install XcodeGen if missing ───────────────────────────────────────────────
if ! command -v xcodegen &>/dev/null; then
    echo "XcodeGen not found. Installing via Homebrew…"
    if ! command -v brew &>/dev/null; then
        echo "Error: Homebrew is required. Install it from https://brew.sh"
        exit 1
    fi
    brew install xcodegen
fi

# ── Generate project ──────────────────────────────────────────────────────────
echo "Generating ClipboardManager.xcodeproj…"
xcodegen generate --spec project.yml

echo ""
echo "Done. Open the project with:"
echo "  open ClipboardManager.xcodeproj"
echo ""
echo "First-time setup:"
echo "  1. Set your Development Team in Xcode → Signing & Capabilities"
echo "  2. Build & Run (⌘R)"
echo "  3. Grant Accessibility access in System Settings when prompted"
