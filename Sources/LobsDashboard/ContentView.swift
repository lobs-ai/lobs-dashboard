import SwiftUI
import UniformTypeIdentifiers

#if os(macOS)
import AppKit
#endif

// MARK: - Drop Delegate

private struct TaskDropDelegate: DropDelegate {
  let status: TaskStatus
  let vm: AppViewModel

  func validateDrop(info: DropInfo) -> Bool { true }

  func performDrop(info: DropInfo) -> Bool {
    guard let id = vm.draggingTaskId else { return false }
    vm.reorderTask(taskId: id, to: status, beforeTaskId: nil)
    return true
  }
}

/// Drop delegate for inserting before a specific task (reorder within column)
private struct TaskInsertDropDelegate: DropDelegate {
  let beforeTaskId: String
  let status: TaskStatus
  let vm: AppViewModel

  func validateDrop(info: DropInfo) -> Bool { true }

  func performDrop(info: DropInfo) -> Bool {
    guard let id = vm.draggingTaskId, id != beforeTaskId else { return false }
    vm.reorderTask(taskId: id, to: status, beforeTaskId: beforeTaskId)
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
  @State private var showCreateProject = false
  @State private var editingProject: Project? = nil
  @State private var showSettings = false
  @State private var showInbox = false
  @State private var showAllDone = false
  @State private var showAllRejected = false
  @State private var quickAddText = ""
  @State private var showTemplates = false

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
          showCreateProject: $showCreateProject,
          editingProject: $editingProject,
          showSettings: $showSettings,
          showInbox: $showInbox,
          showTemplates: $showTemplates
        )

        // Stats bar
        StatsBar(vm: vm)

        Divider()

        // Switch view: overview (home) vs project board
        // Content fills remaining space below the pinned header
        Group {
          if vm.showOverview {
            OverviewView(vm: vm) { projectId in
              vm.selectedProjectId = projectId
              vm.showOverview = false
            }
          } else if vm.isResearchProject {
            ResearchBoardView(vm: vm)
          } else if vm.isTrackerProject {
            TrackerBoardView(vm: vm)
          } else {
            // Kanban board
            BoardView(
              vm: vm,
              showAllDone: $showAllDone,
              showAllRejected: $showAllRejected,
              autoPush: $autoPush,
              quickAddText: $quickAddText
            )
          }
        }
        .frame(maxHeight: .infinity)
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
            .font(.footnote)
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

      // Inbox overlay — clicking outside dismisses (Task #479271CB)
      if showInbox {
        Color.black.opacity(0.3)
          .ignoresSafeArea()
          .onTapGesture { showInbox = false }
          .zIndex(200)

        InboxView(vm: vm, isPresented: $showInbox)
          .frame(minWidth: 1000, idealWidth: 1200, minHeight: 700, idealHeight: 800)
          .clipShape(RoundedRectangle(cornerRadius: 16))
          .shadow(color: .black.opacity(0.3), radius: 30, y: 10)
          .padding(40)
          .onExitCommand { showInbox = false }
          .transition(.opacity.combined(with: .scale(scale: 0.95)))
          .zIndex(201)
      }
    }
    .animation(.easeInOut(duration: 0.3), value: vm.errorBanner != nil)
    .animation(.easeOut(duration: 0.2), value: vm.isGitBusy)
    .animation(.easeInOut(duration: 0.25), value: showInbox)
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
      AddTaskSheet(
        vm: vm,
        autoPush: $autoPush,
        projectId: vm.showOverview ? nil : vm.selectedProjectId
      )
    }
    .sheet(isPresented: $showCreateProject) {
      CreateProjectSheet(vm: vm)
    }
    .sheet(item: $editingProject) { project in
      EditProjectSheet(vm: vm, project: project)
    }
    .sheet(isPresented: $showTemplates) {
      TemplateManagerSheet(vm: vm)
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
    }
    .frame(width: 0, height: 0)
    .allowsHitTesting(false)
    #if os(macOS)
    .background(
      ArrowKeyMonitor(onDown: onNextTask, onUp: onPrevTask)
    )
    #endif
  }
}

#if os(macOS)
/// Uses NSEvent local monitor so arrow keys pass through to text fields
/// and are only intercepted when no text input is focused.
private struct ArrowKeyMonitor: NSViewRepresentable {
  let onDown: () -> Void
  let onUp: () -> Void

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
        return nil // consume
      case 126: // up arrow
        DispatchQueue.main.async { self.onUp() }
        return nil // consume
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
#endif

// MARK: - Toolbar Area

private struct ToolbarArea: View {
  @ObservedObject var vm: AppViewModel
  @Binding var autoPush: Bool
  @Binding var showPicker: Bool
  @Binding var showAddTask: Bool
  @Binding var showCreateProject: Bool
  @Binding var editingProject: Project?
  @Binding var showSettings: Bool
  @Binding var showInbox: Bool
  @Binding var showTemplates: Bool

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

      // Home button
      Button {
        vm.showOverview = true
      } label: {
        Image(systemName: "house.fill")
          .font(.body)
          .padding(6)
          .background(vm.showOverview ? Color.accentColor.opacity(0.15) : Theme.subtle)
          .clipShape(RoundedRectangle(cornerRadius: 8))
      }
      .buttonStyle(.plain)
      .help("Home — Overview")

      // Project
      Menu {
        ForEach(vm.projects.filter { ($0.archived ?? false) == false }) { p in
          Button {
            vm.selectedProjectId = p.id
            vm.showOverview = false
          } label: {
            HStack {
              if vm.selectedProjectId == p.id {
                Image(systemName: "checkmark")
              }
              Image(systemName: projectTypeIcon(p.resolvedType))
              Text(p.title)
            }
          }
        }

        Divider()

        // Project management submenu for selected project
        if let selected = vm.projects.first(where: { $0.id == vm.selectedProjectId }),
           selected.id != "default" {
          Menu("Manage \"\(selected.title)\"") {
            Button {
              editingProject = selected
            } label: {
              Label("Edit…", systemImage: "pencil")
            }

            Button {
              vm.archiveProject(id: selected.id)
            } label: {
              Label("Archive", systemImage: "archivebox")
            }

            Divider()

            Button(role: .destructive) {
              vm.deleteProject(id: selected.id)
            } label: {
              Label("Delete", systemImage: "trash")
            }
          }

          Divider()
        }

        // Archived projects submenu
        let archivedProjects = vm.projects.filter { $0.archived == true }
        if !archivedProjects.isEmpty {
          Menu("Archived (\(archivedProjects.count))") {
            ForEach(archivedProjects) { p in
              Menu(p.title) {
                Button {
                  vm.unarchiveProject(id: p.id)
                } label: {
                  Label("Unarchive", systemImage: "tray.and.arrow.up")
                }

                Button {
                  vm.selectedProjectId = p.id
                } label: {
                  Label("View", systemImage: "eye")
                }

                Divider()

                Button(role: .destructive) {
                  vm.deleteProject(id: p.id)
                } label: {
                  Label("Delete Permanently", systemImage: "trash")
                }
              }
            }
          }

          Divider()
        }

        Button {
          showCreateProject = true
        } label: {
          Label("Create project…", systemImage: "plus")
        }
      } label: {
        HStack(spacing: 6) {
          Image(systemName: projectTypeIcon(vm.selectedProject?.resolvedType ?? .kanban))
            .foregroundStyle(projectTypeAccentColor(vm.selectedProject?.resolvedType ?? .kanban))
            .font(.footnote)
          Text(vm.projects.first(where: { $0.id == vm.selectedProjectId })?.title ?? "Default")
            .font(.footnote)
            .foregroundStyle(.secondary)
          if let type = vm.selectedProject?.resolvedType, type != .kanban {
            Text(type.rawValue.capitalized)
              .font(.system(size: 11, weight: .medium))
              .padding(.horizontal, 5)
              .padding(.vertical, 1)
              .background(projectTypeAccentColor(type).opacity(0.15))
              .foregroundStyle(projectTypeAccentColor(type))
              .clipShape(Capsule())
          }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Theme.subtle)
        .clipShape(RoundedRectangle(cornerRadius: 8))
      }
      .menuStyle(.borderlessButton)

      // Search
      HStack(spacing: 6) {
        Image(systemName: "magnifyingglass")
          .foregroundStyle(.secondary)
          .font(.footnote)
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
              .font(.footnote)
          }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(vm.ownerFilter != "all" ? Color.accentColor.opacity(0.12) : Theme.subtle)
        .clipShape(RoundedRectangle(cornerRadius: 8))
      }
      .menuStyle(.borderlessButton)
      .fixedSize()

      // Inbox button
      Button {
        showInbox = true
      } label: {
        ZStack(alignment: .topTrailing) {
          Image(systemName: "tray.full")
            .font(.body)
            .padding(6)
            .background(Theme.subtle)
            .clipShape(RoundedRectangle(cornerRadius: 8))
          if vm.unreadInboxCount > 0 {
            Text("\(vm.unreadInboxCount)")
              .font(.system(size: 11, weight: .bold))
              .foregroundStyle(.white)
              .padding(.horizontal, 4)
              .padding(.vertical, 1)
              .background(Color.blue)
              .clipShape(Capsule())
              .offset(x: 4, y: -4)
          }
        }
      }
      .buttonStyle(.plain)
      .help("Inbox — Design Docs & Artifacts")

      // Templates button
      if !vm.templates.isEmpty {
        Menu {
          ForEach(vm.templates) { template in
            Button {
              vm.stampTemplate(template, autoPush: true)
            } label: {
              Label(template.name, systemImage: "doc.on.doc")
            }
          }
          Divider()
          Button {
            showTemplates = true
          } label: {
            Label("Manage Templates…", systemImage: "pencil")
          }
        } label: {
          Image(systemName: "doc.on.doc")
            .font(.body)
            .padding(6)
            .background(Theme.subtle)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Task Templates")
      } else {
        Button {
          showTemplates = true
        } label: {
          Image(systemName: "doc.on.doc")
            .font(.body)
            .padding(6)
            .background(Theme.subtle)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .help("Task Templates")
      }

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
    .fixedSize(horizontal: false, vertical: true)
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
  // App icon is bundled; no icon picker.

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text("Settings")
        .font(.headline)
        .fontWeight(.bold)

      // Repository
      GroupBox {
        VStack(alignment: .leading, spacing: 8) {
          Label("Repository", systemImage: "folder.badge.gear")
            .font(.callout)
            .fontWeight(.semibold)

          if let repo = vm.repoURL {
            Text(repo.path)
              .font(.footnote)
              .foregroundStyle(.secondary)
              .lineLimit(2)
          } else {
            Text("Not configured")
              .font(.footnote)
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
            .font(.callout)
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
                .font(.footnote)
              TextField("", value: $vm.archiveCompletedAfterDays, format: .number)
                .textFieldStyle(.roundedBorder)
                .frame(width: 50)
              Text("days")
                .font(.footnote)
            }
          }
        }
      }

      // Display
      GroupBox {
        VStack(alignment: .leading, spacing: 8) {
          Label("Display", systemImage: "eye")
            .font(.callout)
            .fontWeight(.semibold)

          HStack {
            Text("WIP limit (Active)")
              .font(.footnote)
            Stepper(value: $vm.wipLimitActive, in: 1...20) {
              Text("\(vm.wipLimitActive)")
                .font(.footnote)
                .monospacedDigit()
            }
          }
        }
      }

      // App Icon is bundled (Resources/AppIcon.png)

      if let err = vm.lastError {
        GroupBox {
          VStack(alignment: .leading, spacing: 4) {
            Label("Error", systemImage: "exclamationmark.triangle")
              .font(.callout)
              .foregroundStyle(.red)
            Text(err)
              .font(.footnote)
              .foregroundStyle(.secondary)
              .textSelection(.enabled)
          }
        }
      }
    }
    .padding(16)
    .frame(width: 300)

    // App icon is bundled; no icon picker.
  }
}

// MARK: - Stats Bar

private struct StatsBar: View {
  @ObservedObject var vm: AppViewModel

  private var inboxCount: Int { vm.tasks.filter { $0.status == .inbox }.count }
  private var activeCount: Int { vm.tasks.filter { $0.status == .active }.count }
  private var doneCount: Int {
    vm.tasks.filter { $0.status == .completed }.count
  }
  private var blockedCount: Int { vm.tasks.filter { $0.workState == .blocked }.count }
  private var totalCount: Int { vm.tasks.count }

  var body: some View {
    HStack(spacing: 16) {
      Button {
        withAnimation(.easeInOut(duration: 0.15)) {
          vm.showInboxOnly.toggle()
        }
      } label: {
        StatPill(label: vm.showInboxOnly ? "Inbox (showing)" : "Inbox", count: inboxCount, color: .blue)
      }
      .buttonStyle(.plain)

      StatPill(label: "Active", count: activeCount, color: .orange)
      if blockedCount > 0 {
        StatPill(label: "Blocked", count: blockedCount, color: .red)
      }
      StatPill(label: "Done", count: doneCount, color: .green)

      Spacer()

      Text("\(totalCount) tasks")
        .font(.footnote)
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
        .font(.footnote)
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
        .font(.footnote)
        .lineLimit(2)
      Spacer()
      Button {
        dismiss()
      } label: {
        Image(systemName: "xmark")
          .font(.footnote)
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
  @Binding var showAllDone: Bool
  @Binding var showAllRejected: Bool
  @Binding var autoPush: Bool
  @Binding var quickAddText: String

  var body: some View {
    VStack(spacing: 0) {
      // Project README (pinned context doc)
      if !vm.projectReadme.isEmpty || vm.selectedProjectId != "default" {
        ProjectReadmeBar(vm: vm)
      }

      ScrollView(.horizontal, showsIndicators: false) {
        HStack(alignment: .top, spacing: 16) {
          ForEach(vm.columns, id: \.title) { col in
            BoardColumn(
              title: col.title,
              tasks: vm.filteredTasks.filter(col.matches),
              dropStatus: col.dropStatus,
              vm: vm,
              autoPush: $autoPush,
              showAllDone: $showAllDone,
              showAllRejected: $showAllRejected,
              quickAddText: $quickAddText
            )
          }
        }
        .padding(20)
      }
    }
  }
}

// MARK: - Project README Bar

private struct ProjectReadmeBar: View {
  @ObservedObject var vm: AppViewModel
  @State private var isExpanded: Bool = false
  @State private var isEditing: Bool = false
  @State private var editText: String = ""

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      // Header
      HStack(spacing: 8) {
        Button {
          withAnimation(.easeInOut(duration: 0.2)) {
            isExpanded.toggle()
          }
        } label: {
          HStack(spacing: 6) {
            Image(systemName: "doc.text.fill")
              .font(.footnote)
              .foregroundStyle(.blue)
            Text("README")
              .font(.footnote)
              .fontWeight(.semibold)
            if vm.projectReadme.isEmpty {
              Text("(empty)")
                .font(.footnote)
                .foregroundStyle(.tertiary)
            }
            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
              .font(.system(size: 10))
              .foregroundStyle(.secondary)
          }
        }
        .buttonStyle(.plain)

        Spacer()

        if isExpanded {
          Button {
            if isEditing {
              vm.saveProjectReadme(content: editText)
              isEditing = false
            } else {
              editText = vm.projectReadme
              isEditing = true
            }
          } label: {
            HStack(spacing: 3) {
              Image(systemName: isEditing ? "checkmark" : "pencil")
                .font(.system(size: 11))
              Text(isEditing ? "Save" : "Edit")
                .font(.system(size: 11))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Theme.subtle)
            .clipShape(Capsule())
          }
          .buttonStyle(.plain)
        }
      }
      .padding(.horizontal, 20)
      .padding(.vertical, 8)

      if isExpanded {
        Divider()
          .padding(.horizontal, 16)

        if isEditing {
          TextEditor(text: $editText)
            .font(.system(size: 13, design: .monospaced))
            .frame(minHeight: 80, maxHeight: 200)
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
        } else if !vm.projectReadme.isEmpty {
          ScrollView {
            if let md = try? AttributedString(markdown: vm.projectReadme, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
              Text(md)
                .font(.system(size: 13))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
              Text(vm.projectReadme)
                .font(.system(size: 13))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
          }
          .frame(maxHeight: 150)
          .padding(.horizontal, 20)
          .padding(.vertical, 8)
        } else {
          Text("No README yet. Click Edit to add project context.")
            .font(.footnote)
            .foregroundStyle(.tertiary)
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
        }
      }
    }
    .background(Theme.bg.opacity(0.7))
  }
}

// MARK: - Board Column

private struct BoardColumn: View {
  let title: String
  let tasks: [DashboardTask]
  let dropStatus: TaskStatus

  @ObservedObject var vm: AppViewModel
  @Binding var autoPush: Bool
  @Binding var showAllDone: Bool
  @Binding var showAllRejected: Bool
  @Binding var quickAddText: String

  @State private var isHovering = false

  private var columnColor: Color {
    switch title.lowercased() {
    case "inbox": return .blue
    case "active": return .orange
    case "waiting on": return .yellow
    case "done": return .green
    case "rejected": return .red
    default: return .gray
    }
  }

  var body: some View {
    let isDone = title.lowercased() == "done"
    let isRejected = title.lowercased() == "rejected"
    let showAll = isDone ? showAllDone : (isRejected ? showAllRejected : true)
    let visibleTasks = (isDone || isRejected) && !showAll
      ? Array(tasks.sorted { $0.createdAt > $1.createdAt }.prefix(vm.completedShowRecent))
      : tasks

    let wipLimit = (title.lowercased() == "active") ? vm.wipLimitActive : 0

    VStack(alignment: .leading, spacing: 0) {
      // Column header
      HStack(alignment: .center, spacing: 8) {
        Circle()
          .fill(columnColor)
          .frame(width: 8, height: 8)

        Text(title)
          .font(.callout)
          .fontWeight(.bold)
          .foregroundStyle(.primary)

        Text("\(tasks.count)")
          .font(.footnote)
          .fontWeight(.medium)
          .padding(.horizontal, 7)
          .padding(.vertical, 2)
          .background(Theme.subtle)
          .clipShape(Capsule())

        if wipLimit > 0 && tasks.count > wipLimit {
          Text("WIP")
            .font(.footnote)
            .fontWeight(.bold)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.orange.opacity(0.2))
            .foregroundStyle(.orange)
            .clipShape(Capsule())
        }

        Spacer()

        if isDone {
          Button {
            withAnimation(.easeInOut(duration: 0.2)) {
              showAllDone.toggle()
            }
          } label: {
            Image(systemName: showAllDone ? "chevron.up" : "chevron.down")
              .font(.footnote)
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
              .font(.footnote)
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
              .onDrop(of: [.text], delegate: TaskInsertDropDelegate(
                beforeTaskId: t.id,
                status: dropStatus,
                vm: vm
              ))
          }

          if (isDone || isRejected) && !showAll && tasks.count > vm.completedShowRecent {
            Text("+\(tasks.count - vm.completedShowRecent) more")
              .font(.footnote)
              .foregroundStyle(.secondary)
              .frame(maxWidth: .infinity)
              .padding(.vertical, 4)
          }
        }
        .padding(10)
      }

      // Quick-add inline removed (Task #9168CFAF)
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
        .font(.callout)
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
        if let md = try? AttributedString(markdown: notes, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
          Text(md)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .lineLimit(2)
        } else {
          Text(notes)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .lineLimit(2)
        }
      }

      // Duration + relative timestamp
      HStack(spacing: 6) {
        if let started = task.startedAt {
          let end = task.finishedAt ?? Date()
          let dur = end.timeIntervalSince(started)
          HStack(spacing: 2) {
            Image(systemName: "clock")
              .font(.system(size: 10))
            Text(formatDuration(dur))
              .font(.system(size: 11))
          }
          .foregroundStyle(.tertiary)
        }

        Text(relativeTime(task.updatedAt))
          .font(.system(size: 11))
          .foregroundStyle(.tertiary)
      }
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
      TaskDetailPopover(task: task, vm: vm, autoPush: $autoPush, artifactText: vm.artifactText) {
        showDetail = false
        TaskDetailWindowController.open(task: task, vm: vm, artifactText: vm.artifactText)
      }
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
  var onPopOut: (() -> Void)? = nil

  @State private var editTitle: String = ""
  @State private var editNotes: String = ""

  @State private var autosaveWorkItem: DispatchWorkItem? = nil
  @State private var lastAutosavedTitle: String = ""
  @State private var lastAutosavedNotes: String = ""
  @State private var showMarkdownPreview: Bool = false

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
              lastAutosavedTitle = editTitle
              lastAutosavedNotes = editNotes
            }
            .onSubmit {
              vm.editTask(taskId: task.id, title: editTitle, notes: editNotes, autoPush: autoPush)
              lastAutosavedTitle = editTitle
              lastAutosavedNotes = editNotes
            }
            .onChange(of: editTitle) { _ in scheduleAutosave() }

          HStack(spacing: 6) {
            DetailTag(text: task.owner.rawValue, icon: "person", color: .purple)
            DetailTag(text: task.status.rawValue, icon: "circle.grid.2x2", color: .blue)
            if let ws = task.workState {
              DetailTag(text: ws.rawValue, icon: "hammer", color: .indigo)
            }
            if let rs = task.reviewState {
              DetailTag(text: rs.rawValue, icon: "eye", color: .green)
            }
            if let started = task.startedAt {
              let end = task.finishedAt ?? Date()
              let dur = end.timeIntervalSince(started)
              DetailTag(text: formatDuration(dur), icon: "clock", color: .orange)
            }
          }

          VStack(alignment: .leading, spacing: 6) {
            HStack {
              Text("Notes")
                .font(.footnote)
                .foregroundStyle(.secondary)

              Spacer()

              Button {
                showMarkdownPreview.toggle()
              } label: {
                HStack(spacing: 3) {
                  Image(systemName: showMarkdownPreview ? "pencil" : "eye")
                    .font(.system(size: 11))
                  Text(showMarkdownPreview ? "Edit" : "Preview")
                    .font(.system(size: 11))
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Theme.subtle)
                .clipShape(Capsule())
              }
              .buttonStyle(.plain)

              if !showMarkdownPreview {
                Text("Shift+Enter for new line")
                  .font(.footnote)
                  .foregroundStyle(.tertiary)
              }
            }

            if showMarkdownPreview {
              ScrollView {
                if let md = try? AttributedString(markdown: editNotes, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
                  Text(md)
                    .font(.system(size: NSFont.smallSystemFontSize))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                  Text(editNotes)
                    .font(.system(size: NSFont.smallSystemFontSize))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
              }
              .frame(minHeight: 80, maxHeight: 160)
              .padding(8)
              .background(Theme.subtle)
              .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
              SpellCheckingTextEditor(
                text: $editNotes,
                font: .systemFont(ofSize: NSFont.smallSystemFontSize),
                placeholder: "Add notes…",
                onSubmit: {
                  vm.editTask(taskId: task.id, title: editTitle, notes: editNotes, autoPush: autoPush)
                  lastAutosavedTitle = editTitle
                  lastAutosavedNotes = editNotes
                }
              )
              .frame(minHeight: 80, maxHeight: 160)
              .onChange(of: editNotes) { _ in scheduleAutosave() }
            }
          }

          HStack(spacing: 8) {
            Button {
              vm.editTask(taskId: task.id, title: editTitle, notes: editNotes, autoPush: autoPush)
            } label: {
              Label("Save", systemImage: "square.and.arrow.down")
            }
            .buttonStyle(.bordered)

            Spacer()

            if let onPopOut {
              Button {
                onPopOut()
              } label: {
                Label("Pop Out", systemImage: "arrow.up.left.and.arrow.down.right")
              }
              .buttonStyle(.bordered)
              .help("Open in separate window for easier editing")
            }
          }
        }

        Divider()

        // Context-aware actions based on task status
        VStack(alignment: .leading, spacing: 10) {
          Text("Actions")
            .font(.callout)
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
              .font(.footnote)
              .foregroundStyle(.secondary)

          case .active:
            // Active: mark complete, toggle blocked, move to waiting
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
              ActionButton(label: "Waiting On", icon: "person.badge.clock", color: .yellow) {
                vm.moveTask(taskId: task.id, to: .waitingOn)
              }
            }

          case .completed:
            // Completed: either mark as Done (approved) or reopen.
            HStack(spacing: 8) {
              ActionButton(label: "Mark Done", icon: "checkmark.seal.fill", color: .green) {
                vm.markDoneSelected(autoPush: autoPush)
              }
              ActionButton(label: "Reopen", icon: "arrow.counterclockwise.circle.fill", color: .blue) {
                vm.reopenSelected(autoPush: autoPush)
              }
            }

          case .rejected:
            // Rejected: reopen
            HStack(spacing: 8) {
              ActionButton(label: "Reopen", icon: "arrow.counterclockwise.circle.fill", color: .blue) {
                vm.reopenSelected(autoPush: autoPush)
              }
            }

          case .waitingOn:
            // Waiting: move back to active, complete, or reopen
            HStack(spacing: 8) {
              ActionButton(label: "Back to Active", icon: "arrow.forward.circle.fill", color: .orange) {
                vm.moveTask(taskId: task.id, to: .active)
              }
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
              .font(.callout)
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

  private func scheduleAutosave() {
    autosaveWorkItem?.cancel()
    let titleNow = editTitle
    let notesNow = editNotes

    let item = DispatchWorkItem {
      // Avoid noisy commits if nothing materially changed.
      if titleNow == lastAutosavedTitle && notesNow == lastAutosavedNotes { return }
      vm.editTask(taskId: task.id, title: titleNow, notes: notesNow, autoPush: autoPush)
      lastAutosavedTitle = titleNow
      lastAutosavedNotes = notesNow
    }

    autosaveWorkItem = item
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: item)
  }
}

// MARK: - Project Type Helpers

private func projectTypeIcon(_ type: ProjectType) -> String {
  switch type {
  case .kanban: return "rectangle.split.3x1"
  case .research: return "doc.text.magnifyingglass"
  case .tracker: return "checklist"
  }
}

private func projectTypeAccentColor(_ type: ProjectType) -> Color {
  switch type {
  case .kanban: return .secondary
  case .research: return .orange
  case .tracker: return .cyan
  }
}

// MARK: - Relative Time Helper

private func formatDuration(_ seconds: TimeInterval) -> String {
  let totalMinutes = Int(seconds / 60)
  if totalMinutes < 60 { return "\(totalMinutes)m" }
  let hours = totalMinutes / 60
  let mins = totalMinutes % 60
  if hours < 24 {
    return mins > 0 ? "\(hours)h \(mins)m" : "\(hours)h"
  }
  let days = hours / 24
  let remHours = hours % 24
  return remHours > 0 ? "\(days)d \(remHours)h" : "\(days)d"
}

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
      .font(.system(size: 11, weight: .medium))
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
        .font(.system(size: 11))
      Text(text)
        .font(.system(size: 11, weight: .medium))
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
          .font(.footnote)
        Text(label)
          .font(.footnote)
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

// MARK: - Create Project Sheet

private struct CreateProjectSheet: View {
  @ObservedObject var vm: AppViewModel

  @Environment(\.dismiss) private var dismiss

  @State private var title: String = ""
  @State private var notes: String = ""
  @State private var projectType: ProjectType = .kanban

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      HStack {
        Image(systemName: "folder.badge.plus")
          .font(.title2)
          .foregroundStyle(.linearGradient(
            colors: [.blue, .purple],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
          ))
        Text("Create project")
          .font(.title3)
          .fontWeight(.bold)
        Spacer()
      }

      VStack(alignment: .leading, spacing: 10) {
        // Project type picker
        VStack(alignment: .leading, spacing: 6) {
          Text("Project Type")
            .font(.footnote)
            .foregroundStyle(.secondary)

          Picker("Type", selection: $projectType) {
            Text("Kanban").tag(ProjectType.kanban)
            Text("Research").tag(ProjectType.research)
            Text("Tracker").tag(ProjectType.tracker)
          }
          .pickerStyle(.segmented)

          Text(projectType == .kanban
            ? "Track tasks through columns: Active, Waiting, Done."
            : projectType == .research
            ? "Collect research tiles, notes, links, findings. Ask Lobs to investigate."
            : "Track items with status, difficulty, tags, and notes. Great for checklists and learning goals."
          )
            .font(.footnote)
            .foregroundStyle(.tertiary)
            .animation(.easeInOut(duration: 0.15), value: projectType)
        }

        TextField("Project name", text: $title)
          .textFieldStyle(.roundedBorder)

        TextField("Notes (optional)", text: $notes, axis: .vertical)
          .textFieldStyle(.roundedBorder)
          .lineLimit(6, reservesSpace: true)
      }

      HStack {
        Button("Cancel") { dismiss() }
          .keyboardShortcut(.cancelAction)

        Spacer()

        Button("Create") {
          vm.createProject(title: title, notes: notes, type: projectType)
          dismiss()
        }
        .keyboardShortcut(.defaultAction)
        .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
      }
    }
    .padding(20)
    .frame(width: 420)
  }
}

// MARK: - Edit Project Sheet

private struct EditProjectSheet: View {
  @ObservedObject var vm: AppViewModel
  let project: Project

  @Environment(\.dismiss) private var dismiss

  @State private var title: String = ""
  @State private var notes: String = ""

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      HStack {
        Image(systemName: "folder.badge.gear")
          .font(.title2)
          .foregroundStyle(.linearGradient(
            colors: [.blue, .purple],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
          ))
        Text("Edit project")
          .font(.title3)
          .fontWeight(.bold)
        Spacer()
      }

      VStack(alignment: .leading, spacing: 10) {
        TextField("Project name", text: $title)
          .textFieldStyle(.roundedBorder)

        TextField("Description (optional)", text: $notes, axis: .vertical)
          .textFieldStyle(.roundedBorder)
          .lineLimit(6, reservesSpace: true)
      }

      HStack {
        Button("Cancel") { dismiss() }
          .keyboardShortcut(.cancelAction)

        Spacer()

        Button("Save") {
          let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
          if !trimmedTitle.isEmpty && trimmedTitle != project.title {
            vm.renameProject(id: project.id, newTitle: trimmedTitle)
          }
          let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
          let oldNotes = project.notes?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
          if trimmedNotes != oldNotes {
            vm.updateProjectNotes(id: project.id, notes: trimmedNotes.isEmpty ? nil : trimmedNotes)
          }
          dismiss()
        }
        .keyboardShortcut(.defaultAction)
        .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
      }
    }
    .padding(20)
    .frame(width: 420)
    .onAppear {
      title = project.title
      notes = project.notes ?? ""
    }
  }
}

// MARK: - Add Task Sheet

private struct AddTaskSheet: View {
  @ObservedObject var vm: AppViewModel
  @Binding var autoPush: Bool

  /// When nil, the sheet is being presented from the overview/home screen and should
  /// require the user to explicitly choose a project.
  let projectId: String?

  @Environment(\.dismiss) private var dismiss

  @State private var title: String = ""
  @State private var notes: String = ""
  @State private var selectedProjectId: String = ""

  private var activeProjects: [Project] {
    vm.projects.filter { ($0.archived ?? false) == false }
  }

  private var shouldShowProjectPicker: Bool { projectId == nil }

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

      // Project picker (only required when creating from overview/home)
      if shouldShowProjectPicker {
        VStack(alignment: .leading, spacing: 8) {
          Text("Project")
            .font(.callout)
            .fontWeight(.medium)
          Picker("Project", selection: $selectedProjectId) {
            Text("Choose a project")
              .tag("")
            ForEach(activeProjects) { project in
              HStack(spacing: 6) {
                Image(systemName: project.resolvedType == .research ? "doc.text.magnifyingglass" : "rectangle.split.3x1")
                Text(project.title)
              }
              .tag(project.id)
            }
          }
          .labelsHidden()
        }
      }

      VStack(alignment: .leading, spacing: 8) {
        Text("Title")
          .font(.callout)
          .fontWeight(.medium)
        TextField("What needs to be done?", text: $title)
          .textFieldStyle(.roundedBorder)
          .font(.body)
      }

      VStack(alignment: .leading, spacing: 8) {
        Text("Notes")
          .font(.callout)
          .fontWeight(.medium)
        Text("Shift+Enter for new line")
          .font(.footnote)
          .foregroundStyle(.tertiary)
        SpellCheckingTextEditor(
          text: $notes,
          font: .systemFont(ofSize: NSFont.systemFontSize),
          placeholder: "Additional context (optional)",
          onSubmit: {
            let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            guard !selectedProjectId.isEmpty else { return }
            let prevProject = vm.selectedProjectId
            vm.selectedProjectId = selectedProjectId
            vm.submitTaskToLobs(title: title, notes: notes.isEmpty ? nil : notes, autoPush: autoPush)
            if vm.showOverview { vm.selectedProjectId = prevProject }
            dismiss()
          }
        )
        .frame(minHeight: 80, maxHeight: 160)
      }

      Spacer()

      HStack {
        Text("⌘N to open · Enter to create · Shift+Enter for new line")
          .font(.footnote)
          .foregroundStyle(.tertiary)

        Spacer()

        Button("Cancel") { dismiss() }
          .keyboardShortcut(.cancelAction)

        Button {
          let prevProject = vm.selectedProjectId
          vm.selectedProjectId = selectedProjectId
          vm.submitTaskToLobs(title: title, notes: notes.isEmpty ? nil : notes, autoPush: autoPush)
          if vm.showOverview { vm.selectedProjectId = prevProject }
          dismiss()
        } label: {
          Text("Create Task")
            .fontWeight(.semibold)
        }
        .keyboardShortcut(.defaultAction)
        .disabled(
          title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || selectedProjectId.isEmpty
        )
        .buttonStyle(.borderedProminent)
      }
    }
    .padding(24)
    .frame(minWidth: 480, minHeight: 320)
    .onAppear {
      if let projectId {
        selectedProjectId = projectId
      } else {
        // When invoked from the overview/home screen, force an explicit choice.
        selectedProjectId = ""
      }
    }
  }
}

// MARK: - Task Detail Window (Pop Out)

/// Opens a task detail view in a standalone NSWindow for easier editing.
final class TaskDetailWindowController {
  private static var openWindows: [String: NSWindow] = [:]

  static func open(task: DashboardTask, vm: AppViewModel, artifactText: String) {
    // If already open for this task, bring to front
    if let existing = openWindows[task.id], existing.isVisible {
      existing.makeKeyAndOrderFront(nil)
      return
    }

    let autoPushState = Binding<Bool>(get: { true }, set: { _ in })

    let content = TaskDetailPopover(
      task: task,
      vm: vm,
      autoPush: autoPushState,
      artifactText: artifactText
    )
    .frame(minWidth: 450, minHeight: 550)
    .padding(4)

    let hostingView = NSHostingView(rootView: content)

    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 480, height: 600),
      styleMask: [.titled, .closable, .resizable, .miniaturizable],
      backing: .buffered,
      defer: false
    )
    window.title = task.title
    window.contentView = hostingView
    window.center()
    window.isReleasedWhenClosed = false
    window.makeKeyAndOrderFront(nil)

    openWindows[task.id] = window
  }
}

// MARK: - Template Manager Sheet

private struct TemplateManagerSheet: View {
  @ObservedObject var vm: AppViewModel
  @Environment(\.dismiss) private var dismiss

  @State private var showCreateTemplate = false
  @State private var editingTemplate: TaskTemplate? = nil

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      HStack {
        Image(systemName: "doc.on.doc.fill")
          .font(.title2)
          .foregroundStyle(.linearGradient(
            colors: [.orange, .red],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
          ))
        Text("Task Templates")
          .font(.title3)
          .fontWeight(.bold)
        Spacer()
        Button { showCreateTemplate = true } label: {
          Label("New Template", systemImage: "plus")
        }
        .buttonStyle(.bordered)
      }

      if vm.templates.isEmpty {
        VStack(spacing: 12) {
          Image(systemName: "doc.on.doc")
            .font(.system(size: 36))
            .foregroundStyle(.quaternary)
          Text("No templates yet")
            .font(.callout)
            .foregroundStyle(.secondary)
          Text("Create a template to stamp out batches of pre-filled tasks")
            .font(.footnote)
            .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 40)
      } else {
        ScrollView {
          LazyVStack(spacing: 8) {
            ForEach(vm.templates) { template in
              HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                  Text(template.name)
                    .font(.callout)
                    .fontWeight(.semibold)
                  if let desc = template.description, !desc.isEmpty {
                    Text(desc)
                      .font(.footnote)
                      .foregroundStyle(.secondary)
                      .lineLimit(2)
                  }
                  Text("\(template.items.count) task\(template.items.count == 1 ? "" : "s")")
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
                }

                Spacer()

                Button {
                  vm.stampTemplate(template, autoPush: true)
                  dismiss()
                } label: {
                  Label("Use", systemImage: "plus.circle")
                }
                .buttonStyle(.bordered)

                Button {
                  editingTemplate = template
                } label: {
                  Image(systemName: "pencil")
                }
                .buttonStyle(.plain)

                Button(role: .destructive) {
                  vm.deleteTemplate(id: template.id)
                } label: {
                  Image(systemName: "trash")
                    .foregroundStyle(.red)
                }
                .buttonStyle(.plain)
              }
              .padding(12)
              .background(
                RoundedRectangle(cornerRadius: 10)
                  .fill(Color(nsColor: .controlBackgroundColor))
              )
            }
          }
        }
      }

      HStack {
        Spacer()
        Button("Done") { dismiss() }
          .keyboardShortcut(.cancelAction)
      }
    }
    .padding(20)
    .frame(minWidth: 500, minHeight: 300)
    .sheet(isPresented: $showCreateTemplate) {
      EditTemplateSheet(vm: vm, template: nil)
    }
    .sheet(item: $editingTemplate) { template in
      EditTemplateSheet(vm: vm, template: template)
    }
  }
}

// MARK: - Edit Template Sheet

private struct EditTemplateSheet: View {
  @ObservedObject var vm: AppViewModel
  let template: TaskTemplate?

  @Environment(\.dismiss) private var dismiss

  @State private var name: String = ""
  @State private var description: String = ""
  @State private var items: [TaskTemplateItem] = []

  private var isEditing: Bool { template != nil }

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text(isEditing ? "Edit Template" : "New Template")
        .font(.title3)
        .fontWeight(.bold)

      TextField("Template name", text: $name)
        .textFieldStyle(.roundedBorder)

      TextField("Description (optional)", text: $description)
        .textFieldStyle(.roundedBorder)

      Divider()

      HStack {
        Text("Tasks")
          .font(.callout)
          .fontWeight(.semibold)
        Spacer()
        Button {
          items.append(TaskTemplateItem(id: UUID().uuidString, title: "", notes: nil))
        } label: {
          Label("Add Task", systemImage: "plus")
        }
        .controlSize(.small)
      }

      ScrollView {
        LazyVStack(spacing: 6) {
          ForEach(items.indices, id: \.self) { idx in
            HStack(spacing: 8) {
              Text("\(idx + 1).")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(width: 20)

              VStack(spacing: 4) {
                TextField("Task title", text: $items[idx].title)
                  .textFieldStyle(.roundedBorder)
                  .font(.callout)
                TextField("Notes (optional)", text: Binding(
                  get: { items[idx].notes ?? "" },
                  set: { items[idx].notes = $0.isEmpty ? nil : $0 }
                ))
                .textFieldStyle(.roundedBorder)
                .font(.footnote)
              }

              Button {
                items.remove(at: idx)
              } label: {
                Image(systemName: "xmark.circle")
                  .foregroundStyle(.red.opacity(0.6))
              }
              .buttonStyle(.plain)
            }
          }
        }
      }
      .frame(minHeight: 100, maxHeight: 300)

      HStack {
        Button("Cancel") { dismiss() }
          .keyboardShortcut(.cancelAction)
        Spacer()
        Button(isEditing ? "Save" : "Create") {
          let now = Date()
          let t = TaskTemplate(
            id: template?.id ?? UUID().uuidString,
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            description: description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : description.trimmingCharacters(in: .whitespacesAndNewlines),
            items: items.filter { !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty },
            createdAt: template?.createdAt ?? now,
            updatedAt: now
          )
          vm.saveTemplate(t)
          dismiss()
        }
        .keyboardShortcut(.defaultAction)
        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || items.filter { !$0.title.isEmpty }.isEmpty)
        .buttonStyle(.borderedProminent)
      }
    }
    .padding(20)
    .frame(minWidth: 500, minHeight: 400)
    .onAppear {
      if let t = template {
        name = t.name
        description = t.description ?? ""
        items = t.items
      }
      if items.isEmpty {
        items = [TaskTemplateItem(id: UUID().uuidString, title: "", notes: nil)]
      }
    }
  }
}
