# Mariner

A native macOS application for viewing markdown files with GitHub-style rendering.

## Project Goal

Build a native Swift application that displays markdown files with GitHub Flavored Markdown rendering and live preview capabilities.

## Key Requirements

### Must Have
- **Native macOS Application** - Built with Swift using AppKit/SwiftUI
- **GitHub-Style Rendering** - Render markdown files exactly as they appear on GitHub
- **Live Preview** - Real-time updates when markdown files change on disk
  - Watch file system for changes
  - Auto-refresh the view when files are modified
  - No manual refresh needed

### Technical Approach

#### Markdown Rendering
- Use `cmark-gfm` (GitHub's C library for GitHub Flavored Markdown) or `swift-markdown`
- Render to HTML and display in `WKWebView`
- Apply GitHub's public markdown CSS for authentic styling

#### Live Preview Implementation
- Use macOS `FSEvents` API or `DispatchSource.makeFileSystemObjectSource`
- Monitor file changes in real-time
- Automatically re-render and refresh the view

#### Architecture
```
File Watcher → Detect Changes → Parse Markdown → Apply GitHub CSS → Display in WKWebView
```

## Development Status

### Completed
- ✅ Swift project structure with Swift Package Manager
- ✅ GitHub Flavored Markdown rendering using cmark-gfm
- ✅ GitHub CSS styling with syntax highlighting
- ✅ File system watcher for live preview
- ✅ Document-based architecture for multiple windows
- ✅ Recent files menu
- ✅ Custom ship's wheel app icon
- ✅ Image support (local and remote)
- ✅ Links open in default browser
- ✅ Scroll position preservation across reloads and app launches
- ✅ Automatic document restoration on app relaunch
- ✅ PDF export functionality (⌘E)
- ✅ Installation to /Applications via build script
- ✅ Zoom controls (⌘+, ⌘-, ⌘0)

## Future Ideas

### Quick Look Extension
Add a Quick Look extension to provide GitHub-styled markdown previews in Finder (when pressing Space on .md files). This would require:
- Creating a Quick Look Extension target
- Registering it to handle markdown files
- Implementing preview generation using existing rendering code
- Proper code signing and entitlements
