#!/bin/bash
# Generates the Xcode project for the 11am sandbox and opens it.
set -euo pipefail

cd "$(dirname "$0")"

if ! command -v xcodegen >/dev/null 2>&1; then
  if command -v brew >/dev/null 2>&1; then
    echo "Installing XcodeGen with Homebrew..."
    brew install xcodegen
  else
    echo "XcodeGen is needed. Install Homebrew from https://brew.sh, then run: brew install xcodegen"
    exit 1
  fi
fi

xcodegen generate
open ElevenAm.xcodeproj
echo "Opened ElevenAm.xcodeproj. Press Cmd-R in Xcode to build and run."
