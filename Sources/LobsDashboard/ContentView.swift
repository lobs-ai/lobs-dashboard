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

// Theme is defined in Theme.swift

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
  @State private var inboxInitialItemId: String? = nil
  @State private var showAllDone = false
  @State private var showAllRejected = false
  @State private var quickAddText = ""
  @State private var showTemplates = false
  @State private var showHelp = false
  @State private var showTextDump = false
  @State private var showTextDumpResults = false
  @State private var showUpdatePopover = false
  @State private var showAIUsage = false
  @State private var requestSearchFocus = false
  @State private var showCommandPalette = false

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
          showTemplates: $showTemplates,
          showHelp: $showHelp,
          showTextDump: $showTextDump,
          showTextDumpResults: $showTextDumpResults,
          showUpdatePopover: $showUpdatePopover,
          requestSearchFocus: $requestSearchFocus
        )

        StatsBar(vm: vm)

        Divider()

        // Switch view: overview (home) vs project board
        // Content fills remaining space below the pinned header
        Group {
          if vm.showOverview {
            OverviewView(vm: vm, onSelectProject: { projectId in
              vm.selectedProjectId = projectId
              vm.showOverview = false
            }, onOpenInbox: { itemId in
              inboxInitialItemId = itemId
              withAnimation(.easeInOut(duration: 0.25)) { showInbox = true }
            }, onOpenAIUsage: {
              withAnimation(.easeInOut(duration: 0.25)) { showAIUsage = true }
            })
          } else if vm.isResearchProject {
            ResearchDocView(vm: vm)
              .id("research-\(vm.selectedProjectId)")
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

      // Success toast overlay
      if let banner = vm.successBanner {
        SuccessBanner(message: banner) {
          vm.successBanner = nil
        }
        .transition(.move(edge: .top).combined(with: .opacity))
        .zIndex(100)
        .padding(.top, 52)
      }

      // Sync blocked warning — uncommitted changes in local repo
      if vm.syncBlockedByUncommitted {
        HStack(spacing: 8) {
          Image(systemName: "exclamationmark.triangle.fill")
            .foregroundStyle(.orange)
          Text("Sync conflict — local changes couldn't be rebased automatically")
            .font(.footnote.weight(.medium))
          Spacer()
          Button("Dismiss") {
            vm.syncBlockedByUncommitted = false
          }
          .buttonStyle(.plain)
          .font(.footnote)
          .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color.orange.opacity(0.15))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .padding(.horizontal, 16)
        .transition(.move(edge: .top).combined(with: .opacity))
        .zIndex(98)
        .padding(.top, 52)
      }

      // Push failure warning — local commits not published
      if let err = vm.lastPushError {
        HStack(spacing: 8) {
          Image(systemName: "icloud.slash")
            .foregroundStyle(.red)
          Text("Push failed — local changes not published")
            .font(.footnote.weight(.medium))
          Spacer()
          Button("Push Now") {
            vm.pushNow()
          }
          .buttonStyle(.plain)
          .font(.footnote)
          Button("Dismiss") {
            vm.lastPushError = nil
          }
          .buttonStyle(.plain)
          .font(.footnote)
          .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color.red.opacity(0.15))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .padding(.horizontal, 16)
        .transition(.move(edge: .top).combined(with: .opacity))
        .zIndex(98)
        .padding(.top, 52)
        .help(err)
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

      // Floating keyboard shortcuts badge (⌘?)
      VStack {
        Spacer()
        HStack {
          Spacer()
          Button {
            withAnimation(.easeInOut(duration: 0.25)) { showHelp = true }
          } label: {
            HStack(spacing: 3) {
              Text("⌘")
                .font(.system(size: 11, weight: .medium))
              Text("?")
                .font(.system(size: 11, weight: .medium))
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(
              RoundedRectangle(cornerRadius: 6)
                .stroke(Color.primary.opacity(0.1), lineWidth: 0.5)
            )
          }
          .buttonStyle(.plain)
          .help("Keyboard Shortcuts (⌘/)")
          .opacity(showInbox || showHelp ? 0 : 0.7)
          .animation(.easeInOut(duration: 0.15), value: showInbox)
          .animation(.easeInOut(duration: 0.15), value: showHelp)
        }
        .padding(.trailing, 16)
        .padding(.bottom, 12)
      }
      .zIndex(50)
      .allowsHitTesting(!showInbox && !showHelp && !showAIUsage)

      // Inbox overlay — clicking outside dismisses (Task #479271CB)
      if showInbox {
        Color.black.opacity(0.3)
          .ignoresSafeArea()
          .onTapGesture { withAnimation(.easeInOut(duration: 0.25)) { showInbox = false } }
          .transition(.opacity)
          .zIndex(200)

        InboxView(vm: vm, isPresented: $showInbox, initialSelectedItemId: inboxInitialItemId)
          .frame(minWidth: 1000, idealWidth: 1200, minHeight: 700, idealHeight: 800)
          .clipShape(RoundedRectangle(cornerRadius: 16))
          .shadow(color: .black.opacity(0.3), radius: 30, y: 10)
          .padding(40)
          .onExitCommand { withAnimation(.easeInOut(duration: 0.25)) { showInbox = false } }
          .onDisappear { inboxInitialItemId = nil }
          .transition(.opacity.combined(with: .scale(scale: 0.95)))
          .zIndex(201)
      }

      // AI Usage overlay — clicking outside dismisses (Task #2EB50767)
      if showAIUsage {
        Color.black.opacity(0.3)
          .ignoresSafeArea()
          .onTapGesture { withAnimation(.easeInOut(duration: 0.25)) { showAIUsage = false } }
          .transition(.opacity)
          .zIndex(200)

        AIUsageView(vm: vm, isPresented: $showAIUsage)
          .frame(minWidth: 960, idealWidth: 1040, minHeight: 700, idealHeight: 800)
          .clipShape(RoundedRectangle(cornerRadius: 16))
          .shadow(color: .black.opacity(0.3), radius: 30, y: 10)
          .padding(40)
          .onExitCommand { withAnimation(.easeInOut(duration: 0.25)) { showAIUsage = false } }
          .transition(.opacity.combined(with: .scale(scale: 0.95)))
          .zIndex(201)
      }

      // Command Palette overlay (⌘K)
      if showCommandPalette {
        Color.black.opacity(0.3)
          .ignoresSafeArea()
          .onTapGesture { withAnimation(.easeInOut(duration: 0.25)) { showCommandPalette = false } }
          .transition(.opacity)
          .zIndex(200)

        CommandPaletteView(vm: vm, isPresented: $showCommandPalette)
          .frame(width: 560, height: 420)
          .clipShape(RoundedRectangle(cornerRadius: 14))
          .shadow(color: .black.opacity(0.3), radius: 30, y: 10)
          .padding(.top, 80)
          .onExitCommand { withAnimation(.easeInOut(duration: 0.25)) { showCommandPalette = false } }
          .transition(.opacity.combined(with: .move(edge: .top)))
          .zIndex(201)
      }

      // Help overlay — clicking outside dismisses (Task #2EB50767)
      if showHelp {
        Color.black.opacity(0.3)
          .ignoresSafeArea()
          .onTapGesture { withAnimation(.easeInOut(duration: 0.25)) { showHelp = false } }
          .transition(.opacity)
          .zIndex(200)

        HelpPanelSheet(isPresented: $showHelp)
          .frame(minWidth: 500, idealWidth: 600, minHeight: 500, idealHeight: 600)
          .clipShape(RoundedRectangle(cornerRadius: 16))
          .shadow(color: .black.opacity(0.3), radius: 30, y: 10)
          .padding(40)
          .onExitCommand { withAnimation(.easeInOut(duration: 0.25)) { showHelp = false } }
          .transition(.opacity.combined(with: .scale(scale: 0.95)))
          .zIndex(201)
      }
    }
    .animation(.easeInOut(duration: 0.3), value: vm.errorBanner != nil)
    .animation(.easeInOut(duration: 0.3), value: vm.successBanner != nil)
    .animation(.easeInOut(duration: 0.3), value: vm.syncBlockedByUncommitted)
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
    .sheet(isPresented: $showTextDump) {
      TextDumpSheet(vm: vm, projectId: vm.showOverview ? nil : vm.selectedProjectId)
    }
    .sheet(isPresented: $showTextDumpResults) {
      TextDumpResultsSheet(vm: vm)
    }
    .onAppear { vm.reloadIfPossible() }
    .onChange(of: vm.textDumps) { _ in
      // Auto-show results when a dump finishes processing
      if !vm.unreviewedCompletedDumps.isEmpty && !showTextDumpResults {
        showTextDumpResults = true
      }
    }
    // Keyboard shortcuts (Task #84248F22)
    .background(
      KeyboardShortcutReceiver(
        onNewTask: { showAddTask = true },
        onRefresh: { vm.reload() },
        onNextTask: { vm.selectNextTask() },
        onPrevTask: { vm.selectPreviousTask() },
        onNextColumn: { vm.selectNextColumn() },
        onPrevColumn: { vm.selectPreviousColumn() },
        onSearch: {
          // ⌘K: open global command palette
          showCommandPalette = true
        },
        onHelp: { withAnimation(.easeInOut(duration: 0.25)) { showHelp = true } },
        onInbox: { withAnimation(.easeInOut(duration: 0.25)) { showInbox = true } },
        onRequestWorker: {
          vm.requestWorker()
          vm.flashSuccess("Worker requested ⚡")
        },
        onOverview: {
          // ⌘⇧O → Overview
          vm.showOverview = true
        },
        onProjectSwitch: { index in
          let projects = vm.sortedActiveProjects
          if index == 0 {
            // ⌘0 → Overview
            vm.showOverview = true
          } else if index <= projects.count {
            vm.selectedProjectId = projects[index - 1].id
            vm.showOverview = false
          }
        },
        onEscape: {
          if showCommandPalette { withAnimation(.easeInOut(duration: 0.25)) { showCommandPalette = false }; return true }
          if showAIUsage { withAnimation(.easeInOut(duration: 0.25)) { showAIUsage = false }; return true }
          if showInbox { withAnimation(.easeInOut(duration: 0.25)) { showInbox = false }; return true }
          if showSettings { showSettings = false; return true }
          if showHelp { withAnimation(.easeInOut(duration: 0.25)) { showHelp = false }; return true }
          if vm.isMultiSelectActive { withAnimation { vm.clearMultiSelect() }; return true }
          return false
        },
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
  var onNextColumn: (() -> Void)? = nil
  var onPrevColumn: (() -> Void)? = nil
  let onSearch: () -> Void
  var onHelp: (() -> Void)? = nil
  var onInbox: (() -> Void)? = nil
  var onRequestWorker: (() -> Void)? = nil
  var onOverview: (() -> Void)? = nil
  var onProjectSwitch: ((Int) -> Void)? = nil
  var onEscape: (() -> Bool)? = nil

  var body: some View {
    Group {
      Button("") { onNewTask() }
        .keyboardShortcut("n", modifiers: .command)
        .opacity(0)

      Button("") { onRefresh() }
        .keyboardShortcut("r", modifiers: .command)
        .opacity(0)

      Button("") { onHelp?() }
        .keyboardShortcut("/", modifiers: .command)
        .opacity(0)

      Button("") { onInbox?() }
        .keyboardShortcut("i", modifiers: .command)
        .opacity(0)

      Button("") { onSearch() }
        .keyboardShortcut("k", modifiers: .command)
        .opacity(0)

      Button("") { onRequestWorker?() }
        .keyboardShortcut("w", modifiers: .command)
        .opacity(0)

      Button("") { onOverview?() }
        .keyboardShortcut("o", modifiers: [.command, .shift])
        .opacity(0)

    }
    .frame(width: 0, height: 0)
    .allowsHitTesting(false)
    #if os(macOS)
    .background(
      ArrowKeyMonitor(onDown: onNextTask, onUp: onPrevTask, onRight: onNextColumn, onLeft: onPrevColumn, onEscape: onEscape, onProjectSwitch: onProjectSwitch)
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
  var onRight: (() -> Void)? = nil
  var onLeft: (() -> Void)? = nil
  var onEscape: (() -> Bool)? = nil
  var onProjectSwitch: ((Int) -> Void)? = nil

  func makeNSView(context: Context) -> NSView {
    let view = NSView()
    context.coordinator.onEscape = onEscape
    context.coordinator.onRight = onRight
    context.coordinator.onLeft = onLeft
    context.coordinator.onProjectSwitch = onProjectSwitch
    context.coordinator.monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
      // Escape key — close overlays first (works even when text fields are focused)
      if event.keyCode == 53 { // escape
        if let handler = context.coordinator.onEscape {
          let handled = handler()
          if handled { return nil }
        }
        return event
      }

      // ⌘0-9 — project switching (works even in text fields)
      if event.modifierFlags.contains(.command),
         let chars = event.charactersIgnoringModifiers,
         let digit = chars.first,
         digit >= "0" && digit <= "9",
         let handler = context.coordinator.onProjectSwitch {
        let index = Int(String(digit))!
        DispatchQueue.main.async { handler(index) }
        return nil
      }

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
      case 38: // j key (vim-style down)
        DispatchQueue.main.async { self.onDown() }
        return nil // consume
      case 40: // k key (vim-style up)
        DispatchQueue.main.async { self.onUp() }
        return nil // consume
      case 124: // right arrow
        if let handler = context.coordinator.onRight {
          DispatchQueue.main.async { handler() }
          return nil
        }
        return event
      case 123: // left arrow
        if let handler = context.coordinator.onLeft {
          DispatchQueue.main.async { handler() }
          return nil
        }
        return event
      default:
        return event
      }
    }
    return view
  }

  func updateNSView(_ nsView: NSView, context: Context) {
    context.coordinator.onEscape = onEscape
    context.coordinator.onRight = onRight
    context.coordinator.onLeft = onLeft
    context.coordinator.onProjectSwitch = onProjectSwitch
  }

  static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
    if let monitor = coordinator.monitor {
      NSEvent.removeMonitor(monitor)
    }
  }

  func makeCoordinator() -> Coordinator { Coordinator() }

  class Coordinator {
    var monitor: Any?
    var onEscape: (() -> Bool)?
    var onRight: (() -> Void)?
    var onLeft: (() -> Void)?
    var onProjectSwitch: ((Int) -> Void)?
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
  @Binding var showHelp: Bool
  @Binding var showTextDump: Bool
  @Binding var showTextDumpResults: Bool
  @Binding var showUpdatePopover: Bool
  @Binding var requestSearchFocus: Bool

  private enum FocusField { case search }
  @FocusState private var focusField: FocusField?

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

      // Update available indicator
      if vm.dashboardUpdateAvailable {
        Button {
          showUpdatePopover.toggle()
          vm.checkForDashboardUpdate(force: true) // Refresh data when opened
        } label: {
          HStack(spacing: 4) {
            Image(systemName: vm.dashboardNeedsRebuild ? "hammer.circle.fill" : "arrow.down.circle.fill")
              .foregroundStyle(vm.dashboardNeedsRebuild ? .blue : .orange)
              .font(.footnote)
            Text(vm.dashboardNeedsRebuild
              ? "\(vm.dashboardCommitsBehind) to rebuild"
              : "\(vm.dashboardCommitsBehind) update\(vm.dashboardCommitsBehind == 1 ? "" : "s")")
              .font(.system(size: 11, weight: .medium))
              .foregroundStyle(vm.dashboardNeedsRebuild ? .blue : .orange)
          }
          .padding(.horizontal, 8)
          .padding(.vertical, 4)
          .background((vm.dashboardNeedsRebuild ? Color.blue : Color.orange).opacity(0.12))
          .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showUpdatePopover, arrowEdge: .bottom) {
          VStack(alignment: .leading, spacing: 8) {
            Text(vm.dashboardNeedsRebuild
              ? "Pulled but not compiled"
              : "New commits on origin/main")
              .font(.system(size: 12, weight: .semibold))
              .foregroundStyle(.secondary)

            if vm.dashboardUpdateCommits.isEmpty {
              Text("Loading…")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
            } else {
              ForEach(vm.dashboardUpdateCommits, id: \.self) { commit in
                HStack(alignment: .top, spacing: 6) {
                  // Short hash (first 7 chars)
                  let parts = commit.split(separator: " ", maxSplits: 1)
                  Text(String(parts.first ?? ""))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                  Text(String(parts.count > 1 ? parts[1] : ""))
                    .font(.system(size: 11))
                    .lineLimit(2)
                }
              }
            }

            Divider()

            if vm.isUpdating {
              HStack(spacing: 8) {
                ProgressView()
                  .scaleEffect(0.8)
                Text("Updating…")
                  .font(.system(size: 11, weight: .medium))
                  .foregroundStyle(.secondary)
                Spacer()
              }

              if !vm.updateLog.isEmpty {
                ScrollView {
                  VStack(alignment: .leading, spacing: 4) {
                    ForEach(vm.updateLog, id: \.self) { line in
                      Text(line)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                  }
                  .padding(.vertical, 4)
                }
                .frame(maxHeight: 120)
              }
            } else {
              if let err = vm.updateError {
                Text(err)
                  .font(.system(size: 11))
                  .foregroundStyle(.red)
              }

              HStack(spacing: 8) {
                Button {
                  vm.performSelfUpdate()
                } label: {
                  HStack(spacing: 6) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                    Text("Update now")
                  }
                  .font(.system(size: 11, weight: .semibold))
                  .padding(.horizontal, 10)
                  .padding(.vertical, 6)
                  .background(Color.accentColor.opacity(0.15))
                  .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)

                Button {
                  vm.checkForDashboardUpdate(force: true)
                } label: {
                  HStack(spacing: 6) {
                    Image(systemName: "arrow.clockwise")
                    Text("Refresh")
                  }
                  .font(.system(size: 11, weight: .semibold))
                  .padding(.horizontal, 10)
                  .padding(.vertical, 6)
                  .background(Theme.subtle)
                  .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
              }

              Text(vm.dashboardNeedsRebuild
                ? "Will rebuild and relaunch this app."
                : "Will pull, rebuild, and relaunch this app.")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
            }
          }
          .padding(12)
          .frame(minWidth: 280, maxWidth: 400)
        }
      }

      Spacer()

      // Search (hidden on home/overview) — placed left of Home so Home doesn't shift
      if !vm.showOverview {
        HStack(spacing: 6) {
          Image(systemName: "magnifyingglass")
            .foregroundStyle(.secondary)
            .font(.footnote)
          TextField("Search tasks…", text: $vm.searchText)
            .textFieldStyle(.plain)
            .focused($focusField, equals: .search)
            .frame(width: 180)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Theme.subtle)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .onChange(of: requestSearchFocus) { shouldFocus in
          guard shouldFocus else { return }
          focusField = .search
          requestSearchFocus = false
        }
      }

      // Filter (hidden on home/overview)
      if !vm.showOverview {
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

        // Shape filter dropdown
        Menu {
          Button {
            vm.shapeFilter = nil
          } label: {
            Label("Any type", systemImage: vm.shapeFilter == nil ? "checkmark" : "")
          }
          Divider()
          ForEach(TaskShape.allCases, id: \.self) { shape in
            Button {
              vm.shapeFilter = vm.shapeFilter == shape ? nil : shape
            } label: {
              Label(
                "\(shapeIcon(shape)) \(shapeLabel(shape))",
                systemImage: vm.shapeFilter == shape ? "checkmark" : ""
              )
            }
          }
        } label: {
          HStack(spacing: 4) {
            Image(systemName: "tag")
            if let shape = vm.shapeFilter {
              Text("\(shapeIcon(shape)) \(shapeLabel(shape))")
                .font(.footnote)
            }
          }
          .padding(.horizontal, 8)
          .padding(.vertical, 5)
          .background(vm.shapeFilter != nil ? Color.accentColor.opacity(0.12) : Theme.subtle)
          .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
      }

      // Home button
      HoverIconButton(icon: "house.fill", tooltip: "Home — Overview", activeBg: vm.showOverview ? Color.accentColor.opacity(0.15) : nil) {
        vm.showOverview = true
      }

      // Project
      Menu {
        ForEach(vm.sortedActiveProjects) { p in
          let activeCount = vm.tasks.filter { $0.projectId == p.id && $0.status == .active }.count
          Button {
            vm.selectedProjectId = p.id
            vm.showOverview = false
          } label: {
            HStack {
              if !vm.showOverview && vm.selectedProjectId == p.id {
                Image(systemName: "checkmark")
              }
              Image(systemName: projectTypeIcon(p.resolvedType))
              Text(p.title)
              if p.syncMode == .github {
                Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                  .foregroundStyle(.blue)
                  .help("Synced with GitHub Issues")
              }
              if activeCount > 0 {
                Text("(\(activeCount))")
                  .foregroundStyle(.secondary)
              }
            }
          }
        }

        Divider()

        // Project management submenu for selected project
        // Only show this when you're actually viewing a project (not on the home/overview screen).
        if !vm.showOverview,
           let selected = vm.projects.first(where: { $0.id == vm.selectedProjectId }),
           selected.id != "default" { 
          Menu("Manage \"\(selected.title)\"") {
            Button {
              editingProject = selected
            } label: {
              Label("Edit…", systemImage: "pencil")
            }

            let sortedActive = vm.sortedActiveProjects
            let currentIndex = sortedActive.firstIndex(where: { $0.id == selected.id })

            Button {
              vm.moveProject(id: selected.id, direction: -1)
            } label: {
              Label("Move Up", systemImage: "arrow.up")
            }
            .disabled(currentIndex == nil || currentIndex == 0)

            Button {
              vm.moveProject(id: selected.id, direction: 1)
            } label: {
              Label("Move Down", systemImage: "arrow.down")
            }
            .disabled(currentIndex == nil || currentIndex == (sortedActive.count - 1))

            Divider()

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
          if vm.showOverview {
            Image(systemName: "folder")
              .foregroundStyle(.secondary)
              .font(.footnote)
            Text("Projects")
              .font(.footnote)
              .foregroundStyle(.secondary)
          } else {
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
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Theme.subtle)
        .clipShape(RoundedRectangle(cornerRadius: 8))
      }
      .menuStyle(.borderlessButton)

      // Inbox button
      InboxToolbarButton(vm: vm) {
        withAnimation(.easeInOut(duration: 0.25)) { showInbox = true }
      }

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

      ToolbarButton(icon: "arrow.clockwise", label: "Refresh / sync", shortcut: "⌘R") {
        vm.reload()
      }

      // Ahead/behind indicator (clickable to push when ahead>0)
      if vm.controlRepoAhead > 0 || vm.controlRepoBehind > 0 {
        Button {
          if vm.controlRepoAhead > 0 {
            vm.pushNow()
          }
        } label: {
          HStack(spacing: 4) {
            if vm.controlRepoAhead > 0 {
              HStack(spacing: 2) {
                Image(systemName: "arrow.up.circle.fill")
                  .foregroundStyle(.orange)
                Text("\(vm.controlRepoAhead)")
                  .font(.system(size: 11, weight: .medium))
                  .foregroundStyle(.orange)
              }
            }
            if vm.controlRepoBehind > 0 {
              HStack(spacing: 2) {
                Image(systemName: "arrow.down.circle.fill")
                  .foregroundStyle(.blue)
                Text("\(vm.controlRepoBehind)")
                  .font(.system(size: 11, weight: .medium))
                  .foregroundStyle(.blue)
              }
            }
          }
          .padding(.horizontal, 8)
          .padding(.vertical, 4)
          .background(vm.controlRepoAhead > 0 ? Color.orange.opacity(0.15) : Color.blue.opacity(0.15))
          .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .disabled(vm.controlRepoAhead == 0)
        .help(vm.controlRepoAhead > 0 ?
              "Click to push \(vm.controlRepoAhead) unpublished commit\(vm.controlRepoAhead == 1 ? "" : "s")" :
              "Behind by \(vm.controlRepoBehind) commit\(vm.controlRepoBehind == 1 ? "" : "s")")
      }

      // Last push status (show prominently)
      if let lastPush = vm.lastSuccessfulPushAt {
        let elapsed = Date().timeIntervalSince(lastPush)
        let timeAgo = elapsed < 60 ? "just now" :
                      elapsed < 3600 ? "\(Int(elapsed/60))m ago" :
                      elapsed < 86400 ? "\(Int(elapsed/3600))h ago" :
                      "\(Int(elapsed/86400))d ago"
        HStack(spacing: 4) {
          Image(systemName: "checkmark.circle.fill")
            .font(.system(size: 10))
            .foregroundStyle(.green)
          Text("Pushed \(timeAgo)")
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(.secondary)
          if let hash = vm.lastPushedCommitHash {
            Text("(\(hash))")
              .font(.system(size: 9, weight: .regular, design: .monospaced))
              .foregroundStyle(.tertiary)
          }
        }
        .help("Last successful push to origin at \(lastPush.formatted(date: .abbreviated, time: .shortened))")
      } else if let error = vm.lastPushError {
        HStack(spacing: 4) {
          Image(systemName: "exclamationmark.triangle.fill")
            .font(.system(size: 10))
            .foregroundStyle(.red)
          Text("Push failed")
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(.red)
          Button {
            vm.pushNow()
          } label: {
            Text("Retry")
              .font(.system(size: 10, weight: .semibold))
              .foregroundStyle(.red)
          }
          .buttonStyle(.plain)
        }
        .help("Push error: \(error)")
      }

      // GitHub sync status (for collaborative projects)
      if vm.selectedProject?.syncMode == .github {
        if vm.isGitHubSyncing {
          HStack(spacing: 4) {
            ProgressView()
              .scaleEffect(0.6)
              .frame(width: 12, height: 12)
            Text("Syncing GitHub…")
              .font(.system(size: 10, weight: .medium))
              .foregroundStyle(.secondary)
          }
          .help("Syncing with GitHub Issues")
        } else if let lastSync = vm.lastGitHubSyncAt {
          let elapsed = Date().timeIntervalSince(lastSync)
          let timeAgo = elapsed < 60 ? "just now" :
                        elapsed < 3600 ? "\(Int(elapsed/60))m ago" :
                        elapsed < 86400 ? "\(Int(elapsed/3600))h ago" :
                        "\(Int(elapsed/86400))d ago"
          HStack(spacing: 4) {
            Image(systemName: "checkmark.circle.fill")
              .font(.system(size: 10))
              .foregroundStyle(.green)
            Text("GitHub \(timeAgo)")
              .font(.system(size: 10, weight: .medium))
              .foregroundStyle(.secondary)
          }
          .help("Last synced with GitHub Issues at \(lastSync.formatted(date: .abbreviated, time: .shortened))")
        } else if let error = vm.lastGitHubSyncError {
          HStack(spacing: 4) {
            Image(systemName: "exclamationmark.triangle.fill")
              .font(.system(size: 10))
              .foregroundStyle(.orange)
            Text("GitHub sync issue")
              .font(.system(size: 10, weight: .medium))
              .foregroundStyle(.orange)
          }
          .help("GitHub sync error: \(error)")
        }

        // Manual sync button for GitHub projects
        Button {
          vm.reload()
        } label: {
          Image(systemName: "arrow.triangle.2.circlepath")
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .disabled(vm.isGitHubSyncing || vm.isGitBusy)
        .help("Sync with GitHub Issues now")
      }

      // Text dump button — paste bulk text for task breakdown
      TextDumpToolbarButton {
        showTextDump = true
      } badgeCount: {
        vm.unreviewedCompletedDumps.count
      } tooltip: {
        vm.unreviewedCompletedDumps.isEmpty ? "Paste Text → Tasks" : "Paste Text → Tasks (\(vm.unreviewedCompletedDumps.count) ready to review)"
      }
      .contextMenu {
        if !vm.unreviewedCompletedDumps.isEmpty {
          Button("Review Processed Results…") {
            showTextDumpResults = true
          }
        }
        Button("View All Text Dumps…") {
          showTextDumpResults = true
        }
      }

      // Help button (⌘/)
      HoverIconButton(icon: "questionmark.circle", tooltip: "Help & Shortcuts (⌘/)") {
        withAnimation(.easeInOut(duration: 0.25)) { showHelp = true }
      }

      // Settings gear (Task #47AC08C2 — repo sync & auto-push in settings popover)
      HoverIconButton(icon: "gearshape", tooltip: "Settings") {
        showSettings.toggle()
      }
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

  @State private var isHovering = false

  var body: some View {
    Button(action: action) {
      Image(systemName: icon)
        .font(.body)
        .padding(6)
        .background(isHovering ? Theme.subtle.opacity(1.5) : Theme.subtle)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
          RoundedRectangle(cornerRadius: 8)
            .stroke(Color.primary.opacity(isHovering ? 0.15 : 0), lineWidth: 1)
        )
        .scaleEffect(isHovering ? 1.05 : 1.0)
        .animation(.easeOut(duration: 0.15), value: isHovering)
    }
    .buttonStyle(.plain)
    .onHover { h in isHovering = h }
    .help("\(label) (\(shortcut))")
  }
}

// MARK: - Hover Icon Button

/// A toolbar icon button with hover highlight and tooltip.
private struct HoverIconButton: View {
  let icon: String
  let tooltip: String
  var activeBg: Color? = nil
  let action: () -> Void

  @State private var isHovering = false

  var body: some View {
    Button(action: action) {
      Image(systemName: icon)
        .font(.body)
        .padding(6)
        .background(activeBg ?? (isHovering ? Color.primary.opacity(0.08) : Theme.subtle))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
          RoundedRectangle(cornerRadius: 8)
            .stroke(Color.primary.opacity(isHovering ? 0.12 : 0), lineWidth: 1)
        )
        .scaleEffect(isHovering ? 1.06 : 1.0)
        .animation(.easeOut(duration: 0.15), value: isHovering)
    }
    .buttonStyle(.plain)
    .onHover { h in isHovering = h }
    .help(tooltip)
  }
}

// MARK: - Text Dump Toolbar Button

private struct TextDumpToolbarButton: View {
  let action: () -> Void
  let badgeCount: () -> Int
  let tooltip: () -> String

  @State private var isHovering = false

  var body: some View {
    let count = badgeCount()
    Button(action: action) {
      Image(systemName: "doc.plaintext")
        .font(.body)
        .padding(6)
        .background(isHovering ? Color.primary.opacity(0.08) : Theme.subtle)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
          RoundedRectangle(cornerRadius: 8)
            .stroke(Color.primary.opacity(isHovering ? 0.12 : 0), lineWidth: 1)
        )
        .overlay(alignment: .topTrailing) {
          if count > 0 {
            Text("\(count)")
              .font(.system(size: 9, weight: .bold))
              .foregroundColor(.white)
              .padding(.horizontal, 4)
              .padding(.vertical, 1)
              .background(Color.orange)
              .clipShape(Capsule())
              .offset(x: 4, y: -4)
          }
        }
        .scaleEffect(isHovering ? 1.06 : 1.0)
        .animation(.easeOut(duration: 0.15), value: isHovering)
    }
    .buttonStyle(.plain)
    .onHover { h in isHovering = h }
    .help(tooltip())
  }
}

// MARK: - Inbox Toolbar Button

private struct InboxToolbarButton: View {
  @ObservedObject var vm: AppViewModel
  let action: () -> Void

  @State private var isHovering = false

  var body: some View {
    Button(action: action) {
      Image(systemName: "tray.full")
        .font(.body)
        .padding(6)
        .background(isHovering ? Color.primary.opacity(0.08) : Theme.subtle)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
          RoundedRectangle(cornerRadius: 8)
            .stroke(Color.primary.opacity(isHovering ? 0.12 : 0), lineWidth: 1)
        )
        .overlay(alignment: .topTrailing) {
          if vm.unreadInboxCount > 0 {
            Text("\(vm.unreadInboxCount)")
              .font(.system(size: 11, weight: .bold))
              .foregroundStyle(.white)
              .padding(.horizontal, 4)
              .padding(.vertical, 1)
              .background(Color.red)
              .clipShape(Capsule())
              .offset(x: 4, y: -4)
          }
        }
        .scaleEffect(isHovering ? 1.06 : 1.0)
        .animation(.easeOut(duration: 0.15), value: isHovering)
    }
    .buttonStyle(.plain)
    .onHover { h in isHovering = h }
    .help("Inbox — Design Docs & Artifacts (⌘I)")
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
            Text("Appearance")
              .font(.footnote)
            Spacer()
            Picker("", selection: $vm.appearanceMode) {
              Text("System").tag(0)
              Text("Light").tag(1)
              Text("Dark").tag(2)
            }
            .pickerStyle(.segmented)
            .frame(width: 180)
          }

          HStack {
            Text("Quick Capture")
              .font(.footnote)
            Spacer()
            Picker("", selection: $vm.quickCaptureHotkeyMode) {
              Text("⌥Space").tag(1)
              Text("⌘⇧Space").tag(0)
            }
            .pickerStyle(.segmented)
            .frame(width: 180)
          }

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

      // Stale data indicator when ahead>0
      if vm.controlRepoAhead > 0 {
        HStack(spacing: 4) {
          Image(systemName: "exclamationmark.triangle.fill")
            .font(.system(size: 10))
            .foregroundStyle(.orange)
          Text("Local only")
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(.orange)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(Color.orange.opacity(0.15))
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .help("Task counts may not reflect remote state. Push to publish changes.")
      }
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

private struct SuccessBanner: View {
  let message: String
  let dismiss: () -> Void

  var body: some View {
    HStack(spacing: 8) {
      Image(systemName: "checkmark.circle.fill")
        .foregroundStyle(.green)
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
    .background(.green.opacity(0.08))
    .clipShape(RoundedRectangle(cornerRadius: 10))
    .overlay(
      RoundedRectangle(cornerRadius: 10)
        .stroke(Color.green.opacity(0.15))
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
    ZStack(alignment: .bottom) {
      VStack(spacing: 0) {
        // Project README (pinned context doc)
        if !vm.projectReadme.isEmpty || vm.selectedProjectId != "default" {
          ProjectReadmeBar(vm: vm)
        }

        GeometryReader { geo in
          let columnCount = CGFloat(vm.columns.count)
          let totalSpacing: CGFloat = 16 * (columnCount - 1) + 40 // inter-column + padding
          let perColumn = max(Theme.columnMinWidth, (geo.size.width - totalSpacing) / columnCount)
          let needsScroll = perColumn <= Theme.columnMinWidth

          ScrollView(needsScroll ? .horizontal : [], showsIndicators: false) {
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
                  quickAddText: $quickAddText,
                  columnWidth: needsScroll ? Theme.columnMinWidth : perColumn
                )
              }
            }
            .padding(20)
            .frame(minHeight: geo.size.height)
          }
        }
      }

      // Bulk action bar — floats at bottom when multi-select is active
      if vm.isMultiSelectActive {
        BulkActionBar(vm: vm)
          .transition(.move(edge: .bottom).combined(with: .opacity))
          .padding(.bottom, 16)
          .zIndex(50)
      }
    }
    .animation(.spring(response: 0.3, dampingFraction: 0.8), value: vm.isMultiSelectActive)
  }
}

// MARK: - Bulk Action Bar

private struct BulkActionBar: View {
  @ObservedObject var vm: AppViewModel

  private var selectedCount: Int { vm.multiSelectedTaskIds.count }

  /// Determine which bulk actions to show based on the statuses of selected tasks.
  private var hasInboxTasks: Bool {
    vm.multiSelectedTaskIds.contains(where: { id in
      vm.tasks.first(where: { $0.id == id })?.status == .inbox
    })
  }
  private var hasActiveTasks: Bool {
    vm.multiSelectedTaskIds.contains(where: { id in
      let t = vm.tasks.first(where: { $0.id == id })
      return t?.status == .active || t?.status == .waitingOn
    })
  }
  private var hasCompletedTasks: Bool {
    vm.multiSelectedTaskIds.contains(where: { id in
      vm.tasks.first(where: { $0.id == id })?.status == .completed
    })
  }

  var body: some View {
    HStack(spacing: 12) {
      // Selection count
      HStack(spacing: 6) {
        Image(systemName: "checkmark.circle.fill")
          .foregroundStyle(Color.accentColor)
        Text("\(selectedCount) selected")
          .font(.callout)
          .fontWeight(.semibold)
      }

      Divider()
        .frame(height: 20)

      // Approve (for inbox tasks)
      if hasInboxTasks {
        BulkActionButton(label: "Approve", icon: "checkmark.seal.fill", color: .green) {
          vm.bulkApproveSelected()
        }
      }

      // Complete (for active tasks)
      if hasActiveTasks {
        BulkActionButton(label: "Complete", icon: "checkmark.circle.fill", color: .green) {
          vm.bulkMoveSelected(to: .completed)
        }
      }

      // Move to Active (for completed/rejected tasks)
      if hasCompletedTasks {
        BulkActionButton(label: "Reopen", icon: "arrow.counterclockwise.circle.fill", color: .blue) {
          vm.bulkMoveSelected(to: .active)
        }
      }

      // Reject
      BulkActionButton(label: "Reject", icon: "xmark.seal.fill", color: .red) {
        vm.bulkRejectSelected()
      }

      Divider()
        .frame(height: 20)

      // Clear selection
      Button {
        withAnimation { vm.clearMultiSelect() }
      } label: {
        HStack(spacing: 4) {
          Image(systemName: "xmark")
            .font(.footnote)
          Text("Clear")
            .font(.footnote)
            .fontWeight(.medium)
        }
        .foregroundStyle(.secondary)
      }
      .buttonStyle(.plain)
    }
    .padding(.horizontal, 20)
    .padding(.vertical, 12)
    .background(
      RoundedRectangle(cornerRadius: 14)
        .fill(.ultraThickMaterial)
        .shadow(color: .black.opacity(0.15), radius: 20, y: 5)
    )
    .overlay(
      RoundedRectangle(cornerRadius: 14)
        .stroke(Color.primary.opacity(0.1), lineWidth: 1)
    )
  }
}

private struct BulkActionButton: View {
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
      .padding(.horizontal, 12)
      .padding(.vertical, 7)
      .background(isHovering ? color.opacity(0.2) : color.opacity(0.12))
      .foregroundStyle(color)
      .clipShape(RoundedRectangle(cornerRadius: 8))
    }
    .buttonStyle(.plain)
    .onHover { h in isHovering = h }
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
  var columnWidth: CGFloat = Theme.columnMinWidth

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
            Button {
              withAnimation(.easeInOut(duration: 0.2)) {
                if isDone { showAllDone = true } else { showAllRejected = true }
              }
            } label: {
              HStack(spacing: 6) {
                Image(systemName: "chevron.down")
                  .font(.system(size: 10))
                Text("See all \(tasks.count) tasks")
                  .font(.footnote)
                  .fontWeight(.medium)
              }
              .foregroundStyle(columnColor)
              .frame(maxWidth: .infinity)
              .padding(.vertical, 8)
              .background(columnColor.opacity(0.08))
              .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
          }

          if (isDone || isRejected) && showAll && tasks.count > vm.completedShowRecent {
            Button {
              withAnimation(.easeInOut(duration: 0.2)) {
                if isDone { showAllDone = false } else { showAllRejected = false }
              }
            } label: {
              HStack(spacing: 6) {
                Image(systemName: "chevron.up")
                  .font(.system(size: 10))
                Text("Show less")
                  .font(.footnote)
                  .fontWeight(.medium)
              }
              .foregroundStyle(.secondary)
              .frame(maxWidth: .infinity)
              .padding(.vertical, 8)
              .background(Theme.subtle)
              .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
          }
        }
        .padding(10)
      }

      // Quick-add inline removed (Task #9168CFAF)
    }
    .frame(width: columnWidth)
    .frame(maxHeight: .infinity)
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
  @State private var isEditingTitle = false
  @State private var inlineTitle = ""

  private var isSelected: Bool { vm.selectedTaskId == task.id }
  private var isMultiSelected: Bool { vm.multiSelectedTaskIds.contains(task.id) }

  /// Staleness: tasks sitting in inbox/active too long get visual attention.
  /// Yellow → orange → red border after 3/7/14 days.
  private var stalenessColor: Color? {
    guard task.status == .inbox || task.status == .active else { return nil }
    let age = Date().timeIntervalSince(task.updatedAt)
    if age > 14 * 86400 { return .red }       // >14 days
    if age > 7 * 86400 { return .orange }     // >7 days
    if age > 3 * 86400 { return .yellow }     // >3 days
    return nil
  }

  private var stalenessLabel: String {
    let age = Date().timeIntervalSince(task.updatedAt)
    let days = Int(age / 86400)
    if days >= 14 { return "Stale (\(days)d)" }
    if days >= 7 { return "Aging (\(days)d)" }
    return "Idle (\(days)d)"
  }

  var body: some View {
    HStack(alignment: .top, spacing: 8) {
      // Multi-select checkbox — visible when multi-select is active or hovering
      if vm.isMultiSelectActive || isHovering {
        Button {
          vm.toggleMultiSelect(taskId: task.id)
        } label: {
          Image(systemName: isMultiSelected ? "checkmark.circle.fill" : "circle")
            .font(.system(size: 16))
            .foregroundStyle(isMultiSelected ? Color.accentColor : .secondary)
        }
        .buttonStyle(.plain)
        .transition(.opacity.combined(with: .scale(scale: 0.8)))
        .padding(.top, 2)
      }

      VStack(alignment: .leading, spacing: 8) {
      if isEditingTitle {
        TextField("Task title", text: $inlineTitle, onCommit: {
          let trimmed = inlineTitle.trimmingCharacters(in: .whitespacesAndNewlines)
          if !trimmed.isEmpty && trimmed != task.title {
            vm.editTask(taskId: task.id, title: trimmed, notes: task.notes ?? "", autoPush: autoPush)
          }
          isEditingTitle = false
        })
        .font(.callout)
        .fontWeight(.medium)
        .textFieldStyle(.plain)
        .onExitCommand { isEditingTitle = false }
      } else {
        HStack(alignment: .top, spacing: 4) {
          Text(task.title)
            .font(.callout)
            .fontWeight(.medium)
            .lineLimit(3)
            .onTapGesture(count: 2) {
              inlineTitle = task.title
              isEditingTitle = true
            }

          // GitHub issue number badge
          if let issueNumber = task.githubIssueNumber {
            Text("#\(issueNumber)")
              .font(.system(size: 9, weight: .medium, design: .monospaced))
              .foregroundStyle(.secondary)
              .padding(.horizontal, 4)
              .padding(.vertical, 2)
              .background(Color.secondary.opacity(0.1))
              .clipShape(RoundedRectangle(cornerRadius: 3))
              .help("GitHub Issue #\(issueNumber)")
          }

          Spacer()
          // Pin/star indicator + toggle
          if task.pinned == true || isHovering {
            Button {
              vm.togglePinTask(taskId: task.id, autoPush: autoPush)
            } label: {
              Image(systemName: task.pinned == true ? "star.fill" : "star")
                .font(.system(size: 12))
                .foregroundStyle(task.pinned == true ? .yellow : .secondary.opacity(0.4))
            }
            .buttonStyle(.plain)
            .help(task.pinned == true ? "Unpin task" : "Pin task to top")
            .transition(.opacity)
          }
        }
      }

      HStack(spacing: 5) {
        MiniTag(text: task.owner.rawValue, color: ownerColor)

        if let shape = task.shape {
          MiniTag(text: "\(shapeIcon(shape)) \(shapeLabel(shape))", color: shapeColor(shape))
        }

        if let ws = task.workState {
          MiniTag(text: workStateLabel(ws), color: workStateColor(ws))
        }

        if let rs = task.reviewState {
          MiniTag(text: reviewStateLabel(rs), color: reviewStateColor(rs))
        }
      }

      // Blocked-by dependency indicator
      if let blockers = task.blockedBy, !blockers.isEmpty {
        HStack(spacing: 4) {
          Image(systemName: "link")
            .font(.system(size: 10))
            .foregroundStyle(.red)
          Text("Blocked by \(blockers.count) task\(blockers.count == 1 ? "" : "s")")
            .font(.system(size: 11))
            .foregroundStyle(.red.opacity(0.8))
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

        if let staleColor = stalenessColor {
          Spacer()
          HStack(spacing: 2) {
            Image(systemName: "exclamationmark.triangle.fill")
              .font(.system(size: 10))
            Text(stalenessLabel)
              .font(.system(size: 10, weight: .medium))
          }
          .foregroundStyle(staleColor)
        }
      }
      } // end inner VStack
    } // end HStack
    .padding(12)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(
      RoundedRectangle(cornerRadius: Theme.cardRadius)
        .fill(isMultiSelected ? Theme.accent.opacity(0.12) : (isSelected ? Theme.accent.opacity(0.08) : Theme.cardBg))
        .shadow(color: .black.opacity(isHovering ? 0.06 : 0.02), radius: isHovering ? 6 : 2, y: 1)
    )
    .overlay(
      RoundedRectangle(cornerRadius: Theme.cardRadius)
        .stroke(
          isMultiSelected ? Theme.accent.opacity(0.6)
            : (isSelected ? Theme.accent.opacity(0.4)
            : (stalenessColor?.opacity(0.4) ?? Theme.border)),
          lineWidth: isMultiSelected ? 2.0 : (isSelected ? 1.5 : (stalenessColor != nil ? 1.0 : 0.5))
        )
    )
    .scaleEffect(isHovering ? 1.01 : 1.0)
    .animation(.easeOut(duration: 0.15), value: isHovering)
    .animation(.easeOut(duration: 0.15), value: isMultiSelected)
    .onHover { h in isHovering = h }
    .onTapGesture {
      // If multi-select is active, toggle selection instead of opening detail
      if vm.isMultiSelectActive {
        vm.toggleMultiSelect(taskId: task.id)
        return
      }
      vm.selectTask(task)
      showDetail = true
    }
    .simultaneousGesture(
      TapGesture().modifiers(.command).onEnded {
        vm.toggleMultiSelect(taskId: task.id)
      }
    )
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

  private enum FocusField { case title }
  @FocusState private var focusField: FocusField?
  @State private var isEditingTitle: Bool = false

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 16) {
        // Header
        VStack(alignment: .leading, spacing: 8) {
          // Don't auto-focus the title field when opening the popover; it steals
          // keyboard navigation (↑/↓) from the board. Enter edit mode explicitly.
          Group {
            if isEditingTitle {
              TextField("Title", text: $editTitle)
                .font(.title3)
                .fontWeight(.bold)
                .textFieldStyle(.plain)
                .focused($focusField, equals: .title)
                .onSubmit {
                  vm.editTask(taskId: task.id, title: editTitle, notes: editNotes, autoPush: autoPush)
                  lastAutosavedTitle = editTitle
                  lastAutosavedNotes = editNotes
                  isEditingTitle = false
                  focusField = nil
                }
                .onChange(of: editTitle) { _ in scheduleAutosave() }
                .onExitCommand {
                  isEditingTitle = false
                  focusField = nil
                }
            } else {
              HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(editTitle)
                  .font(.title3)
                  .fontWeight(.bold)
                  .lineLimit(3)
                  .frame(maxWidth: .infinity, alignment: .leading)
                  .onTapGesture(count: 2) {
                    isEditingTitle = true
                    DispatchQueue.main.async { focusField = .title }
                  }

                Button {
                  isEditingTitle = true
                  DispatchQueue.main.async { focusField = .title }
                } label: {
                  Image(systemName: "pencil")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Edit title")
              }
            }
          }
          .onAppear {
            editTitle = task.title
            editNotes = task.notes ?? ""
            lastAutosavedTitle = editTitle
            lastAutosavedNotes = editNotes
            isEditingTitle = false
            focusField = nil
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
            if let started = task.startedAt {
              let end = task.finishedAt ?? Date()
              let dur = end.timeIntervalSince(started)
              DetailTag(text: formatDuration(dur), icon: "clock", color: .orange)
            }
          }

          // Shape picker
          HStack(spacing: 4) {
            Text("Shape:")
              .font(.system(size: 12))
              .foregroundStyle(.secondary)
            Menu {
              Button {
                vm.setTaskShape(taskId: task.id, shape: nil, autoPush: autoPush)
              } label: {
                Label("None", systemImage: task.shape == nil ? "checkmark" : "")
              }
              Divider()
              ForEach(TaskShape.allCases, id: \.self) { shape in
                Button {
                  vm.setTaskShape(taskId: task.id, shape: shape, autoPush: autoPush)
                } label: {
                  Label("\(shapeIcon(shape)) \(shapeLabel(shape))", systemImage: task.shape == shape ? "checkmark" : "")
                }
              }
            } label: {
              HStack(spacing: 3) {
                if let shape = task.shape {
                  Text("\(shapeIcon(shape)) \(shapeLabel(shape))")
                    .font(.system(size: 11, weight: .medium))
                } else {
                  Text("Set shape…")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                }
              }
              .padding(.horizontal, 8)
              .padding(.vertical, 3)
              .background(Theme.subtle)
              .clipShape(Capsule())
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
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
              // Full markdown preview with support for headers, lists, code blocks, etc.
              if editNotes.isEmpty {
                Text("No notes")
                  .font(.footnote)
                  .foregroundStyle(.tertiary)
                  .frame(maxWidth: .infinity, alignment: .leading)
                  .frame(minHeight: 80)
                  .padding(8)
                  .background(Theme.subtle)
                  .clipShape(RoundedRectangle(cornerRadius: 8))
              } else {
                ScrollView {
                  SelfSizingMarkdownView(markdown: editNotes, minHeight: 60)
                    .padding(8)
                }
                .frame(minHeight: 80, maxHeight: 300)
                .background(Theme.subtle)
                .clipShape(RoundedRectangle(cornerRadius: 8))
              }
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

        // Dependencies section
        DependencySection(task: task, vm: vm, autoPush: $autoPush)

        Divider()

        // Context-aware actions based on task status
        VStack(alignment: .leading, spacing: 10) {
          HStack {
            Text("Actions")
              .font(.callout)
              .fontWeight(.bold)
            Spacer()
            Button {
              vm.togglePinTask(taskId: task.id, autoPush: autoPush)
            } label: {
              HStack(spacing: 4) {
                Image(systemName: task.pinned == true ? "star.fill" : "star")
                  .font(.footnote)
                Text(task.pinned == true ? "Unpin" : "Pin")
                  .font(.footnote)
                  .fontWeight(.medium)
              }
              .padding(.horizontal, 10)
              .padding(.vertical, 5)
              .background((task.pinned == true ? Color.yellow : Color.secondary).opacity(0.12))
              .foregroundStyle(task.pinned == true ? .yellow : .secondary)
              .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
          }

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

          case .active, .waitingOn:
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

// MARK: - Task Shape Helpers

private func shapeIcon(_ shape: TaskShape) -> String {
  switch shape {
  case .deep: return "🧠"
  case .shallow: return "⚡"
  case .creative: return "🎨"
  case .waiting: return "⏳"
  case .admin: return "📋"
  }
}

private func shapeLabel(_ shape: TaskShape) -> String {
  switch shape {
  case .deep: return "Deep"
  case .shallow: return "Quick"
  case .creative: return "Creative"
  case .waiting: return "Waiting"
  case .admin: return "Admin"
  }
}

private func shapeColor(_ shape: TaskShape) -> Color {
  switch shape {
  case .deep: return .purple
  case .shallow: return .green
  case .creative: return .orange
  case .waiting: return .yellow
  case .admin: return .blue
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
  if seconds < 0 { return "just now" } // future date — treat as now
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

// MARK: - Shake Effect (validation feedback)

private struct ShakeEffect: ViewModifier {
  var shaking: Bool

  func body(content: Content) -> some View {
    content
      .offset(x: shaking ? -6 : 0)
      .animation(
        shaking
          ? .interpolatingSpring(stiffness: 300, damping: 8).speed(2)
          : .default,
        value: shaking
      )
  }
}

// MARK: - Dependency Section (Task Detail)

private struct DependencySection: View {
  let task: DashboardTask
  @ObservedObject var vm: AppViewModel
  @Binding var autoPush: Bool
  @State private var showBlockerPicker = false

  private var blockerTasks: [DashboardTask] {
    guard let blockerIds = task.blockedBy else { return [] }
    return blockerIds.compactMap { id in
      vm.tasks.first(where: { $0.id == id })
    }
  }

  /// Tasks that could be added as blockers (same project, not self, not already blocking).
  private var availableBlockers: [DashboardTask] {
    let existingBlockers = Set(task.blockedBy ?? [])
    return vm.tasks.filter { t in
      t.id != task.id
      && !existingBlockers.contains(t.id)
      && (t.projectId ?? "default") == (task.projectId ?? "default")
      && t.status != .completed
      && t.status != .rejected
    }
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Label("Dependencies", systemImage: "link")
          .font(.callout)
          .fontWeight(.bold)
        Spacer()
        Button {
          showBlockerPicker = true
        } label: {
          Image(systemName: "plus.circle")
            .font(.footnote)
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showBlockerPicker) {
          BlockerPickerPopover(
            availableBlockers: availableBlockers,
            onSelect: { blockerTaskId in
              vm.addBlocker(taskId: task.id, blockerTaskId: blockerTaskId, autoPush: autoPush)
              showBlockerPicker = false
            }
          )
        }
      }

      if blockerTasks.isEmpty {
        Text("No dependencies")
          .font(.footnote)
          .foregroundStyle(.tertiary)
      } else {
        ForEach(blockerTasks) { blocker in
          HStack(spacing: 6) {
            Circle()
              .fill(blocker.status == .completed ? Color.green : Color.red)
              .frame(width: 6, height: 6)
            Text(blocker.title)
              .font(.footnote)
              .lineLimit(1)
              .strikethrough(blocker.status == .completed)
              .foregroundStyle(blocker.status == .completed ? .secondary : .primary)
            Spacer()
            Button {
              vm.removeBlocker(taskId: task.id, blockerTaskId: blocker.id, autoPush: autoPush)
            } label: {
              Image(systemName: "xmark.circle")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
          }
        }
      }
    }
  }
}

private struct BlockerPickerPopover: View {
  let availableBlockers: [DashboardTask]
  let onSelect: (String) -> Void
  @State private var searchText = ""

  private var filtered: [DashboardTask] {
    let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    if q.isEmpty { return availableBlockers }
    return availableBlockers.filter { $0.title.lowercased().contains(q) }
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Add Blocker")
        .font(.callout)
        .fontWeight(.bold)

      TextField("Search tasks…", text: $searchText)
        .textFieldStyle(.roundedBorder)
        .font(.footnote)

      ScrollView {
        LazyVStack(alignment: .leading, spacing: 4) {
          ForEach(filtered) { task in
            Button {
              onSelect(task.id)
            } label: {
              HStack(spacing: 6) {
                Image(systemName: "circle")
                  .font(.system(size: 10))
                  .foregroundStyle(.secondary)
                Text(task.title)
                  .font(.footnote)
                  .lineLimit(2)
                  .foregroundStyle(.primary)
                Spacer()
              }
              .padding(.vertical, 4)
              .padding(.horizontal, 6)
              .background(Color.primary.opacity(0.04))
              .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
          }

          if filtered.isEmpty {
            Text("No matching tasks")
              .font(.footnote)
              .foregroundStyle(.tertiary)
          }
        }
      }
      .frame(maxHeight: 200)
    }
    .padding(12)
    .frame(width: 280)
  }
}

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

struct CreateProjectSheet: View {
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
            ? "Track tasks through columns: Active, Done."
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
  @State private var syncMode: SyncMode = .local
  @State private var ghOwner: String = ""
  @State private var ghRepo: String = ""
  @State private var ghToken: String = ""
  @State private var ghLabels: String = ""

  var body: some View {
    ScrollView {
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

        Divider()

        // Sync mode configuration
        VStack(alignment: .leading, spacing: 12) {
          Text("Sync Mode")
            .font(.headline)

          Picker("", selection: $syncMode) {
            Text("Local (Personal)").tag(SyncMode.local)
            Text("GitHub (Collaborative)").tag(SyncMode.github)
          }
          .pickerStyle(.segmented)

          if syncMode == .local {
            Text("Tasks stored locally in JSON files")
              .font(.caption)
              .foregroundStyle(.secondary)
          } else {
            Text("Tasks synced with GitHub Issues")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
        }

        // GitHub configuration (only shown when GitHub mode selected)
        if syncMode == .github {
          Divider()

          VStack(alignment: .leading, spacing: 12) {
            Text("GitHub Configuration")
              .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
              Text("Repository Owner")
                .font(.caption)
                .foregroundStyle(.secondary)
              TextField("e.g., RafeSymonds", text: $ghOwner)
                .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 8) {
              Text("Repository Name")
                .font(.caption)
                .foregroundStyle(.secondary)
              TextField("e.g., my-project", text: $ghRepo)
                .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 8) {
              HStack {
                Text("Access Token")
                  .font(.caption)
                  .foregroundStyle(.secondary)
                Spacer()
                Button {
                  if let url = URL(string: "https://github.com/settings/tokens/new?description=Lobs%20Dashboard&scopes=repo") {
                    #if os(macOS)
                    NSWorkspace.shared.open(url)
                    #endif
                  }
                } label: {
                  HStack(spacing: 4) {
                    Image(systemName: "link")
                    Text("Create token")
                  }
                  .font(.caption2)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.blue)
              }
              SecureField("GitHub Personal Access Token", text: $ghToken)
                .textFieldStyle(.roundedBorder)
              Text("Requires 'repo' scope. Keep this secure!")
                .font(.caption2)
                .foregroundStyle(.orange)
            }

            VStack(alignment: .leading, spacing: 8) {
              Text("Labels (Optional)")
                .font(.caption)
                .foregroundStyle(.secondary)
              TextField("e.g., lobs, dashboard", text: $ghLabels)
                .textFieldStyle(.roundedBorder)
              Text("Comma-separated labels to add to all issues")
                .font(.caption2)
                .foregroundStyle(.secondary)
            }

            // Validation warning
            if ghOwner.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || ghRepo.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
              HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                  .foregroundStyle(.orange)
                Text("Owner and repository are required for GitHub mode")
                  .font(.caption)
                  .foregroundStyle(.secondary)
              }
              .padding(.top, 4)
            }
          }
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

            // Update sync mode and GitHub config
            vm.updateProjectSyncMode(id: project.id, syncMode: syncMode, githubConfig: syncMode == .github ? GitHubConfig(
              owner: ghOwner.trimmingCharacters(in: .whitespacesAndNewlines),
              repo: ghRepo.trimmingCharacters(in: .whitespacesAndNewlines),
              accessToken: ghToken.isEmpty ? nil : ghToken,
              syncLabels: ghLabels.isEmpty ? nil : ghLabels.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            ) : nil)

            dismiss()
          }
          .keyboardShortcut(.defaultAction)
          .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || (syncMode == .github && (ghOwner.isEmpty || ghRepo.isEmpty)))
        }
      }
      .padding(20)
    }
    .frame(width: 480, height: 600)
    .onAppear {
      title = project.title
      notes = project.notes ?? ""
      syncMode = project.syncMode ?? .local
      if let config = project.githubConfig {
        ghOwner = config.owner
        ghRepo = config.repo
        ghToken = config.accessToken ?? ""
        ghLabels = config.syncLabels?.joined(separator: ", ") ?? ""
      }
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
  @State private var shakeTitle: Bool = false
  @State private var shakeProject: Bool = false

  private var activeProjects: [Project] {
    vm.sortedActiveProjects
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
          .padding(4)
          .background(
            RoundedRectangle(cornerRadius: 6)
              .stroke(shakeProject ? Color.red : Color.clear, lineWidth: 2)
          )
          .modifier(ShakeEffect(shaking: shakeProject))
        }
      }

      VStack(alignment: .leading, spacing: 8) {
        Text("Title")
          .font(.callout)
          .fontWeight(.medium)
        TextField("What needs to be done?", text: $title)
          .textFieldStyle(.roundedBorder)
          .font(.body)
          .overlay(
            RoundedRectangle(cornerRadius: 6)
              .stroke(shakeTitle ? Color.red : Color.clear, lineWidth: 2)
          )
          .modifier(ShakeEffect(shaking: shakeTitle))
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
            let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
            let missingTitle = trimmedTitle.isEmpty
            let missingProject = selectedProjectId.isEmpty

            if missingTitle || missingProject {
              withAnimation(.default) {
                if missingProject { shakeProject = true }
                if missingTitle { shakeTitle = true }
              }
              DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                withAnimation { shakeProject = false; shakeTitle = false }
              }
              return
            }

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
          let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
          let missingTitle = trimmedTitle.isEmpty
          let missingProject = selectedProjectId.isEmpty

          if missingTitle || missingProject {
            // Shake the missing fields to draw attention
            withAnimation(.default) {
              if missingProject { shakeProject = true }
              if missingTitle { shakeTitle = true }
            }
            // Reset after animation
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
              withAnimation { shakeProject = false; shakeTitle = false }
            }
            return
          }

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
        .buttonStyle(.borderedProminent)
        // Keep the visual "disabled" affordance, but allow clicks so we can
        // shake/highlight missing fields instead of silently ignoring the tap.
        .opacity((title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || (shouldShowProjectPicker && selectedProjectId.isEmpty)) ? 0.55 : 1.0)
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

// MARK: - Command Palette (⌘K)

/// Global fuzzy-finder that searches tasks across ALL projects.
/// Selecting a result switches to that project and selects the task.
private struct CommandPaletteView: View {
  @ObservedObject var vm: AppViewModel
  @Binding var isPresented: Bool
  @State private var query: String = ""
  @State private var selectedIndex: Int = 0
  @FocusState private var searchFocused: Bool

  private var results: [(task: DashboardTask, project: Project?)] {
    let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    let allTasks = vm.tasks
    let filtered: [DashboardTask]
    if q.isEmpty {
      // Show active tasks across all projects when no query
      filtered = Array(allTasks.filter { $0.status == .active }.prefix(20))
    } else {
      filtered = allTasks.filter { task in
        task.title.lowercased().contains(q)
          || (task.notes ?? "").lowercased().contains(q)
          || task.id.lowercased().hasPrefix(q)
      }
    }
    return filtered.map { task in
      let project = vm.projects.first(where: { $0.id == task.projectId })
      return (task: task, project: project)
    }
  }

  private func selectResult(_ result: (task: DashboardTask, project: Project?)) {
    vm.selectedProjectId = result.task.projectId ?? "default"
    vm.showOverview = false
    vm.selectedTaskId = result.task.id
    vm.popoverTaskId = result.task.id
    withAnimation(.easeInOut(duration: 0.25)) { isPresented = false }
  }

  var body: some View {
    VStack(spacing: 0) {
      // Search bar
      HStack(spacing: 10) {
        Image(systemName: "magnifyingglass")
          .font(.title3)
          .foregroundStyle(.secondary)

        TextField("Search all tasks…", text: $query)
          .focused($searchFocused)
          .textFieldStyle(.plain)
          .font(.title3)
          .onSubmit {
            if !results.isEmpty && selectedIndex < results.count {
              selectResult(results[selectedIndex])
            }
          }

        if !query.isEmpty {
          Button {
            query = ""
          } label: {
            Image(systemName: "xmark.circle.fill")
              .foregroundStyle(.tertiary)
          }
          .buttonStyle(.plain)
        }

        Text("esc")
          .font(.system(size: 11, weight: .medium))
          .foregroundStyle(.tertiary)
          .padding(.horizontal, 6)
          .padding(.vertical, 3)
          .background(Theme.subtle)
          .clipShape(RoundedRectangle(cornerRadius: 4))
      }
      .padding(.horizontal, 16)
      .padding(.vertical, 14)

      Divider()

      // Results
      if results.isEmpty {
        VStack(spacing: 10) {
          Spacer()
          Image(systemName: "magnifyingglass")
            .font(.system(size: 28))
            .foregroundStyle(.quaternary)
          Text(query.isEmpty ? "Start typing to search…" : "No tasks found")
            .font(.callout)
            .foregroundStyle(.tertiary)
          Spacer()
        }
        .frame(maxWidth: .infinity)
      } else {
        ScrollViewReader { proxy in
          ScrollView {
            LazyVStack(spacing: 2) {
              ForEach(Array(results.enumerated()), id: \.element.task.id) { index, result in
                CommandPaletteRow(
                  task: result.task,
                  projectName: result.project?.title ?? "Default",
                  isSelected: index == selectedIndex
                )
                .id(index)
                .onTapGesture {
                  selectResult(result)
                }
              }
            }
            .padding(6)
          }
          .onChange(of: selectedIndex) { idx in
            // Avoid scroll lag when moving selection quickly via arrow keys.
            var tx = Transaction()
            tx.disablesAnimations = true
            withTransaction(tx) {
              proxy.scrollTo(idx, anchor: .center)
            }
          }
        }
      }
    }
    .background(Theme.bg)
    .background(
      CommandPaletteKeyHandler(
        onUp: {
          if selectedIndex > 0 { selectedIndex -= 1 }
        },
        onDown: {
          if selectedIndex < results.count - 1 { selectedIndex += 1 }
        }
      )
    )
    .onChange(of: query) { _ in
      selectedIndex = 0
    }
    .onAppear {
      // Ensure typing goes straight into the search field.
      DispatchQueue.main.async { searchFocused = true }
    }
  }
}

private struct CommandPaletteRow: View {
  let task: DashboardTask
  let projectName: String
  let isSelected: Bool

  @State private var isHovering = false

  private var statusColor: Color {
    switch task.status {
    case .active: return .blue
    case .completed: return .green
    case .rejected: return .red
    case .waitingOn: return .orange
    default: return .secondary
    }
  }

  var body: some View {
    HStack(spacing: 10) {
      Circle()
        .fill(statusColor)
        .frame(width: 8, height: 8)

      VStack(alignment: .leading, spacing: 2) {
        Text(task.title)
          .font(.callout)
          .fontWeight(isSelected ? .semibold : .regular)
          .lineLimit(1)

        HStack(spacing: 6) {
          Text(projectName)
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
          Text("·")
            .foregroundStyle(.quaternary)
          Text(task.status.rawValue)
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
        }
      }

      Spacer()

      Text(task.id.prefix(8))
        .font(.system(size: 10, design: .monospaced))
        .foregroundStyle(.quaternary)
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 8)
    .background(
      RoundedRectangle(cornerRadius: 8)
        .fill(isSelected ? Color.accentColor.opacity(0.12) : (isHovering ? Theme.subtle : Color.clear))
    )
    .onHover { h in isHovering = h }
  }
}

/// Arrow key handler for the command palette.
private struct CommandPaletteKeyHandler: NSViewRepresentable {
  let onUp: () -> Void
  let onDown: () -> Void

  func makeNSView(context: Context) -> NSView {
    let view = NSView()
    context.coordinator.monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
      switch event.keyCode {
      case 125: // down arrow
        DispatchQueue.main.async { self.onDown() }
        return nil
      case 126: // up arrow
        DispatchQueue.main.async { self.onUp() }
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
  class Coordinator { var monitor: Any? }
}

// MARK: - Help Panel

private struct HelpPanelSheet: View {
  @Binding var isPresented: Bool
  @Environment(\.dismiss) private var dismiss

  private struct ShortcutRow: View {
    let keys: String
    let description: String

    var body: some View {
      HStack {
        Text(keys)
          .font(.system(size: 13, design: .monospaced))
          .padding(.horizontal, 8)
          .padding(.vertical, 3)
          .background(Color.primary.opacity(0.08))
          .clipShape(RoundedRectangle(cornerRadius: 5))
        Spacer()
        Text(description)
          .font(.system(size: 13))
          .foregroundStyle(.secondary)
      }
    }
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      // Header
      HStack {
        Image(systemName: "questionmark.circle.fill")
          .font(.title2)
          .foregroundStyle(.blue)
        Text("Help & Shortcuts")
          .font(.title2)
          .fontWeight(.bold)
        Spacer()
        Button { withAnimation(.easeInOut(duration: 0.25)) { isPresented = false } } label: {
          Image(systemName: "xmark.circle.fill")
            .font(.title3)
            .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
      }
      .padding(20)

      Divider()

      ScrollView {
        VStack(alignment: .leading, spacing: 24) {
          // Keyboard Shortcuts
          VStack(alignment: .leading, spacing: 12) {
            Label("Keyboard Shortcuts", systemImage: "keyboard")
              .font(.headline)

            VStack(spacing: 8) {
              ShortcutRow(keys: "⌘ K", description: "Global fuzzy-finder")
              ShortcutRow(keys: "⌘ N", description: "Create new task")
              ShortcutRow(keys: "⌘ R", description: "Refresh / sync with git")
              ShortcutRow(keys: "⌘ W", description: "Request worker")
              ShortcutRow(keys: "⌘ /", description: "Show this help panel")
              ShortcutRow(keys: "↑ ↓", description: "Navigate between tasks")
              ShortcutRow(keys: "Esc", description: "Close overlays / deselect")
            }
          }

          Divider()

          // Board Overview
          VStack(alignment: .leading, spacing: 12) {
            Label("Kanban Board", systemImage: "square.grid.3x3.topleft.filled")
              .font(.headline)

            VStack(alignment: .leading, spacing: 6) {
              Text("• **Drag tasks** between columns to change status")
              Text("• **Click a task** to view details and edit notes")
              Text("• **Drag within a column** to reorder tasks")
              Text("• Tasks flow: **Inbox → Active → Done**")
              Text("• Use the **quick-add bar** at the top of Active to add tasks fast")
            }
            .font(.system(size: 13))
            .foregroundStyle(.secondary)
          }

          Divider()

          // Project Types
          VStack(alignment: .leading, spacing: 12) {
            Label("Project Types", systemImage: "folder")
              .font(.headline)

            VStack(alignment: .leading, spacing: 6) {
              HStack(alignment: .top, spacing: 8) {
                Image(systemName: "square.grid.3x3.topleft.filled")
                  .foregroundStyle(.blue)
                  .frame(width: 20)
                VStack(alignment: .leading) {
                  Text("Kanban").fontWeight(.medium)
                  Text("Task board with columns for workflow stages.")
                    .foregroundStyle(.secondary)
                }
              }
              HStack(alignment: .top, spacing: 8) {
                Image(systemName: "doc.text.magnifyingglass")
                  .foregroundStyle(.green)
                  .frame(width: 20)
                VStack(alignment: .leading) {
                  Text("Research").fontWeight(.medium)
                  Text("Tile-based workspace for notes, links, findings, and comparisons.")
                    .foregroundStyle(.secondary)
                }
              }
              HStack(alignment: .top, spacing: 8) {
                Image(systemName: "checklist")
                  .foregroundStyle(.orange)
                  .frame(width: 20)
                VStack(alignment: .leading) {
                  Text("Tracker").fontWeight(.medium)
                  Text("Checklist-style tracker for progress on items.")
                    .foregroundStyle(.secondary)
                }
              }
            }
            .font(.system(size: 13))
          }

          Divider()

          // Features
          VStack(alignment: .leading, spacing: 12) {
            Label("Features", systemImage: "sparkles")
              .font(.headline)

            VStack(alignment: .leading, spacing: 6) {
              Text("• **README** — Each project has a pinned README for context. Click to expand/edit.")
              Text("• **Inbox** — Review design docs and artifacts from Lobs. Threaded conversations supported.")
              Text("• **Templates** — Create task templates to quickly add groups of related tasks.")
              Text("• **Project Management** — Reorder, archive, or delete projects from the project menu.")
              Text("• **Auto-refresh** — Dashboard syncs with git automatically (configurable in settings).")
              Text("• **Worker Status** — See if Lobs is currently working on tasks (shown in stats bar).")
            }
            .font(.system(size: 13))
            .foregroundStyle(.secondary)
          }

          Divider()

          // Git Sync
          VStack(alignment: .leading, spacing: 12) {
            Label("How It Works", systemImage: "arrow.triangle.2.circlepath")
              .font(.headline)

            VStack(alignment: .leading, spacing: 6) {
              Text("Lobs Dashboard syncs state through a shared git repository (**lobs-control**). All tasks, projects, and research are stored as JSON files.")
              Text("")
              Text("• **You** create tasks and requests through the dashboard")
              Text("• **Lobs** (the AI worker) picks up tasks, does the work, and updates status")
              Text("• Everything stays in sync via git — pull to see updates, push to share changes")
            }
            .font(.system(size: 13))
            .foregroundStyle(.secondary)
          }
        }
        .padding(20)
      }
    }
    .frame(width: 500, height: 600)
    .background(Theme.boardBg)
  }
}

// MARK: - Text Dump Sheet

private struct TextDumpSheet: View {
  @ObservedObject var vm: AppViewModel
  /// When nil, the user must choose a project (invoked from home screen).
  let projectId: String?
  @Environment(\.dismiss) private var dismiss

  @State private var text: String = ""
  @State private var selectedProjectId: String = ""
  @State private var shakeProject: Bool = false

  private var shouldShowPicker: Bool { projectId == nil }
  private var resolvedProjectId: String { projectId ?? selectedProjectId }

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      HStack {
        Image(systemName: "doc.plaintext.fill")
          .font(.title2)
          .foregroundStyle(.linearGradient(
            colors: [.orange, .red],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
          ))
        VStack(alignment: .leading, spacing: 2) {
          Text("Paste Text → Tasks")
            .font(.title3)
            .fontWeight(.bold)
          Text("Paste feedback, requirements, or any text. Lobs will break it down into individual tasks on the next run.")
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
        Spacer()
      }

      // Project picker or static label
      if shouldShowPicker {
        VStack(alignment: .leading, spacing: 6) {
          Text("Project")
            .font(.callout)
            .fontWeight(.medium)
          Picker("Project", selection: $selectedProjectId) {
            Text("Choose a project")
              .tag("")
            ForEach(vm.sortedActiveProjects) { project in
              HStack(spacing: 6) {
                Image(systemName: project.resolvedType == .research ? "doc.text.magnifyingglass" : "rectangle.split.3x1")
                Text(project.title)
              }
              .tag(project.id)
            }
          }
          .labelsHidden()
          .padding(4)
          .background(
            RoundedRectangle(cornerRadius: 6)
              .stroke(shakeProject ? Color.red : Color.clear, lineWidth: 2)
          )
          .modifier(ShakeEffect(shaking: shakeProject))
        }
      } else {
        HStack(spacing: 6) {
          Text("Project:")
            .font(.footnote)
            .foregroundStyle(.secondary)
          Text(vm.projects.first(where: { $0.id == resolvedProjectId })?.title ?? resolvedProjectId)
            .font(.footnote)
            .fontWeight(.medium)
        }
      }

      TextEditor(text: $text)
        .font(.system(size: 13))
        .frame(minHeight: 200, maxHeight: 400)
        .overlay(
          Group {
            if text.isEmpty {
              Text("Paste user feedback, feature requests, bug reports, or any text here…")
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

        let wordCount = text.split(separator: " ").count
        if wordCount > 0 {
          Text("\(wordCount) words")
            .font(.footnote)
            .foregroundStyle(.tertiary)
        }

        Button("Submit") {
          if shouldShowPicker && selectedProjectId.isEmpty {
            withAnimation(.default) { shakeProject = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
              withAnimation { shakeProject = false }
            }
            return
          }
          vm.submitTextDump(text: text, projectId: resolvedProjectId)
          dismiss()
        }
        .keyboardShortcut(.defaultAction)
        .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
      }
    }
    .padding(20)
    .frame(width: 520)
  }
}

// MARK: - Text Dump Results Sheet

private struct TextDumpResultsSheet: View {
  @ObservedObject var vm: AppViewModel
  @Environment(\.dismiss) private var dismiss

  @State private var expandedDumpId: String? = nil
  @State private var editingTaskId: String? = nil
  @State private var editTitle: String = ""
  @State private var editNotes: String = ""

  private var completedDumps: [TextDump] {
    vm.textDumps.filter { $0.status == .completed }
  }

  private var pendingDumps: [TextDump] {
    vm.textDumps.filter { $0.status == .pending || $0.status == .processing }
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      // Header
      HStack {
        Image(systemName: "doc.plaintext.fill")
          .font(.title2)
          .foregroundStyle(.linearGradient(
            colors: [.orange, .red],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
          ))
        VStack(alignment: .leading, spacing: 2) {
          Text("Text → Tasks Results")
            .font(.title3)
            .fontWeight(.bold)
          Text("Review and edit tasks created from your text dumps.")
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
        Spacer()
        Button("Done") { dismiss() }
          .keyboardShortcut(.cancelAction)
      }
      .padding(20)

      Divider()

      ScrollView {
        VStack(alignment: .leading, spacing: 16) {
          // Pending dumps
          if !pendingDumps.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
              Label("Processing", systemImage: "clock")
                .font(.headline)
                .foregroundStyle(.secondary)
              ForEach(pendingDumps) { dump in
                HStack(spacing: 8) {
                  ProgressView()
                    .scaleEffect(0.7)
                  Text(dump.text.prefix(80) + (dump.text.count > 80 ? "…" : ""))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                  Spacer()
                  Text(projectName(dump.projectId))
                    .font(.caption)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Theme.subtle)
                    .clipShape(Capsule())
                }
                .padding(10)
                .background(Theme.subtle.opacity(0.5))
                .clipShape(RoundedRectangle(cornerRadius: 8))
              }
            }
          }

          // Completed dumps
          if completedDumps.isEmpty && pendingDumps.isEmpty {
            VStack(spacing: 12) {
              Image(systemName: "tray")
                .font(.largeTitle)
                .foregroundStyle(.tertiary)
              Text("No text dumps yet.")
                .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 40)
          }

          ForEach(completedDumps) { dump in
            completedDumpRow(dump)
          }
        }
        .padding(20)
      }
    }
    .frame(minWidth: 680, maxWidth: 680, minHeight: 400, maxHeight: 700)
    .onAppear {
      // Auto-expand the first unreviewed dump
      if let first = vm.unreviewedCompletedDumps.first {
        expandedDumpId = first.id
      }
    }
  }

  @ViewBuilder
  private func completedDumpRow(_ dump: TextDump) -> some View {
    let isExpanded = expandedDumpId == dump.id
    let isUnreviewed = !vm.reviewedDumpIds.contains(dump.id)
    let createdTasks = vm.tasksForDump(dump)

    VStack(alignment: .leading, spacing: 0) {
      // Dump header — clickable to expand/collapse
      Button {
        withAnimation(.easeInOut(duration: 0.2)) {
          expandedDumpId = isExpanded ? nil : dump.id
        }
      } label: {
        HStack(spacing: 10) {
          Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
            .font(.caption)
            .foregroundStyle(.tertiary)
            .frame(width: 12)

          if isUnreviewed {
            Circle()
              .fill(.orange)
              .frame(width: 8, height: 8)
          }

          VStack(alignment: .leading, spacing: 2) {
            Text(dump.text.prefix(100) + (dump.text.count > 100 ? "…" : ""))
              .font(.callout)
              .fontWeight(isUnreviewed ? .semibold : .regular)
              .lineLimit(1)
              .foregroundColor(.primary)
            HStack(spacing: 8) {
              Text(projectName(dump.projectId))
                .font(.caption)
                .padding(.horizontal, 6)
                .padding(.vertical, 1)
                .background(Theme.subtle)
                .clipShape(Capsule())
              Text("\(createdTasks.count) task\(createdTasks.count == 1 ? "" : "s") created")
                .font(.caption)
                .foregroundStyle(.secondary)
              Text(dump.updatedAt, style: .relative)
                .font(.caption2)
                .foregroundStyle(.tertiary)
            }
          }

          Spacer()

          if isUnreviewed {
            Button("Mark Reviewed") {
              vm.markDumpReviewed(dump.id)
            }
            .font(.caption)
            .buttonStyle(.bordered)
            .tint(.orange)
          } else {
            Image(systemName: "checkmark.circle.fill")
              .foregroundStyle(.green)
              .font(.callout)
          }
        }
        .padding(12)
      }
      .buttonStyle(.plain)

      // Expanded: show created tasks
      if isExpanded {
        Divider()
          .padding(.horizontal, 12)

        VStack(alignment: .leading, spacing: 1) {
          ForEach(createdTasks) { task in
            if editingTaskId == task.id {
              taskEditRow(task: task, dump: dump)
            } else {
              taskDisplayRow(task: task)
            }
          }

          if createdTasks.isEmpty {
            Text("No tasks found (they may have been deleted or archived).")
              .font(.caption)
              .foregroundStyle(.tertiary)
              .padding(12)
          }
        }
        .padding(.bottom, 8)

        // Original text (collapsed by default)
        DisclosureGroup("Original Text") {
          Text(dump.text)
            .font(.system(size: 11, design: .monospaced))
            .foregroundStyle(.secondary)
            .textSelection(.enabled)
            .padding(8)
            .background(Theme.subtle.opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.bottom, 12)

        // Mark reviewed at bottom if expanded
        if isUnreviewed {
          HStack {
            Spacer()
            Button {
              vm.markDumpReviewed(dump.id)
            } label: {
              Label("Mark as Reviewed", systemImage: "checkmark.circle")
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)
            .controlSize(.small)
          }
          .padding(.horizontal, 12)
          .padding(.bottom, 12)
        }
      }
    }
    .background(isUnreviewed ? Color.orange.opacity(0.04) : Color.clear)
    .clipShape(RoundedRectangle(cornerRadius: 10))
    .overlay(
      RoundedRectangle(cornerRadius: 10)
        .stroke(isUnreviewed ? Color.orange.opacity(0.2) : Color.primary.opacity(0.06), lineWidth: 1)
    )
  }

  @ViewBuilder
  private func taskDisplayRow(task: DashboardTask) -> some View {
    HStack(spacing: 8) {
      statusIcon(task.status)
        .font(.caption)
        .frame(width: 16)

      Text(task.title)
        .font(.callout)
        .lineLimit(2)

      Spacer()

      if let notes = task.notes, !notes.isEmpty {
        Image(systemName: "note.text")
          .font(.caption2)
          .foregroundStyle(.tertiary)
      }

      // Edit button
      Button {
        editingTaskId = task.id
        editTitle = task.title
        editNotes = task.notes ?? ""
      } label: {
        Image(systemName: "pencil")
          .font(.caption)
      }
      .buttonStyle(.plain)
      .foregroundStyle(.secondary)

      // Delete button
      Button {
        vm.deleteTask(taskId: task.id)
      } label: {
        Image(systemName: "trash")
          .font(.caption)
      }
      .buttonStyle(.plain)
      .foregroundStyle(.red.opacity(0.6))
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 6)
    .contentShape(Rectangle())
  }

  @ViewBuilder
  private func taskEditRow(task: DashboardTask, dump: TextDump) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      TextField("Title", text: $editTitle)
        .textFieldStyle(.roundedBorder)
        .font(.callout)

      TextField("Notes (optional)", text: $editNotes, axis: .vertical)
        .textFieldStyle(.roundedBorder)
        .font(.caption)
        .lineLimit(2...5)

      HStack {
        Button("Cancel") {
          editingTaskId = nil
        }
        .keyboardShortcut(.cancelAction)

        Spacer()

        Button("Save") {
          let cleanTitle = editTitle.trimmingCharacters(in: .whitespacesAndNewlines)
          let cleanNotes = editNotes.trimmingCharacters(in: .whitespacesAndNewlines)
          if !cleanTitle.isEmpty {
            vm.updateTaskTitleAndNotes(
              taskId: task.id,
              title: cleanTitle,
              notes: cleanNotes.isEmpty ? nil : cleanNotes
            )
          }
          editingTaskId = nil
        }
        .keyboardShortcut(.defaultAction)
        .disabled(editTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
      }
    }
    .padding(12)
    .background(Theme.subtle.opacity(0.5))
  }

  private func projectName(_ id: String) -> String {
    vm.projects.first(where: { $0.id == id })?.title ?? id
  }

  @ViewBuilder
  private func statusIcon(_ status: TaskStatus) -> some View {
    switch status {
    case .active:
      Image(systemName: "circle.inset.filled")
        .foregroundStyle(.blue)
    case .completed:
      Image(systemName: "checkmark.circle.fill")
        .foregroundStyle(.green)
    case .rejected:
      Image(systemName: "xmark.circle.fill")
        .foregroundStyle(.red)
    case .inbox:
      Image(systemName: "tray.circle")
        .foregroundStyle(.secondary)
    default:
      Image(systemName: "circle")
        .foregroundStyle(.secondary)
    }
  }
}
