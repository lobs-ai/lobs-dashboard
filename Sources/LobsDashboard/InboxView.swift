import SwiftUI
import AppKit

// MARK: - Enter-to-Send Text View

/// A text view that sends on Return and inserts newline on Shift+Return.
private struct EnterToSendTextView: NSViewRepresentable {
  @Binding var text: String
  var onSend: () -> Void

  func makeCoordinator() -> Coordinator { Coordinator(self) }

  func makeNSView(context: Context) -> NSScrollView {
    let scrollView = NSScrollView()
    let textView = NSTextView()
    textView.delegate = context.coordinator
    textView.isRichText = false
    textView.font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
    textView.isEditable = true
    textView.isSelectable = true
    textView.allowsUndo = true
    textView.drawsBackground = false
    textView.isVerticallyResizable = true
    textView.isHorizontallyResizable = false
    textView.textContainer?.widthTracksTextView = true
    textView.textContainer?.lineFragmentPadding = 4
    textView.textContainerInset = NSSize(width: 4, height: 6)

    scrollView.documentView = textView
    scrollView.hasVerticalScroller = false
    scrollView.drawsBackground = false
    scrollView.borderType = .noBorder
    return scrollView
  }

  func updateNSView(_ scrollView: NSScrollView, context: Context) {
    guard let textView = scrollView.documentView as? NSTextView else { return }
    if textView.string != text {
      textView.string = text
    }
  }

  class Coordinator: NSObject, NSTextViewDelegate {
    var parent: EnterToSendTextView
    init(_ parent: EnterToSendTextView) { self.parent = parent }

    func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
      if commandSelector == #selector(NSResponder.insertNewline(_:)) {
        // Check for shift key
        if NSApp.currentEvent?.modifierFlags.contains(.shift) == true {
          textView.insertNewlineIgnoringFieldEditor(nil)
          return true
        }
        // Send on plain Enter
        parent.onSend()
        return true
      }
      return false
    }

    func textDidChange(_ notification: Notification) {
      guard let textView = notification.object as? NSTextView else { return }
      parent.text = textView.string
    }
  }
}

// MARK: - Theme (consistent with rest of app)

// Theme is defined in Theme.swift
private typealias ITheme = Theme

// MARK: - Inbox View

struct InboxView: View {
  @ObservedObject var vm: AppViewModel
  @Binding var isPresented: Bool
  var initialSelectedItemId: String? = nil

  @State private var selectedItem: InboxItem? = nil
  @State private var searchText: String = ""
  @AppStorage("inboxShowReadItems") private var showReadItems: Bool = true
  @State private var didApplyInitialSelection: Bool = false

  private var filteredItems: [InboxItem] {
    var items = vm.inboxItems
    if !showReadItems {
      items = items.filter { !$0.isRead || vm.unreadFollowupCount(docId: $0.id) > 0 }
    }
    let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    if !q.isEmpty {
      items = items.filter { item in
        item.title.lowercased().contains(q)
          || item.filename.lowercased().contains(q)
          || item.summary.lowercased().contains(q)
      }
    }
    return items
  }

  var body: some View {
    VStack(spacing: 0) {
      // Header
      HStack(spacing: 12) {
        HStack(spacing: 8) {
          Image(systemName: "tray.full.fill")
            .font(.title2)
            .foregroundStyle(.linearGradient(
              colors: [.blue, .indigo],
              startPoint: .topLeading,
              endPoint: .bottomTrailing
            ))
          Text("Inbox")
            .font(.title3)
            .fontWeight(.bold)

          if vm.unreadInboxCount > 0 {
            Text("\(vm.unreadInboxCount) new")
              .font(.system(size: 11, weight: .semibold))
              .padding(.horizontal, 8)
              .padding(.vertical, 3)
              .background(Color.blue.opacity(0.15))
              .foregroundStyle(.blue)
              .clipShape(Capsule())
          }
        }

        Spacer()

        // Search
        HStack(spacing: 6) {
          Image(systemName: "magnifyingglass")
            .foregroundStyle(.secondary)
            .font(.footnote)
          TextField("Search inbox…", text: $searchText)
            .textFieldStyle(.plain)
            .frame(width: 160)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(ITheme.subtle)
        .clipShape(RoundedRectangle(cornerRadius: 8))

        // Toggle read
        Button {
          showReadItems.toggle()
        } label: {
          HStack(spacing: 4) {
            Image(systemName: showReadItems ? "eye" : "eye.slash")
            Text(showReadItems ? "All" : "Unread")
              .font(.footnote)
          }
          .padding(.horizontal, 10)
          .padding(.vertical, 6)
          .background(showReadItems ? ITheme.subtle : Color.blue.opacity(0.12))
          .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)

        Button {
          isPresented = false
        } label: {
          Image(systemName: "xmark")
            .font(.body)
            .padding(6)
            .background(ITheme.subtle)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
      }
      .padding(.horizontal, 20)
      .padding(.vertical, 14)
      .background(.ultraThinMaterial)

      Divider()

      // Content
      HSplitView {
        // Left: Item list
        ScrollView {
          LazyVStack(spacing: 6) {
            if filteredItems.isEmpty {
              VStack(spacing: 12) {
                Image(systemName: "tray")
                  .font(.system(size: 36))
                  .foregroundStyle(.quaternary)
                Text("No documents")
                  .font(.callout)
                  .foregroundStyle(.secondary)
                Text("Design docs and artifacts will appear here")
                  .font(.footnote)
                  .foregroundStyle(.tertiary)
              }
              .frame(maxWidth: .infinity)
              .padding(.top, 60)
            } else {
              ForEach(filteredItems) { item in
                InboxItemRow(
                  item: item,
                  isSelected: selectedItem?.id == item.id,
                  vm: vm,
                  onSelect: {
                    selectedItem = item
                    vm.markInboxItemRead(item)
                  }
                )
              }
            }
          }
          .padding(12)
        }
        .frame(minWidth: 260, idealWidth: 300, maxWidth: 360)

        // Right: Document viewer
        if let item = selectedItem {
          DocumentViewer(item: item, vm: vm)
            .frame(minWidth: 500, idealWidth: 700)
        } else {
          VStack(spacing: 12) {
            Image(systemName: "doc.text")
              .font(.system(size: 40))
              .foregroundStyle(.quaternary)
            Text("Select a document to read")
              .font(.callout)
              .foregroundStyle(.tertiary)
          }
          .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
      }
    }
    .background(ITheme.boardBg)
    .overlay {
      InboxArrowKeyMonitor(
        onUp: { selectAdjacentItem(direction: -1) },
        onDown: { selectAdjacentItem(direction: 1) },
        onEscape: { isPresented = false }
      )
      .frame(width: 0, height: 0)
    }
    .onAppear {
      if !didApplyInitialSelection, let targetId = initialSelectedItemId,
         let item = vm.inboxItems.first(where: { $0.id == targetId }) {
        selectedItem = item
        vm.markInboxItemRead(item)
        didApplyInitialSelection = true
      }
    }
  }

  private func selectAdjacentItem(direction: Int) {
    let items = filteredItems
    guard !items.isEmpty else { return }

    if let current = selectedItem,
       let idx = items.firstIndex(where: { $0.id == current.id }) {
      let newIdx = idx + direction
      if newIdx >= 0 && newIdx < items.count {
        selectedItem = items[newIdx]
        vm.markInboxItemRead(items[newIdx])
      }
    } else {
      // Nothing selected — select first or last depending on direction
      let item = direction > 0 ? items.first! : items.last!
      selectedItem = item
      vm.markInboxItemRead(item)
    }
  }
}

// MARK: - Inbox Arrow Key Monitor

/// NSEvent-based arrow key handler for inbox navigation.
/// Skips interception when a text field is focused.
private struct InboxArrowKeyMonitor: NSViewRepresentable {
  let onUp: () -> Void
  let onDown: () -> Void
  let onEscape: () -> Void

  func makeNSView(context: Context) -> NSView {
    let view = NSView()
    context.coordinator.monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
      // Let text fields handle their own key events
      if let responder = NSApp.keyWindow?.firstResponder,
         responder is NSTextView || responder is NSTextField {
        return event
      }
      switch event.keyCode {
      case 125: // down arrow
        DispatchQueue.main.async { self.onDown() }
        return nil
      case 126: // up arrow
        DispatchQueue.main.async { self.onUp() }
        return nil
      case 53: // escape
        DispatchQueue.main.async { self.onEscape() }
        return nil
      default:
        return event
      }
    }
    return view
  }

  func updateNSView(_ nsView: NSView, context: Context) {}

  static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
    if let monitor = coordinator.monitor {
      NSEvent.removeMonitor(monitor)
    }
  }

  func makeCoordinator() -> Coordinator { Coordinator() }

  class Coordinator {
    var monitor: Any?
  }
}

// MARK: - Inbox Item Row

private struct InboxItemRow: View {
  let item: InboxItem
  let isSelected: Bool
  @ObservedObject var vm: AppViewModel
  let onSelect: () -> Void

  @State private var isHovering = false

  var body: some View {
    Button(action: onSelect) {
      HStack(spacing: 12) {
        // Unread indicator (doc unread OR unread follow-up thread messages)
        let followupsUnread = vm.unreadFollowupCount(docId: item.id)
        Circle()
          .fill((item.isRead && followupsUnread == 0) ? Color.clear : (followupsUnread > 0 ? Color.purple : Color.blue))
          .frame(width: 8, height: 8)

        VStack(alignment: .leading, spacing: 4) {
          Text(item.title)
            .font(.callout)
            .fontWeight(item.isRead ? .regular : .semibold)
            .foregroundStyle(.primary)
            .lineLimit(2)

          Text(item.summary)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .lineLimit(2)

          HStack(spacing: 8) {
            // Source badge
            let isInbox = item.relativePath.hasPrefix("inbox/")
            HStack(spacing: 3) {
              Image(systemName: isInbox ? "tray" : "doc.text")
                .font(.system(size: 9))
              Text(isInbox ? "Inbox" : "Artifact")
                .font(.system(size: 11, weight: .medium))
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(isInbox ? Color.blue.opacity(0.12) : Color.purple.opacity(0.12))
            .foregroundStyle(isInbox ? .blue : .purple)
            .clipShape(Capsule())

            let followupsUnread = vm.unreadFollowupCount(docId: item.id)
            if followupsUnread > 0 {
              HStack(spacing: 3) {
                Image(systemName: "bubble.left.and.bubble.right.fill")
                  .font(.system(size: 9))
                Text("+\(followupsUnread)")
                  .font(.system(size: 11, weight: .semibold))
              }
              .padding(.horizontal, 6)
              .padding(.vertical, 2)
              .background(Color.purple.opacity(0.12))
              .foregroundStyle(.purple)
              .clipShape(Capsule())
            }

            Text(relativeTime(item.modifiedAt))
              .font(.system(size: 11))
              .foregroundStyle(.tertiary)
          }
        }

        Spacer()

        Image(systemName: "chevron.right")
          .font(.footnote)
          .foregroundStyle(.quaternary)
      }
      .padding(10)
      .background(
        RoundedRectangle(cornerRadius: ITheme.cardRadius)
          .fill(isSelected ? Color.accentColor.opacity(0.1) : (isHovering ? ITheme.subtle : ITheme.cardBg))
      )
      .overlay(
        RoundedRectangle(cornerRadius: ITheme.cardRadius)
          .stroke(isSelected ? Color.accentColor.opacity(0.3) : ITheme.border, lineWidth: isSelected ? 1.5 : 0.5)
      )
    }
    .buttonStyle(.plain)
    .onHover { h in isHovering = h }
  }
}

// MARK: - Document Viewer

private struct DocumentViewer: View {
  let item: InboxItem
  @ObservedObject var vm: AppViewModel

  @State private var replyText: String = ""
  @State private var showOriginalMessage: Bool = true

  /// Live read state from the view model (not the stale item snapshot).
  private var isRead: Bool {
    vm.readItemIds.contains(item.id)
  }

  /// Live item from the view model (reflects current read state).
  private var liveItem: InboxItem {
    vm.inboxItems.first(where: { $0.id == item.id }) ?? item
  }

  private var thread: InboxThread? {
    vm.inboxThreadsByDocId[item.id]
  }

  private func sendReply() {
    let text = replyText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty else { return }
    vm.postInboxThreadMessage(docId: item.id, author: "rafe", text: text)
    replyText = ""
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      // Document header
      HStack(spacing: 10) {
        VStack(alignment: .leading, spacing: 4) {
          Text(item.title)
            .font(.title2)
            .fontWeight(.bold)

          HStack(spacing: 8) {
            HStack(spacing: 3) {
              Image(systemName: "doc.text")
                .font(.system(size: 12))
              Text(item.filename)
                .font(.system(size: 12, design: .monospaced))
            }
            .foregroundStyle(.secondary)

            Text("·")
              .foregroundStyle(.quaternary)

            Text(item.modifiedAt.formatted(date: .abbreviated, time: .shortened))
              .font(.system(size: 12))
              .foregroundStyle(.tertiary)
          }
        }

        Spacer()

        // Actions
        HStack(spacing: 6) {
          Button {
            if isRead {
              vm.markInboxItemUnread(liveItem)
            } else {
              vm.markInboxItemRead(liveItem)
            }
          } label: {
            Image(systemName: isRead ? "envelope.open" : "envelope.badge")
              .font(.body)
              .padding(6)
              .background(ITheme.subtle)
              .clipShape(RoundedRectangle(cornerRadius: 8))
          }
          .buttonStyle(.plain)
          .help(isRead ? "Mark as unread" : "Mark as read")

          Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(item.content, forType: .string)
          } label: {
            Image(systemName: "doc.on.doc")
              .font(.body)
              .padding(6)
              .background(ITheme.subtle)
              .clipShape(RoundedRectangle(cornerRadius: 8))
          }
          .buttonStyle(.plain)
          .help("Copy to clipboard")
        }
      }
      .padding(.horizontal, 20)
      .padding(.vertical, 14)
      .background(ITheme.bg.opacity(0.6))

      Divider()

      // Message stream — original doc is the first message, thread follows naturally
      ScrollViewReader { proxy in
        ScrollView {
          VStack(alignment: .leading, spacing: 6) {
            // Original document as the first "message" from Lobs
            HStack(alignment: .top, spacing: 8) {
              ZStack {
                Circle()
                  .fill(Color.purple.opacity(0.15))
                  .frame(width: 28, height: 28)
                Text("L")
                  .font(.system(size: 13, weight: .bold))
                  .foregroundStyle(.purple)
              }

              VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                  Text("Lobs")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.purple)
                  Text(item.modifiedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                }

                if showOriginalMessage {
                  MarkdownWebView(markdown: item.content)
                    .frame(maxWidth: .infinity, minHeight: 200)
                } else {
                  Text(item.summary)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                }

                Button {
                  showOriginalMessage.toggle()
                } label: {
                  Text(showOriginalMessage ? "Collapse" : "Show full message")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
              }

              Spacer()
            }
            .padding(10)
            .background(
              RoundedRectangle(cornerRadius: 10)
                .fill(Color.purple.opacity(0.05))
            )
            .padding(.horizontal, 24)
            .padding(.top, 16)

            // Thread messages flow naturally after
            if let thread = thread {
              ForEach(thread.messages) { msg in
                ThreadMessageBubble(message: msg, docId: item.id, vm: vm)
                  .padding(.horizontal, 24)
                  .padding(.vertical, 3)
              }
            }

            Color.clear
              .frame(height: 1)
              .id("thread-bottom")
          }
        }
        .onChange(of: thread?.messages.count) { _ in
          withAnimation {
            proxy.scrollTo("thread-bottom", anchor: .bottom)
          }
        }
      }

      Divider()

      // Reply box at bottom (Enter sends, Shift+Enter for newline)
      HStack(spacing: 10) {
        ZStack(alignment: .topLeading) {
          EnterToSendTextView(text: $replyText, onSend: sendReply)
            .frame(minHeight: 32, maxHeight: 80)
            .padding(6)
            .background(ITheme.cardBg)
            .clipShape(RoundedRectangle(cornerRadius: 10))

          if replyText.isEmpty {
            Text("Reply… (Enter to send, ⇧Enter for newline)")
              .foregroundStyle(.tertiary)
              .padding(.horizontal, 14)
              .padding(.vertical, 14)
              .allowsHitTesting(false)
          }
        }

        Button(action: sendReply) {
          Image(systemName: "arrow.up.circle.fill")
            .font(.title2)
            .foregroundStyle(
              replyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? Color.secondary : Color.accentColor
            )
        }
        .buttonStyle(.plain)
        .disabled(replyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        .help("Send reply (Enter)")
      }
      .padding(.horizontal, 20)
      .padding(.vertical, 12)
      .background(ITheme.bg.opacity(0.5))
    }
    .background(ITheme.bg)
  }
}

// MARK: - Thread Message Bubble

private struct ThreadMessageBubble: View {
  let message: InboxThreadMessage
  let docId: String
  @ObservedObject var vm: AppViewModel

  @State private var isEditing = false
  @State private var editText = ""

  private var isRafe: Bool { message.author.lowercased() == "rafe" }
  private var isLobs: Bool { message.author.lowercased() == "lobs" }

  private var authorColor: Color {
    isLobs ? .purple : .blue
  }

  var body: some View {
    HStack(alignment: .top, spacing: 8) {
      // Author avatar
      ZStack {
        Circle()
          .fill(authorColor.opacity(0.15))
          .frame(width: 28, height: 28)
        Text(isLobs ? "L" : "R")
          .font(.system(size: 13, weight: .bold))
          .foregroundStyle(authorColor)
      }

      VStack(alignment: .leading, spacing: 4) {
        HStack(spacing: 6) {
          Text(message.author.capitalized)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(authorColor)

          Text(message.createdAt.formatted(date: .abbreviated, time: .shortened))
            .font(.system(size: 11))
            .foregroundStyle(.tertiary)

          if isRafe && !isEditing {
            Button {
              editText = message.text
              isEditing = true
            } label: {
              Image(systemName: "pencil")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
            .help("Edit message")
          }
        }

        if isEditing {
          VStack(alignment: .leading, spacing: 6) {
            TextEditor(text: $editText)
              .font(.system(size: 13))
              .frame(minHeight: 32, maxHeight: 120)
              .padding(4)
              .background(ITheme.cardBg)
              .clipShape(RoundedRectangle(cornerRadius: 6))

            HStack(spacing: 8) {
              Button("Save") {
                let trimmed = editText.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return }
                vm.editInboxThreadMessage(docId: docId, messageId: message.id, newText: trimmed)
                isEditing = false
              }
              .buttonStyle(.borderedProminent)
              .controlSize(.small)
              .disabled(editText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

              Button("Cancel") {
                isEditing = false
              }
              .buttonStyle(.bordered)
              .controlSize(.small)
            }
          }
        } else {
          Group {
            if let md = try? AttributedString(markdown: message.text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
              Text(md)
            } else {
              Text(message.text)
            }
          }
            .font(.system(size: 13))
            .textSelection(.enabled)
            .lineSpacing(3)
        }
      }

      Spacer()
    }
    .padding(10)
    .background(
      RoundedRectangle(cornerRadius: 10)
        .fill(isLobs ? Color.purple.opacity(0.05) : Color.blue.opacity(0.05))
    )
  }
}

// MARK: - Helpers

private func relativeTime(_ date: Date) -> String {
  let seconds = Date().timeIntervalSince(date)
  if seconds < 0 { return "just now" } // future date — treat as now
  if seconds < 60 { return "just now" }
  let minutes = Int(seconds / 60)
  if minutes < 60 { return "\(minutes)m ago" }
  let hours = Int(seconds / 3600)
  if hours < 24 { return "\(hours)h ago" }
  let days = Int(seconds / 86400)
  if days < 30 { return "\(days)d ago" }
  return "\(Int(seconds / 2_592_000))mo ago"
}
