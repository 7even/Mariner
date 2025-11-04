# Mariner

A native macOS markdown viewer with GitHub-style rendering and live preview.

## Features

- **GitHub Flavored Markdown** - Full GFM support including tables, task lists, strikethrough, and autolinks
- **Syntax Highlighting** - Code blocks with syntax highlighting for Swift, Rust, Go, Kotlin, Clojure, Elixir, and more
- **Live Preview** - Automatically reloads when markdown files change
- **Multiple Windows** - Open multiple markdown files simultaneously in separate windows
- **Native Performance** - Built with Swift and AppKit for fast, native macOS experience
- **Clean UI** - GitHub-style CSS rendering with proper typography and spacing

## Requirements

- macOS 12.0 or later
- Xcode Command Line Tools
- Swift 5.7 or later

## Building

1. **Install Xcode Command Line Tools** (if not already installed):
   ```bash
   xcode-select --install
   ```

2. **Clone the repository**:
   ```bash
   git clone https://github.com/yourusername/Mariner.git
   cd Mariner
   ```

3. **Build and run**:
   ```bash
   ./build-app.sh
   open Mariner.app
   ```

The build script will:
- Compile the Swift code
- Download and build dependencies (cmark-gfm)
- Create the app bundle
- Place `Mariner.app` in the project directory

## Usage

1. Launch `Mariner.app`
2. Select a markdown file (`.md` or `.markdown`)
3. The file opens in a new window with live preview
4. Edit the file in your favorite editor - Mariner automatically reloads changes

You can open multiple markdown files, each in its own window.

## Architecture

- **Swift Package Manager** for dependency management
- **cmark-gfm** for GitHub Flavored Markdown parsing
- **WKWebView** for HTML rendering
- **NSDocument** architecture for multi-window support
- **DispatchSource** for file system monitoring

## License

This project is open source and available under the MIT License.
