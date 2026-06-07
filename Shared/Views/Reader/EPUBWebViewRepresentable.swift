import SwiftUI
import WebKit

// MARK: - Platform Type Aliases

#if os(macOS)
typealias PlatformViewRepresentable = NSViewRepresentable
#else
typealias PlatformViewRepresentable = UIViewRepresentable
#endif

// MARK: - WebView Representable

/// Context menu action types for text selection
enum SelectionContextAction {
    case highlight
    case annotateWithAI
    case annotateWithCustomPrompt(String)
    case copy
}

struct EPUBWebViewRepresentable: PlatformViewRepresentable {
    let html: String
    let highlights: [Highlight]
    let marginNotes: [MarginNoteData]
    let customCSS: String?
    let onTextSelected: (SelectionData) -> Void
    let onHighlightTapped: (UUID) -> Void
    let onMarginNoteAction: ((MarginNoteAction) -> Void)?
    let onSearchResults: ((Int, Int) -> Void)?
    let onContentLoaded: (() -> Void)?
    /// Reports the chapter index, scroll position (0–1), and an optional
    /// element-level CFI for the top of the viewport. The CFI is `nil`
    /// when the page is empty or no candidate element is near the top.
    let onVisibleSection: ((Int, Double, String?) -> Void)?
    let onContextMenuAction: ((SelectionData, SelectionContextAction) -> Void)?
    /// Called when the user clicks an internal hyperlink inside the
    /// rendered EPUB. The path is the link's `lastPathComponent` (so
    /// callers can match against `Chapter.filePath` regardless of
    /// whether the link was relative or absolute against the bundle
    /// base URL). Fragment is the bare anchor, no leading `#`.
    var onInternalLink: ((_ path: String, _ fragment: String?) -> Void)? = nil

    func makeCoordinator() -> WebViewCoordinator {
        WebViewCoordinator(
            onTextSelected: onTextSelected,
            onHighlightTapped: onHighlightTapped,
            onMarginNoteAction: onMarginNoteAction,
            onContextMenuAction: onContextMenuAction,
            onSearchResults: onSearchResults,
            onContentLoaded: onContentLoaded,
            onVisibleSection: onVisibleSection,
            onInternalLink: onInternalLink
        )
    }

    #if os(macOS)
    func makeNSView(context: Context) -> WKWebView {
        makeWebView(context: context)
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        updateWebView(webView, context: context)
    }
    #else
    func makeUIView(context: Context) -> WKWebView {
        makeWebView(context: context)
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        updateWebView(webView, context: context)
    }
    #endif

    // MARK: - Shared Implementation

    private func makeWebView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.userContentController.add(context.coordinator, name: "textSelection")
        config.userContentController.add(context.coordinator, name: "highlightTapped")
        config.userContentController.add(context.coordinator, name: "marginNoteAction")
        config.userContentController.add(context.coordinator, name: "searchResults")
        config.userContentController.add(context.coordinator, name: "visibleSection")
        config.userContentController.add(context.coordinator, name: "contextMenuRequest")

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator

        // Load HTML with bundle base URL for resource loading
        if let styledHTML = ReaderResources.buildHTML(content: html, customCSS: customCSS),
           let baseURL = ReaderResources.baseURL {
            webView.loadHTMLString(styledHTML, baseURL: baseURL)
        }

        context.coordinator.lastLoadedHTML = html
        context.coordinator.pendingHighlights = highlights
        context.coordinator.pendingMarginNotes = marginNotes
        context.coordinator.webView = webView

        return webView
    }

    private func updateWebView(_ webView: WKWebView, context: Context) {
        // Only reload if the HTML content actually changed or if customCSS changed
        let cssChanged = context.coordinator.lastCustomCSS != customCSS

        if context.coordinator.lastLoadedHTML != html || cssChanged {
            if let styledHTML = ReaderResources.buildHTML(content: html, customCSS: customCSS),
               let baseURL = ReaderResources.baseURL {
                webView.loadHTMLString(styledHTML, baseURL: baseURL)
            }
            context.coordinator.lastLoadedHTML = html
            context.coordinator.lastCustomCSS = customCSS
            context.coordinator.pendingHighlights = highlights
            context.coordinator.pendingMarginNotes = marginNotes
            context.coordinator.highlightsApplied = []
        } else if Set(context.coordinator.highlightsApplied) != Set(highlights.compactMap { $0.cfiRange != nil ? $0.id : nil }) {
            // Highlights changed but HTML didn't - apply new highlights
            context.coordinator.pendingHighlights = highlights
            context.coordinator.pendingMarginNotes = marginNotes
            let currentMarginNotes = marginNotes
            context.coordinator.applyHighlights(highlights, to: webView) {
                context.coordinator.updateMarginNotes(currentMarginNotes)
                context.coordinator.lastMarginNotes = currentMarginNotes
            }
            return
        }

        // Update margin notes if they changed
        if context.coordinator.lastMarginNotes != marginNotes {
            context.coordinator.updateMarginNotes(marginNotes)
            context.coordinator.lastMarginNotes = marginNotes
        }
    }
}

// MARK: - Coordinator

class WebViewCoordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
    let onTextSelected: (SelectionData) -> Void
    let onHighlightTapped: (UUID) -> Void
    let onMarginNoteAction: ((MarginNoteAction) -> Void)?
    let onSearchResults: ((Int, Int) -> Void)?
    let onContentLoaded: (() -> Void)?
    let onVisibleSection: ((Int, Double, String?) -> Void)?
    let onContextMenuAction: ((SelectionData, SelectionContextAction) -> Void)?
    let onInternalLink: ((String, String?) -> Void)?

    var lastLoadedHTML: String = ""
    var lastCustomCSS: String? = nil
    var pendingHighlights: [Highlight] = []
    var pendingMarginNotes: [MarginNoteData] = []
    var highlightsApplied: [UUID] = []
    var lastMarginNotes: [MarginNoteData] = []
    weak var webView: WKWebView?
    
    // Store pending selection for context menu
    var pendingContextSelection: SelectionData?

    init(
        onTextSelected: @escaping (SelectionData) -> Void,
        onHighlightTapped: @escaping (UUID) -> Void,
        onMarginNoteAction: ((MarginNoteAction) -> Void)?,
        onContextMenuAction: ((SelectionData, SelectionContextAction) -> Void)?,
        onSearchResults: ((Int, Int) -> Void)?,
        onContentLoaded: (() -> Void)?,
        onVisibleSection: ((Int, Double, String?) -> Void)?,
        onInternalLink: ((String, String?) -> Void)?
    ) {
        self.onTextSelected = onTextSelected
        self.onHighlightTapped = onHighlightTapped
        self.onMarginNoteAction = onMarginNoteAction
        self.onContextMenuAction = onContextMenuAction
        self.onSearchResults = onSearchResults
        self.onContentLoaded = onContentLoaded
        self.onVisibleSection = onVisibleSection
        self.onInternalLink = onInternalLink
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        // Allow the initial HTML-string load and any same-document
        // anchor jumps the system handles itself. Only intercept user
        // link activations.
        guard navigationAction.navigationType == .linkActivated,
              let url = navigationAction.request.url else {
            decisionHandler(.allow)
            return
        }

        // External links (https://...) — open in the default browser
        // instead of replacing the EPUB view.
        if let scheme = url.scheme?.lowercased(),
           scheme == "http" || scheme == "https" {
            decisionHandler(.cancel)
            #if os(macOS)
            NSWorkspace.shared.open(url)
            #else
            UIApplication.shared.open(url)
            #endif
            return
        }

        // Internal EPUB link. The bundle base URL gives the link a
        // file:// scheme; we only care about the path's last
        // component (e.g., "chapter02.xhtml") and the fragment so the
        // host can match against Chapter.filePath.
        decisionHandler(.cancel)
        let path = url.lastPathComponent
        let fragment = url.fragment
        DispatchQueue.main.async {
            self.onInternalLink?(path, fragment)
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        applyHighlights(pendingHighlights, to: webView) { [weak self] in
            self?.updateMarginNotes(self?.pendingMarginNotes ?? [])
            DispatchQueue.main.async {
                self?.onContentLoaded?()
            }
        }
    }

    func applyHighlights(_ highlights: [Highlight], to webView: WKWebView, completion: (() -> Void)? = nil) {
        let highlightsWithCFI = highlights.compactMap { h -> [String: Any]? in
            guard let cfi = h.cfiRange else { return nil }
            return [
                "id": h.id.uuidString,
                "startPath": cfi.startPath,
                "startOffset": cfi.startOffset,
                "endPath": cfi.endPath,
                "endOffset": cfi.endOffset,
                // Carried so the highlighter can re-anchor by text search
                // if the CFI path no longer resolves on a later session.
                "text": h.selectedText
            ]
        }

        guard !highlightsWithCFI.isEmpty,
              let jsonData = try? JSONSerialization.data(withJSONObject: highlightsWithCFI),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            completion?()
            return
        }

        let js = "CruxHighlighter.applyHighlights(\(jsonString));"
        webView.evaluateJavaScript(js) { [weak self] _, error in
            if error == nil {
                self?.highlightsApplied = highlightsWithCFI.compactMap { UUID(uuidString: $0["id"] as? String ?? "") }
            }
            completion?()
        }
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        if message.name == "textSelection", let body = message.body as? [String: Any] {
            guard let text = body["text"] as? String, !text.isEmpty,
                  let startPath = body["startPath"] as? String,
                  let startOffset = body["startOffset"] as? Int,
                  let endPath = body["endPath"] as? String,
                  let endOffset = body["endOffset"] as? Int else { return }

            let context = body["context"] as? String ?? ""
            let images = body["images"] as? [String] ?? []
            let cfiRange = CFIRange(
                startPath: startPath,
                startOffset: startOffset,
                endPath: endPath,
                endOffset: endOffset
            )
            let selectionData = SelectionData(text: text, cfiRange: cfiRange, context: context, images: images)

            DispatchQueue.main.async {
                self.onTextSelected(selectionData)
            }
        } else if message.name == "highlightTapped", let idString = message.body as? String {
            if let uuid = UUID(uuidString: idString) {
                DispatchQueue.main.async {
                    self.onHighlightTapped(uuid)
                }
            }
        } else if message.name == "marginNoteAction", let body = message.body as? [String: Any] {
            guard let action = body["action"] as? String else { return }

            let noteAction: MarginNoteAction
            switch action {
            case "openSettings":
                noteAction = .openSettings
            case "commitHighlight", "startThread", "sendFollowUp", "deleteHighlight":
                guard let idString = body["highlightId"] as? String,
                      let highlightId = UUID(uuidString: idString) else { return }

                switch action {
                case "commitHighlight":
                    noteAction = .commitHighlight(highlightId: highlightId)
                case "startThread":
                    noteAction = .startThread(highlightId: highlightId)
                case "sendFollowUp":
                    let message = body["message"] as? String ?? ""
                    noteAction = .sendFollowUp(highlightId: highlightId, message: message)
                case "deleteHighlight":
                    noteAction = .deleteHighlight(highlightId: highlightId)
                default:
                    return
                }
            default:
                return
            }

            DispatchQueue.main.async {
                self.onMarginNoteAction?(noteAction)
            }
        } else if message.name == "searchResults", let body = message.body as? [String: Any] {
            let matchCount = body["matchCount"] as? Int ?? 0
            let currentIndex = body["currentIndex"] as? Int ?? -1
            DispatchQueue.main.async {
                self.onSearchResults?(matchCount, currentIndex)
            }
        } else if message.name == "visibleSection", let body = message.body as? [String: Any] {
            if let chapterIndex = body["chapterIndex"] as? Int {
                let scrollPosition = body["scrollPosition"] as? Double ?? 0
                let cfi = body["cfi"] as? String
                DispatchQueue.main.async {
                    self.onVisibleSection?(chapterIndex, scrollPosition, cfi)
                }
            }
        } else if message.name == "contextMenuRequest", let body = message.body as? [String: Any] {
            #if os(macOS)
            guard let text = body["text"] as? String, !text.isEmpty,
                  let startPath = body["startPath"] as? String,
                  let startOffset = body["startOffset"] as? Int,
                  let endPath = body["endPath"] as? String,
                  let endOffset = body["endOffset"] as? Int else { return }
            
            let context = body["context"] as? String ?? ""
            let images = body["images"] as? [String] ?? []
            let cfiRange = CFIRange(
                startPath: startPath,
                startOffset: startOffset,
                endPath: endPath,
                endOffset: endOffset
            )
            let selectionData = SelectionData(text: text, cfiRange: cfiRange, context: context, images: images)

            // Store for context menu actions
            self.pendingContextSelection = selectionData
            
            DispatchQueue.main.async {
                self.showContextMenu(for: selectionData)
            }
            #endif
        }
    }
    
    #if os(macOS)
    private func showContextMenu(for selection: SelectionData) {
        guard let webView = webView else { return }
        
        let menu = NSMenu(title: "Selection")
        
        // Highlight action
        let highlightItem = NSMenuItem(title: "Highlight", action: #selector(contextMenuHighlight), keyEquivalent: "")
        highlightItem.target = self
        highlightItem.image = NSImage(systemSymbolName: "highlighter", accessibilityDescription: nil)
        menu.addItem(highlightItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Annotate with AI action
        let annotateItem = NSMenuItem(title: "Annotate with AI", action: #selector(contextMenuAnnotate), keyEquivalent: "")
        annotateItem.target = self
        annotateItem.image = NSImage(systemSymbolName: "sparkles", accessibilityDescription: nil)
        menu.addItem(annotateItem)
        
        // Custom prompt action
        let customPromptItem = NSMenuItem(title: "Annotate with Custom Prompt...", action: #selector(contextMenuCustomPrompt), keyEquivalent: "")
        customPromptItem.target = self
        customPromptItem.image = NSImage(systemSymbolName: "text.bubble", accessibilityDescription: nil)
        menu.addItem(customPromptItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Copy action
        let copyItem = NSMenuItem(title: "Copy", action: #selector(contextMenuCopy), keyEquivalent: "c")
        copyItem.target = self
        copyItem.image = NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: nil)
        menu.addItem(copyItem)
        
        // Show the menu
        let mouseLocation = NSEvent.mouseLocation
        if let window = webView.window {
            let windowPoint = window.convertPoint(fromScreen: mouseLocation)
            let viewPoint = webView.convert(windowPoint, from: nil)
            menu.popUp(positioning: nil, at: viewPoint, in: webView)
        }
    }
    
    @objc private func contextMenuHighlight() {
        guard let selection = pendingContextSelection else { return }
        onContextMenuAction?(selection, .highlight)
        pendingContextSelection = nil
    }
    
    @objc private func contextMenuAnnotate() {
        guard let selection = pendingContextSelection else { return }
        onContextMenuAction?(selection, .annotateWithAI)
        pendingContextSelection = nil
    }
    
    @objc private func contextMenuCustomPrompt() {
        guard let selection = pendingContextSelection else { return }
        
        // Show custom prompt dialog
        let alert = NSAlert()
        alert.messageText = "Custom AI Prompt"
        alert.informativeText = "Enter a custom prompt to guide the AI annotation:"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Annotate")
        alert.addButton(withTitle: "Cancel")
        
        let inputField = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 80))
        inputField.placeholderString = "e.g., Explain the historical context of this passage..."
        inputField.stringValue = ""
        inputField.isEditable = true
        inputField.isBezeled = true
        inputField.bezelStyle = .roundedBezel
        
        // Use a text view for multiline input
        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 350, height: 100))
        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 350, height: 100))
        textView.isEditable = true
        textView.isRichText = false
        textView.font = NSFont.systemFont(ofSize: 13)
        textView.textContainerInset = NSSize(width: 8, height: 8)
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .bezelBorder
        
        alert.accessoryView = scrollView
        
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            let customPrompt = textView.string.trimmingCharacters(in: .whitespacesAndNewlines)
            if !customPrompt.isEmpty {
                onContextMenuAction?(selection, .annotateWithCustomPrompt(customPrompt))
            }
        }
        
        pendingContextSelection = nil
    }
    
    @objc private func contextMenuCopy() {
        guard let selection = pendingContextSelection else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(selection.text, forType: .string)
        onContextMenuAction?(selection, .copy)
        pendingContextSelection = nil
    }
    #endif

    func initViewportTracking(chapters: [Chapter], currentFilePath: String) {
        var anchors: [[String: Any]] = []

        for (index, chapter) in chapters.enumerated() {
            guard chapter.filePath == currentFilePath else { continue }

            if let fragment = chapter.fragment {
                anchors.append(["id": fragment, "chapterIndex": index, "isFileStart": false])
            } else {
                anchors.append(["id": "__crux_doc_start__", "chapterIndex": index, "isFileStart": true])
            }
        }

        guard !anchors.isEmpty,
              let jsonData = try? JSONSerialization.data(withJSONObject: anchors),
              let jsonString = String(data: jsonData, encoding: .utf8) else { return }

        webView?.evaluateJavaScript("CruxViewportTracker.init(\(jsonString));", completionHandler: nil)
    }

    func updateMarginNotes(_ notes: [MarginNoteData]) {
        guard let webView = webView,
              let jsonData = try? JSONEncoder().encode(notes),
              let jsonString = String(data: jsonData, encoding: .utf8) else { return }

        let js = "CruxMarginNotes.updateNotes(\(jsonString));"
        webView.evaluateJavaScript(js, completionHandler: nil)
    }
}
