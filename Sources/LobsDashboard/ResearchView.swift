import SwiftUI

// MARK: - Theme (shared reference — uses same palette as ContentView)

private enum RTheme {
  static let bg = Color(nsColor: .windowBackgroundColor)
  static let boardBg = Color(nsColor: .underPageBackgroundColor)
  static let cardBg = Color(nsColor: .controlBackgroundColor)
  static let accent = Color.accentColor
  static let subtle = Color.primary.opacity(0.06)
  static let border = Color.primary.opacity(0.08)
  static let cardRadius: CGFloat = 14
}

// MARK: - Research Board View (replaces kanban for research projects)

struct ResearchBoardView: View {
  @ObservedObject var vm: AppViewModel

  @State private var showAddTile = false
  @State private var showAddRequest = false
  @State private var selectedTile: ResearchTile? = nil
  @State private var pendingRequestTileId: String? = nil
  @State private var pendingRequestPrompt: String = ""
  @State private var filterType: ResearchTileType? = nil
  @State private var searchText: String = ""

  private var filteredTiles: [ResearchTile] {
    var tiles = vm.researchTiles.filter { $0.resolvedStatus == .active }
    if let filterType {
      tiles = tiles.filter { $0.type == filterType }
    }
    let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    if !q.isEmpty {
      tiles = tiles.filter { tile in
        let hay = [tile.title, tile.content, tile.summary, tile.claim, tile.url]
          .compactMap { $0 }
          .joined(separator: " ")
          .lowercased()
        return hay.contains(q)
      }
    }
    return tiles
  }

  private var openRequests: [ResearchRequest] {
    vm.researchRequests.filter { $0.status != .done }
  }

  private var completedRequests: [ResearchRequest] {
    vm.researchRequests.filter { $0.status == .done }
  }

  private let columns = [
    GridItem(.adaptive(minimum: 280, maximum: 400), spacing: 16)
  ]

  var body: some View {
    HSplitView {
      // Left: Tile Grid + Requests
      VStack(spacing: 0) {
        // Filter bar
        ResearchFilterBar(
          filterType: $filterType,
          searchText: $searchText,
          tileCount: filteredTiles.count,
          requestCount: openRequests.count,
          onAddTile: { showAddTile = true },
          onAddRequest: { showAddRequest = true }
        )

        Divider()

        ScrollView {
          VStack(alignment: .leading, spacing: 20) {
            // Open requests section
            if !openRequests.isEmpty {
              VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                  Image(systemName: "questionmark.bubble")
                    .foregroundStyle(.orange)
                  Text("Open Requests")
                    .font(.callout)
                    .fontWeight(.bold)
                  Text("\(openRequests.count)")
                    .font(.footnote)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.orange.opacity(0.15))
                    .foregroundStyle(.orange)
                    .clipShape(Capsule())
                }

                ForEach(openRequests) { req in
                  RequestCard(request: req, vm: vm)
                }
              }
              .padding(.horizontal, 20)
              .padding(.top, 16)
            }

            // Tiles grid
            if !filteredTiles.isEmpty {
              VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                  Image(systemName: "square.grid.2x2")
                    .foregroundStyle(.blue)
                  Text("Research Tiles")
                    .font(.callout)
                    .fontWeight(.bold)
                  Text("\(filteredTiles.count)")
                    .font(.footnote)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.blue.opacity(0.15))
                    .foregroundStyle(.blue)
                    .clipShape(Capsule())
                }
                .padding(.horizontal, 20)

                LazyVGrid(columns: columns, spacing: 16) {
                  ForEach(filteredTiles) { tile in
                    TileCard(
                      tile: tile,
                      onAskFollowUp: {
                        pendingRequestTileId = tile.id
                        pendingRequestPrompt = "Follow up on: \(tile.title)"
                        showAddRequest = true
                      }
                    )
                    .onTapGesture {
                      selectedTile = tile
                    }
                  }
                }
                .padding(.horizontal, 20)
              }
              .padding(.top, openRequests.isEmpty ? 16 : 8)
            }

            // Completed requests (collapsed)
            if !completedRequests.isEmpty {
              DisclosureGroup {
                VStack(alignment: .leading, spacing: 8) {
                  ForEach(completedRequests) { req in
                    RequestCard(request: req, vm: vm)
                  }
                }
              } label: {
                HStack(spacing: 6) {
                  Image(systemName: "checkmark.bubble")
                    .foregroundStyle(.green)
                  Text("Completed Requests")
                    .font(.callout)
                    .fontWeight(.bold)
                  Text("\(completedRequests.count)")
                    .font(.footnote)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.green.opacity(0.15))
                    .foregroundStyle(.green)
                    .clipShape(Capsule())
                }
              }
              .padding(.horizontal, 20)
              .padding(.top, 8)
            }

            if filteredTiles.isEmpty && openRequests.isEmpty && completedRequests.isEmpty {
              VStack(spacing: 12) {
                Image(systemName: "doc.text.magnifyingglass")
                  .font(.system(size: 40))
                  .foregroundStyle(.secondary)
                Text("No research yet")
                  .font(.title3)
                  .foregroundStyle(.secondary)
                Text("Add tiles or ask Lobs to research something")
                  .font(.footnote)
                  .foregroundStyle(.tertiary)
                HStack(spacing: 12) {
                  Button {
                    showAddTile = true
                  } label: {
                    Label("Add Tile", systemImage: "plus.square")
                  }
                  .buttonStyle(.bordered)
                  Button {
                    showAddRequest = true
                  } label: {
                    Label("Ask Lobs", systemImage: "questionmark.bubble")
                  }
                  .buttonStyle(.borderedProminent)
                }
              }
              .frame(maxWidth: .infinity)
              .padding(.top, 80)
            }
          }
          .padding(.bottom, 20)
        }
      }
      .frame(minWidth: 500)

      // Right: Tile detail
      if let tile = selectedTile,
         let liveTile = vm.researchTiles.first(where: { $0.id == tile.id }) {
        TileDetailView(tile: liveTile, vm: vm, onClose: { selectedTile = nil })
          .frame(minWidth: 350, idealWidth: 420)
      } else {
        VStack(spacing: 8) {
          Image(systemName: "sidebar.right")
            .font(.system(size: 30))
            .foregroundStyle(.quaternary)
          Text("Select a tile to view details")
            .font(.footnote)
            .foregroundStyle(.tertiary)
        }
        .frame(minWidth: 300, idealWidth: 350)
        .frame(maxHeight: .infinity)
      }
    }
    .sheet(isPresented: $showAddTile) {
      AddTileSheet(vm: vm)
    }
    .sheet(isPresented: $showAddRequest) {
      AddRequestSheet(
        vm: vm,
        initialPrompt: pendingRequestPrompt,
        initialTileId: pendingRequestTileId
      )
      .onDisappear {
        pendingRequestTileId = nil
        pendingRequestPrompt = ""
      }
    }
  }
}

// MARK: - Filter Bar

private struct ResearchFilterBar: View {
  @Binding var filterType: ResearchTileType?
  @Binding var searchText: String
  let tileCount: Int
  let requestCount: Int
  let onAddTile: () -> Void
  let onAddRequest: () -> Void

  var body: some View {
    HStack(spacing: 12) {
      // Type filter chips
      FilterChip(label: "All", isActive: filterType == nil) {
        filterType = nil
      }
      ForEach(ResearchTileType.allCases, id: \.self) { type in
        FilterChip(
          label: tileTypeLabel(type),
          icon: tileTypeIcon(type),
          isActive: filterType == type
        ) {
          filterType = (filterType == type) ? nil : type
        }
      }

      Spacer()

      // Search
      HStack(spacing: 6) {
        Image(systemName: "magnifyingglass")
          .foregroundStyle(.secondary)
          .font(.footnote)
        TextField("Search tiles…", text: $searchText)
          .textFieldStyle(.plain)
          .frame(width: 160)
      }
      .padding(.horizontal, 10)
      .padding(.vertical, 6)
      .background(RTheme.subtle)
      .clipShape(RoundedRectangle(cornerRadius: 8))

      // Action buttons
      Button(action: onAddTile) {
        Image(systemName: "plus.square")
          .font(.body)
          .padding(6)
          .background(RTheme.subtle)
          .clipShape(RoundedRectangle(cornerRadius: 8))
      }
      .buttonStyle(.plain)
      .help("Add research tile")

      Button(action: onAddRequest) {
        Image(systemName: "questionmark.bubble")
          .font(.body)
          .padding(6)
          .background(Color.orange.opacity(0.12))
          .clipShape(RoundedRectangle(cornerRadius: 8))
      }
      .buttonStyle(.plain)
      .help("Ask Lobs to research something")
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 8)
  }
}

private struct FilterChip: View {
  let label: String
  var icon: String? = nil
  let isActive: Bool
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      HStack(spacing: 4) {
        if let icon {
          Image(systemName: icon)
            .font(.footnote)
        }
        Text(label)
          .font(.footnote)
          .fontWeight(isActive ? .semibold : .regular)
      }
      .padding(.horizontal, 10)
      .padding(.vertical, 5)
      .background(isActive ? Color.accentColor.opacity(0.15) : RTheme.subtle)
      .foregroundStyle(isActive ? .primary : .secondary)
      .clipShape(Capsule())
    }
    .buttonStyle(.plain)
  }
}

// MARK: - Tile Card

private struct TileCard: View {
  let tile: ResearchTile
  let onAskFollowUp: () -> Void

  @State private var isHovering = false

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      // Type badge + title
      HStack(spacing: 6) {
        Image(systemName: tileTypeIcon(tile.type))
          .font(.footnote)
          .foregroundStyle(tileTypeColor(tile.type))
        Text(tileTypeLabel(tile.type))
          .font(.system(size: 11, weight: .medium))
          .foregroundStyle(tileTypeColor(tile.type))
          .padding(.horizontal, 6)
          .padding(.vertical, 2)
          .background(tileTypeColor(tile.type).opacity(0.12))
          .clipShape(Capsule())
        Spacer()

        if isHovering {
          Button {
            onAskFollowUp()
          } label: {
            Image(systemName: "questionmark.bubble")
              .font(.footnote)
              .padding(6)
              .background(RTheme.subtle)
              .clipShape(RoundedRectangle(cornerRadius: 8))
          }
          .buttonStyle(.plain)
          .help("Ask follow-up")
        }

        if let author = tile.author {
          Text(author)
            .font(.system(size: 11))
            .foregroundStyle(.tertiary)
        }
      }

      Text(tile.title)
        .font(.headline)
        .fontWeight(.semibold)
        .lineLimit(2)

      // Type-specific preview
      Group {
        switch tile.type {
        case .link:
          if let url = tile.url {
            Text(url)
              .font(.footnote)
              .foregroundStyle(.blue)
              .lineLimit(1)
          }
          if let summary = tile.summary {
            Text(summary)
              .font(.body)
              .foregroundStyle(.secondary)
              .lineLimit(3)
          }

        case .note:
          if let content = tile.content {
            Text(content)
              .font(.footnote)
              .foregroundStyle(.secondary)
              .lineLimit(4)
          }

        case .finding:
          if let claim = tile.claim, !claim.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            VStack(alignment: .leading, spacing: 4) {
              Text("Key Finding")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
              Text(claim)
                .font(.body)
                .foregroundStyle(.secondary)
                .lineLimit(4)
            }
          } else if let content = tile.content, !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            // Fallback: show content preview when claim is absent
            Text(content)
              .font(.body)
              .foregroundStyle(.secondary)
              .lineLimit(4)
          }

          if let confidence = tile.confidence {
            HStack(spacing: 6) {
              Text("Certainty")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
              ConfidenceBar(value: confidence)
            }
          }

          if let summary = tile.summary, !summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            VStack(alignment: .leading, spacing: 4) {
              Text("Summary")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
              ForEach(topBullets(summary, max: 3), id: \.self) { line in
                Text("• \(line)")
                  .font(.body)
                  .foregroundStyle(.secondary)
                  .lineLimit(2)
              }
            }
          }

          if let evidence = tile.evidence, !evidence.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
              Text("Evidence")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
              ForEach(evidence.prefix(2), id: \.self) { e in
                Text("• \(e)")
                  .font(.system(size: 11))
                  .foregroundStyle(.secondary)
                  .lineLimit(2)
              }
            }
          }

          if let counter = tile.counterpoints, !counter.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
              Text("Counterpoints")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
              ForEach(counter.prefix(2), id: \.self) { c in
                Text("• \(c)")
                  .font(.system(size: 11))
                  .foregroundStyle(.secondary)
                  .lineLimit(2)
              }
            }
          }

        case .comparison:
          if let options = tile.options {
            HStack(spacing: 4) {
              ForEach(options.prefix(3), id: \.name) { opt in
                Text(opt.name)
                  .font(.system(size: 11, weight: .medium))
                  .padding(.horizontal, 6)
                  .padding(.vertical, 2)
                  .background(RTheme.subtle)
                  .clipShape(Capsule())
              }
              if options.count > 3 {
                Text("+\(options.count - 3)")
                  .font(.system(size: 11))
                  .foregroundStyle(.tertiary)
              }
            }
          }
        }
      }

      // Tags
      if let tags = tile.tags, !tags.isEmpty {
        HStack(spacing: 4) {
          ForEach(tags.prefix(4), id: \.self) { tag in
            Text("#\(tag)")
              .font(.system(size: 11))
              .foregroundStyle(.blue)
          }
        }
      }

      // Timestamp
      Text(relativeTime(tile.updatedAt))
        .font(.system(size: 11))
        .foregroundStyle(.quaternary)
    }
    .padding(12)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(
      RoundedRectangle(cornerRadius: RTheme.cardRadius)
        .fill(RTheme.cardBg)
        .shadow(color: .black.opacity(isHovering ? 0.08 : 0.03), radius: isHovering ? 8 : 3, y: 1)
    )
    .overlay(
      RoundedRectangle(cornerRadius: RTheme.cardRadius)
        .stroke(RTheme.border, lineWidth: 0.5)
    )
    .scaleEffect(isHovering ? 1.01 : 1.0)
    .animation(.easeOut(duration: 0.15), value: isHovering)
    .onHover { h in isHovering = h }
  }
}

// MARK: - Confidence Bar

private struct ConfidenceBar: View {
  let value: Double

  var body: some View {
    HStack(spacing: 2) {
      GeometryReader { geo in
        ZStack(alignment: .leading) {
          RoundedRectangle(cornerRadius: 2)
            .fill(Color.primary.opacity(0.08))
          RoundedRectangle(cornerRadius: 2)
            .fill(confidenceColor)
            .frame(width: geo.size.width * min(max(value, 0), 1))
        }
      }
      .frame(width: 50, height: 6)

      Text("\(Int(value * 100))%")
        .font(.system(size: 11, weight: .medium, design: .monospaced))
        .foregroundStyle(.secondary)
    }
  }

  private var confidenceColor: Color {
    if value >= 0.8 { return .green }
    if value >= 0.5 { return .orange }
    return .red
  }
}

// MARK: - Request Card

private struct RequestCard: View {
  let request: ResearchRequest
  @ObservedObject var vm: AppViewModel

  @State private var isHovering = false

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(spacing: 8) {
        Circle()
          .fill(requestStatusColor(request.status))
          .frame(width: 8, height: 8)
        Text(request.prompt)
          .font(.callout)
          .fontWeight(.medium)
          .lineLimit(2)
        Spacer()
        Text(request.status.rawValue.replacingOccurrences(of: "_", with: " "))
          .font(.system(size: 11, weight: .medium))
          .padding(.horizontal, 7)
          .padding(.vertical, 2)
          .background(requestStatusColor(request.status).opacity(0.12))
          .foregroundStyle(requestStatusColor(request.status))
          .clipShape(Capsule())
      }

      if let response = request.response, !response.isEmpty {
        Text(response)
          .font(.footnote)
          .foregroundStyle(.secondary)
          .lineLimit(4)
          .padding(8)
          .frame(maxWidth: .infinity, alignment: .leading)
          .background(RTheme.subtle)
          .clipShape(RoundedRectangle(cornerRadius: 8))
      }

      HStack {
        if let author = request.author {
          Text("by \(author)")
            .font(.system(size: 11))
            .foregroundStyle(.tertiary)
        }
        Text("·")
          .font(.system(size: 11))
          .foregroundStyle(.quaternary)
        Text(relativeTime(request.createdAt))
          .font(.system(size: 11))
          .foregroundStyle(.quaternary)
      }
    }
    .padding(12)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(
      RoundedRectangle(cornerRadius: RTheme.cardRadius)
        .fill(RTheme.cardBg)
        .shadow(color: .black.opacity(isHovering ? 0.06 : 0.02), radius: isHovering ? 6 : 2, y: 1)
    )
    .overlay(
      RoundedRectangle(cornerRadius: RTheme.cardRadius)
        .stroke(requestStatusColor(request.status).opacity(0.2), lineWidth: 1)
    )
    .onHover { h in isHovering = h }
  }
}

// MARK: - Tile Detail View

private struct TileDetailView: View {
  let tile: ResearchTile
  @ObservedObject var vm: AppViewModel
  let onClose: () -> Void

  @State private var editTitle: String = ""
  @State private var editContent: String = ""
  @State private var editUrl: String = ""
  @State private var editClaim: String = ""
  @State private var editSummary: String = ""
  @State private var editTags: String = ""
  @State private var editConfidence: Double = 0.5
  @State private var showAskLobs = false
  @State private var askPrompt: String = ""

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 16) {
        // Header
        HStack {
          Image(systemName: tileTypeIcon(tile.type))
            .foregroundStyle(tileTypeColor(tile.type))
          Text(tileTypeLabel(tile.type))
            .font(.callout)
            .fontWeight(.bold)
            .foregroundStyle(tileTypeColor(tile.type))
          Spacer()
          Button(action: onClose) {
            Image(systemName: "xmark")
              .font(.footnote)
              .foregroundStyle(.secondary)
          }
          .buttonStyle(.plain)
        }

        // Title
        TextField("Title", text: $editTitle)
          .font(.headline)
          .fontWeight(.semibold)
          .textFieldStyle(.plain)
          .onAppear { loadFields() }
          .onChange(of: tile.id) { _ in loadFields() }

        // Type-specific fields
        switch tile.type {
        case .link:
          VStack(alignment: .leading, spacing: 8) {
            Text("URL")
              .font(.callout)
              .foregroundStyle(.secondary)
            TextField("https://…", text: $editUrl)
              .font(.body)
              .textFieldStyle(.roundedBorder)

            if !editUrl.isEmpty {
              Button {
                if let url = URL(string: editUrl) {
                  NSWorkspace.shared.open(url)
                }
              } label: {
                Label("Open in Browser", systemImage: "arrow.up.right.square")
              }
              .buttonStyle(.bordered)
              .controlSize(.small)
            }

            Text("Summary")
              .font(.callout)
              .foregroundStyle(.secondary)
            TextField("Summary…", text: $editSummary, axis: .vertical)
              .font(.body)
              .textFieldStyle(.roundedBorder)
              .lineLimit(6, reservesSpace: true)
          }

        case .note:
          VStack(alignment: .leading, spacing: 8) {
            Text("Content")
              .font(.callout)
              .foregroundStyle(.secondary)
            TextField("Write your notes…", text: $editContent, axis: .vertical)
              .font(.body)
              .textFieldStyle(.roundedBorder)
              .lineLimit(12, reservesSpace: true)
          }

        case .finding:
          VStack(alignment: .leading, spacing: 8) {
            // Summary
            Text("Summary")
              .font(.callout)
              .foregroundStyle(.secondary)
            TextField("Summarize the finding…", text: $editSummary, axis: .vertical)
              .font(.body)
              .textFieldStyle(.roundedBorder)
              .lineLimit(4, reservesSpace: true)

            // Key Finding
            Text("Key Finding")
              .font(.callout)
              .foregroundStyle(.secondary)
            TextField("State the finding…", text: $editClaim, axis: .vertical)
              .font(.body)
              .textFieldStyle(.roundedBorder)
              .lineLimit(4, reservesSpace: true)

            // Certainty
            HStack {
              Text("Certainty")
                .font(.callout)
                .foregroundStyle(.secondary)
              Slider(value: $editConfidence, in: 0...1, step: 0.05)
              Text("\(Int(editConfidence * 100))%")
                .font(.callout)
                .monospacedDigit()
                .frame(width: 35, alignment: .trailing)
            }

            // Evidence
            if let evidence = tile.evidence, !evidence.isEmpty {
              VStack(alignment: .leading, spacing: 6) {
                Text("Evidence")
                  .font(.callout)
                  .foregroundStyle(.secondary)
                ForEach(evidence, id: \.self) { e in
                  HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                      .font(.system(size: 13))
                      .foregroundStyle(.green)
                    Text(e)
                      .font(.body)
                  }
                }
              }
            }

            // Counterpoints
            if let counterpoints = tile.counterpoints, !counterpoints.isEmpty {
              VStack(alignment: .leading, spacing: 6) {
                Text("Counterpoints")
                  .font(.callout)
                  .foregroundStyle(.secondary)
                ForEach(counterpoints, id: \.self) { c in
                  HStack(spacing: 4) {
                    Image(systemName: "xmark.circle.fill")
                      .font(.system(size: 13))
                      .foregroundStyle(.red)
                    Text(c)
                      .font(.body)
                  }
                }
              }
            }

            // Content (detailed notes/body text)
            if let content = tile.content, !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
              VStack(alignment: .leading, spacing: 4) {
                Text("Content")
                  .font(.callout)
                  .foregroundStyle(.secondary)
                Text(content)
                  .font(.body)
                  .foregroundStyle(.secondary)
                  .textSelection(.enabled)
              }
            }
          }

        case .comparison:
          if let options = tile.options {
            VStack(alignment: .leading, spacing: 12) {
              Text("Options")
                .font(.callout)
                .foregroundStyle(.secondary)
              ForEach(options, id: \.name) { opt in
                ComparisonOptionView(option: opt)
              }
            }
          }
        }

        Divider()

        // Tags
        VStack(alignment: .leading, spacing: 4) {
          Text("Tags (comma-separated)")
            .font(.callout)
            .foregroundStyle(.secondary)
          TextField("tag1, tag2, …", text: $editTags)
            .font(.body)
            .textFieldStyle(.roundedBorder)
        }

        // Actions
        HStack(spacing: 8) {
          Button {
            saveChanges()
          } label: {
            Label("Save", systemImage: "square.and.arrow.down")
          }
          .buttonStyle(.borderedProminent)
          .controlSize(.small)

          Button {
            showAskLobs.toggle()
          } label: {
            Label("Ask Lobs", systemImage: "questionmark.bubble")
          }
          .buttonStyle(.bordered)
          .controlSize(.small)

          Spacer()

          Button(role: .destructive) {
            vm.removeTile(tile)
            onClose()
          } label: {
            Label("Delete", systemImage: "trash")
          }
          .buttonStyle(.bordered)
          .controlSize(.small)
        }

        if showAskLobs {
          VStack(alignment: .leading, spacing: 8) {
            Text("Ask Lobs about this tile")
              .font(.footnote)
              .foregroundStyle(.secondary)
            TextField("What should Lobs investigate?", text: $askPrompt, axis: .vertical)
              .textFieldStyle(.roundedBorder)
              .lineLimit(3, reservesSpace: true)
            Button {
              let prompt = askPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
              guard !prompt.isEmpty else { return }
              vm.addRequest(prompt: prompt, tileId: tile.id)
              askPrompt = ""
              showAskLobs = false
            } label: {
              Label("Submit Request", systemImage: "paperplane")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(askPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
          }
          .padding(10)
          .background(RTheme.subtle)
          .clipShape(RoundedRectangle(cornerRadius: 10))
        }

        // Related requests
        let relatedRequests = vm.researchRequests.filter { $0.tileId == tile.id }
        if !relatedRequests.isEmpty {
          Divider()
          VStack(alignment: .leading, spacing: 8) {
            Text("Related Requests")
              .font(.footnote)
              .fontWeight(.bold)
              .foregroundStyle(.secondary)
            ForEach(relatedRequests) { req in
              RequestCard(request: req, vm: vm)
            }
          }
        }

        // Metadata
        Divider()
        VStack(alignment: .leading, spacing: 4) {
          Text("ID: \(tile.id)")
            .font(.system(size: 11, design: .monospaced))
            .foregroundStyle(.quaternary)
            .textSelection(.enabled)
          Text("Created: \(tile.createdAt.formatted())")
            .font(.system(size: 11))
            .foregroundStyle(.quaternary)
          Text("Updated: \(tile.updatedAt.formatted())")
            .font(.system(size: 11))
            .foregroundStyle(.quaternary)
        }
      }
      .padding(20)
    }
    .background(RTheme.bg)
  }

  private func loadFields() {
    editTitle = tile.title
    editContent = tile.content ?? ""
    editUrl = tile.url ?? ""
    editClaim = tile.claim ?? ""
    editSummary = tile.summary ?? ""
    editConfidence = tile.confidence ?? 0.5
    editTags = tile.tags?.joined(separator: ", ") ?? ""
  }

  private func saveChanges() {
    var updated = tile
    updated.title = editTitle
    updated.tags = editTags.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }

    switch tile.type {
    case .link:
      updated.url = editUrl.isEmpty ? nil : editUrl
      updated.summary = editSummary.isEmpty ? nil : editSummary
    case .note:
      updated.content = editContent.isEmpty ? nil : editContent
    case .finding:
      updated.claim = editClaim.isEmpty ? nil : editClaim
      updated.summary = editSummary.isEmpty ? nil : editSummary
      updated.confidence = editConfidence
    case .comparison:
      break // Options editing is complex; keep existing for now
    }

    vm.updateTile(updated)
  }
}

// MARK: - Comparison Option View

private struct ComparisonOptionView: View {
  let option: ComparisonOption

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(option.name)
        .font(.callout)
        .fontWeight(.semibold)

      if let pros = option.pros, !pros.isEmpty {
        ForEach(pros, id: \.self) { pro in
          HStack(spacing: 4) {
            Image(systemName: "plus.circle.fill")
              .font(.system(size: 11))
              .foregroundStyle(.green)
            Text(pro).font(.footnote)
          }
        }
      }

      if let cons = option.cons, !cons.isEmpty {
        ForEach(cons, id: \.self) { con in
          HStack(spacing: 4) {
            Image(systemName: "minus.circle.fill")
              .font(.system(size: 11))
              .foregroundStyle(.red)
            Text(con).font(.footnote)
          }
        }
      }

      HStack(spacing: 12) {
        if let cost = option.cost {
          HStack(spacing: 2) {
            Text("Cost:").font(.system(size: 11)).foregroundStyle(.tertiary)
            Text(cost).font(.system(size: 11, weight: .medium))
          }
        }
        if let risk = option.risk {
          HStack(spacing: 2) {
            Text("Risk:").font(.system(size: 11)).foregroundStyle(.tertiary)
            Text(risk).font(.system(size: 11, weight: .medium))
          }
        }
      }

      if let notes = option.notes {
        Text(notes)
          .font(.footnote)
          .foregroundStyle(.secondary)
      }
    }
    .padding(10)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(RTheme.subtle)
    .clipShape(RoundedRectangle(cornerRadius: 8))
  }
}

// MARK: - Add Tile Sheet

private struct AddTileSheet: View {
  @ObservedObject var vm: AppViewModel
  @Environment(\.dismiss) private var dismiss

  @State private var tileType: ResearchTileType = .note
  @State private var title: String = ""
  @State private var url: String = ""
  @State private var content: String = ""
  @State private var claim: String = ""

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      HStack {
        Image(systemName: "plus.square.fill")
          .font(.title2)
          .foregroundStyle(.linearGradient(
            colors: [.blue, .cyan],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
          ))
        Text("Add Research Tile")
          .font(.title3)
          .fontWeight(.bold)
        Spacer()
      }

      // Type picker
      VStack(alignment: .leading, spacing: 6) {
        Text("Type")
          .font(.footnote)
          .foregroundStyle(.secondary)
        Picker("Type", selection: $tileType) {
          ForEach(ResearchTileType.allCases, id: \.self) { type in
            Label(tileTypeLabel(type), systemImage: tileTypeIcon(type))
              .tag(type)
          }
        }
        .pickerStyle(.segmented)
      }

      // Title
      TextField("Title", text: $title)
        .textFieldStyle(.roundedBorder)

      // Type-specific fields
      switch tileType {
      case .link:
        TextField("URL", text: $url)
          .textFieldStyle(.roundedBorder)

      case .note:
        TextField("Content…", text: $content, axis: .vertical)
          .textFieldStyle(.roundedBorder)
          .lineLimit(6, reservesSpace: true)

      case .finding:
        TextField("Claim / finding…", text: $claim, axis: .vertical)
          .textFieldStyle(.roundedBorder)
          .lineLimit(4, reservesSpace: true)

      case .comparison:
        Text("You can add comparison options after creating the tile.")
          .font(.footnote)
          .foregroundStyle(.secondary)
      }

      HStack {
        Button("Cancel") { dismiss() }
          .keyboardShortcut(.cancelAction)
        Spacer()
        Button("Create") {
          vm.addTile(
            type: tileType,
            title: title,
            url: url.isEmpty ? nil : url,
            content: content.isEmpty ? nil : content,
            claim: claim.isEmpty ? nil : claim
          )
          dismiss()
        }
        .keyboardShortcut(.defaultAction)
        .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
      }
    }
    .padding(20)
    .frame(width: 480)
  }
}

// MARK: - Add Request Sheet

private struct AddRequestSheet: View {
  @ObservedObject var vm: AppViewModel
  let initialPrompt: String
  let initialTileId: String?

  init(vm: AppViewModel, initialPrompt: String = "", initialTileId: String? = nil) {
    self.vm = vm
    self.initialPrompt = initialPrompt
    self.initialTileId = initialTileId
  }

  @Environment(\.dismiss) private var dismiss

  @State private var prompt: String = ""
  @State private var selectedTileId: String? = nil

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      HStack {
        Image(systemName: "questionmark.bubble.fill")
          .font(.title2)
          .foregroundStyle(.linearGradient(
            colors: [.orange, .yellow],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
          ))
        Text("Ask Lobs to Research")
          .font(.title3)
          .fontWeight(.bold)
        Spacer()
      }

      VStack(alignment: .leading, spacing: 6) {
        Text("What should Lobs investigate?")
          .font(.footnote)
          .foregroundStyle(.secondary)
        TextField("Describe what you want researched…", text: $prompt, axis: .vertical)
          .textFieldStyle(.roundedBorder)
          .lineLimit(6, reservesSpace: true)
      }

      // Optionally attach to a tile
      if !vm.researchTiles.isEmpty {
        VStack(alignment: .leading, spacing: 6) {
          Text("Related tile (optional)")
            .font(.footnote)
            .foregroundStyle(.secondary)
          Picker("Tile", selection: $selectedTileId) {
            Text("None").tag(nil as String?)
            ForEach(vm.researchTiles.filter { $0.resolvedStatus == .active }) { tile in
              Text(tile.title).tag(tile.id as String?)
            }
          }
        }
      }

      HStack {
        Button("Cancel") { dismiss() }
          .keyboardShortcut(.cancelAction)
        Spacer()
        Button("Submit Request") {
          vm.addRequest(prompt: prompt, tileId: selectedTileId)
          dismiss()
        }
        .keyboardShortcut(.defaultAction)
        .buttonStyle(.borderedProminent)
        .disabled(prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
      }
    }
    .padding(20)
    .frame(width: 480)
    .onAppear {
      prompt = initialPrompt
      selectedTileId = initialTileId
    }
  }
}

// MARK: - Helpers

private func tileTypeLabel(_ type: ResearchTileType) -> String {
  switch type {
  case .link: return "Link"
  case .note: return "Note"
  case .finding: return "Finding"
  case .comparison: return "Comparison"
  }
}

private func tileTypeIcon(_ type: ResearchTileType) -> String {
  switch type {
  case .link: return "link"
  case .note: return "note.text"
  case .finding: return "lightbulb"
  case .comparison: return "arrow.left.arrow.right"
  }
}

private func tileTypeColor(_ type: ResearchTileType) -> Color {
  switch type {
  case .link: return .blue
  case .note: return .green
  case .finding: return .orange
  case .comparison: return .purple
  }
}

private func requestStatusColor(_ status: ResearchRequestStatus) -> Color {
  switch status {
  case .open: return .orange
  case .inProgress: return .blue
  case .done: return .green
  case .blocked: return .red
  }
}

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

private func topBullets(_ text: String, max: Int) -> [String] {
  var lines = text
    .split(separator: "\n", omittingEmptySubsequences: true)
    .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
    .filter { !$0.isEmpty }

  if lines.isEmpty { return [] }

  // If it's a single long paragraph, try a naive sentence split.
  if lines.count == 1 {
    let s = lines[0]
    if s.count > 140 {
      lines = s
        .split(separator: ".")
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
    }
  }

  func normalize(_ s: String) -> String {
    var out = s
    for prefix in ["- ", "* ", "• "] {
      if out.hasPrefix(prefix) { out = String(out.dropFirst(prefix.count)) }
    }
    return out.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  return Array(lines.prefix(max)).map(normalize).filter { !$0.isEmpty }
}
