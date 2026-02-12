import SwiftUI
import AppKit

// MARK: - Documents View

struct DocumentsView: View {
  @ObservedObject var vm: AppViewModel
  @Binding var isPresented: Bool

  @State private var selectedDocument: AgentDocument? = nil
  @State private var searchText: String = ""
  @AppStorage("documentsShowReadItems") private var showReadItems: Bool = true
  @AppStorage("documentsSourceFilter") private var sourceFilter: String = "all"
  @AppStorage("documentsStatusFilter") private var statusFilter: String = "all"

  private var filteredDocuments: [AgentDocument] {
    var docs = vm.agentDocuments

    // Filter by read status
    if !showReadItems {
      docs = docs.filter { !$0.isRead }
    }

    // Filter by source
    if sourceFilter != "all" {
      docs = docs.filter { $0.source.rawValue == sourceFilter }
    }

    // Filter by status (only applicable for reports)
    if statusFilter != "all" {
      docs = docs.filter { $0.status?.rawValue == statusFilter }
    }

    // Filter by search text
    let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    if !q.isEmpty {
      docs = docs.filter { doc in
        doc.title.lowercased().contains(q)
          || doc.filename.lowercased().contains(q)
          || (doc.topic?.lowercased().contains(q) ?? false)
          || (doc.projectId?.lowercased().contains(q) ?? false)
      }
    }

    return docs
  }

  var body: some View {
    VStack(spacing: 0) {
      // Header
      HStack(spacing: 12) {
        HStack(spacing: 8) {
          Image(systemName: "doc.text.fill")
            .font(.title2)
            .foregroundStyle(.linearGradient(
              colors: [.purple, .pink],
              startPoint: .topLeading,
              endPoint: .bottomTrailing
            ))
          Text("Documents")
            .font(.title3)
            .fontWeight(.bold)

          if vm.agentDocuments.filter({ !$0.isRead }).count > 0 {
            Text("\(vm.agentDocuments.filter({ !$0.isRead }).count) new")
              .font(.system(size: 11, weight: .semibold))
              .padding(.horizontal, 8)
              .padding(.vertical, 3)
              .background(Color.purple.opacity(0.15))
              .foregroundStyle(.purple)
              .clipShape(Capsule())
          }
        }

        Spacer()

        // Close button
        Button {
          isPresented = false
        } label: {
          Image(systemName: "xmark.circle.fill")
            .font(.title2)
            .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .help("Close")
      }
      .padding()

      Divider()

      // Toolbar
      HStack(spacing: 12) {
        // Search
        HStack(spacing: 6) {
          Image(systemName: "magnifyingglass")
            .foregroundStyle(.secondary)
          TextField("Search documents...", text: $searchText)
            .textFieldStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color(NSColor.textBackgroundColor))
        .cornerRadius(6)

        // Source filter
        Menu {
          Button("All Sources") { sourceFilter = "all" }
          Divider()
          ForEach(DocumentSource.allCases, id: \.self) { source in
            Button(source.displayName) {
              sourceFilter = source.rawValue
            }
          }
        } label: {
          HStack(spacing: 4) {
            Image(systemName: sourceFilter == "all" ? "doc.text.fill" : DocumentSource(rawValue: sourceFilter)?.icon ?? "doc.text.fill")
            Text(sourceFilter == "all" ? "All Sources" : (DocumentSource(rawValue: sourceFilter)?.displayName ?? "All"))
            Image(systemName: "chevron.down")
              .font(.system(size: 10))
          }
          .font(.system(size: 13))
          .padding(.horizontal, 10)
          .padding(.vertical, 6)
          .background(Color(NSColor.controlBackgroundColor))
          .cornerRadius(6)
        }
        .menuStyle(.borderlessButton)
        .help("Filter by source")

        // Status filter (only for reports)
        if filteredDocuments.contains(where: { $0.status != nil }) {
          Menu {
            Button("All Statuses") { statusFilter = "all" }
            Divider()
            ForEach(DocumentStatus.allCases, id: \.self) { status in
              Button(status.displayName) {
                statusFilter = status.rawValue
              }
            }
          } label: {
            HStack(spacing: 4) {
              Image(systemName: "flag.fill")
              Text(statusFilter == "all" ? "All Statuses" : (DocumentStatus(rawValue: statusFilter)?.displayName ?? "All"))
              Image(systemName: "chevron.down")
                .font(.system(size: 10))
            }
            .font(.system(size: 13))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(6)
          }
          .menuStyle(.borderlessButton)
          .help("Filter by status")
        }

        // Read filter toggle
        Toggle(isOn: $showReadItems) {
          HStack(spacing: 4) {
            Image(systemName: showReadItems ? "eye" : "eye.slash")
            Text(showReadItems ? "Hide Read" : "Show All")
          }
          .font(.system(size: 13))
        }
        .toggleStyle(.button)
        .buttonStyle(.borderless)
        .help(showReadItems ? "Hide read documents" : "Show all documents")

        Spacer()

        // Document count
        Text("\(filteredDocuments.count) document\(filteredDocuments.count == 1 ? "" : "s")")
          .font(.system(size: 12))
          .foregroundStyle(.secondary)
      }
      .padding(.horizontal)
      .padding(.vertical, 8)

      Divider()

      // Content - Split view
      HSplitView {
        // Left: Document list
        ScrollView {
          LazyVStack(spacing: 0) {
            if filteredDocuments.isEmpty {
              VStack(spacing: 12) {
                Image(systemName: "doc.text")
                  .font(.system(size: 48))
                  .foregroundStyle(.secondary)
                Text("No documents")
                  .font(.headline)
                Text(searchText.isEmpty ? "Agent documents will appear here" : "No documents match your filters")
                  .font(.subheadline)
                  .foregroundStyle(.secondary)
              }
              .frame(maxWidth: .infinity)
              .padding(.vertical, 60)
            } else {
              ForEach(filteredDocuments) { doc in
                DocumentListRow(
                  doc: doc,
                  isSelected: selectedDocument?.id == doc.id,
                  onSelect: {
                    selectedDocument = doc
                    if !doc.isRead {
                      vm.markDocumentRead(doc)
                    }
                  }
                )
              }
            }
          }
        }
        .frame(minWidth: 300, idealWidth: 400, maxWidth: 500)

        // Right: Document detail
        if let doc = selectedDocument {
          DocumentDetailView(doc: doc, vm: vm)
        } else {
          VStack(spacing: 12) {
            Image(systemName: "doc.text")
              .font(.system(size: 64))
              .foregroundStyle(.tertiary)
            Text("Select a document")
              .font(.headline)
              .foregroundStyle(.secondary)
          }
          .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
      }
    }
    .background(Theme.boardBg)
    .frame(minWidth: 900, idealWidth: 1200, minHeight: 600, idealHeight: 800)
    .onExitCommand {
      withAnimation(.easeInOut(duration: 0.25)) {
        isPresented = false
      }
    }
    .onAppear {
      // Select first document if none selected
      if selectedDocument == nil, let first = filteredDocuments.first {
        selectedDocument = first
        if !first.isRead {
          vm.markDocumentRead(first)
        }
      }
    }
  }
}

// MARK: - Document List Row

private struct DocumentListRow: View {
  let doc: AgentDocument
  let isSelected: Bool
  let onSelect: () -> Void

  var body: some View {
    Button {
      onSelect()
    } label: {
      HStack(spacing: 12) {
        // Source icon
        Image(systemName: doc.source.icon)
          .font(.title3)
          .foregroundStyle(doc.source == .writer ? .blue : .purple)
          .frame(width: 24)

        VStack(alignment: .leading, spacing: 4) {
          // Title
          HStack(spacing: 6) {
            Text(doc.title)
              .font(.system(size: 14, weight: doc.isRead ? .regular : .semibold))
              .lineLimit(2)
              .multilineTextAlignment(.leading)

            if !doc.isRead {
              Circle()
                .fill(.blue)
                .frame(width: 6, height: 6)
            }
          }

          // Metadata
          HStack(spacing: 6) {
            // Source badge
            Text(doc.source.displayName)
              .font(.system(size: 11))
              .padding(.horizontal, 6)
              .padding(.vertical, 2)
              .background(doc.source == .writer ? Color.blue.opacity(0.15) : Color.purple.opacity(0.15))
              .foregroundStyle(doc.source == .writer ? .blue : .purple)
              .cornerRadius(4)

            // Status badge (if applicable)
            if let status = doc.status {
              Text(status.displayName)
                .font(.system(size: 11))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(statusColor(status).opacity(0.15))
                .foregroundStyle(statusColor(status))
                .cornerRadius(4)
            }

            // Topic/Project
            if let topic = doc.topic {
              Text(topic)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            }

            Spacer()

            // Date
            Text(doc.date, style: .relative)
              .font(.system(size: 11))
              .foregroundStyle(.secondary)
          }
        }

        Spacer()
      }
      .padding(.horizontal, 12)
      .padding(.vertical, 10)
      .background(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .help(doc.filename)
  }

  private func statusColor(_ status: DocumentStatus) -> Color {
    switch status {
    case .pending: return .orange
    case .approved: return .green
    case .rejected: return .red
    }
  }
}

// MARK: - Document Detail View

private struct DocumentDetailView: View {
  let doc: AgentDocument
  @ObservedObject var vm: AppViewModel

  var body: some View {
    VStack(spacing: 0) {
      // Header
      VStack(alignment: .leading, spacing: 8) {
        HStack {
          Text(doc.title)
            .font(.title2)
            .fontWeight(.bold)

          Spacer()

          // Mark read/unread toggle
          Button {
            if doc.isRead {
              vm.markDocumentUnread(doc)
            } else {
              vm.markDocumentRead(doc)
            }
          } label: {
            Image(systemName: doc.isRead ? "eye.slash" : "eye")
              .foregroundStyle(.secondary)
          }
          .buttonStyle(.plain)
          .help(doc.isRead ? "Mark as unread" : "Mark as read")
        }

        // Metadata
        HStack(spacing: 8) {
          // Source
          Label(doc.source.displayName, systemImage: doc.source.icon)
            .font(.system(size: 12))
            .foregroundStyle(doc.source == .writer ? .blue : .purple)

          // Status
          if let status = doc.status {
            Label(status.displayName, systemImage: "flag.fill")
              .font(.system(size: 12))
              .foregroundStyle(statusColor(status))
          }

          // Topic
          if let topic = doc.topic {
            Label(topic, systemImage: "folder")
              .font(.system(size: 12))
              .foregroundStyle(.secondary)
          }

          // Date
          HStack(spacing: 4) {
            Image(systemName: "calendar")
            Text(doc.date, style: .date)
          }
          .font(.system(size: 12))
          .foregroundStyle(.secondary)

          Spacer()

          // Filename
          Text(doc.filename)
            .font(.system(size: 11, design: .monospaced))
            .foregroundStyle(.tertiary)
        }
      }
      .padding()

      Divider()

      // Content
      ScrollView {
        VStack(alignment: .leading, spacing: 0) {
          if doc.contentIsTruncated {
            HStack(spacing: 8) {
              Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
              Text("Content truncated for performance. Full document available in repository.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            }
            .padding()
            .background(Color.orange.opacity(0.1))
            .cornerRadius(8)
            .padding()
          }

          MarkdownWebView(markdown: doc.content)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
      }
    }
  }

  private func statusColor(_ status: DocumentStatus) -> Color {
    switch status {
    case .pending: return .orange
    case .approved: return .green
    case .rejected: return .red
    }
  }
}

// MARK: - Preview

#Preview {
  DocumentsView(
    vm: AppViewModel(),
    isPresented: .constant(true)
  )
  .frame(width: 1200, height: 800)
}
