import SwiftUI
import AppKit

/// A multi-line text editor that explicitly enables macOS native spell checking.
/// Wraps NSTextView with continuousSpellCheckingEnabled and
/// grammarCheckingEnabled set to true.
struct SpellCheckingTextEditor: NSViewRepresentable {
  @Binding var text: String
  var font: NSFont = .systemFont(ofSize: NSFont.systemFontSize)
  var isEditable: Bool = true
  var placeholder: String = ""

  func makeCoordinator() -> Coordinator {
    Coordinator(self)
  }

  func makeNSView(context: Context) -> NSScrollView {
    let scrollView = NSTextView.scrollableTextView()
    guard let textView = scrollView.documentView as? NSTextView else {
      return scrollView
    }

    textView.delegate = context.coordinator
    textView.font = font
    textView.isEditable = isEditable
    textView.isSelectable = true
    textView.isRichText = false
    textView.allowsUndo = true
    textView.usesFindBar = true

    // Enable spell checking
    textView.isContinuousSpellCheckingEnabled = true
    textView.isGrammarCheckingEnabled = true
    textView.isAutomaticSpellingCorrectionEnabled = false // Don't auto-correct, just underline
    textView.isAutomaticTextReplacementEnabled = true
    textView.isAutomaticDashSubstitutionEnabled = true
    textView.isAutomaticQuoteSubstitutionEnabled = true

    textView.textContainerInset = NSSize(width: 6, height: 8)
    textView.backgroundColor = .textBackgroundColor
    textView.drawsBackground = true

    // Placeholder support
    if text.isEmpty && !placeholder.isEmpty {
      textView.string = ""
    } else {
      textView.string = text
    }

    scrollView.hasVerticalScroller = true
    scrollView.hasHorizontalScroller = false
    scrollView.autohidesScrollers = true
    scrollView.borderType = .bezelBorder

    return scrollView
  }

  func updateNSView(_ scrollView: NSScrollView, context: Context) {
    guard let textView = scrollView.documentView as? NSTextView else { return }
    // Only update if the text actually changed (avoid cursor jump)
    if textView.string != text {
      textView.string = text
    }
  }

  class Coordinator: NSObject, NSTextViewDelegate {
    var parent: SpellCheckingTextEditor

    init(_ parent: SpellCheckingTextEditor) {
      self.parent = parent
    }

    func textDidChange(_ notification: Notification) {
      guard let textView = notification.object as? NSTextView else { return }
      parent.text = textView.string
    }
  }
}
