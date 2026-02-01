import SwiftUI

// MARK: - Theme (consistent with rest of app)

private enum ITheme {
  static let bg = Color(nsColor: .windowBackgroundColor)
  static let boardBg = Color(nsColor: .underPageBackgroundColor)
  static let cardBg = Color(nsColor: .controlBackgroundColor)
  static let subtle = Color.primary.opacity(0.06)
  static let border = Color.primary.opacity(0.08)
  static let cardRadius: CGFloat = 14
}

// MARK: - Inbox View

struct InboxView: View {
  @ObservedObject var vm: AppViewModel
  @Binding var isPresented: Bool

  @State private var selectedItem: InboxItem? = nil
  @State private var searchText: String = ""
  @State private var showReadItems: Bool = true

  private var filteredItems: [InboxItem] {
    var items = vm.inboxItems
    if !showReadItems {
      items = items.filter { !$0.isRead }
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
            .font(.caption)
          TextField("Search docs…", text: $searchText)
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
              .font(.caption)
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
                  .font(.subheadline)
                  .foregroundStyle(.secondary)
                Text("Design docs and artifacts will appear here")
                  .font(.caption)
                  .foregroundStyle(.tertiary)
              }
              .frame(maxWidth: .infinity)
              .padding(.top, 60)
            } else {
              ForEach(filteredItems) { item in
                InboxItemRow(
                  item: item,
                  isSelected: selectedItem?.id == item.id,
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
        .frame(minWidth: 300, idealWidth: 360)

        // Right: Document viewer
        if let item = selectedItem {
          DocumentViewer(item: item, vm: vm)
            .frame(minWidth: 400, idealWidth: 600)
        } else {
          VStack(spacing: 12) {
            Image(systemName: "doc.text")
              .font(.system(size: 40))
              .foregroundStyle(.quaternary)
            Text("Select a document to read")
              .font(.subheadline)
              .foregroundStyle(.tertiary)
          }
          .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
      }
    }
    .background(ITheme.boardBg)
  }
}

// MARK: - Inbox Item Row

private struct InboxItemRow: View {
  let item: InboxItem
  let isSelected: Bool
  let onSelect: () -> Void

  @State private var isHovering = false

  var body: some View {
    Button(action: onSelect) {
      HStack(spacing: 12) {
        // Unread indicator
        Circle()
          .fill(item.isRead ? Color.clear : Color.blue)
          .frame(width: 8, height: 8)

        VStack(alignment: .leading, spacing: 4) {
          Text(item.title)
            .font(.subheadline)
            .fontWeight(item.isRead ? .regular : .semibold)
            .foregroundStyle(.primary)
            .lineLimit(2)

          Text(item.summary)
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(2)

          HStack(spacing: 8) {
            // Source badge
            let isInbox = item.relativePath.hasPrefix("inbox/")
            HStack(spacing: 3) {
              Image(systemName: isInbox ? "tray" : "doc.text")
                .font(.system(size: 8))
              Text(isInbox ? "Inbox" : "Artifact")
                .font(.system(size: 9, weight: .medium))
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(isInbox ? Color.blue.opacity(0.12) : Color.purple.opacity(0.12))
            .foregroundStyle(isInbox ? .blue : .purple)
            .clipShape(Capsule())

            Text(relativeTime(item.modifiedAt))
              .font(.system(size: 9))
              .foregroundStyle(.tertiary)
          }
        }

        Spacer()

        Image(systemName: "chevron.right")
          .font(.caption2)
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

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      // Document header
      HStack(spacing: 10) {
        VStack(alignment: .leading, spacing: 4) {
          Text(item.title)
            .font(.title3)
            .fontWeight(.bold)

          HStack(spacing: 8) {
            HStack(spacing: 3) {
              Image(systemName: "doc.text")
                .font(.system(size: 10))
              Text(item.filename)
                .font(.system(size: 11, design: .monospaced))
            }
            .foregroundStyle(.secondary)

            Text("·")
              .foregroundStyle(.quaternary)

            Text(item.modifiedAt.formatted(date: .abbreviated, time: .shortened))
              .font(.system(size: 11))
              .foregroundStyle(.tertiary)
          }
        }

        Spacer()

        // Actions
        HStack(spacing: 6) {
          Button {
            if item.isRead {
              vm.markInboxItemUnread(item)
            } else {
              vm.markInboxItemRead(item)
            }
          } label: {
            Image(systemName: item.isRead ? "envelope.open" : "envelope.badge")
              .font(.body)
              .padding(6)
              .background(ITheme.subtle)
              .clipShape(RoundedRectangle(cornerRadius: 8))
          }
          .buttonStyle(.plain)
          .help(item.isRead ? "Mark as unread" : "Mark as read")

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

      // Document content
      ScrollView {
        Text(item.content)
          .font(.system(.body, design: .monospaced))
          .textSelection(.enabled)
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(20)
      }
    }
    .background(ITheme.bg)
  }
}

// MARK: - Helpers

private func relativeTime(_ date: Date) -> String {
  let seconds = Date().timeIntervalSince(date)
  if seconds < 60 { return "just now" }
  let minutes = Int(seconds / 60)
  if minutes < 60 { return "\(minutes)m ago" }
  let hours = Int(seconds / 3600)
  if hours < 24 { return "\(hours)h ago" }
  let days = Int(seconds / 86400)
  if days < 30 { return "\(days)d ago" }
  return "\(Int(seconds / 2_592_000))mo ago"
}
