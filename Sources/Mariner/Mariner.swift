import Cocoa
import WebKit
import Markdown

class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    var webView: WKWebView!
    var currentFilePath: String?
    var fileSystemSource: DispatchSourceFileSystemObject?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Setup menu bar
        setupMenuBar()

        // Create window
        let windowRect = NSRect(x: 100, y: 100, width: 900, height: 700)
        window = NSWindow(
            contentRect: windowRect,
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Mariner - Markdown Viewer"
        window.center()

        // Create WKWebView
        webView = WKWebView(frame: window.contentView!.bounds)
        webView.autoresizingMask = [.width, .height]
        window.contentView?.addSubview(webView)

        // Show window
        window.makeKeyAndOrderFront(nil)

        // Activate app
        NSApp.activate(ignoringOtherApps: true)

        // Show file picker
        showFilePicker()
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

        fileMenu.addItem(withTitle: "Open...", action: #selector(openFile), keyEquivalent: "o")
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

    @objc func openFile() {
        showFilePicker()
    }

    @objc func showAbout() {
        let alert = NSAlert()
        alert.messageText = "Mariner"
        alert.informativeText = "A native macOS markdown viewer with GitHub-style rendering.\n\nVersion 1.0"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    func showFilePicker() {
        let openPanel = NSOpenPanel()
        openPanel.title = "Choose a Markdown file"
        openPanel.allowedFileTypes = ["md"]
        openPanel.allowsMultipleSelection = false
        openPanel.canChooseDirectories = false

        openPanel.begin { [weak self] response in
            if response == .OK, let url = openPanel.url {
                self?.loadMarkdownFile(at: url.path)
            }
        }
    }

    func loadMarkdownFile(at path: String) {
        currentFilePath = path
        window.title = "Mariner - \((path as NSString).lastPathComponent)"

        // Stop watching previous file
        fileSystemSource?.cancel()

        // Render markdown
        renderMarkdown(at: path)

        // Start watching file for changes
        watchFile(at: path)
    }

    func renderMarkdown(at path: String, retryCount: Int = 0) {
        guard let content = try? String(contentsOfFile: path, encoding: .utf8) else {
            // If we fail to read, retry up to 3 times with increasing delays
            if retryCount < 3 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05 * Double(retryCount + 1)) {
                    self.renderMarkdown(at: path, retryCount: retryCount + 1)
                }
            } else {
                webView.loadHTMLString("<h1>Error</h1><p>Could not read file</p>", baseURL: nil)
            }
            return
        }

        // Parse markdown using swift-markdown
        let document = Document(parsing: content)
        let html = HTMLRenderer.renderHTML(from: document)

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

        webView.loadHTMLString(fullHTML, baseURL: nil)
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
                self?.renderMarkdown(at: path)
            }
        }

        source.setCancelHandler {
            close(fileDescriptor)
        }

        source.resume()
        fileSystemSource = source
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
}

// Simple HTML renderer for swift-markdown
struct HTMLRenderer {
    static func renderHTML(from document: Document) -> String {
        var html = ""

        for child in document.children {
            html += renderBlock(child)
        }

        return html
    }

    static func renderBlock(_ markup: Markup) -> String {
        switch markup {
        case let heading as Heading:
            let level = heading.level
            let content = renderInlineChildren(heading)
            return "<h\(level)>\(content)</h\(level)>\n"

        case let paragraph as Paragraph:
            let content = renderInlineChildren(paragraph)
            return "<p>\(content)</p>\n"

        case let list as UnorderedList:
            var items = ""
            for item in list.listItems {
                items += "<li>\(renderInlineChildren(item))</li>\n"
            }
            return "<ul>\n\(items)</ul>\n"

        case let list as OrderedList:
            var items = ""
            for item in list.listItems {
                items += "<li>\(renderInlineChildren(item))</li>\n"
            }
            return "<ol>\n\(items)</ol>\n"

        case let code as CodeBlock:
            let language = code.language ?? ""
            let codeContent = code.code.trimmingCharacters(in: .newlines)
            return "<pre><code class=\"language-\(language)\">\(escapeHTML(codeContent))</code></pre>\n"

        case let quote as BlockQuote:
            var content = ""
            for child in quote.children {
                content += renderBlock(child)
            }
            return "<blockquote>\n\(content)</blockquote>\n"

        case _ as ThematicBreak:
            return "<hr>\n"

        default:
            var content = ""
            for child in markup.children {
                content += renderBlock(child)
            }
            return content
        }
    }

    static func renderInlineChildren(_ markup: Markup) -> String {
        var html = ""
        for child in markup.children {
            html += renderInline(child)
        }
        return html
    }

    static func renderInline(_ markup: Markup) -> String {
        switch markup {
        case let text as Text:
            return escapeHTML(text.string)

        case let strong as Strong:
            return "<strong>\(renderInlineChildren(strong))</strong>"

        case let emphasis as Emphasis:
            return "<em>\(renderInlineChildren(emphasis))</em>"

        case let code as InlineCode:
            return "<code>\(escapeHTML(code.code))</code>"

        case let link as Link:
            let destination = link.destination ?? ""
            return "<a href=\"\(escapeHTML(destination))\">\(renderInlineChildren(link))</a>"

        case let image as Image:
            let source = image.source ?? ""
            let title = image.title ?? ""
            return "<img src=\"\(escapeHTML(source))\" alt=\"\(renderInlineChildren(image))\" title=\"\(escapeHTML(title))\">"

        case _ as LineBreak:
            return "<br>"

        case _ as SoftBreak:
            return " "

        default:
            return renderInlineChildren(markup)
        }
    }

    static func escapeHTML(_ string: String) -> String {
        return string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }
}

// GitHub Markdown CSS (minimal version for now)
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

// Main entry point
@main
struct MarinerApp {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}
