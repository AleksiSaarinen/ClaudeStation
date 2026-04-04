#!/bin/bash
set -e

APP="build/ClaudeStation.app"
BINARY="$APP/Contents/MacOS/ClaudeStation"
IDENTITY="ClaudeStation Dev"

echo "Building..."
swift build 2>&1 | tail -3

echo "Bundling..."
mkdir -p "$APP/Contents/MacOS"

# Only copy if binary actually changed
if ! cmp -s .build/debug/ClaudeStation "$BINARY" 2>/dev/null; then
    cp .build/debug/ClaudeStation "$BINARY"
    echo "Binary updated."
else
    echo "Binary unchanged, skipping copy."
fi

# Create Info.plist if missing
if [ ! -f "$APP/Contents/Info.plist" ]; then
    cat > "$APP/Contents/Info.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>ClaudeStation</string>
    <key>CFBundleIdentifier</key>
    <string>com.claudestation.app</string>
    <key>CFBundleName</key>
    <string>ClaudeStation</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleVersion</key>
    <string>1.0</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>CFBundleIconFile</key>
    <string>ClaudeStation</string>
    <key>CFBundleURLTypes</key>
    <array>
        <dict>
            <key>CFBundleURLName</key>
            <string>ClaudeStation Commands</string>
            <key>CFBundleURLSchemes</key>
            <array>
                <string>claudestation</string>
            </array>
        </dict>
    </array>
</dict>
</plist>
PLIST
fi

# Copy resources
mkdir -p "$APP/Contents/Resources/PetFrames"
cp Resources/ClaudeStation.icns "$APP/Contents/Resources/" 2>/dev/null
cp Resources/PetFrames/*.png "$APP/Contents/Resources/PetFrames/" 2>/dev/null

echo "Signing with '$IDENTITY'..."
codesign --force --deep --sign "$IDENTITY" "$APP" 2>&1

# Install to /Applications
cp -R "$APP" /Applications/ClaudeStation.app 2>/dev/null && echo "Installed to /Applications"

echo "Done! Run with: open /Applications/ClaudeStation.app"
