import Cocoa
import WebKit
import cmark_gfm
import cmark_gfm_extensions

// MARK: - Markdown Document

@objc(MarkdownDocument)
class MarkdownDocument: NSDocument, WKNavigationDelegate {
    var webView: WKWebView!
    var fileSystemSource: DispatchSourceFileSystemObject?
    var markdownContent: String = ""
    var savedScrollPosition: CGFloat = 0
    var isInitialLoad = true

    override class var autosavesInPlace: Bool {
        return false
    }

    override class var readableTypes: [String] {
        return ["net.daringfireball.markdown"]
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
        webView.navigationDelegate = self
        webView.autoresizingMask = [.width, .height]
        window.contentView?.addSubview(webView)

        let windowController = NSWindowController(window: window)
        addWindowController(windowController)

        // Show the window
        windowController.showWindow(nil)
        window.center()

        // Set window title
        updateWindowTitle()

        // Load saved scroll position from UserDefaults
        if let fileURL = fileURL {
            let key = "scroll_\(fileURL.path)"
            savedScrollPosition = CGFloat(UserDefaults.standard.double(forKey: key))
        }

        // Render initial content
        renderMarkdown()

        // Start watching file for changes
        if let fileURL = fileURL {
            watchFile(at: fileURL.path)
        }

        // Update recent files menu after document is opened
        if let appDelegate = NSApp.delegate as? AppDelegate {
            DispatchQueue.main.async {
                appDelegate.updateRecentFilesMenu()
            }
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

            // Render to HTML with extensions
            let extensions = cmark_parser_get_syntax_extensions(parser)
            let htmlCString = cmark_render_html(document, CMARK_OPT_DEFAULT, extensions)
            defer { free(htmlCString) }
            return String(cString: htmlCString!)
        }

        // Convert local images to base64 data URLs
        let htmlWithEmbeddedImages = embedLocalImages(html: html, baseDirectory: url.deletingLastPathComponent())

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
                \(htmlWithEmbeddedImages)
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

        // Save scroll position before reloading (but not on initial load)
        if isInitialLoad {
            isInitialLoad = false
            // Load HTML with baseURL set to the markdown's directory
            // This allows loading remote images (http/https) while base64 handles local images
            webView?.loadHTMLString(fullHTML, baseURL: url.deletingLastPathComponent())
        } else {
            webView?.evaluateJavaScript("window.pageYOffset") { [weak self] result, error in
                if let scrollY = result as? CGFloat {
                    self?.savedScrollPosition = scrollY
                }

                // Load HTML with baseURL set to the markdown's directory
                // This allows loading remote images (http/https) while base64 handles local images
                self?.webView?.loadHTMLString(fullHTML, baseURL: url.deletingLastPathComponent())
            }
        }
    }

    func embedLocalImages(html: String, baseDirectory: URL) -> String {
        var processedHTML = html

        // Pattern to match img tags with src attributes
        let pattern = #"<img\s+[^>]*src="([^"]+)"[^>]*>"#

        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return html
        }

        let matches = regex.matches(in: html, options: [], range: NSRange(html.startIndex..., in: html))

        // Process matches in reverse to maintain string indices
        for match in matches.reversed() {
            if match.numberOfRanges >= 2 {
                let srcRange = match.range(at: 1)
                if let range = Range(srcRange, in: html) {
                    let imagePath = String(html[range])

                    // Skip if it's already a URL (http://, https://, data:)
                    if imagePath.hasPrefix("http://") ||
                       imagePath.hasPrefix("https://") ||
                       imagePath.hasPrefix("data:") {
                        continue
                    }

                    // Construct full path to image
                    let imageURL = baseDirectory.appendingPathComponent(imagePath)

                    // Convert to base64 if file exists
                    if let imageData = try? Data(contentsOf: imageURL),
                       let base64String = imageData.base64EncodedString() as String? {

                        // Determine MIME type from file extension
                        let ext = imageURL.pathExtension.lowercased()
                        let mimeType: String
                        switch ext {
                        case "jpg", "jpeg": mimeType = "image/jpeg"
                        case "png": mimeType = "image/png"
                        case "gif": mimeType = "image/gif"
                        case "svg": mimeType = "image/svg+xml"
                        case "webp": mimeType = "image/webp"
                        default: mimeType = "image/png"
                        }

                        let dataURL = "data:\(mimeType);base64,\(base64String)"

                        // Replace the src value
                        if let htmlRange = Range(srcRange, in: processedHTML) {
                            processedHTML.replaceSubrange(htmlRange, with: dataURL)
                        }
                    }
                }
            }
        }

        return processedHTML
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
            guard let self = self else { return }

            let flags = source.data

            // Add a small delay to let the file finish writing
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self.renderMarkdown()

                // If file was deleted or renamed, re-establish watch
                if flags.contains(.delete) || flags.contains(.rename) {
                    self.fileSystemSource?.cancel()
                    self.fileSystemSource = nil
                    if let fileURL = self.fileURL {
                        self.watchFile(at: fileURL.path)
                    }
                }
            }
        }

        source.setCancelHandler {
            Darwin.close(fileDescriptor)
        }

        source.resume()
        fileSystemSource = source
    }

    func saveScrollPosition() {
        // Save current scroll position to UserDefaults asynchronously
        guard let fileURL = fileURL else { return }

        webView?.evaluateJavaScript("window.pageYOffset") { [weak self] result, error in
            if let scrollY = result as? CGFloat {
                let key = "scroll_\(fileURL.path)"
                UserDefaults.standard.set(Double(scrollY), forKey: key)
                self?.savedScrollPosition = scrollY
            }
        }
    }

    override func close() {
        fileSystemSource?.cancel()
        fileSystemSource = nil
        super.close()
    }

    // MARK: - WKNavigationDelegate

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        // Allow initial HTML load
        if navigationAction.navigationType == .other {
            decisionHandler(.allow)
            return
        }

        // Open links in default browser
        if navigationAction.navigationType == .linkActivated,
           let url = navigationAction.request.url {
            NSWorkspace.shared.open(url)
            decisionHandler(.cancel)
            return
        }

        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // Restore scroll position after page loads
        if savedScrollPosition > 0 {
            webView.evaluateJavaScript("window.scrollTo(0, \(savedScrollPosition))")
        }
    }
}

// MARK: - App Delegate

class AppDelegate: NSObject, NSApplicationDelegate {
    var recentFilesMenu: NSMenu?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Setup menu bar
        setupMenuBar()
    }

    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool {
        // Show open panel if no documents were restored
        NSDocumentController.shared.openDocument(nil)
        return false
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Save scroll positions for all open documents before quitting
        for document in NSDocumentController.shared.documents {
            if let markdownDoc = document as? MarkdownDocument {
                markdownDoc.saveScrollPosition()
            }
        }

        // Run the runloop briefly to allow async JavaScript calls to complete
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.1))

        // Force UserDefaults to save immediately
        UserDefaults.standard.synchronize()
    }

    func updateRecentFilesMenu() {
        guard let menu = recentFilesMenu else { return }

        // Remove all existing items except Clear Menu
        while menu.items.count > 1 {
            menu.removeItem(at: 0)
        }

        // Add recent document menu items
        let urls = NSDocumentController.shared.recentDocumentURLs
        for url in urls {
            let item = NSMenuItem(title: url.lastPathComponent, action: #selector(AppDelegate.openRecentDocument(_:)), keyEquivalent: "")
            item.representedObject = url
            item.target = self
            menu.insertItem(item, at: menu.items.count - 1)
        }

        // Add separator if there are recent files
        if !urls.isEmpty {
            menu.insertItem(NSMenuItem.separator(), at: menu.items.count - 1)
        }
    }

    @objc func openRecentDocument(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, _ in }
    }

    @objc func clearRecentDocuments(_ sender: Any) {
        NSDocumentController.shared.clearRecentDocuments(sender)
        updateRecentFilesMenu()
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

        // Open Recent submenu
        fileMenu.addItem(NSMenuItem.separator())

        // Create Open Recent menu with standard setup
        let openRecentMenuItem = NSMenuItem(title: "Open Recent", action: nil, keyEquivalent: "")
        fileMenu.addItem(openRecentMenuItem)

        // Create the submenu
        let openRecentMenu = NSMenu(title: "Open Recent")
        openRecentMenuItem.submenu = openRecentMenu

        // Store reference for updating
        recentFilesMenu = openRecentMenu

        // Add clear menu item (always present)
        let clearItem = openRecentMenu.addItem(withTitle: "Clear Menu", action: #selector(AppDelegate.clearRecentDocuments(_:)), keyEquivalent: "")
        clearItem.target = self

        // Populate with current recent files
        updateRecentFilesMenu()

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

/* Standalone images (like logos) in their own paragraph */
.markdown-body p > img:only-child {
    display: block;
    margin: 0 auto;
}

.markdown-body strong {
    font-weight: 600;
}

.markdown-body table {
    border-spacing: 0;
    border-collapse: collapse;
    margin-top: 0;
    margin-bottom: 16px;
}

.markdown-body table th,
.markdown-body table td {
    padding: 6px 13px;
    border: 1px solid #dfe2e5;
}

.markdown-body table th {
    font-weight: 600;
    background-color: #f6f8fa;
}

.markdown-body table tr {
    background-color: #ffffff;
    border-top: 1px solid #c6cbd1;
}

.markdown-body table tr:nth-child(2n) {
    background-color: #f6f8fa;
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
