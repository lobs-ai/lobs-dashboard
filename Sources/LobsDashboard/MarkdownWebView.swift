import SwiftUI
import WebKit

// MARK: - Self-Sizing Markdown View

/// A SwiftUI wrapper that renders markdown and automatically expands to fit its content.
/// Uses MarkdownWebView internally but manages height measurement so the web view
/// expands inline within the parent ScrollView instead of creating a separate scroll area.
struct SelfSizingMarkdownView: View {
  let markdown: String
  var minHeight: CGFloat = 20

  @State private var contentHeight: CGFloat = 20

  var body: some View {
    MarkdownWebView(markdown: markdown) { height in
      // Only update if meaningfully different to avoid layout loops
      if abs(height - contentHeight) > 1 {
        contentHeight = height
      }
    }
    .frame(height: max(minHeight, contentHeight))
  }
}

// MARK: - Markdown Web View

/// Renders markdown content using WKWebView for full-fidelity block-level markdown
/// (headers, lists, code blocks, tables, horizontal rules, blockquotes, etc.)
struct MarkdownWebView: NSViewRepresentable {
  let markdown: String
  var onContentHeightChanged: ((CGFloat) -> Void)?

  init(markdown: String, onContentHeightChanged: ((CGFloat) -> Void)? = nil) {
    self.markdown = markdown
    self.onContentHeightChanged = onContentHeightChanged
  }

  func makeNSView(context: Context) -> WKWebView {
    let config = WKWebViewConfiguration()

    // Register message handler for height reporting if callback is provided
    if onContentHeightChanged != nil {
      config.userContentController.add(context.coordinator, name: "heightChanged")
    }

    let webView = WKWebView(frame: .zero, configuration: config)
    webView.setValue(false, forKey: "drawsBackground")
    webView.navigationDelegate = context.coordinator

    // Disable internal scrolling when we're self-sizing
    if onContentHeightChanged != nil {
      webView.enclosingScrollView?.hasVerticalScroller = false
      // For WKWebView, disable scrolling at the scroll view level after it's added
      DispatchQueue.main.async {
        if let scrollView = webView.enclosingScrollView {
          scrollView.hasVerticalScroller = false
          scrollView.hasHorizontalScroller = false
        }
      }
    }

    loadContent(in: webView, measureHeight: onContentHeightChanged != nil)
    return webView
  }

  func updateNSView(_ webView: WKWebView, context: Context) {
    context.coordinator.onContentHeightChanged = onContentHeightChanged
    loadContent(in: webView, measureHeight: onContentHeightChanged != nil)
  }

  func makeCoordinator() -> Coordinator {
    Coordinator(onContentHeightChanged: onContentHeightChanged)
  }

  private func loadContent(in webView: WKWebView, measureHeight: Bool) {
    let escaped = markdown
      .replacingOccurrences(of: "\\", with: "\\\\")
      .replacingOccurrences(of: "`", with: "\\`")
      .replacingOccurrences(of: "$", with: "\\$")
    let html = Self.htmlTemplate(markdownLiteral: escaped, measureHeight: measureHeight)
    webView.loadHTMLString(html, baseURL: nil)
  }

  // MARK: - HTML Template

  /// Generates a self-contained HTML page that parses markdown client-side
  /// using a tiny built-in parser (no external CDN dependency).
  private static func htmlTemplate(markdownLiteral: String, measureHeight: Bool = false) -> String {
    let heightScript = measureHeight ? """
    // Report content height to Swift
    function reportHeight() {
      var height = document.body.scrollHeight;
      if (height > 0) {
        window.webkit.messageHandlers.heightChanged.postMessage(height);
      }
    }
    // Report after render, after images load, and on resize
    reportHeight();
    window.addEventListener('load', reportHeight);
    window.addEventListener('resize', reportHeight);
    // Also observe DOM changes (images loading, etc.)
    new MutationObserver(reportHeight).observe(document.body, {
      childList: true, subtree: true, attributes: true
    });
    // Fallback: re-measure after a short delay for late layout
    setTimeout(reportHeight, 100);
    setTimeout(reportHeight, 500);
    """ : ""

    let overflowStyle = measureHeight ? "overflow: hidden;" : ""

    return """
    <!DOCTYPE html>
    <html>
    <head>
    <meta charset="utf-8">
    <style>
      :root {
        color-scheme: light dark;
      }
      html, body {
        \(overflowStyle)
      }
      body {
        font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", "Helvetica Neue", sans-serif;
        font-size: 13px;
        line-height: 1.6;
        color: var(--text);
        padding: 24px;
        margin: 0;
        background: transparent;
        -webkit-font-smoothing: antialiased;
      }
      @media (prefers-color-scheme: dark) {
        :root {
          --text: #e5e5e7;
          --text-secondary: #98989d;
          --border: rgba(255,255,255,0.1);
          --code-bg: rgba(255,255,255,0.06);
          --blockquote-border: rgba(255,255,255,0.15);
          --link: #64a4ff;
        }
      }
      @media (prefers-color-scheme: light) {
        :root {
          --text: #1d1d1f;
          --text-secondary: #6e6e73;
          --border: rgba(0,0,0,0.1);
          --code-bg: rgba(0,0,0,0.04);
          --blockquote-border: rgba(0,0,0,0.15);
          --link: #0066cc;
        }
      }
      h1 { font-size: 1.7em; font-weight: 700; margin: 0.8em 0 0.4em; }
      h2 { font-size: 1.35em; font-weight: 650; margin: 0.7em 0 0.35em; }
      h3 { font-size: 1.1em; font-weight: 600; margin: 0.6em 0 0.3em; }
      h4, h5, h6 { font-size: 1em; font-weight: 600; margin: 0.5em 0 0.25em; }
      h1:first-child, h2:first-child, h3:first-child { margin-top: 0; }
      p { margin: 0.5em 0; }
      a { color: var(--link); text-decoration: none; }
      a:hover { text-decoration: underline; }
      hr {
        border: none;
        border-top: 1px solid var(--border);
        margin: 1.2em 0;
      }
      ul, ol { padding-left: 1.5em; margin: 0.4em 0; }
      li { margin: 0.15em 0; }
      li > ul, li > ol { margin: 0.1em 0; }
      code {
        font-family: "SF Mono", Menlo, Consolas, monospace;
        font-size: 0.9em;
        background: var(--code-bg);
        padding: 0.15em 0.35em;
        border-radius: 4px;
      }
      pre {
        background: var(--code-bg);
        padding: 12px 16px;
        border-radius: 8px;
        overflow-x: auto;
        margin: 0.6em 0;
      }
      pre code {
        background: none;
        padding: 0;
        font-size: 12px;
        line-height: 1.5;
      }
      blockquote {
        border-left: 3px solid var(--blockquote-border);
        margin: 0.6em 0;
        padding: 0.2em 0 0.2em 1em;
        color: var(--text-secondary);
      }
      table {
        border-collapse: collapse;
        margin: 0.6em 0;
        width: 100%;
      }
      th, td {
        border: 1px solid var(--border);
        padding: 6px 10px;
        text-align: left;
        font-size: 12px;
      }
      th {
        font-weight: 600;
        background: var(--code-bg);
      }
      strong { font-weight: 600; }
      em { font-style: italic; }
      img { max-width: 100%; border-radius: 6px; }
    </style>
    </head>
    <body>
    <div id="content"></div>
    <script>
    // Minimal markdown → HTML parser (no dependencies)
    function md(src) {
      // Normalize line endings
      src = src.replace(/\\r\\n/g, '\\n');

      var lines = src.split('\\n');
      var html = [];
      var inCode = false, codeLang = '', codeLines = [];
      var inList = false, listType = '';
      var inBlockquote = false, bqLines = [];
      var inTable = false, tableRows = [];

      function inline(t) {
        // Images
        t = t.replace(/!\\[([^\\]]*)\\]\\(([^)]+)\\)/g, '<img alt="$1" src="$2">');
        // Links
        t = t.replace(/\\[([^\\]]*)\\]\\(([^)]+)\\)/g, '<a href="$2" target="_blank">$1</a>');
        // Bold+italic
        t = t.replace(/\\*\\*\\*(.+?)\\*\\*\\*/g, '<strong><em>$1</em></strong>');
        // Bold
        t = t.replace(/\\*\\*(.+?)\\*\\*/g, '<strong>$1</strong>');
        t = t.replace(/__(.+?)__/g, '<strong>$1</strong>');
        // Italic
        t = t.replace(/\\*(.+?)\\*/g, '<em>$1</em>');
        t = t.replace(/_([^_]+)_/g, '<em>$1</em>');
        // Strikethrough
        t = t.replace(/~~(.+?)~~/g, '<del>$1</del>');
        // Inline code
        t = t.replace(/`([^`]+)`/g, '<code>$1</code>');
        return t;
      }

      function flushList() {
        if (inList) { html.push('</' + listType + '>'); inList = false; }
      }
      function flushBlockquote() {
        if (inBlockquote) {
          html.push('<blockquote>' + md(bqLines.join('\\n')) + '</blockquote>');
          bqLines = []; inBlockquote = false;
        }
      }
      function flushTable() {
        if (!inTable) return;
        var out = '<table>';
        for (var r = 0; r < tableRows.length; r++) {
          // Skip separator row
          if (r === 1 && /^[\\s|:-]+$/.test(tableRows[r])) continue;
          var tag = r === 0 ? 'th' : 'td';
          var cells = tableRows[r].replace(/^\\|/, '').replace(/\\|$/, '').split('|');
          out += '<tr>';
          for (var c = 0; c < cells.length; c++) {
            out += '<' + tag + '>' + inline(cells[c].trim()) + '</' + tag + '>';
          }
          out += '</tr>';
        }
        out += '</table>';
        html.push(out);
        tableRows = []; inTable = false;
      }

      for (var i = 0; i < lines.length; i++) {
        var line = lines[i];

        // Fenced code blocks
        if (/^```/.test(line.trim())) {
          if (!inCode) {
            flushList(); flushBlockquote(); flushTable();
            inCode = true;
            codeLang = line.trim().slice(3).trim();
            codeLines = [];
          } else {
            var escaped = codeLines.join('\\n')
              .replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;');
            html.push('<pre><code>' + escaped + '</code></pre>');
            inCode = false;
          }
          continue;
        }
        if (inCode) { codeLines.push(line); continue; }

        var trimmed = line.trim();

        // Blockquote
        if (/^>\\s?/.test(trimmed)) {
          flushList(); flushTable();
          inBlockquote = true;
          bqLines.push(trimmed.replace(/^>\\s?/, ''));
          continue;
        } else {
          flushBlockquote();
        }

        // Table detection
        if (/^\\|/.test(trimmed) && trimmed.indexOf('|', 1) > 0) {
          flushList(); flushBlockquote();
          inTable = true;
          tableRows.push(trimmed);
          continue;
        } else {
          flushTable();
        }

        // Blank line
        if (trimmed === '') { flushList(); html.push(''); continue; }

        // Headings
        var hm = trimmed.match(/^(#{1,6})\\s+(.*)/);
        if (hm) {
          flushList();
          var lvl = hm[1].length;
          html.push('<h' + lvl + '>' + inline(hm[2]) + '</h' + lvl + '>');
          continue;
        }

        // Horizontal rule
        if (/^(---+|\\*\\*\\*+|___+)$/.test(trimmed)) {
          flushList();
          html.push('<hr>');
          continue;
        }

        // Unordered list
        if (/^[-*+]\\s+/.test(trimmed)) {
          if (!inList || listType !== 'ul') { flushList(); html.push('<ul>'); inList = true; listType = 'ul'; }
          html.push('<li>' + inline(trimmed.replace(/^[-*+]\\s+/, '')) + '</li>');
          continue;
        }

        // Ordered list
        if (/^\\d+\\.\\s+/.test(trimmed)) {
          if (!inList || listType !== 'ol') { flushList(); html.push('<ol>'); inList = true; listType = 'ol'; }
          html.push('<li>' + inline(trimmed.replace(/^\\d+\\.\\s+/, '')) + '</li>');
          continue;
        }

        flushList();

        // Paragraph
        html.push('<p>' + inline(trimmed) + '</p>');
      }

      // Flush any remaining state
      flushList(); flushBlockquote(); flushTable();
      if (inCode) {
        var escaped = codeLines.join('\\n')
          .replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;');
        html.push('<pre><code>' + escaped + '</code></pre>');
      }

      return html.join('\\n');
    }

    var raw = `\(markdownLiteral)`;
    document.getElementById('content').innerHTML = md(raw);
    \(heightScript)
    </script>
    </body>
    </html>
    """
  }

  // MARK: - Coordinator

  class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
    var onContentHeightChanged: ((CGFloat) -> Void)?

    init(onContentHeightChanged: ((CGFloat) -> Void)?) {
      self.onContentHeightChanged = onContentHeightChanged
    }

    // MARK: WKScriptMessageHandler

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
      if message.name == "heightChanged", let height = message.body as? CGFloat, height > 0 {
        DispatchQueue.main.async { [weak self] in
          self?.onContentHeightChanged?(height)
        }
      }
    }

    // MARK: WKNavigationDelegate

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
      // Open links in the default browser instead of navigating within the web view
      if navigationAction.navigationType == .linkActivated, let url = navigationAction.request.url {
        NSWorkspace.shared.open(url)
        decisionHandler(.cancel)
        return
      }
      decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
      // After navigation finishes, disable internal scrolling if we're measuring height
      guard onContentHeightChanged != nil else { return }
      if let scrollView = webView.enclosingScrollView {
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
      }
    }
  }
}
