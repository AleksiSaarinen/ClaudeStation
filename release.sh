#!/bin/bash
# Create a new GitHub Release with the current built app
# Usage: bash release.sh v1.1.0 "Description of changes"

set -e

VERSION="${1:?Usage: bash release.sh v1.1.0 \"changelog\"}"
NOTES="${2:-"Release $VERSION"}"

echo "Building..."
bash build.sh

echo "Zipping..."
cd /Applications && zip -r /tmp/ClaudeStation.zip ClaudeStation.app
cd -

echo "Creating release $VERSION..."
gh release create "$VERSION" /tmp/ClaudeStation.zip \
    --title "ClaudeStation $VERSION" \
    --notes "$NOTES"

echo "Done! Release: https://github.com/AleksiSaarinen/ClaudeStation/releases/tag/$VERSION"
