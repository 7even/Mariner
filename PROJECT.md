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

Project initialized. Ready to begin development.

## Next Steps

1. Set up Swift project structure
2. Implement basic markdown rendering
3. Add GitHub CSS styling
4. Implement file system watcher for live preview
5. Build UI for file selection and display
