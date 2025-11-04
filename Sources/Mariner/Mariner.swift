import Cocoa
import WebKit
import cmark_gfm
import cmark_gfm_extensions

// MARK: - Markdown Document

@objc(MarkdownDocument)
class MarkdownDocument: NSDocument {
    var webView: WKWebView!
    var fileSystemSource: DispatchSourceFileSystemObject?
    var markdownContent: String = ""

    override class var autosavesInPlace: Bool {
        return false
    }

    override class var readableTypes: [String] {
        return ["net.daringfireball.markdown", "public.plain-text", "public.text"]
    }

    override class func canConcurrentlyReadDocuments(ofType typeName: String) -> Bool {
        return true
    }

    override func makeWindowControllers() {
        let window = NSWindow(
            contentRect: NSRect(x: 100, y: 100, width: 900, height: 700),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )

        // Create WKWebView
        webView = WKWebView(frame: window.contentView!.bounds)
        webView.autoresizingMask = [.width, .height]
        window.contentView?.addSubview(webView)

        let windowController = NSWindowController(window: window)
        addWindowController(windowController)

        // Show the window
        windowController.showWindow(nil)
        window.center()

        // Set window title
        updateWindowTitle()

        // Render initial content
        renderMarkdown()

        // Start watching file for changes
        if let fileURL = fileURL {
            watchFile(at: fileURL.path)
        }
    }

    override func read(from url: URL, ofType typeName: String) throws {
        markdownContent = try String(contentsOf: url, encoding: .utf8)
    }

    override func data(ofType typeName: String) throws -> Data {
        // Read-only viewer, no saving
        return markdownContent.data(using: .utf8) ?? Data()
    }

    func updateWindowTitle() {
        if let fileName = fileURL?.lastPathComponent {
            windowControllers.first?.window?.title = "Mariner - \(fileName)"
        } else {
            windowControllers.first?.window?.title = "Mariner"
        }
    }

    func renderMarkdown(retryCount: Int = 0) {
        guard let url = fileURL else { return }

        // Re-read file content
        guard let content = try? String(contentsOf: url, encoding: .utf8) else {
            // If we fail to read, retry up to 3 times with increasing delays
            if retryCount < 3 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05 * Double(retryCount + 1)) {
                    self.renderMarkdown(retryCount: retryCount + 1)
                }
            } else {
                webView?.loadHTMLString("<h1>Error</h1><p>Could not read file</p>", baseURL: nil)
            }
            return
        }

        markdownContent = content

        // Parse markdown using cmark-gfm with all GitHub extensions
        let html = content.withCString { cString -> String in
            // Register GFM extensions
            cmark_gfm_core_extensions_ensure_registered()

            // Create parser with GFM extensions
            let parser = cmark_parser_new(CMARK_OPT_DEFAULT)
            defer { cmark_parser_free(parser) }

            // Attach all GFM extensions
            let extensionNames = ["table", "strikethrough", "autolink", "tagfilter", "tasklist"]
            for name in extensionNames {
                if let ext = cmark_find_syntax_extension(name) {
                    cmark_parser_attach_syntax_extension(parser, ext)
                }
            }

            // Parse the markdown
            cmark_parser_feed(parser, cString, strlen(cString))
            let document = cmark_parser_finish(parser)
            defer { cmark_node_free(document) }

            // Render to HTML
            let htmlCString = cmark_render_html(document, CMARK_OPT_DEFAULT, nil)
            defer { free(htmlCString) }
            return String(cString: htmlCString!)
        }

        // Create full HTML with GitHub styling
        let fullHTML = """
        <!DOCTYPE html>
        <html>
        <head>
            <meta charset="utf-8">
            <meta name="viewport" content="width=device-width, initial-scale=1">
            <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.9.0/styles/github.min.css">
            <script src="https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.9.0/highlight.min.js"></script>
            <!-- Additional language support -->
            <script src="https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.9.0/languages/clojure.min.js"></script>
            <script src="https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.9.0/languages/swift.min.js"></script>
            <script src="https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.9.0/languages/rust.min.js"></script>
            <script src="https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.9.0/languages/go.min.js"></script>
            <script src="https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.9.0/languages/kotlin.min.js"></script>
            <script src="https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.9.0/languages/elixir.min.js"></script>
            <style>
                \(githubMarkdownCSS)
            </style>
        </head>
        <body>
            <article class="markdown-body">
                \(html)
            </article>
            <script>
                // Apply syntax highlighting to all code blocks
                document.querySelectorAll('pre code').forEach((block) => {
                    hljs.highlightElement(block);
                });

            </script>
        </body>
        </html>
        """

        webView?.loadHTMLString(fullHTML, baseURL: nil)
    }

    func watchFile(at path: String) {
        let fileDescriptor = open(path, O_EVTONLY)
        guard fileDescriptor >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor,
            eventMask: [.write, .delete, .rename],
            queue: DispatchQueue.main
        )

        source.setEventHandler { [weak self] in
            // Add a small delay to let the file finish writing
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self?.renderMarkdown()
            }
        }

        source.setCancelHandler {
            Darwin.close(fileDescriptor)
        }

        source.resume()
        fileSystemSource = source
    }

    override func close() {
        fileSystemSource?.cancel()
        fileSystemSource = nil
        super.close()
    }
}

// MARK: - App Delegate

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Setup menu bar
        setupMenuBar()

        // Show open panel on launch
        DispatchQueue.main.async {
            NSDocumentController.shared.openDocument(nil)
        }
    }

    func setupMenuBar() {
        let mainMenu = NSMenu()

        // App Menu
        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenuItem.submenu = appMenu

        appMenu.addItem(withTitle: "About Mariner", action: #selector(showAbout), keyEquivalent: "")
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: "Quit Mariner", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        mainMenu.addItem(appMenuItem)

        // File Menu
        let fileMenuItem = NSMenuItem()
        let fileMenu = NSMenu(title: "File")
        fileMenuItem.submenu = fileMenu

        fileMenu.addItem(withTitle: "Open...", action: #selector(NSDocumentController.openDocument(_:)), keyEquivalent: "o")
        fileMenu.addItem(NSMenuItem.separator())
        fileMenu.addItem(withTitle: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")

        mainMenu.addItem(fileMenuItem)

        // Edit Menu
        let editMenuItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenuItem.submenu = editMenu

        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")

        mainMenu.addItem(editMenuItem)

        // Window Menu
        let windowMenuItem = NSMenuItem()
        let windowMenu = NSMenu(title: "Window")
        windowMenuItem.submenu = windowMenu

        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.miniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "Zoom", action: #selector(NSWindow.zoom(_:)), keyEquivalent: "")

        mainMenu.addItem(windowMenuItem)

        NSApp.mainMenu = mainMenu
    }

    @objc func showAbout() {
        let alert = NSAlert()
        alert.messageText = "Mariner"
        alert.informativeText = "A native macOS markdown viewer with GitHub-style rendering.\n\nVersion 1.0"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Keep app running like TextEdit, Pages, etc.
        return false
    }
}

// MARK: - GitHub CSS

let githubMarkdownCSS = """
body {
    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Helvetica, Arial, sans-serif;
    font-size: 16px;
    line-height: 1.5;
    color: #24292e;
    background-color: #ffffff;
    margin: 0;
    padding: 0;
}

.markdown-body {
    box-sizing: border-box;
    min-width: 200px;
    max-width: 980px;
    margin: 0 auto;
    padding: 45px;
}

.markdown-body h1, .markdown-body h2, .markdown-body h3,
.markdown-body h4, .markdown-body h5, .markdown-body h6 {
    margin-top: 24px;
    margin-bottom: 16px;
    font-weight: 600;
    line-height: 1.25;
}

.markdown-body h1 {
    font-size: 2em;
    border-bottom: 1px solid #eaecef;
    padding-bottom: .3em;
}

.markdown-body h2 {
    font-size: 1.5em;
    border-bottom: 1px solid #eaecef;
    padding-bottom: .3em;
}

.markdown-body h3 { font-size: 1.25em; }
.markdown-body h4 { font-size: 1em; }
.markdown-body h5 { font-size: .875em; }
.markdown-body h6 { font-size: .85em; color: #6a737d; }

.markdown-body p {
    margin-top: 0;
    margin-bottom: 16px;
}

.markdown-body a {
    color: #0366d6;
    text-decoration: none;
}

.markdown-body a:hover {
    text-decoration: underline;
}

.markdown-body code {
    padding: .2em .4em;
    margin: 0;
    font-size: 85%;
    background-color: rgba(27, 31, 35, 0.05);
    border-radius: 3px;
    font-family: "SFMono-Regular", Consolas, "Liberation Mono", Menlo, monospace;
}

.markdown-body pre {
    padding: 16px;
    overflow: auto;
    font-size: 85%;
    line-height: 1.45;
    background-color: #f6f8fa;
    border-radius: 3px;
    margin-bottom: 16px;
}

.markdown-body pre code {
    display: inline;
    padding: 0;
    margin: 0;
    overflow: visible;
    line-height: inherit;
    background-color: transparent;
    border: 0;
}

.markdown-body ul, .markdown-body ol {
    padding-left: 2em;
    margin-top: 0;
    margin-bottom: 16px;
}

.markdown-body li {
    margin-bottom: 0.25em;
}

/* Task list styling - target any li containing a checkbox */
.markdown-body li:has(> input[type="checkbox"]) {
    list-style-type: none;
}

.markdown-body li > input[type="checkbox"] {
    margin-right: 0.5em;
    margin-left: -2.2em;
    vertical-align: middle;
    width: 16px;
    height: 16px;
    cursor: default;
}

.markdown-body li > input[type="checkbox"]:checked {
    background-color: #0366d6;
    border-color: #0366d6;
}

.markdown-body blockquote {
    padding: 0 1em;
    color: #6a737d;
    border-left: 0.25em solid #dfe2e5;
    margin: 0 0 16px 0;
}

.markdown-body hr {
    height: 0.25em;
    padding: 0;
    margin: 24px 0;
    background-color: #e1e4e8;
    border: 0;
}

.markdown-body img {
    max-width: 100%;
    box-sizing: content-box;
}

.markdown-body strong {
    font-weight: 600;
}
"""

// MARK: - Main Entry Point

@main
struct MarinerApp {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}
