import SwiftUI

// MARK: - Native Markdown Text

/// Renders markdown using native SwiftUI Text, avoiding WKWebView scroll issues.
/// Handles block-level elements (headings, lists, code blocks, HRs) by splitting
/// into separate Text/view elements, with inline markdown handled by AttributedString.
///
/// This is significantly lighter than WKWebView-based rendering and doesn't capture
/// scroll events, making it ideal for use within ScrollViews.
struct NativeMarkdownText: View {
  let markdown: String

  private enum Block: Identifiable {
    case text(String)
    case heading(Int, String)
    case code(String)
    case hr
    case listItem(String)

    var id: String {
      switch self {
      case .text(let s): return "t:\(s.prefix(40).hashValue)"
      case .heading(let l, let s): return "h\(l):\(s.prefix(40).hashValue)"
      case .code(let s): return "c:\(s.prefix(40).hashValue)"
      case .hr: return "hr:\(UUID().uuidString)"
      case .listItem(let s): return "li:\(s.prefix(40).hashValue)"
      }
    }
  }

  private var blocks: [Block] {
    var result: [Block] = []
    let lines = markdown.components(separatedBy: "\n")
    var i = 0
    var textBuffer: [String] = []

    func flushText() {
      let joined = textBuffer.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
      if !joined.isEmpty { result.append(.text(joined)) }
      textBuffer = []
    }

    while i < lines.count {
      let line = lines[i]
      let trimmed = line.trimmingCharacters(in: .whitespaces)

      // Fenced code block
      if trimmed.hasPrefix("```") {
        flushText()
        var codeLines: [String] = []
        i += 1
        while i < lines.count && !lines[i].trimmingCharacters(in: .whitespaces).hasPrefix("```") {
          codeLines.append(lines[i])
          i += 1
        }
        result.append(.code(codeLines.joined(separator: "\n")))
        i += 1
        continue
      }

      // Horizontal rule
      if trimmed.range(of: #"^(---+|\*\*\*+|___+)$"#, options: .regularExpression) != nil {
        flushText()
        result.append(.hr)
        i += 1
        continue
      }

      // Headings
      if let match = trimmed.range(of: #"^(#{1,6})\s+(.*)"#, options: .regularExpression) {
        flushText()
        let hashes = trimmed.prefix(while: { $0 == "#" })
        let text = String(trimmed.dropFirst(hashes.count).trimmingCharacters(in: .whitespaces))
        result.append(.heading(hashes.count, text))
        i += 1
        continue
      }

      // List items
      if trimmed.range(of: #"^[-*+]\s+"#, options: .regularExpression) != nil {
        flushText()
        let content = String(trimmed.drop(while: { $0 == "-" || $0 == "*" || $0 == "+" || $0 == " " }))
        result.append(.listItem(content))
        i += 1
        continue
      }
      if trimmed.range(of: #"^\d+\.\s+"#, options: .regularExpression) != nil {
        flushText()
        let content = String(trimmed.drop(while: { $0.isNumber || $0 == "." || $0 == " " }))
        result.append(.listItem(content))
        i += 1
        continue
      }

      textBuffer.append(line)
      i += 1
    }
    flushText()
    return blocks
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
        switch block {
        case .text(let str):
          inlineMarkdown(str)
            .font(.body)

        case .heading(let level, let str):
          inlineMarkdown(str)
            .font(level == 1 ? .title2 : (level == 2 ? .title3 : .headline))
            .fontWeight(.bold)
            .padding(.top, level <= 2 ? 8 : 4)

        case .code(let str):
          Text(str)
            .font(.system(size: 12, design: .monospaced))
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.subtle)
            .clipShape(RoundedRectangle(cornerRadius: 6))

        case .hr:
          Divider().padding(.vertical, 4)

        case .listItem(let str):
          HStack(alignment: .top, spacing: 6) {
            Text("•").foregroundStyle(.secondary)
            inlineMarkdown(str).font(.body)
          }
        }
      }
    }
  }

  /// Render inline markdown (bold, italic, links, code) via AttributedString
  @ViewBuilder
  private func inlineMarkdown(_ text: String) -> some View {
    if let attr = try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
      Text(attr)
    } else {
      Text(text)
    }
  }
}
