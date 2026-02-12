import SwiftUI

// MARK: - Documents View

/// View for displaying agent-produced documents (writer reports and researcher findings)
struct DocumentsView: View {
  @ObservedObject var vm: AppViewModel
  @Binding var isPresented: Bool
  
  @State private var selectedDocumentId: String? = nil
  @State private var searchText = ""
  @State private var filterSource: DocumentSource? = nil
  @State private var filterStatus: DocumentStatus? = nil
  
  private var filteredDocuments: [AgentDocument] {
    var docs = vm.agentDocuments
    
    // Apply source filter
    if let source = filterSource {
      docs = docs.filter { $0.source == source }
    }
    
    // Apply status filter (reports only)
    if let status = filterStatus {
      docs = docs.filter { $0.status == status }
    }
    
    // Apply search
    if !searchText.isEmpty {
      let query = searchText.lowercased()
      docs = docs.filter { doc in
        doc.title.lowercased().contains(query) ||
        doc.filename.lowercased().contains(query) ||
        (doc.topic?.lowercased().contains(query) ?? false) ||
        doc.content.lowercased().contains(query)
      }
    }
    
    return docs
  }
  
  var body: some View {
    HStack(spacing: 0) {
      // Left sidebar: Document list
      VStack(spacing: 0) {
        // Header
        HStack {
          Text("Documents")
            .font(.title2)
            .fontWeight(.bold)
          
          Spacer()
          
          Button {
            withAnimation(.easeInOut(duration: 0.25)) {
              isPresented = false
            }
          } label: {
            Image(systemName: "xmark.circle.fill")
              .font(.title3)
              .foregroundStyle(.secondary)
          }
          .buttonStyle(.plain)
          .help("Close (esc)")
        }
        .padding()
        
        // Search and filters
        VStack(spacing: 12) {
          // Search
          HStack {
            Image(systemName: "magnifyingglass")
              .foregroundStyle(.secondary)
            TextField("Search documents...", text: $searchText)
              .textFieldStyle(.plain)
            if !searchText.isEmpty {
              Button {
                searchText = ""
              } label: {
                Image(systemName: "xmark.circle.fill")
                  .foregroundStyle(.secondary)
              }
              .buttonStyle(.plain)
            }
          }
          .padding(8)
          .background(Color(NSColor.controlBackgroundColor))
          .clipShape(RoundedRectangle(cornerRadius: 6))
          
          // Filters
          HStack(spacing: 8) {
            // Source filter
            Menu {
              Button("All Sources") {
                filterSource = nil
              }
              Divider()
              Button("Writer") {
                filterSource = .writer
              }
              Button("Researcher") {
                filterSource = .researcher
              }
            } label: {
              HStack(spacing: 4) {
                Image(systemName: "person.fill")
                  .font(.system(size: 10))
                Text(filterSource?.rawValue.capitalized ?? "All Sources")
                  .font(.system(size: 11))
                Image(systemName: "chevron.down")
                  .font(.system(size: 8))
              }
              .padding(.horizontal, 8)
              .padding(.vertical, 4)
              .background(filterSource != nil ? Color.blue.opacity(0.15) : Color(NSColor.controlBackgroundColor))
              .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            
            // Status filter (for reports)
            Menu {
              Button("All Statuses") {
                filterStatus = nil
              }
              Divider()
              Button("Pending") {
                filterStatus = .pending
              }
              Button("Approved") {
                filterStatus = .approved
              }
              Button("Rejected") {
                filterStatus = .rejected
              }
            } label: {
              HStack(spacing: 4) {
                Image(systemName: "flag.fill")
                  .font(.system(size: 10))
                Text(filterStatus?.rawValue.capitalized ?? "All Statuses")
                  .font(.system(size: 11))
                Image(systemName: "chevron.down")
                  .font(.system(size: 8))
              }
              .padding(.horizontal, 8)
              .padding(.vertical, 4)
              .background(filterStatus != nil ? Color.orange.opacity(0.15) : Color(NSColor.controlBackgroundColor))
              .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            
            Spacer()
            
            // Document count
            Text("\(filteredDocuments.count) doc\(filteredDocuments.count == 1 ? "" : "s")")
              .font(.system(size: 11))
              .foregroundStyle(.secondary)
          }
        }
        .padding(.horizontal)
        .padding(.bottom, 12)
        
        Divider()
        
        // Document list
        if filteredDocuments.isEmpty {
          VStack(spacing: 12) {
            Image(systemName: "doc.text")
              .font(.system(size: 48))
              .foregroundStyle(.tertiary)
            Text(searchText.isEmpty ? "No documents" : "No matching documents")
              .font(.system(size: 15))
              .foregroundStyle(.secondary)
          }
          .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
          ScrollView {
            LazyVStack(spacing: 0) {
              ForEach(filteredDocuments) { doc in
                DocumentRow(
                  document: doc,
                  isSelected: selectedDocumentId == doc.id,
                  onTap: {
                    selectedDocumentId = doc.id
                    if !doc.isRead {
                      vm.markDocumentRead(doc)
                    }
                  }
                )
                
                if doc.id != filteredDocuments.last?.id {
                  Divider()
                    .padding(.leading, 16)
                }
              }
            }
          }
        }
      }
      .frame(width: 400)
      .background(Color(NSColor.windowBackgroundColor))
      
      Divider()
      
      // Right panel: Document content
      if let docId = selectedDocumentId,
         let doc = vm.agentDocuments.first(where: { $0.id == docId }) {
        DocumentDetailView(document: doc, vm: vm)
      } else {
        VStack(spacing: 12) {
          Image(systemName: "doc.text.magnifyingglass")
            .font(.system(size: 48))
            .foregroundStyle(.tertiary)
          Text("Select a document to view")
            .font(.system(size: 15))
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.3))
      }
    }
    .onAppear {
      vm.loadAgentDocuments()
    }
  }
}

// MARK: - Document Row

private struct DocumentRow: View {
  let document: AgentDocument
  let isSelected: Bool
  let onTap: () -> Void
  
  @State private var isHovering = false
  
  var body: some View {
    Button(action: onTap) {
      HStack(alignment: .top, spacing: 12) {
        // Icon
        VStack {
          Image(systemName: document.source == .writer ? "doc.text.fill" : "magnifyingglass")
            .font(.system(size: 16))
            .foregroundStyle(document.isRead ? .secondary : .blue)
        }
        .frame(width: 24)
        .padding(.top, 2)
        
        // Content
        VStack(alignment: .leading, spacing: 4) {
          // Title
          HStack {
            Text(document.title)
              .font(.system(size: 13, weight: document.isRead ? .regular : .semibold))
              .foregroundStyle(isSelected ? .white : .primary)
              .lineLimit(2)
            
            if !document.isRead {
              Circle()
                .fill(Color.blue)
                .frame(width: 6, height: 6)
            }
          }
          
          // Metadata
          HStack(spacing: 6) {
            // Source
            Text(document.source.rawValue.capitalized)
              .font(.system(size: 10, weight: .medium))
              .foregroundStyle(isSelected ? .white.opacity(0.8) : .secondary)
            
            Text("•")
              .font(.system(size: 10))
              .foregroundStyle(isSelected ? .white.opacity(0.6) : .tertiary)
            
            // Date
            Text(document.date, style: .relative)
              .font(.system(size: 10))
              .foregroundStyle(isSelected ? .white.opacity(0.8) : .secondary)
            
            // Status badge (reports only)
            if let status = document.status {
              Text("•")
                .font(.system(size: 10))
                .foregroundStyle(isSelected ? .white.opacity(0.6) : .tertiary)
              
              StatusBadge(status: status, isSelected: isSelected)
            }
            
            // Topic (research only)
            if let topic = document.topic {
              Text("•")
                .font(.system(size: 10))
                .foregroundStyle(isSelected ? .white.opacity(0.6) : .tertiary)
              
              Text(topic)
                .font(.system(size: 10))
                .foregroundStyle(isSelected ? .white.opacity(0.8) : .secondary)
                .lineLimit(1)
            }
          }
        }
        
        Spacer()
      }
      .padding(.horizontal, 16)
      .padding(.vertical, 12)
      .background(isSelected ? Color.accentColor : (isHovering ? Color.primary.opacity(0.05) : Color.clear))
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .onHover { hovering in
      isHovering = hovering
    }
  }
}

// MARK: - Status Badge

private struct StatusBadge: View {
  let status: DocumentStatus
  let isSelected: Bool
  
  var body: some View {
    Text(status.rawValue.capitalized)
      .font(.system(size: 9, weight: .medium))
      .foregroundStyle(isSelected ? .white : statusColor)
      .padding(.horizontal, 5)
      .padding(.vertical, 2)
      .background((isSelected ? Color.white : statusColor).opacity(0.15))
      .clipShape(Capsule())
  }
  
  private var statusColor: Color {
    switch status {
    case .pending: return .orange
    case .approved: return .green
    case .rejected: return .red
    }
  }
}

// MARK: - Document Detail View

private struct DocumentDetailView: View {
  let document: AgentDocument
  @ObservedObject var vm: AppViewModel
  
  var body: some View {
    VStack(spacing: 0) {
      // Header
      VStack(alignment: .leading, spacing: 8) {
        HStack {
          VStack(alignment: .leading, spacing: 4) {
            Text(document.title)
              .font(.title2)
              .fontWeight(.bold)
            
            HStack(spacing: 8) {
              Label(document.source.rawValue.capitalized, systemImage: document.source == .writer ? "doc.text" : "magnifyingglass")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
              
              Text("•")
                .foregroundStyle(.tertiary)
              
              Text(document.date, style: .date)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
              
              if let status = document.status {
                Text("•")
                  .foregroundStyle(.tertiary)
                StatusBadge(status: status, isSelected: false)
              }
              
              if let topic = document.topic {
                Text("•")
                  .foregroundStyle(.tertiary)
                Text(topic)
                  .font(.system(size: 12))
                  .foregroundStyle(.secondary)
              }
            }
          }
          
          Spacer()
          
          // Actions
          HStack(spacing: 8) {
            Button {
              if document.isRead {
                vm.markDocumentUnread(document)
              } else {
                vm.markDocumentRead(document)
              }
            } label: {
              Image(systemName: document.isRead ? "envelope.badge" : "envelope.open")
                .font(.system(size: 14))
            }
            .buttonStyle(.plain)
            .help(document.isRead ? "Mark as unread" : "Mark as read")
          }
        }
      }
      .padding()
      .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
      
      Divider()
      
      // Content (markdown)
      ScrollView {
        VStack(alignment: .leading, spacing: 0) {
          MarkdownWebView(markdown: document.content)
            .frame(maxWidth: .infinity, minHeight: 600)
        }
      }
      .background(Color(NSColor.controlBackgroundColor).opacity(0.3))
    }
  }
}
