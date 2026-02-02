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

// MARK: - Research Board View (document-first layout)

struct ResearchBoardView: View {
  @ObservedObject var vm: AppViewModel

  @State private var showAddTile = false
  @State private var showAddRequest = false
  @State private var selectedTile: ResearchTile? = nil
  @State private var pendingRequestTileId: String? = nil
  @State private var pendingRequestPrompt: String = ""
  @State private var searchText: String = ""

  private var activeTiles: [ResearchTile] {
    vm.researchTiles.filter { $0.resolvedStatus == .active }
  }

  /// Tiles sorted into document sections: findings first, then notes, links, comparisons
  private var documentSections: [(String, String, [ResearchTile])] {
    let tiles = activeTiles
    var sections: [(String, String, [ResearchTile])] = []

    let findings = tiles.filter { $0.type == .finding }
    if !findings.isEmpty { sections.append(("Findings", "lightbulb", findings)) }

    let comparisons = tiles.filter { $0.type == .comparison }
    if !comparisons.isEmpty { sections.append(("Comparisons", "arrow.left.arrow.right", comparisons)) }

    let notes = tiles.filter { $0.type == .note }
    if !notes.isEmpty { sections.append(("Notes", "note.text", notes)) }

    let links = tiles.filter { $0.type == .link }
    if !links.isEmpty { sections.append(("Links & Sources", "link", links)) }

    return sections
  }

  /// All source URLs collected from tiles
  private var sources: [(String, String)] { // (title, url)
    var result: [(String, String)] = []
    for tile in activeTiles {
      if let url = tile.url, !url.isEmpty {
        result.append((tile.title, url))
      }
    }
    return result
  }

  private var openRequests: [ResearchRequest] {
    vm.researchRequests.filter { $0.status != .done }
  }

  private var completedRequests: [ResearchRequest] {
    vm.researchRequests.filter { $0.status == .done }
  }

  var body: some View {
    HSplitView {
      // Left sidebar: sources & requests
      VStack(alignment: .leading, spacing: 0) {
        // Sidebar header
        HStack(spacing: 8) {
          Image(systemName: "doc.text.magnifyingglass")
            .foregroundStyle(.orange)
          Text("Research")
            .font(.callout)
            .fontWeight(.bold)
          Spacer()
          Button(action: { showAddRequest = true }) {
            Image(systemName: "questionmark.bubble")
              .font(.body)
              .padding(4)
              .background(Color.orange.opacity(0.12))
              .clipShape(RoundedRectangle(cornerRadius: 6))
          }
          .buttonStyle(.plain)
          .help("Ask Lobs to research something")

          Button(action: { showAddTile = true }) {
            Image(systemName: "plus.square")
              .font(.body)
              .padding(4)
              .background(RTheme.subtle)
              .clipShape(RoundedRectangle(cornerRadius: 6))
          }
          .buttonStyle(.plain)
          .help("Add tile manually")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)

        Divider()

        ScrollView {
          VStack(alignment: .leading, spacing: 16) {
            // Open requests
            if !openRequests.isEmpty {
              SidebarSection(title: "Open Requests", icon: "questionmark.bubble", color: .orange) {
                ForEach(openRequests) { req in
                  SidebarRequestRow(request: req)
                }
              }
            }

            // Sources list
            if !sources.isEmpty {
              SidebarSection(title: "Sources", icon: "link", color: .blue) {
                ForEach(sources, id: \.1) { title, url in
                  SidebarSourceRow(title: title, url: url)
                }
              }
            }

            // Document outline / table of contents
            if !documentSections.isEmpty {
              SidebarSection(title: "Contents", icon: "list.bullet", color: .secondary) {
                ForEach(documentSections, id: \.0) { sectionTitle, icon, tiles in
                  HStack(spacing: 6) {
                    Image(systemName: icon)
                      .font(.system(size: 13))
                      .foregroundStyle(.secondary)
                    Text(sectionTitle)
                      .font(.footnote)
                      .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(tiles.count)")
                      .font(.system(size: 11))
                      .foregroundStyle(.tertiary)
                  }
                  .padding(.vertical, 2)
                }
              }
            }

            // Completed requests
            if !completedRequests.isEmpty {
              DisclosureGroup {
                ForEach(completedRequests) { req in
                  SidebarRequestRow(request: req)
                }
              } label: {
                HStack(spacing: 6) {
                  Image(systemName: "checkmark.bubble")
                    .font(.footnote)
                    .foregroundStyle(.green)
                  Text("Done (\(completedRequests.count))")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }
              }
              .padding(.horizontal, 14)
            }
          }
          .padding(.vertical, 12)
        }
      }
      .frame(minWidth: 220, idealWidth: 260, maxWidth: 320)
      .background(RTheme.bg)

      // Main content: document view
      ScrollView {
        VStack(alignment: .leading, spacing: 0) {
          // Document header
          if let project = vm.selectedProject {
            VStack(alignment: .leading, spacing: 8) {
              Text(project.title)
                .font(.largeTitle)
                .fontWeight(.bold)

              if let notes = project.notes, !notes.isEmpty {
                Text(notes)
                  .font(.body)
                  .foregroundStyle(.secondary)
              }

              HStack(spacing: 12) {
                HStack(spacing: 4) {
                  Image(systemName: "square.grid.2x2")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                  Text("\(activeTiles.count) items")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }
                HStack(spacing: 4) {
                  Image(systemName: "link")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                  Text("\(sources.count) sources")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }
              }

              Divider()
                .padding(.top, 4)
            }
            .padding(.horizontal, 40)
            .padding(.top, 32)
            .padding(.bottom, 16)
          }

          // Document body — render tiles as sections of a brief
          if activeTiles.isEmpty {
            emptyState
          } else {
            VStack(alignment: .leading, spacing: 32) {
              ForEach(documentSections, id: \.0) { sectionTitle, icon, tiles in
                DocumentSection(
                  title: sectionTitle,
                  icon: icon,
                  tiles: tiles,
                  selectedTile: $selectedTile,
                  onAskFollowUp: { tile in
                    pendingRequestTileId = tile.id
                    pendingRequestPrompt = "Follow up on: \(tile.title)"
                    showAddRequest = true
                  }
                )
              }
            }
            .padding(.horizontal, 40)
            .padding(.bottom, 40)
          }
        }
      }
      .frame(minWidth: 500)
      .background(RTheme.boardBg)

      // Right panel: tile detail editor (when selected)
      if let tile = selectedTile,
         let liveTile = vm.researchTiles.first(where: { $0.id == tile.id }) {
        TileDetailView(tile: liveTile, vm: vm, onClose: { selectedTile = nil })
          .id(liveTile.id)
          .frame(minWidth: 320, idealWidth: 380)
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

  private var emptyState: some View {
    VStack(spacing: 12) {
      Image(systemName: "doc.text.magnifyingglass")
        .font(.system(size: 40))
        .foregroundStyle(.secondary)
      Text("No research yet")
        .font(.title3)
        .foregroundStyle(.secondary)
      Text("Ask Lobs to research something, or add tiles manually")
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
    .padding(.horizontal, 40)
  }
}

// MARK: - Sidebar Components

private struct SidebarSection<Content: View>: View {
  let title: String
  let icon: String
  let color: Color
  @ViewBuilder let content: () -> Content

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack(spacing: 6) {
        Image(systemName: icon)
          .font(.footnote)
          .foregroundStyle(color)
        Text(title)
          .font(.system(size: 12, weight: .bold))
          .foregroundStyle(.secondary)
          .textCase(.uppercase)
      }
      .padding(.horizontal, 14)

      VStack(alignment: .leading, spacing: 2) {
        content()
      }
      .padding(.horizontal, 14)
    }
  }
}

private struct SidebarSourceRow: View {
  let title: String
  let url: String
  @State private var isHovering = false

  var body: some View {
    Button {
      if let u = URL(string: url) { NSWorkspace.shared.open(u) }
    } label: {
      HStack(spacing: 6) {
        Image(systemName: "arrow.up.right.square")
          .font(.system(size: 13))
          .foregroundStyle(.blue)
        Text(title)
          .font(.footnote)
          .foregroundStyle(.primary)
          .lineLimit(2)
      }
      .padding(.vertical, 4)
      .padding(.horizontal, 6)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(isHovering ? RTheme.subtle : Color.clear)
      .clipShape(RoundedRectangle(cornerRadius: 6))
    }
    .buttonStyle(.plain)
    .onHover { h in isHovering = h }
    .help(url)
  }
}

private struct SidebarRequestRow: View {
  let request: ResearchRequest

  var body: some View {
    VStack(alignment: .leading, spacing: 2) {
      HStack(spacing: 6) {
        Circle()
          .fill(requestStatusColor(request.status))
          .frame(width: 6, height: 6)
        Text(request.prompt)
          .font(.footnote)
          .lineLimit(2)
      }
      Text(relativeTime(request.createdAt))
        .font(.system(size: 11))
        .foregroundStyle(.quaternary)
    }
    .padding(.vertical, 4)
    .padding(.horizontal, 6)
  }
}

// MARK: - Document Section

private struct DocumentSection: View {
  let title: String
  let icon: String
  let tiles: [ResearchTile]
  @Binding var selectedTile: ResearchTile?
  let onAskFollowUp: (ResearchTile) -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      // Section heading
      HStack(spacing: 8) {
        Image(systemName: icon)
          .font(.title3)
          .foregroundStyle(sectionColor)
        Text(title)
          .font(.title2)
          .fontWeight(.bold)
      }

      // Render each tile as a paragraph/subsection of the document
      ForEach(tiles) { tile in
        DocumentTileBlock(
          tile: tile,
          isSelected: selectedTile?.id == tile.id,
          onTap: { selectedTile = tile },
          onAskFollowUp: { onAskFollowUp(tile) }
        )
      }
    }
  }

  private var sectionColor: Color {
    switch title {
    case "Findings": return .orange
    case "Comparisons": return .purple
    case "Notes": return .green
    case "Links & Sources": return .blue
    default: return .secondary
    }
  }
}

// MARK: - Document Tile Block (renders a tile as a document paragraph)

private struct DocumentTileBlock: View {
  let tile: ResearchTile
  let isSelected: Bool
  let onTap: () -> Void
  let onAskFollowUp: () -> Void

  @State private var isHovering = false

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      // Title as a subheading
      HStack(spacing: 8) {
        Text(tile.title)
          .font(.title3)
          .fontWeight(.semibold)

        Spacer()

        if isHovering {
          HStack(spacing: 4) {
            Button(action: onAskFollowUp) {
              Image(systemName: "questionmark.bubble")
                .font(.footnote)
                .padding(4)
                .background(RTheme.subtle)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
            .help("Ask follow-up")

            Button(action: onTap) {
              Image(systemName: "pencil")
                .font(.footnote)
                .padding(4)
                .background(RTheme.subtle)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
            .help("Edit tile")
          }
        }
      }

      // Confidence label for findings
      if tile.type == .finding, let confidence = tile.confidence {
        HStack(spacing: 6) {
          Text("Certainty:")
            .font(.footnote)
            .foregroundStyle(.secondary)
          ConfidenceLabel(value: confidence)
        }
      }

      // Claim / key finding — rendered prominently
      if let claim = tile.claim, !claim.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        Text(claim)
          .font(.body)
          .fontWeight(.medium)
          .padding(12)
          .frame(maxWidth: .infinity, alignment: .leading)
          .background(Color.orange.opacity(0.06))
          .clipShape(RoundedRectangle(cornerRadius: 8))
      }

      // Main content — rendered as body text
      if let content = tile.content, !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        Text(contentToAttributed(content))
          .font(.body)
          .foregroundStyle(.primary.opacity(0.85))
          .textSelection(.enabled)
      }

      // Summary
      if let summary = tile.summary, !summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        if tile.content == nil || tile.content?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true {
          Text(contentToAttributed(summary))
            .font(.body)
            .foregroundStyle(.primary.opacity(0.85))
            .textSelection(.enabled)
        } else {
          Text(summary)
            .font(.callout)
            .foregroundStyle(.secondary)
            .italic()
        }
      }

      // URL for link tiles
      if let url = tile.url, !url.isEmpty {
        Button {
          if let u = URL(string: url) { NSWorkspace.shared.open(u) }
        } label: {
          HStack(spacing: 4) {
            Image(systemName: "arrow.up.right.square")
              .font(.footnote)
            Text(url)
              .font(.footnote)
              .lineLimit(1)
          }
          .foregroundStyle(.blue)
        }
        .buttonStyle(.plain)
      }

      // Evidence
      if let evidence = tile.evidence, !evidence.isEmpty {
        VStack(alignment: .leading, spacing: 4) {
          Text("Evidence")
            .font(.footnote)
            .fontWeight(.bold)
            .foregroundStyle(.secondary)
          ForEach(evidence, id: \.self) { e in
            HStack(alignment: .top, spacing: 6) {
              Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 12))
                .foregroundStyle(.green)
                .padding(.top, 2)
              Text(e)
                .font(.callout)
                .foregroundStyle(.secondary)
            }
          }
        }
      }

      // Counterpoints
      if let counterpoints = tile.counterpoints, !counterpoints.isEmpty {
        VStack(alignment: .leading, spacing: 4) {
          Text("Counterpoints")
            .font(.footnote)
            .fontWeight(.bold)
            .foregroundStyle(.secondary)
          ForEach(counterpoints, id: \.self) { c in
            HStack(alignment: .top, spacing: 6) {
              Image(systemName: "xmark.circle.fill")
                .font(.system(size: 12))
                .foregroundStyle(.red)
                .padding(.top, 2)
              Text(c)
                .font(.callout)
                .foregroundStyle(.secondary)
            }
          }
        }
      }

      // Comparison options
      if let options = tile.options, !options.isEmpty {
        VStack(alignment: .leading, spacing: 12) {
          ForEach(options, id: \.name) { opt in
            ComparisonOptionView(option: opt)
          }
        }
      }

      // Tags
      if let tags = tile.tags, !tags.isEmpty {
        HStack(spacing: 4) {
          ForEach(tags, id: \.self) { tag in
            Text("#\(tag)")
              .font(.system(size: 11))
              .foregroundStyle(.blue)
          }
        }
      }

      // Authorship & timestamp
      HStack(spacing: 8) {
        if let author = tile.author {
          Text("by \(author)")
            .font(.system(size: 11))
            .foregroundStyle(.quaternary)
        }
        Text(relativeTime(tile.updatedAt))
          .font(.system(size: 11))
          .foregroundStyle(.quaternary)
      }
    }
    .padding(16)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(
      RoundedRectangle(cornerRadius: RTheme.cardRadius)
        .fill(isSelected ? RTheme.accent.opacity(0.05) : Color.clear)
    )
    .overlay(
      RoundedRectangle(cornerRadius: RTheme.cardRadius)
        .stroke(isSelected ? RTheme.accent.opacity(0.3) : Color.clear, lineWidth: 1)
    )
    .contentShape(Rectangle())
    .onTapGesture { onTap() }
    .onHover { h in isHovering = h }
  }
}

// MARK: - Confidence Label (Strong / Moderate / Weak)

private struct ConfidenceLabel: View {
  let value: Double

  private var tier: (String, Color) {
    if value >= 0.7 { return ("Strong", .green) }
    if value >= 0.4 { return ("Moderate", .yellow) }
    return ("Weak", .red)
  }

  var body: some View {
    let (label, color) = tier
    Text(label)
      .font(.system(size: 11, weight: .semibold))
      .padding(.horizontal, 7)
      .padding(.vertical, 2)
      .background(color.opacity(0.15))
      .foregroundStyle(color)
      .clipShape(Capsule())
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
              .font(.system(size: 13))
              .foregroundStyle(.green)
            Text(pro).font(.footnote)
          }
        }
      }

      if let cons = option.cons, !cons.isEmpty {
        ForEach(cons, id: \.self) { con in
          HStack(spacing: 4) {
            Image(systemName: "minus.circle.fill")
              .font(.system(size: 13))
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

// MARK: - Request Card (used in detail panel)

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
              ConfidenceLabel(value: editConfidence)
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

/// Simple markdown-like rendering: converts **bold** and bullet points for display.
private func contentToAttributed(_ text: String) -> AttributedString {
  var result = AttributedString(text)
  // SwiftUI's Text handles basic markdown in AttributedString
  if let parsed = try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
    result = parsed
  }
  return result
}
