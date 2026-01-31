import SwiftUI

// MARK: - Drop Delegate

private struct TaskDropDelegate: DropDelegate {
  let status: TaskStatus
  let vm: AppViewModel

  func validateDrop(info: DropInfo) -> Bool { true }

  func performDrop(info: DropInfo) -> Bool {
    guard let id = vm.draggingTaskId else { return false }
    vm.moveTask(taskId: id, to: status)
    return true
  }
}

// MARK: - Theme Constants

private enum Theme {
  static let bg = Color(nsColor: .windowBackgroundColor)
  static let boardBg = Color(nsColor: .underPageBackgroundColor)
  static let cardBg = Color(nsColor: .controlBackgroundColor)
  static let accent = Color.accentColor
  static let subtle = Color.primary.opacity(0.06)
  static let border = Color.primary.opacity(0.08)
  static let cardRadius: CGFloat = 14
  static let colRadius: CGFloat = 16
  static let columnWidth: CGFloat = 300
}

// MARK: - Content View (Top Level)

struct ContentView: View {
  @EnvironmentObject var vm: AppViewModel

  @State private var showPicker = false
  @State private var autoPush = true
  @State private var showAddTask = false
  @State private var showSettings = false
  @State private var showAllCompleted = false
  @State private var showAllRejected = false
  @State private var quickAddText = ""

  var body: some View {
    ZStack(alignment: .top) {
      // Board
      VStack(spacing: 0) {
        // Toolbar area
        ToolbarArea(
          vm: vm,
          autoPush: $autoPush,
          showPicker: $showPicker,
          showAddTask: $showAddTask,
          showSettings: $showSettings
        )

        // Stats bar
        StatsBar(vm: vm)

        Divider()

        // Kanban board
        BoardView(
          vm: vm,
          showAllCompleted: $showAllCompleted,
          showAllRejected: $showAllRejected,
          autoPush: $autoPush,
          quickAddText: $quickAddText
        )
      }
      .background(Theme.boardBg)

      // Error banner overlay
      if let banner = vm.errorBanner {
        ErrorBanner(message: banner) {
          vm.errorBanner = nil
        }
        .transition(.move(edge: .top).combined(with: .opacity))
        .zIndex(100)
        .padding(.top, 52)
      }

      // Git busy indicator
      if vm.isGitBusy {
        HStack(spacing: 6) {
          ProgressView()
            .scaleEffect(0.6)
          Text("Syncing…")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
        .transition(.opacity)
        .zIndex(99)
        .padding(.top, 52)
      }
    }
    .animation(.easeInOut(duration: 0.3), value: vm.errorBanner != nil)
    .animation(.easeOut(duration: 0.2), value: vm.isGitBusy)
    .fileImporter(
      isPresented: $showPicker,
      allowedContentTypes: [.folder]
    ) { result in
      switch result {
      case .success(let url):
        vm.setRepoURL(url)
        vm.reload()
      case .failure(let err):
        vm.lastError = String(describing: err)
      }
    }
    .sheet(isPresented: $showAddTask) {
      AddTaskSheet(vm: vm, autoPush: $autoPush)
    }
    .onAppear { vm.reloadIfPossible() }
    // Keyboard shortcuts (Task #84248F22)
    .background(
      KeyboardShortcutReceiver(
        onNewTask: { showAddTask = true },
        onRefresh: { vm.reload() },
        onNextTask: { vm.selectNextTask() },
        onPrevTask: { vm.selectPreviousTask() },
        onSearch: { /* Focus is handled by ⌘F via toolbar */ }
      )
    )
  }
}

// MARK: - Keyboard Shortcut Receiver

private struct KeyboardShortcutReceiver: View {
  let onNewTask: () -> Void
  let onRefresh: () -> Void
  let onNextTask: () -> Void
  let onPrevTask: () -> Void
  let onSearch: () -> Void

  var body: some View {
    Group {
      Button("") { onNewTask() }
        .keyboardShortcut("n", modifiers: .command)
        .opacity(0)

      Button("") { onRefresh() }
        .keyboardShortcut("r", modifiers: .command)
        .opacity(0)

      Button("") { onNextTask() }
        .keyboardShortcut(.downArrow, modifiers: [])
        .opacity(0)

      Button("") { onPrevTask() }
        .keyboardShortcut(.upArrow, modifiers: [])
        .opacity(0)
    }
    .frame(width: 0, height: 0)
    .allowsHitTesting(false)
  }
}

// MARK: - Toolbar Area

private struct ToolbarArea: View {
  @ObservedObject var vm: AppViewModel
  @Binding var autoPush: Bool
  @Binding var showPicker: Bool
  @Binding var showAddTask: Bool
  @Binding var showSettings: Bool

  var body: some View {
    HStack(spacing: 12) {
      // App title
      HStack(spacing: 6) {
        Image(systemName: "square.grid.3x3.topleft.filled")
          .font(.title2)
          .foregroundStyle(.linearGradient(
            colors: [.blue, .purple],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
          ))
        Text("Lobs Dashboard")
          .font(.title3)
          .fontWeight(.bold)
      }

      Spacer()

      // Search
      HStack(spacing: 6) {
        Image(systemName: "magnifyingglass")
          .foregroundStyle(.secondary)
          .font(.caption)
        TextField("Search tasks… (⌘F)", text: $vm.searchText)
          .textFieldStyle(.plain)
          .frame(width: 180)
      }
      .padding(.horizontal, 10)
      .padding(.vertical, 6)
      .background(Theme.subtle)
      .clipShape(RoundedRectangle(cornerRadius: 8))

      // Filter
      Menu {
        Button { vm.ownerFilter = "all" } label: {
          Label("All tasks", systemImage: vm.ownerFilter == "all" ? "checkmark" : "")
        }
        Button { vm.ownerFilter = "lobs" } label: {
          Label("Lobs only", systemImage: vm.ownerFilter == "lobs" ? "checkmark" : "")
        }
        Button { vm.ownerFilter = "rafe" } label: {
          Label("Rafe only", systemImage: vm.ownerFilter == "rafe" ? "checkmark" : "")
        }
        Divider()
        Button { vm.ownerFilter = "other" } label: {
          Label("Other", systemImage: vm.ownerFilter == "other" ? "checkmark" : "")
        }
      } label: {
        HStack(spacing: 4) {
          Image(systemName: "line.3.horizontal.decrease.circle")
          if vm.ownerFilter != "all" {
            Text(vm.ownerFilter.capitalized)
              .font(.caption)
          }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(vm.ownerFilter != "all" ? Color.accentColor.opacity(0.12) : Theme.subtle)
        .clipShape(RoundedRectangle(cornerRadius: 8))
      }
      .menuStyle(.borderlessButton)
      .fixedSize()

      // Action buttons
      ToolbarButton(icon: "plus", label: "New task", shortcut: "⌘N") {
        showAddTask = true
      }

      ToolbarButton(icon: "arrow.clockwise", label: "Refresh", shortcut: "⌘R") {
        vm.reload()
      }

      // Settings gear (Task #47AC08C2 — repo sync & auto-push in settings popover)
      Button {
        showSettings.toggle()
      } label: {
        Image(systemName: "gearshape")
          .font(.body)
          .padding(6)
          .background(Theme.subtle)
          .clipShape(RoundedRectangle(cornerRadius: 8))
      }
      .buttonStyle(.plain)
      .popover(isPresented: $showSettings, arrowEdge: .bottom) {
        SettingsPopover(
          vm: vm,
          autoPush: $autoPush,
          showPicker: $showPicker
        )
      }
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 10)
    .background(.ultraThinMaterial)
  }
}

private struct ToolbarButton: View {
  let icon: String
  let label: String
  let shortcut: String
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Image(systemName: icon)
        .font(.body)
        .padding(6)
        .background(Theme.subtle)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
    .buttonStyle(.plain)
    .help("\(label) (\(shortcut))")
  }
}

// MARK: - Settings Popover (Task #47AC08C2)

private struct SettingsPopover: View {
  @ObservedObject var vm: AppViewModel
  @Binding var autoPush: Bool
  @Binding var showPicker: Bool

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text("Settings")
        .font(.headline)
        .fontWeight(.bold)

      // Repository
      GroupBox {
        VStack(alignment: .leading, spacing: 8) {
          Label("Repository", systemImage: "folder.badge.gear")
            .font(.subheadline)
            .fontWeight(.semibold)

          if let repo = vm.repoURL {
            Text(repo.path)
              .font(.caption)
              .foregroundStyle(.secondary)
              .lineLimit(2)
          } else {
            Text("Not configured")
              .font(.caption)
              .foregroundStyle(.orange)
          }

          Button {
            showPicker = true
          } label: {
            Label("Choose lobs-control…", systemImage: "folder")
          }
          .controlSize(.small)
        }
      }

      // Sync
      GroupBox {
        VStack(alignment: .leading, spacing: 8) {
          Label("Sync", systemImage: "arrow.triangle.2.circlepath")
            .font(.subheadline)
            .fontWeight(.semibold)

          Toggle("Auto-push on changes", isOn: $autoPush)
            .toggleStyle(.switch)
            .controlSize(.small)

          Toggle("Auto-refresh (\(vm.autoRefreshIntervalSeconds)s)", isOn: $vm.autoRefreshEnabled)
            .toggleStyle(.switch)
            .controlSize(.small)
            .onChange(of: vm.autoRefreshEnabled) { _ in
              vm.startAutoRefreshIfNeeded()
            }

          Toggle("Auto-archive completed tasks", isOn: $vm.autoArchiveCompleted)
            .toggleStyle(.switch)
            .controlSize(.small)

          if vm.autoArchiveCompleted {
            HStack {
              Text("Archive after")
                .font(.caption)
              TextField("", value: $vm.archiveCompletedAfterDays, format: .number)
                .textFieldStyle(.roundedBorder)
                .frame(width: 50)
              Text("days")
                .font(.caption)
            }
          }
        }
      }

      // Display
      GroupBox {
        VStack(alignment: .leading, spacing: 8) {
          Label("Display", systemImage: "eye")
            .font(.subheadline)
            .fontWeight(.semibold)

          HStack {
            Text("WIP limit (Active)")
              .font(.caption)
            Stepper(value: $vm.wipLimitActive, in: 1...20) {
              Text("\(vm.wipLimitActive)")
                .font(.caption)
                .monospacedDigit()
            }
          }
        }
      }

      if let err = vm.lastError {
        GroupBox {
          VStack(alignment: .leading, spacing: 4) {
            Label("Error", systemImage: "exclamationmark.triangle")
              .font(.subheadline)
              .foregroundStyle(.red)
            Text(err)
              .font(.caption)
              .foregroundStyle(.secondary)
              .textSelection(.enabled)
          }
        }
      }
    }
    .padding(16)
    .frame(width: 300)
  }
}

// MARK: - Stats Bar

private struct StatsBar: View {
  @ObservedObject var vm: AppViewModel

  private var inboxCount: Int { vm.tasks.filter { $0.status == .inbox }.count }
  private var activeCount: Int { vm.tasks.filter { $0.status == .active }.count }
  private var completedCount: Int { vm.tasks.filter { $0.status == .completed }.count }
  private var blockedCount: Int { vm.tasks.filter { $0.workState == .blocked }.count }
  private var totalCount: Int { vm.tasks.count }

  var body: some View {
    HStack(spacing: 16) {
      StatPill(label: "Inbox", count: inboxCount, color: .blue)
      StatPill(label: "Active", count: activeCount, color: .orange)
      if blockedCount > 0 {
        StatPill(label: "Blocked", count: blockedCount, color: .red)
      }
      StatPill(label: "Done", count: completedCount, color: .green)

      Spacer()

      Text("\(totalCount) tasks")
        .font(.caption)
        .foregroundStyle(.tertiary)
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 6)
    .background(Theme.bg.opacity(0.5))
  }
}

private struct StatPill: View {
  let label: String
  let count: Int
  let color: Color

  var body: some View {
    HStack(spacing: 4) {
      Circle()
        .fill(color)
        .frame(width: 6, height: 6)
      Text("\(label): \(count)")
        .font(.caption)
        .foregroundStyle(.secondary)
    }
  }
}

// MARK: - Error Banner

private struct ErrorBanner: View {
  let message: String
  let dismiss: () -> Void

  var body: some View {
    HStack(spacing: 8) {
      Image(systemName: "exclamationmark.triangle.fill")
        .foregroundStyle(.orange)
      Text(message)
        .font(.caption)
        .lineLimit(2)
      Spacer()
      Button {
        dismiss()
      } label: {
        Image(systemName: "xmark")
          .font(.caption2)
          .foregroundStyle(.secondary)
      }
      .buttonStyle(.plain)
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 10)
    .background(.red.opacity(0.08))
    .clipShape(RoundedRectangle(cornerRadius: 10))
    .overlay(
      RoundedRectangle(cornerRadius: 10)
        .stroke(Color.red.opacity(0.15))
    )
    .padding(.horizontal, 20)
  }
}

// MARK: - Board View

private struct BoardView: View {
  @ObservedObject var vm: AppViewModel
  @Binding var showAllCompleted: Bool
  @Binding var showAllRejected: Bool
  @Binding var autoPush: Bool
  @Binding var quickAddText: String

  var body: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(alignment: .top, spacing: 16) {
        ForEach(vm.columns, id: \.title) { col in
          BoardColumn(
            title: col.title,
            tasks: vm.filteredTasks.filter(col.matches),
            dropStatus: col.dropStatus,
            vm: vm,
            autoPush: $autoPush,
            showAllCompleted: $showAllCompleted,
            showAllRejected: $showAllRejected,
            quickAddText: $quickAddText
          )
        }
      }
      .padding(20)
    }
  }
}

// MARK: - Board Column

private struct BoardColumn: View {
  let title: String
  let tasks: [DashboardTask]
  let dropStatus: TaskStatus

  @ObservedObject var vm: AppViewModel
  @Binding var autoPush: Bool
  @Binding var showAllCompleted: Bool
  @Binding var showAllRejected: Bool
  @Binding var quickAddText: String

  @State private var isHovering = false

  private var columnColor: Color {
    switch title.lowercased() {
    case "inbox": return .blue
    case "active": return .orange
    case "waiting on": return .yellow
    case "completed": return .green
    case "rejected": return .red
    default: return .gray
    }
  }

  var body: some View {
    let isCompleted = title.lowercased() == "completed"
    let isRejected = title.lowercased() == "rejected"
    let isInbox = title.lowercased() == "inbox"

    let showAll = isCompleted ? showAllCompleted : (isRejected ? showAllRejected : true)
    let visibleTasks = (isCompleted || isRejected) && !showAll
      ? Array(tasks.sorted { $0.updatedAt > $1.updatedAt }.prefix(vm.completedShowRecent))
      : tasks

    let wipLimit = (title.lowercased() == "active") ? vm.wipLimitActive : 0

    VStack(alignment: .leading, spacing: 0) {
      // Column header
      HStack(alignment: .center, spacing: 8) {
        Circle()
          .fill(columnColor)
          .frame(width: 8, height: 8)

        Text(title)
          .font(.subheadline)
          .fontWeight(.bold)
          .foregroundStyle(.primary)

        Text("\(tasks.count)")
          .font(.caption2)
          .fontWeight(.medium)
          .padding(.horizontal, 7)
          .padding(.vertical, 2)
          .background(Theme.subtle)
          .clipShape(Capsule())

        if wipLimit > 0 && tasks.count > wipLimit {
          Text("WIP")
            .font(.caption2)
            .fontWeight(.bold)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.orange.opacity(0.2))
            .foregroundStyle(.orange)
            .clipShape(Capsule())
        }

        Spacer()

        if isCompleted {
          Button {
            withAnimation(.easeInOut(duration: 0.2)) {
              showAllCompleted.toggle()
            }
          } label: {
            Image(systemName: showAllCompleted ? "chevron.up" : "chevron.down")
              .font(.caption2)
              .foregroundStyle(.secondary)
          }
          .buttonStyle(.plain)
        }

        if isRejected {
          Button {
            withAnimation(.easeInOut(duration: 0.2)) {
              showAllRejected.toggle()
            }
          } label: {
            Image(systemName: showAllRejected ? "chevron.up" : "chevron.down")
              .font(.caption2)
              .foregroundStyle(.secondary)
          }
          .buttonStyle(.plain)
        }
      }
      .padding(.horizontal, 14)
      .padding(.vertical, 12)

      Divider()
        .padding(.horizontal, 10)

      // Cards
      ScrollView(.vertical, showsIndicators: false) {
        LazyVStack(alignment: .leading, spacing: 8) {
          ForEach(visibleTasks) { t in
            TaskTile(task: t, vm: vm, autoPush: $autoPush)
              .onDrag {
                vm.draggingTaskId = t.id
                return NSItemProvider(object: t.id as NSString)
              }
          }

          if (isCompleted || isRejected) && !showAll && tasks.count > vm.completedShowRecent {
            Text("+\(tasks.count - vm.completedShowRecent) more")
              .font(.caption2)
              .foregroundStyle(.secondary)
              .frame(maxWidth: .infinity)
              .padding(.vertical, 4)
          }
        }
        .padding(10)
      }

      // Quick-add inline for Inbox (Task #84248F22)
      if isInbox {
        Divider()
          .padding(.horizontal, 10)

        HStack(spacing: 6) {
          Image(systemName: "plus.circle")
            .foregroundStyle(.secondary)
            .font(.caption)
          TextField("Quick add task…", text: $quickAddText)
            .textFieldStyle(.plain)
            .font(.caption)
            .onSubmit {
              let trimmed = quickAddText.trimmingCharacters(in: .whitespacesAndNewlines)
              if !trimmed.isEmpty {
                vm.submitTaskToLobs(title: trimmed, notes: nil, autoPush: autoPush)
                quickAddText = ""
              }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
      }
    }
    .frame(width: Theme.columnWidth)
    .frame(maxHeight: 600)
    .background(
      RoundedRectangle(cornerRadius: Theme.colRadius)
        .fill(Theme.bg)
        .shadow(color: .black.opacity(isHovering ? 0.08 : 0.04), radius: isHovering ? 12 : 6, y: 2)
    )
    .overlay(
      RoundedRectangle(cornerRadius: Theme.colRadius)
        .stroke(Theme.border, lineWidth: 1)
    )
    .onHover { hovering in
      withAnimation(.easeOut(duration: 0.15)) { isHovering = hovering }
    }
    .onDrop(of: [.text], delegate: TaskDropDelegate(status: dropStatus, vm: vm))
  }
}

// MARK: - Task Tile (Card)

private struct TaskTile: View {
  let task: DashboardTask
  @ObservedObject var vm: AppViewModel
  @Binding var autoPush: Bool

  @State private var isHovering = false
  @State private var showDetail = false

  private var isSelected: Bool { vm.selectedTaskId == task.id }

  /// Staleness: tasks sitting in inbox/active too long get visual attention.
  private var stalenessColor: Color? {
    guard task.status == .inbox || task.status == .active else { return nil }
    let age = Date().timeIntervalSince(task.updatedAt)
    if age > 7 * 86400 { return .red }       // >7 days
    if age > 3 * 86400 { return .orange }     // >3 days
    if age > 1 * 86400 { return .yellow }     // >1 day
    return nil
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(task.title)
        .font(.subheadline)
        .fontWeight(.medium)
        .lineLimit(3)

      HStack(spacing: 5) {
        MiniTag(text: task.owner.rawValue, color: ownerColor)

        if let ws = task.workState {
          MiniTag(text: workStateLabel(ws), color: workStateColor(ws))
        }

        if let rs = task.reviewState {
          MiniTag(text: reviewStateLabel(rs), color: reviewStateColor(rs))
        }
      }

      if let notes = task.notes, !notes.isEmpty {
        Text(notes)
          .font(.caption)
          .foregroundStyle(.secondary)
          .lineLimit(2)
      }

      // Relative timestamp
      Text(relativeTime(task.updatedAt))
        .font(.system(size: 9))
        .foregroundStyle(.tertiary)
    }
    .padding(12)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(
      RoundedRectangle(cornerRadius: Theme.cardRadius)
        .fill(isSelected ? Theme.accent.opacity(0.08) : Theme.cardBg)
        .shadow(color: .black.opacity(isHovering ? 0.06 : 0.02), radius: isHovering ? 6 : 2, y: 1)
    )
    .overlay(
      RoundedRectangle(cornerRadius: Theme.cardRadius)
        .stroke(
          isSelected ? Theme.accent.opacity(0.4)
            : (stalenessColor?.opacity(0.4) ?? Theme.border),
          lineWidth: isSelected ? 1.5 : (stalenessColor != nil ? 1.0 : 0.5)
        )
    )
    .scaleEffect(isHovering ? 1.01 : 1.0)
    .animation(.easeOut(duration: 0.15), value: isHovering)
    .onHover { h in isHovering = h }
    .onTapGesture {
      vm.selectTask(task)
      showDetail = true
    }
    .popover(isPresented: $showDetail, arrowEdge: .trailing) {
      TaskDetailPopover(task: task, vm: vm, autoPush: $autoPush, artifactText: vm.artifactText)
        .frame(width: 400, height: 500)
    }
  }

  private var ownerColor: Color {
    switch task.owner {
    case .lobs: return .purple
    case .rafe: return .blue
    case .other: return .gray
    }
  }

  private func workStateLabel(_ ws: WorkState) -> String {
    switch ws {
    case .notStarted: return "Not started"
    case .inProgress: return "In progress"
    case .blocked: return "Blocked"
    case .other(let v): return v
    }
  }

  private func workStateColor(_ ws: WorkState) -> Color {
    switch ws {
    case .notStarted: return .gray
    case .inProgress: return .blue
    case .blocked: return .red
    case .other: return .gray
    }
  }

  private func reviewStateLabel(_ rs: ReviewState) -> String {
    switch rs {
    case .pending: return "Pending"
    case .approved: return "Approved"
    case .changesRequested: return "Changes"
    case .rejected: return "Rejected"
    case .other(let v): return v
    }
  }

  private func reviewStateColor(_ rs: ReviewState) -> Color {
    switch rs {
    case .pending: return .orange
    case .approved: return .green
    case .changesRequested: return .yellow
    case .rejected: return .red
    case .other: return .gray
    }
  }
}

// MARK: - Task Detail Popover (replaces right-side detail panel — Task #47AC08C2)

private struct TaskDetailPopover: View {
  let task: DashboardTask
  @ObservedObject var vm: AppViewModel
  @Binding var autoPush: Bool
  let artifactText: String

  @State private var editTitle: String = ""
  @State private var editNotes: String = ""

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 16) {
        // Header
        VStack(alignment: .leading, spacing: 8) {
          TextField("Title", text: $editTitle)
            .font(.title3)
            .fontWeight(.bold)
            .textFieldStyle(.plain)
            .onAppear {
              editTitle = task.title
              editNotes = task.notes ?? ""
            }

          HStack(spacing: 6) {
            DetailTag(text: task.owner.rawValue, icon: "person", color: .purple)
            DetailTag(text: task.status.rawValue, icon: "circle.grid.2x2", color: .blue)
            if let ws = task.workState {
              DetailTag(text: ws.rawValue, icon: "hammer", color: .indigo)
            }
            if let rs = task.reviewState {
              DetailTag(text: rs.rawValue, icon: "eye", color: .green)
            }
          }

          VStack(alignment: .leading, spacing: 6) {
            Text("Notes")
              .font(.caption)
              .foregroundStyle(.secondary)

            TextField("Add notes…", text: $editNotes, axis: .vertical)
              .textFieldStyle(.roundedBorder)
              .lineLimit(6, reservesSpace: true)
          }

          Button {
            vm.editTask(taskId: task.id, title: editTitle, notes: editNotes, autoPush: autoPush)
          } label: {
            Label("Save", systemImage: "square.and.arrow.down")
          }
          .buttonStyle(.bordered)
        }

        Divider()

        // Context-aware actions based on task status
        VStack(alignment: .leading, spacing: 10) {
          Text("Actions")
            .font(.subheadline)
            .fontWeight(.bold)

          switch task.status {
          case .inbox:
            // Inbox: approve (→ active), request changes, reject
            HStack(spacing: 8) {
              ActionButton(label: "Approve", icon: "checkmark.seal.fill", color: .green) {
                vm.approveSelected(autoPush: autoPush)
              }
              ActionButton(label: "Changes", icon: "pencil.circle.fill", color: .orange) {
                vm.requestChangesSelected(autoPush: autoPush)
              }
              ActionButton(label: "Reject", icon: "xmark.seal.fill", color: .red) {
                vm.rejectSelected(autoPush: autoPush)
              }
            }
            Text("Approve moves this task to Active for Lobs to work on.")
              .font(.caption2)
              .foregroundStyle(.secondary)

          case .active:
            // Active: mark complete, toggle blocked
            HStack(spacing: 8) {
              ActionButton(label: "Mark Complete", icon: "checkmark.circle.fill", color: .green) {
                vm.completeSelected(autoPush: autoPush)
              }
              ActionButton(
                label: task.workState == .blocked ? "Unblock" : "Block",
                icon: task.workState == .blocked ? "play.circle.fill" : "exclamationmark.octagon.fill",
                color: task.workState == .blocked ? .blue : .red
              ) {
                vm.toggleBlockSelected(autoPush: autoPush)
              }
            }

          case .completed, .rejected:
            // Completed/Rejected: reopen
            HStack(spacing: 8) {
              ActionButton(label: "Reopen", icon: "arrow.counterclockwise.circle.fill", color: .blue) {
                vm.reopenSelected(autoPush: autoPush)
              }
            }

          case .waitingOn:
            // Waiting: complete or move back to active
            HStack(spacing: 8) {
              ActionButton(label: "Mark Complete", icon: "checkmark.circle.fill", color: .green) {
                vm.completeSelected(autoPush: autoPush)
              }
              ActionButton(label: "Reopen", icon: "arrow.counterclockwise.circle.fill", color: .blue) {
                vm.reopenSelected(autoPush: autoPush)
              }
            }

          case .other:
            HStack(spacing: 8) {
              ActionButton(label: "Reopen", icon: "arrow.counterclockwise.circle.fill", color: .blue) {
                vm.reopenSelected(autoPush: autoPush)
              }
            }
          }
        }

        // Artifact
        if artifactText != "(select a task)" {
          Divider()

          VStack(alignment: .leading, spacing: 6) {
            Text("Artifact")
              .font(.subheadline)
              .fontWeight(.bold)

            ScrollView {
              Text(artifactText)
                .font(.system(.caption, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
            }
            .frame(maxHeight: 200)
            .padding(8)
            .background(Theme.subtle)
            .clipShape(RoundedRectangle(cornerRadius: 8))
          }
        }
      }
      .padding(20)
    }
  }
}

// MARK: - Relative Time Helper

private func relativeTime(_ date: Date) -> String {
  let now = Date()
  let seconds = now.timeIntervalSince(date)
  if seconds < 60 { return "just now" }
  let minutes = Int(seconds / 60)
  if minutes < 60 { return "\(minutes)m ago" }
  let hours = Int(seconds / 3600)
  if hours < 24 { return "\(hours)h ago" }
  let days = Int(seconds / 86400)
  if days < 30 { return "\(days)d ago" }
  let months = Int(seconds / 2_592_000)
  return "\(months)mo ago"
}

// MARK: - Mini Tag (for cards)

private struct MiniTag: View {
  let text: String
  let color: Color

  var body: some View {
    Text(text)
      .font(.system(size: 10, weight: .medium))
      .padding(.horizontal, 7)
      .padding(.vertical, 3)
      .background(color.opacity(0.12))
      .foregroundStyle(color)
      .clipShape(Capsule())
  }
}

// MARK: - Detail Tag (for popover)

private struct DetailTag: View {
  let text: String
  let icon: String
  let color: Color

  var body: some View {
    HStack(spacing: 3) {
      Image(systemName: icon)
        .font(.system(size: 9))
      Text(text)
        .font(.system(size: 10, weight: .medium))
    }
    .padding(.horizontal, 7)
    .padding(.vertical, 3)
    .background(color.opacity(0.12))
    .foregroundStyle(color)
    .clipShape(Capsule())
  }
}

// MARK: - Action Button

private struct ActionButton: View {
  let label: String
  let icon: String
  let color: Color
  let action: () -> Void

  @State private var isHovering = false

  var body: some View {
    Button(action: action) {
      HStack(spacing: 4) {
        Image(systemName: icon)
          .font(.caption2)
        Text(label)
          .font(.caption)
          .fontWeight(.medium)
      }
      .padding(.horizontal, 10)
      .padding(.vertical, 6)
      .background(isHovering ? color.opacity(0.18) : color.opacity(0.1))
      .foregroundStyle(color)
      .clipShape(RoundedRectangle(cornerRadius: 8))
    }
    .buttonStyle(.plain)
    .onHover { h in isHovering = h }
  }
}

// MARK: - Add Task Sheet

private struct AddTaskSheet: View {
  @ObservedObject var vm: AppViewModel
  @Binding var autoPush: Bool

  @Environment(\.dismiss) private var dismiss

  @State private var title: String = ""
  @State private var notes: String = ""

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      HStack {
        Image(systemName: "plus.circle.fill")
          .font(.title2)
          .foregroundStyle(.linearGradient(
            colors: [.blue, .purple],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
          ))
        Text("New Task")
          .font(.title2)
          .fontWeight(.bold)
      }

      VStack(alignment: .leading, spacing: 8) {
        Text("Title")
          .font(.subheadline)
          .fontWeight(.medium)
        TextField("What needs to be done?", text: $title)
          .textFieldStyle(.roundedBorder)
          .font(.body)
      }

      VStack(alignment: .leading, spacing: 8) {
        Text("Notes")
          .font(.subheadline)
          .fontWeight(.medium)
        TextField("Additional context (optional)", text: $notes, axis: .vertical)
          .textFieldStyle(.roundedBorder)
          .lineLimit(4, reservesSpace: true)
      }

      Spacer()

      HStack {
        Text("⌘N to open · Enter to create")
          .font(.caption)
          .foregroundStyle(.tertiary)

        Spacer()

        Button("Cancel") { dismiss() }
          .keyboardShortcut(.cancelAction)

        Button {
          vm.submitTaskToLobs(title: title, notes: notes.isEmpty ? nil : notes, autoPush: autoPush)
          dismiss()
        } label: {
          Text("Create Task")
            .fontWeight(.semibold)
        }
        .keyboardShortcut(.defaultAction)
        .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        .buttonStyle(.borderedProminent)
      }
    }
    .padding(24)
    .frame(minWidth: 480, minHeight: 280)
  }
}
