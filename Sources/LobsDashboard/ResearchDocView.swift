import SwiftUI

// MARK: - Theme

private enum DocTheme {
  static let bg = Color(nsColor: .windowBackgroundColor)
  static let boardBg = Color(nsColor: .underPageBackgroundColor)
  static let cardBg = Color(nsColor: .controlBackgroundColor)
  static let subtle = Color.primary.opacity(0.06)
  static let border = Color.primary.opacity(0.08)
  static let cardRadius: CGFloat = 14
}

// MARK: - Research Doc View (document-first)

struct ResearchDocView: View {
  @ObservedObject var vm: AppViewModel

  @State private var showAddSource = false
  @State private var showAddRequest = false
  @State private var isEditing = true
  @State private var isCondensed = false
  @State private var editContent: String = ""
  @State private var saveTimer: Timer? = nil
  @State private var docSearchText: String = ""
  @State private var collapsedSections: Set<String> = []
  @State private var followUpSection: String? = nil

  /// Table of contents derived from headings in the doc
  private var tableOfContents: [(Int, String)] { // (level, heading text)
    editContent.split(separator: "\n", omittingEmptySubsequences: false).compactMap { line in
      let trimmed = line.trimmingCharacters(in: .whitespaces)
      if trimmed.hasPrefix("### ") { return (3, String(trimmed.dropFirst(4))) }
      if trimmed.hasPrefix("## ") { return (2, String(trimmed.dropFirst(3))) }
      if trimmed.hasPrefix("# ") { return (1, String(trimmed.dropFirst(2))) }
      return nil
    }
  }

  private var openRequests: [ResearchRequest] {
    vm.researchRequests.filter { $0.status != .done }
  }

  private var completedRequests: [ResearchRequest] {
    vm.researchRequests.filter { $0.status == .done }
  }

  var body: some View {
    HSplitView {
      // Left sidebar: TOC + Sources + Requests
      sidebar
        .frame(minWidth: 220, idealWidth: 260, maxWidth: 320)

      // Main content: document editor
      documentEditor
        .frame(minWidth: 500)
    }
    .onAppear {
      editContent = vm.researchDocContent
    }
    .onChange(of: vm.researchDocContent) { newValue in
      // Sync from external changes (git pull) only if significantly different
      if editContent != newValue && !isEditing {
        editContent = newValue
      }
    }
    .sheet(isPresented: $showAddSource) {
      AddSourceSheet(vm: vm)
    }
    .sheet(isPresented: $showAddRequest) {
      AskLobsResearchSheet(vm: vm, sectionContext: followUpSection)
    }
    .onChange(of: showAddRequest) { isShowing in
      if !isShowing { followUpSection = nil }
    }
  }

  // MARK: - Sidebar

  private var sidebar: some View {
    VStack(alignment: .leading, spacing: 0) {
      // Header
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
            .background(Color.purple.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .help("Ask Lobs to research something")
      }
      .padding(.horizontal, 16)
      .padding(.vertical, 12)

      Divider()

      ScrollView {
        VStack(alignment: .leading, spacing: 16) {
          // Table of Contents
          if !tableOfContents.isEmpty {
            tocSection
          }

          // Sources
          sourcesSection

          // Open Requests
          if !openRequests.isEmpty {
            requestsSection
          }

          // Completed Requests
          if !completedRequests.isEmpty {
            completedRequestsSection
          }
        }
        .padding(12)
      }
    }
    .background(DocTheme.boardBg)
  }

  private var tocSection: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack {
        Image(systemName: "list.bullet")
          .font(.footnote)
          .foregroundStyle(.secondary)
        Text("Contents")
          .font(.footnote)
          .fontWeight(.semibold)
          .foregroundStyle(.secondary)
      }

      // Quick search within doc
      HStack(spacing: 4) {
        Image(systemName: "magnifyingglass")
          .font(.system(size: 10))
          .foregroundStyle(.tertiary)
        TextField("Search doc…", text: $docSearchText)
          .textFieldStyle(.plain)
          .font(.system(size: 11))
      }
      .padding(.horizontal, 6)
      .padding(.vertical, 4)
      .background(DocTheme.bg)
      .clipShape(RoundedRectangle(cornerRadius: 6))

      ForEach(Array(tableOfContents.enumerated()), id: \.offset) { _, entry in
        let (level, heading) = entry
        let isMatch = !docSearchText.isEmpty &&
          heading.localizedCaseInsensitiveContains(docSearchText)
        Button {
          scrollToHeading(heading)
        } label: {
          HStack(spacing: 4) {
            Text(heading)
              .font(.footnote)
              .foregroundStyle(isMatch ? .orange : .primary)
              .lineLimit(1)
            if collapsedSections.contains(heading) {
              Image(systemName: "chevron.right")
                .font(.system(size: 8))
                .foregroundStyle(.tertiary)
            }
          }
        }
        .buttonStyle(.plain)
        .padding(.leading, CGFloat((level - 1) * 12))
      }
    }
    .padding(10)
    .background(DocTheme.subtle)
    .clipShape(RoundedRectangle(cornerRadius: 8))
  }

  private var sourcesSection: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack {
        Image(systemName: "link")
          .font(.footnote)
          .foregroundStyle(.secondary)
        Text("Sources (\(vm.researchSources.count))")
          .font(.footnote)
          .fontWeight(.semibold)
          .foregroundStyle(.secondary)
        Spacer()
        Button(action: { showAddSource = true }) {
          Image(systemName: "plus")
            .font(.system(size: 10, weight: .bold))
            .padding(3)
            .background(DocTheme.subtle)
            .clipShape(Circle())
        }
        .buttonStyle(.plain)
      }

      if vm.researchSources.isEmpty {
        Text("No sources yet")
          .font(.footnote)
          .foregroundStyle(.tertiary)
          .italic()
      } else {
        ForEach(Array(vm.researchSources.enumerated()), id: \.element.id) { idx, source in
          HStack(spacing: 6) {
            // Citation number badge
            Text("\(idx + 1)")
              .font(.system(size: 9, weight: .bold, design: .rounded))
              .foregroundColor(.white)
              .frame(width: 16, height: 16)
              .background(Color.orange)
              .clipShape(Circle())
            VStack(alignment: .leading, spacing: 1) {
              Text(source.title)
                .font(.footnote)
                .fontWeight(.medium)
                .lineLimit(1)
              Text(domainFromURL(source.url))
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
            }
            Spacer()
            // Copy citation to clipboard
            Button {
              let citation = "[\(idx + 1)]"
              NSPasteboard.general.clearContents()
              NSPasteboard.general.setString(citation, forType: .string)
            } label: {
              Image(systemName: "doc.on.clipboard")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Copy citation [\(idx + 1)] to clipboard")
            // Insert citation into doc
            Button {
              insertCitation(source: source)
            } label: {
              Image(systemName: "text.insert")
                .font(.system(size: 10))
                .foregroundStyle(.orange)
            }
            .buttonStyle(.plain)
            .help("Insert [\(idx + 1)] into document")
          }
          .padding(.vertical, 2)
          .contextMenu {
            Button("Insert Citation [\(idx + 1)]") {
              insertCitation(source: source)
            }
            Button("Copy Citation [\(idx + 1)]") {
              NSPasteboard.general.clearContents()
              NSPasteboard.general.setString("[\(idx + 1)]", forType: .string)
            }
            Divider()
            Button("Open in Browser") {
              if let url = URL(string: source.url) {
                NSWorkspace.shared.open(url)
              }
            }
            Button("Copy URL") {
              NSPasteboard.general.clearContents()
              NSPasteboard.general.setString(source.url, forType: .string)
            }
            Divider()
            Button("Remove", role: .destructive) {
              vm.removeResearchSource(id: source.id)
            }
          }
        }
      }
    }
    .padding(10)
    .background(DocTheme.subtle)
    .clipShape(RoundedRectangle(cornerRadius: 8))
  }

  private var requestsSection: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack {
        Image(systemName: "questionmark.bubble")
          .font(.footnote)
          .foregroundStyle(.purple)
        Text("Open Requests (\(openRequests.count))")
          .font(.footnote)
          .fontWeight(.semibold)
          .foregroundStyle(.secondary)
      }

      ForEach(openRequests) { req in
        HStack(spacing: 6) {
          Circle()
            .fill(req.status == .inProgress ? Color.blue : Color.purple)
            .frame(width: 6, height: 6)
          Text(req.prompt)
            .font(.footnote)
            .lineLimit(2)
            .foregroundStyle(.secondary)
        }
      }
    }
    .padding(10)
    .background(Color.purple.opacity(0.06))
    .clipShape(RoundedRectangle(cornerRadius: 8))
  }

  private var completedRequestsSection: some View {
    DisclosureGroup {
      ForEach(completedRequests) { req in
        VStack(alignment: .leading, spacing: 2) {
          Text(req.prompt)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .lineLimit(1)
          if let response = req.response, !response.isEmpty {
            Text(response.prefix(100) + (response.count > 100 ? "…" : ""))
              .font(.system(size: 11))
              .foregroundStyle(.tertiary)
          }
        }
        .padding(.vertical, 2)
      }
    } label: {
      HStack {
        Image(systemName: "checkmark.circle")
          .font(.footnote)
          .foregroundStyle(.green)
        Text("Completed (\(completedRequests.count))")
          .font(.footnote)
          .fontWeight(.semibold)
          .foregroundStyle(.secondary)
      }
    }
    .padding(10)
    .background(DocTheme.subtle)
    .clipShape(RoundedRectangle(cornerRadius: 8))
  }

  // MARK: - Document Editor

  private var documentEditor: some View {
    VStack(spacing: 0) {
      // Toolbar
      HStack(spacing: 12) {
        // Edit/Preview toggle
        Picker("Mode", selection: $isEditing) {
          Text("Edit").tag(true)
          Text("Preview").tag(false)
        }
        .pickerStyle(.segmented)
        .frame(width: 160)

        // Condensed view toggle (preview mode only)
        if !isEditing {
          Button {
            isCondensed.toggle()
          } label: {
            Image(systemName: isCondensed ? "text.justify.leading" : "list.bullet.below.rectangle")
              .font(.body)
              .foregroundStyle(isCondensed ? .orange : .secondary)
              .padding(4)
              .background(isCondensed ? Color.orange.opacity(0.12) : Color.clear)
              .clipShape(RoundedRectangle(cornerRadius: 6))
          }
          .buttonStyle(.plain)
          .help(isCondensed ? "Show full document" : "Condensed view (headings + summaries)")
        }

        Spacer()

        if vm.isGitBusy {
          ProgressView()
            .scaleEffect(0.6)
          Text("Syncing…")
            .font(.footnote)
            .foregroundStyle(.secondary)
        }

        // Word count
        let wordCount = editContent.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
        if wordCount > 0 {
          Text("\(wordCount) words")
            .font(.footnote)
            .foregroundStyle(.quaternary)
            .monospacedDigit()
        }
      }
      .padding(.horizontal, 16)
      .padding(.vertical, 10)

      Divider()

      if isEditing {
        // Markdown editor
        SpellCheckingTextEditor(text: $editContent)
          .padding(16)
          .onChange(of: editContent) { _ in
            scheduleSave()
          }
      } else {
        // Preview (rendered markdown with collapsible sections)
        ScrollView {
          SectionedMarkdownPreview(
            content: editContent,
            sources: vm.researchSources,
            isCondensed: isCondensed,
            collapsedSections: $collapsedSections,
            searchText: docSearchText,
            onAskFollowUp: { sectionHeading in
              followUpSection = sectionHeading
              showAddRequest = true
            }
          )
          .padding(20)
          .frame(maxWidth: .infinity, alignment: .leading)
        }
      }
    }
    .background(DocTheme.bg)
  }

  // MARK: - Helpers

  private func scheduleSave() {
    saveTimer?.invalidate()
    saveTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { _ in
      Task { @MainActor in
        vm.saveResearchDocContent(editContent)
      }
    }
  }

  private func scrollToHeading(_ heading: String) {
    // For now, switch to edit mode and find the heading
    isEditing = true
    // Could enhance with NSTextView scrolling later
  }

  private func insertCitation(source: ResearchSource) {
    if let idx = vm.researchSources.firstIndex(where: { $0.id == source.id }) {
      let citation = "[\(idx + 1)]"
      editContent += citation
    }
  }

  private func domainFromURL(_ urlString: String) -> String {
    guard let url = URL(string: urlString), let host = url.host else {
      return urlString
    }
    return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
  }
}

// MARK: - Markdown Line with Citations

/// Renders a single line of text, replacing [N] patterns with hoverable citation badges.
/// Uses Text concatenation for natural text flow with styled citation markers.
private struct CitationRichText: View {
  let text: String
  let sources: [ResearchSource]

  // Regex to match [N] citation patterns
  private static let citationPattern = try! NSRegularExpression(pattern: #"\[(\d+)\]"#)

  /// Parse text into segments: plain text and citation references
  private var segments: [(String, Int?)] { // (text, citationIndex or nil)
    let nsText = text as NSString
    let matches = Self.citationPattern.matches(in: text, range: NSRange(location: 0, length: nsText.length))

    var result: [(String, Int?)] = []
    var lastEnd = 0

    for match in matches {
      let matchRange = match.range
      if matchRange.location > lastEnd {
        let plainRange = NSRange(location: lastEnd, length: matchRange.location - lastEnd)
        result.append((nsText.substring(with: plainRange), nil))
      }
      let numRange = match.range(at: 1)
      if let num = Int(nsText.substring(with: numRange)) {
        result.append(("[\(num)]", num))
      }
      lastEnd = matchRange.location + matchRange.length
    }

    if lastEnd < nsText.length {
      result.append((nsText.substring(from: lastEnd), nil))
    }

    return result
  }

  /// Build concatenated Text with styled citations inline
  private var richText: Text {
    segments.reduce(Text("")) { accumulated, segment in
      let (segText, citIdx) = segment
      if let idx = citIdx, idx >= 1, idx <= sources.count {
        return accumulated + Text("[\(idx)]")
          .font(.system(size: 11, weight: .bold, design: .rounded))
          .foregroundColor(.orange)
          .baselineOffset(4)
      } else if citIdx != nil {
        // Out-of-range citation — render as plain text
        return accumulated + Text(segText)
      } else {
        return accumulated + Text(segText)
      }
    }
  }

  var body: some View {
    richText
  }
}

// MARK: - Document Section Model

/// A parsed section of the markdown document
private struct DocSection: Identifiable {
  let id: String          // heading text (unique enough for our use)
  let heading: String
  let level: Int          // 1, 2, or 3
  let lines: [String]     // body lines (not including the heading line)

  /// First ~120 chars of body text, for condensed view summary chip
  var summary: String {
    let bodyText = lines
      .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
      .prefix(3)
      .joined(separator: " ")
      .trimmingCharacters(in: .whitespaces)
    if bodyText.count > 120 {
      return String(bodyText.prefix(117)) + "…"
    }
    return bodyText
  }

  /// Number of non-empty body lines
  var lineCount: Int {
    lines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.count
  }
}

/// Parse markdown content into sections by heading
private func parseDocSections(_ content: String) -> (preamble: [String], sections: [DocSection]) {
  let allLines = content.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
  var preamble: [String] = []
  var sections: [DocSection] = []
  var currentHeading: String? = nil
  var currentLevel: Int = 0
  var currentLines: [String] = []

  func flush() {
    if let heading = currentHeading {
      sections.append(DocSection(
        id: heading,
        heading: heading,
        level: currentLevel,
        lines: currentLines
      ))
    } else {
      preamble = currentLines
    }
    currentLines = []
  }

  for line in allLines {
    let trimmed = line.trimmingCharacters(in: .whitespaces)
    if trimmed.hasPrefix("### ") {
      flush()
      currentHeading = String(trimmed.dropFirst(4))
      currentLevel = 3
    } else if trimmed.hasPrefix("## ") {
      flush()
      currentHeading = String(trimmed.dropFirst(3))
      currentLevel = 2
    } else if trimmed.hasPrefix("# ") {
      flush()
      currentHeading = String(trimmed.dropFirst(2))
      currentLevel = 1
    } else {
      currentLines.append(line)
    }
  }
  flush()

  return (preamble, sections)
}

// MARK: - Sectioned Markdown Preview

private struct SectionedMarkdownPreview: View {
  let content: String
  let sources: [ResearchSource]
  let isCondensed: Bool
  @Binding var collapsedSections: Set<String>
  let searchText: String
  let onAskFollowUp: (String) -> Void

  private var parsed: (preamble: [String], sections: [DocSection]) {
    parseDocSections(content)
  }

  var body: some View {
    let data = parsed
    VStack(alignment: .leading, spacing: 4) {
      // Preamble (text before first heading)
      if !isCondensed {
        ForEach(Array(data.preamble.enumerated()), id: \.offset) { _, line in
          renderLine(line)
        }
      }

      // Sections
      ForEach(data.sections) { section in
        let isCollapsed = collapsedSections.contains(section.heading)
        let matchesSearch = !searchText.isEmpty && (
          section.heading.localizedCaseInsensitiveContains(searchText) ||
          section.lines.contains { $0.localizedCaseInsensitiveContains(searchText) }
        )

        SectionCardView(
          section: section,
          sources: sources,
          isCollapsed: isCollapsed,
          isCondensed: isCondensed,
          isSearchHighlighted: matchesSearch,
          searchText: searchText,
          onToggleCollapse: {
            if collapsedSections.contains(section.heading) {
              collapsedSections.remove(section.heading)
            } else {
              collapsedSections.insert(section.heading)
            }
          },
          onAskFollowUp: { onAskFollowUp(section.heading) }
        )
      }

      // Citation footnotes
      if !sources.isEmpty && !isCondensed {
        citationFootnotes
      }
    }
    .textSelection(.enabled)
  }

  @ViewBuilder
  private func renderLine(_ text: String) -> some View {
    if text.hasPrefix("- ") {
      HStack(alignment: .top, spacing: 6) {
        Text("•")
          .foregroundStyle(.secondary)
        CitationRichText(text: String(text.dropFirst(2)), sources: sources)
      }
    } else if text.trimmingCharacters(in: .whitespaces).isEmpty {
      Spacer().frame(height: 4)
    } else {
      CitationRichText(text: text, sources: sources)
    }
  }

  private var citationFootnotes: some View {
    VStack(alignment: .leading, spacing: 0) {
      Divider()
        .padding(.vertical, 12)

      Text("Sources")
        .font(.footnote)
        .fontWeight(.bold)
        .foregroundStyle(.secondary)
        .padding(.bottom, 6)

      ForEach(Array(sources.enumerated()), id: \.element.id) { idx, source in
        HStack(alignment: .top, spacing: 8) {
          Text("\(idx + 1)")
            .font(.system(size: 10, weight: .bold, design: .rounded))
            .foregroundColor(.white)
            .frame(width: 18, height: 18)
            .background(Color.orange)
            .clipShape(Circle())

          VStack(alignment: .leading, spacing: 1) {
            Text(source.title)
              .font(.footnote)
              .fontWeight(.medium)

            Text(domainFromURL(source.url))
              .font(.system(size: 11))
              .foregroundStyle(.blue)
              .onTapGesture {
                if let url = URL(string: source.url) {
                  NSWorkspace.shared.open(url)
                }
              }
              .onHover { hovering in
                if hovering {
                  NSCursor.pointingHand.push()
                } else {
                  NSCursor.pop()
                }
              }
          }
        }
        .padding(.vertical, 3)
      }
    }
  }

  private func domainFromURL(_ urlString: String) -> String {
    guard let url = URL(string: urlString), let host = url.host else { return urlString }
    return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
  }
}

// MARK: - Section Card View

private struct SectionCardView: View {
  let section: DocSection
  let sources: [ResearchSource]
  let isCollapsed: Bool
  let isCondensed: Bool
  let isSearchHighlighted: Bool
  let searchText: String
  let onToggleCollapse: () -> Void
  let onAskFollowUp: () -> Void

  @State private var isHovering = false

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      // Section header (always visible)
      HStack(spacing: 8) {
        // Collapse chevron
        Button(action: onToggleCollapse) {
          Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.secondary)
            .frame(width: 14)
        }
        .buttonStyle(.plain)

        // Heading
        CitationRichText(text: section.heading, sources: sources)
          .font(headingFont)
          .fontWeight(section.level <= 2 ? .bold : .semibold)

        Spacer()

        // Line count chip
        if isCollapsed || isCondensed {
          Text("\(section.lineCount) lines")
            .font(.system(size: 10))
            .foregroundStyle(.tertiary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(DocTheme.subtle)
            .clipShape(Capsule())
        }

        // Ask follow-up button (visible on hover)
        if isHovering {
          Button(action: onAskFollowUp) {
            HStack(spacing: 3) {
              Image(systemName: "questionmark.bubble")
                .font(.system(size: 10))
              Text("Follow up")
                .font(.system(size: 10))
            }
            .foregroundStyle(.orange)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(Color.orange.opacity(0.1))
            .clipShape(Capsule())
          }
          .buttonStyle(.plain)
        }
      }
      .padding(.vertical, 6)
      .padding(.horizontal, 8)

      // Summary chip (when collapsed or condensed)
      if (isCollapsed || isCondensed) && !section.summary.isEmpty {
        Text(section.summary)
          .font(.system(size: 12))
          .foregroundStyle(.secondary)
          .lineLimit(2)
          .padding(.horizontal, 30) // indent past chevron
          .padding(.bottom, 6)
      }

      // Full body (when expanded and not condensed)
      if !isCollapsed && !isCondensed {
        VStack(alignment: .leading, spacing: 6) {
          ForEach(Array(section.lines.enumerated()), id: \.offset) { _, line in
            renderBodyLine(line)
          }
        }
        .padding(.horizontal, 30)  // indent past chevron
        .padding(.bottom, 10)
      }
    }
    .background(
      RoundedRectangle(cornerRadius: 10)
        .fill(isSearchHighlighted ? Color.orange.opacity(0.06) : Color.clear)
    )
    .overlay(
      RoundedRectangle(cornerRadius: 10)
        .strokeBorder(
          isSearchHighlighted ? Color.orange.opacity(0.2) : Color.clear,
          lineWidth: 1
        )
    )
    .onHover { hovering in isHovering = hovering }
    .padding(.top, section.level == 1 ? 16 : (section.level == 2 ? 10 : 6))
  }

  private var headingFont: Font {
    switch section.level {
    case 1: return .title
    case 2: return .title2
    default: return .title3
    }
  }

  @ViewBuilder
  private func renderBodyLine(_ text: String) -> some View {
    if text.hasPrefix("- ") {
      HStack(alignment: .top, spacing: 6) {
        Text("•")
          .foregroundStyle(.secondary)
        CitationRichText(text: String(text.dropFirst(2)), sources: sources)
      }
    } else if text.trimmingCharacters(in: .whitespaces).isEmpty {
      Spacer().frame(height: 4)
    } else {
      CitationRichText(text: text, sources: sources)
    }
  }
}

// MARK: - Add Source Sheet

private struct AddSourceSheet: View {
  @ObservedObject var vm: AppViewModel
  @Environment(\.dismiss) private var dismiss

  @State private var title: String = ""
  @State private var url: String = ""
  @State private var tags: String = ""

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      HStack {
        Image(systemName: "link.badge.plus")
          .font(.title2)
          .foregroundStyle(.blue)
        Text("Add Source")
          .font(.title3)
          .fontWeight(.bold)
        Spacer()
      }

      TextField("URL", text: $url)
        .textFieldStyle(.roundedBorder)

      TextField("Title", text: $title)
        .textFieldStyle(.roundedBorder)

      TextField("Tags (comma-separated, optional)", text: $tags)
        .textFieldStyle(.roundedBorder)

      HStack {
        Button("Cancel") { dismiss() }
          .keyboardShortcut(.cancelAction)
        Spacer()
        Button("Add") {
          let parsedTags = tags.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
          vm.addResearchSource(
            url: url,
            title: title,
            tags: parsedTags.isEmpty ? nil : parsedTags
          )
          dismiss()
        }
        .keyboardShortcut(.defaultAction)
        .disabled(url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                  || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
      }
    }
    .padding(20)
    .frame(width: 440)
  }
}

// MARK: - Ask Lobs Sheet (Research)

private struct AskLobsResearchSheet: View {
  @ObservedObject var vm: AppViewModel
  @Environment(\.dismiss) private var dismiss

  /// Optional section heading for follow-up context
  var sectionContext: String? = nil

  @State private var prompt: String = ""

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      HStack {
        Image(systemName: "questionmark.bubble.fill")
          .font(.title2)
          .foregroundStyle(.linearGradient(
            colors: [.orange, .red],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
          ))
        VStack(alignment: .leading, spacing: 2) {
          Text(sectionContext != nil ? "Follow Up on Section" : "Ask Lobs to Research")
            .font(.title3)
            .fontWeight(.bold)
          Text("Lobs will research your question and update the document with findings.")
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
        Spacer()
      }

      // Section context badge
      if let section = sectionContext {
        HStack(spacing: 6) {
          Image(systemName: "text.quote")
            .font(.system(size: 11))
            .foregroundStyle(.orange)
          Text("Re: \(section)")
            .font(.footnote)
            .fontWeight(.medium)
            .foregroundStyle(.orange)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.orange.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
      }

      TextEditor(text: $prompt)
        .font(.system(size: 13))
        .frame(minHeight: 80, maxHeight: 160)
        .overlay(
          Group {
            if prompt.isEmpty {
              Text(sectionContext != nil
                ? "What would you like to know more about in this section?"
                : "What should Lobs research?")
                .font(.system(size: 13))
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 5)
                .padding(.vertical, 8)
                .allowsHitTesting(false)
            }
          },
          alignment: .topLeading
        )
        .border(Color.primary.opacity(0.1), width: 1)

      HStack {
        Button("Cancel") { dismiss() }
          .keyboardShortcut(.cancelAction)
        Spacer()
        Button("Submit") {
          let fullPrompt: String
          if let section = sectionContext {
            fullPrompt = "[Section: \(section)] \(prompt)"
          } else {
            fullPrompt = prompt
          }
          vm.addRequest(prompt: fullPrompt)
          dismiss()
        }
        .keyboardShortcut(.defaultAction)
        .disabled(prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
      }
    }
    .padding(20)
    .frame(width: 480)
  }
}
