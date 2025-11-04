#!/bin/bash

# Kill any running instances
echo "Stopping any running Mariner instances..."
pkill -9 Mariner 2>/dev/null || true

# Clean up old app bundle
echo "Cleaning up old app bundle..."
rm -rf Mariner.app

# Build the executable
echo "Building Mariner..."
swift build

# Create app bundle structure
echo "Creating app bundle..."
APP_DIR="Mariner.app/Contents"
mkdir -p "$APP_DIR/MacOS"
mkdir -p "$APP_DIR/Resources"

# Copy executable
cp .build/debug/Mariner "$APP_DIR/MacOS/Mariner"

# Copy Info.plist
cp Info.plist "$APP_DIR/Info.plist"

# Copy app icon
cp Mariner.icns "$APP_DIR/Resources/Mariner.icns"

echo "App bundle created: Mariner.app"
echo "To run: open Mariner.app"
