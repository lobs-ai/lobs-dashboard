import SwiftUI

// MARK: - Theme

private enum TTheme {
  static let bg = Color(nsColor: .windowBackgroundColor)
  static let boardBg = Color(nsColor: .underPageBackgroundColor)
  static let cardBg = Color(nsColor: .controlBackgroundColor)
  static let subtle = Color.primary.opacity(0.06)
  static let border = Color.primary.opacity(0.08)
  static let cardRadius: CGFloat = 14
}

// MARK: - Tracker Board View

struct TrackerBoardView: View {
  @ObservedObject var vm: AppViewModel

  @State private var showAddItem = false
  @State private var selectedItem: TrackerItem? = nil
  @State private var filterStatus: TrackerItemStatus? = nil
  @State private var filterTag: String? = nil
  @State private var searchText: String = ""

  private var filteredItems: [TrackerItem] {
    var items = vm.trackerItems
    if let filterStatus {
      items = items.filter { $0.status == filterStatus }
    }
    if let filterTag, !filterTag.isEmpty {
      items = items.filter { $0.tags?.contains(filterTag) == true }
    }
    let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    if !q.isEmpty {
      items = items.filter { item in
        let hay = [item.title, item.notes, item.difficulty]
          .compactMap { $0 }
          .joined(separator: " ")
          .lowercased()
        return hay.contains(q)
      }
    }
    return items
  }

  private var allTags: [String] {
    var tags = Set<String>()
    for item in vm.trackerItems {
      if let t = item.tags { tags.formUnion(t) }
    }
    return tags.sorted()
  }

  // Progress stats
  private var totalCount: Int { vm.trackerItems.count }
  private var doneCount: Int { vm.trackerItems.filter { $0.status == .done }.count }
  private var inProgressCount: Int { vm.trackerItems.filter { $0.status == .inProgress }.count }
  private var skippedCount: Int { vm.trackerItems.filter { $0.status == .skipped }.count }
  private var notStartedCount: Int { vm.trackerItems.filter { $0.status == .notStarted }.count }

  private var progressFraction: Double {
    guard totalCount > 0 else { return 0 }
    return Double(doneCount) / Double(totalCount)
  }

  var body: some View {
    HSplitView {
      // Main list
      VStack(spacing: 0) {
        // Progress bar + stats
        VStack(spacing: 8) {
          HStack(spacing: 12) {
            // Progress bar
            VStack(alignment: .leading, spacing: 4) {
              HStack {
                Text("\(doneCount)/\(totalCount) completed")
                  .font(.callout)
                  .fontWeight(.bold)
                Text("(\(Int(progressFraction * 100))%)")
                  .font(.callout)
                  .foregroundStyle(.secondary)
                Spacer()
              }

              GeometryReader { geo in
                ZStack(alignment: .leading) {
                  RoundedRectangle(cornerRadius: 4)
                    .fill(Color.primary.opacity(0.08))
                  HStack(spacing: 0) {
                    if doneCount > 0 {
                      RoundedRectangle(cornerRadius: 4)
                        .fill(Color.green)
                        .frame(width: geo.size.width * CGFloat(doneCount) / CGFloat(max(totalCount, 1)))
                    }
                    if inProgressCount > 0 {
                      Rectangle()
                        .fill(Color.blue)
                        .frame(width: geo.size.width * CGFloat(inProgressCount) / CGFloat(max(totalCount, 1)))
                    }
                    if skippedCount > 0 {
                      Rectangle()
                        .fill(Color.gray.opacity(0.5))
                        .frame(width: geo.size.width * CGFloat(skippedCount) / CGFloat(max(totalCount, 1)))
                    }
                  }
                  .clipShape(RoundedRectangle(cornerRadius: 4))
                }
              }
              .frame(height: 8)
            }

            // Stat pills
            HStack(spacing: 8) {
              TrackerStatPill(label: "Done", count: doneCount, color: .green)
              TrackerStatPill(label: "In Progress", count: inProgressCount, color: .blue)
              TrackerStatPill(label: "Not Started", count: notStartedCount, color: .gray)
              if skippedCount > 0 {
                TrackerStatPill(label: "Skipped", count: skippedCount, color: .secondary)
              }
            }
          }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)

        Divider()

        // Filter bar
        HStack(spacing: 10) {
          // Status filter
          FilterChip(label: "All", isActive: filterStatus == nil) {
            filterStatus = nil
          }
          ForEach(TrackerItemStatus.allCases, id: \.self) { status in
            FilterChip(
              label: trackerStatusLabel(status),
              icon: trackerStatusIcon(status),
              isActive: filterStatus == status
            ) {
              filterStatus = (filterStatus == status) ? nil : status
            }
          }

          // Tag filter
          if !allTags.isEmpty {
            Divider().frame(height: 16)
            Menu {
              Button("All Tags") { filterTag = nil }
              Divider()
              ForEach(allTags, id: \.self) { tag in
                Button {
                  filterTag = (filterTag == tag) ? nil : tag
                } label: {
                  HStack {
                    if filterTag == tag { Image(systemName: "checkmark") }
                    Text("#\(tag)")
                  }
                }
              }
            } label: {
              HStack(spacing: 4) {
                Image(systemName: "tag")
                  .font(.footnote)
                if let tag = filterTag {
                  Text("#\(tag)")
                    .font(.footnote)
                } else {
                  Text("Tags")
                    .font(.footnote)
                }
              }
              .padding(.horizontal, 8)
              .padding(.vertical, 5)
              .background(filterTag != nil ? Color.accentColor.opacity(0.15) : TTheme.subtle)
              .clipShape(Capsule())
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
          }

          Spacer()

          // Search
          HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
              .foregroundStyle(.secondary)
              .font(.footnote)
            TextField("Search…", text: $searchText)
              .textFieldStyle(.plain)
              .frame(width: 140)
          }
          .padding(.horizontal, 10)
          .padding(.vertical, 6)
          .background(TTheme.subtle)
          .clipShape(RoundedRectangle(cornerRadius: 8))

          // Add button
          Button(action: { showAddItem = true }) {
            Image(systemName: "plus")
              .font(.body)
              .padding(6)
              .background(TTheme.subtle)
              .clipShape(RoundedRectangle(cornerRadius: 8))
          }
          .buttonStyle(.plain)
          .help("Add tracker item")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)

        Divider()

        // Item list
        if filteredItems.isEmpty {
          VStack(spacing: 12) {
            Image(systemName: "checklist")
              .font(.system(size: 40))
              .foregroundStyle(.secondary)
            Text(vm.trackerItems.isEmpty ? "No items yet" : "No matching items")
              .font(.title3)
              .foregroundStyle(.secondary)
            if vm.trackerItems.isEmpty {
              Button {
                showAddItem = true
              } label: {
                Label("Add First Item", systemImage: "plus")
              }
              .buttonStyle(.borderedProminent)
            }
          }
          .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
          List(selection: Binding(
            get: { selectedItem?.id },
            set: { id in selectedItem = filteredItems.first(where: { $0.id == id }) }
          )) {
            ForEach(filteredItems) { item in
              TrackerItemRow(item: item, vm: vm)
                .tag(item.id)
            }
          }
          .listStyle(.inset(alternatesRowBackgrounds: true))
        }
      }
      .frame(minWidth: 500)

      // Detail panel
      if let item = selectedItem,
         let liveItem = vm.trackerItems.first(where: { $0.id == item.id }) {
        TrackerItemDetail(item: liveItem, vm: vm, onClose: { selectedItem = nil })
          .id(liveItem.id)
          .frame(minWidth: 320, idealWidth: 400)
      } else {
        VStack(spacing: 8) {
          Image(systemName: "sidebar.right")
            .font(.system(size: 30))
            .foregroundStyle(.quaternary)
          Text("Select an item to view details")
            .font(.footnote)
            .foregroundStyle(.tertiary)
        }
        .frame(minWidth: 280, idealWidth: 320)
        .frame(maxHeight: .infinity)
      }
    }
    .sheet(isPresented: $showAddItem) {
      AddTrackerItemSheet(vm: vm)
    }
  }
}

// MARK: - Tracker Item Row

private struct TrackerItemRow: View {
  let item: TrackerItem
  @ObservedObject var vm: AppViewModel

  var body: some View {
    HStack(spacing: 12) {
      // Status toggle button
      Button {
        var updated = item
        updated.status = nextStatus(item.status)
        vm.updateTrackerItem(updated)
      } label: {
        Image(systemName: trackerStatusIcon(item.status))
          .font(.body)
          .foregroundStyle(trackerStatusColor(item.status))
      }
      .buttonStyle(.plain)
      .help("Cycle status: \(trackerStatusLabel(item.status))")

      VStack(alignment: .leading, spacing: 2) {
        HStack(spacing: 6) {
          Text(item.title)
            .font(.callout)
            .fontWeight(.medium)
            .strikethrough(item.status == .done || item.status == .skipped)
            .foregroundStyle(item.status == .skipped ? .secondary : .primary)

          if let difficulty = item.difficulty, !difficulty.isEmpty {
            Text(difficulty)
              .font(.system(size: 11, weight: .medium))
              .padding(.horizontal, 6)
              .padding(.vertical, 1)
              .background(difficultyColor(difficulty).opacity(0.12))
              .foregroundStyle(difficultyColor(difficulty))
              .clipShape(Capsule())
          }
        }

        if let tags = item.tags, !tags.isEmpty {
          HStack(spacing: 4) {
            ForEach(tags.prefix(4), id: \.self) { tag in
              Text("#\(tag)")
                .font(.system(size: 11))
                .foregroundStyle(.blue)
            }
          }
        }
      }

      Spacer()

      // Status label
      Text(trackerStatusLabel(item.status))
        .font(.system(size: 11, weight: .medium))
        .padding(.horizontal, 7)
        .padding(.vertical, 2)
        .background(trackerStatusColor(item.status).opacity(0.12))
        .foregroundStyle(trackerStatusColor(item.status))
        .clipShape(Capsule())

      Text(relativeTime(item.updatedAt))
        .font(.system(size: 11))
        .foregroundStyle(.quaternary)
    }
    .padding(.vertical, 4)
  }
}

// MARK: - Tracker Item Detail

private struct TrackerItemDetail: View {
  let item: TrackerItem
  @ObservedObject var vm: AppViewModel
  let onClose: () -> Void

  @State private var editTitle: String = ""
  @State private var editNotes: String = ""
  @State private var editDifficulty: String = ""
  @State private var editTags: String = ""
  @State private var editLinks: String = ""
  @State private var editStatus: TrackerItemStatus = .notStarted

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 16) {
        // Header
        HStack {
          Image(systemName: trackerStatusIcon(item.status))
            .font(.title2)
            .foregroundStyle(trackerStatusColor(item.status))
          Text(trackerStatusLabel(item.status))
            .font(.callout)
            .fontWeight(.bold)
            .foregroundStyle(trackerStatusColor(item.status))
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
          .onChange(of: item.id) { _ in loadFields() }

        // Status picker
        VStack(alignment: .leading, spacing: 6) {
          Text("Status")
            .font(.callout)
            .foregroundStyle(.secondary)
          Picker("Status", selection: $editStatus) {
            ForEach(TrackerItemStatus.allCases, id: \.self) { status in
              Text(trackerStatusLabel(status)).tag(status)
            }
          }
          .pickerStyle(.segmented)
        }

        // Difficulty
        VStack(alignment: .leading, spacing: 6) {
          Text("Difficulty")
            .font(.callout)
            .foregroundStyle(.secondary)
          HStack(spacing: 8) {
            ForEach(["Easy", "Medium", "Hard"], id: \.self) { diff in
              Button {
                editDifficulty = (editDifficulty == diff) ? "" : diff
              } label: {
                Text(diff)
                  .font(.footnote)
                  .fontWeight(editDifficulty == diff ? .bold : .regular)
                  .padding(.horizontal, 10)
                  .padding(.vertical, 5)
                  .background(editDifficulty == diff ? difficultyColor(diff).opacity(0.15) : TTheme.subtle)
                  .foregroundStyle(editDifficulty == diff ? difficultyColor(diff) : .secondary)
                  .clipShape(Capsule())
              }
              .buttonStyle(.plain)
            }
            TextField("Custom…", text: $editDifficulty)
              .textFieldStyle(.roundedBorder)
              .frame(width: 100)
          }
        }

        // Tags
        VStack(alignment: .leading, spacing: 4) {
          Text("Tags (comma-separated)")
            .font(.callout)
            .foregroundStyle(.secondary)
          TextField("tag1, tag2, …", text: $editTags)
            .textFieldStyle(.roundedBorder)
        }

        // Notes
        VStack(alignment: .leading, spacing: 4) {
          Text("Notes")
            .font(.callout)
            .foregroundStyle(.secondary)
          TextField("Write notes, solutions, observations…", text: $editNotes, axis: .vertical)
            .textFieldStyle(.roundedBorder)
            .lineLimit(12, reservesSpace: true)
        }

        // Links
        VStack(alignment: .leading, spacing: 4) {
          Text("Links (one per line)")
            .font(.callout)
            .foregroundStyle(.secondary)
          TextField("https://…", text: $editLinks, axis: .vertical)
            .textFieldStyle(.roundedBorder)
            .lineLimit(4, reservesSpace: true)

          // Render clickable links
          if let links = item.links, !links.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
              ForEach(links, id: \.self) { link in
                Button {
                  if let url = URL(string: link) { NSWorkspace.shared.open(url) }
                } label: {
                  HStack(spacing: 4) {
                    Image(systemName: "arrow.up.right.square")
                      .font(.system(size: 11))
                    Text(link)
                      .font(.footnote)
                      .lineLimit(1)
                  }
                  .foregroundStyle(.blue)
                }
                .buttonStyle(.plain)
              }
            }
          }
        }

        Divider()

        // Actions
        HStack(spacing: 8) {
          Button {
            saveChanges()
          } label: {
            Label("Save", systemImage: "square.and.arrow.down")
          }
          .buttonStyle(.borderedProminent)
          .controlSize(.small)

          Spacer()

          Button(role: .destructive) {
            vm.removeTrackerItem(item)
            onClose()
          } label: {
            Label("Delete", systemImage: "trash")
          }
          .buttonStyle(.bordered)
          .controlSize(.small)
        }

        // Metadata
        Divider()
        VStack(alignment: .leading, spacing: 4) {
          Text("ID: \(item.id)")
            .font(.system(size: 11, design: .monospaced))
            .foregroundStyle(.quaternary)
            .textSelection(.enabled)
          Text("Created: \(item.createdAt.formatted())")
            .font(.system(size: 11))
            .foregroundStyle(.quaternary)
          Text("Updated: \(item.updatedAt.formatted())")
            .font(.system(size: 11))
            .foregroundStyle(.quaternary)
        }
      }
      .padding(20)
    }
    .background(TTheme.bg)
  }

  private func loadFields() {
    editTitle = item.title
    editNotes = item.notes ?? ""
    editDifficulty = item.difficulty ?? ""
    editTags = item.tags?.joined(separator: ", ") ?? ""
    editLinks = item.links?.joined(separator: "\n") ?? ""
    editStatus = item.status
  }

  private func saveChanges() {
    var updated = item
    updated.title = editTitle
    updated.status = editStatus
    updated.difficulty = editDifficulty.isEmpty ? nil : editDifficulty
    updated.tags = editTags.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    updated.notes = editNotes.isEmpty ? nil : editNotes
    updated.links = editLinks.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    vm.updateTrackerItem(updated)
  }
}

// MARK: - Add Tracker Item Sheet

private struct AddTrackerItemSheet: View {
  @ObservedObject var vm: AppViewModel
  @Environment(\.dismiss) private var dismiss

  @State private var title: String = ""
  @State private var difficulty: String = ""
  @State private var tags: String = ""
  @State private var notes: String = ""
  @State private var links: String = ""

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      HStack {
        Image(systemName: "plus.circle.fill")
          .font(.title2)
          .foregroundStyle(.linearGradient(
            colors: [.cyan, .blue],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
          ))
        Text("Add Tracker Item")
          .font(.title3)
          .fontWeight(.bold)
        Spacer()
      }

      TextField("Title", text: $title)
        .textFieldStyle(.roundedBorder)

      HStack(spacing: 8) {
        Text("Difficulty:")
          .font(.callout)
          .foregroundStyle(.secondary)
        ForEach(["Easy", "Medium", "Hard"], id: \.self) { diff in
          Button {
            difficulty = (difficulty == diff) ? "" : diff
          } label: {
            Text(diff)
              .font(.footnote)
              .fontWeight(difficulty == diff ? .bold : .regular)
              .padding(.horizontal, 10)
              .padding(.vertical, 5)
              .background(difficulty == diff ? difficultyColor(diff).opacity(0.15) : TTheme.subtle)
              .foregroundStyle(difficulty == diff ? difficultyColor(diff) : .secondary)
              .clipShape(Capsule())
          }
          .buttonStyle(.plain)
        }
      }

      TextField("Tags (comma-separated)", text: $tags)
        .textFieldStyle(.roundedBorder)

      TextField("Notes (optional)", text: $notes, axis: .vertical)
        .textFieldStyle(.roundedBorder)
        .lineLimit(4, reservesSpace: true)

      TextField("Links (one per line, optional)", text: $links, axis: .vertical)
        .textFieldStyle(.roundedBorder)
        .lineLimit(3, reservesSpace: true)

      HStack {
        Button("Cancel") { dismiss() }
          .keyboardShortcut(.cancelAction)
        Spacer()
        Button("Create") {
          let parsedTags = tags.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
          let parsedLinks = links.split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

          vm.addTrackerItem(
            title: title,
            difficulty: difficulty.isEmpty ? nil : difficulty,
            tags: parsedTags.isEmpty ? nil : parsedTags,
            notes: notes.isEmpty ? nil : notes,
            links: parsedLinks.isEmpty ? nil : parsedLinks
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

// MARK: - Filter Chip

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
      .background(isActive ? Color.accentColor.opacity(0.15) : TTheme.subtle)
      .foregroundStyle(isActive ? .primary : .secondary)
      .clipShape(Capsule())
    }
    .buttonStyle(.plain)
  }
}

// MARK: - Stat Pill

private struct TrackerStatPill: View {
  let label: String
  let count: Int
  let color: Color

  var body: some View {
    HStack(spacing: 3) {
      Circle()
        .fill(color)
        .frame(width: 5, height: 5)
      Text("\(count)")
        .font(.footnote)
        .fontWeight(.medium)
        .monospacedDigit()
    }
    .help("\(count) \(label)")
  }
}

// MARK: - Helpers

private func trackerStatusLabel(_ status: TrackerItemStatus) -> String {
  switch status {
  case .notStarted: return "Not Started"
  case .inProgress: return "In Progress"
  case .done: return "Done"
  case .skipped: return "Skipped"
  }
}

private func trackerStatusIcon(_ status: TrackerItemStatus) -> String {
  switch status {
  case .notStarted: return "circle"
  case .inProgress: return "circle.lefthalf.filled"
  case .done: return "checkmark.circle.fill"
  case .skipped: return "slash.circle"
  }
}

private func trackerStatusColor(_ status: TrackerItemStatus) -> Color {
  switch status {
  case .notStarted: return .gray
  case .inProgress: return .blue
  case .done: return .green
  case .skipped: return .secondary
  }
}

private func difficultyColor(_ difficulty: String) -> Color {
  switch difficulty.lowercased() {
  case "easy": return .green
  case "medium": return .orange
  case "hard": return .red
  default: return .purple
  }
}

/// Cycle through statuses: not_started → in_progress → done → skipped → not_started
private func nextStatus(_ current: TrackerItemStatus) -> TrackerItemStatus {
  switch current {
  case .notStarted: return .inProgress
  case .inProgress: return .done
  case .done: return .skipped
  case .skipped: return .notStarted
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
