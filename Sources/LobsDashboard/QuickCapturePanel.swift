import AppKit
import Combine
import SwiftUI

// MARK: - Quick Capture Panel (Global Hotkey — Task E1F2A3B4-1002)

/// A floating panel that appears with Cmd+Shift+Space to quickly capture a task.
final class QuickCapturePanel {
  static let shared = QuickCapturePanel()

  private var panel: NSPanel?
  private var globalMonitor: Any?
  private var localMonitor: Any?
  private weak var vm: AppViewModel?
  private var cachedHotkeyMode: Int = 1
  private var hotkeyModeCancellable: AnyCancellable?

  func setup(vm: AppViewModel) {
    self.vm = vm

    // Cache the hotkey mode for use in the global event monitor (which may fire off-main-thread).
    cachedHotkeyMode = vm.quickCaptureHotkeyMode
    hotkeyModeCancellable = vm.$quickCaptureHotkeyMode
      .receive(on: DispatchQueue.main)
      .sink { [weak self] newValue in
        self?.cachedHotkeyMode = newValue
      }

    registerGlobalHotkey()
  }

  private func registerGlobalHotkey() {
    // Global monitor for when app is NOT focused
    globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
      if self?.isHotkey(event) == true {
        DispatchQueue.main.async {
          self?.toggle()
        }
      }
    }

    // Local monitor for when app IS focused
    localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
      if self?.isHotkey(event) == true {
        DispatchQueue.main.async {
          self?.toggle()
        }
        return nil // consume the event
      }
      return event
    }
  }

  private func isHotkey(_ event: NSEvent) -> Bool {
    // Hotkey is configurable (managed by AppViewModel via ~/.lobs/config.json)
    // 0 = ⌘⇧Space, 1 = ⌥Space
    let mode = cachedHotkeyMode
    let isSpace = (event.keyCode == 49)
    if !isSpace { return false }

    switch mode {
    case 0:
      return event.modifierFlags.contains(.command) && event.modifierFlags.contains(.shift)
    default:
      return event.modifierFlags.contains(.option)
    }
  }

  func toggle() {
    if let panel = panel, panel.isVisible {
      dismiss()
    } else {
      show()
    }
  }

  func show() {
    guard let vm = vm else { return }

    let captureView = QuickCaptureView(vm: vm) { [weak self] in
      self?.dismiss()
    }

    let hostingView = NSHostingView(rootView: captureView)
    hostingView.frame = NSRect(x: 0, y: 0, width: 560, height: 260)

    if panel == nil {
      let p = NSPanel(
        contentRect: NSRect(x: 0, y: 0, width: 560, height: 260),
        styleMask: [.titled, .closable, .fullSizeContentView, .nonactivatingPanel, .hudWindow],
        backing: .buffered,
        defer: false
      )
      p.titlebarAppearsTransparent = true
      p.titleVisibility = .hidden
      p.isMovableByWindowBackground = true
      p.level = .floating
      p.isFloatingPanel = true
      p.hidesOnDeactivate = false
      p.becomesKeyOnlyIfNeeded = false
      p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
      p.backgroundColor = .clear
      panel = p
    }

    panel?.contentView = hostingView
    panel?.center()

    // Position near top center of screen
    if let screen = NSScreen.main {
      let screenFrame = screen.visibleFrame
      let panelFrame = panel!.frame
      let x = screenFrame.midX - panelFrame.width / 2
      let y = screenFrame.maxY - panelFrame.height - 100
      panel?.setFrameOrigin(NSPoint(x: x, y: y))
    }

    panel?.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
  }

  func dismiss() {
    panel?.orderOut(nil)
  }

  deinit {
    if let m = globalMonitor { NSEvent.removeMonitor(m) }
    if let m = localMonitor { NSEvent.removeMonitor(m) }
  }
}

// MARK: - Quick Capture SwiftUI View

struct QuickCaptureView: View {
  @ObservedObject var vm: AppViewModel
  let onDismiss: () -> Void

  @State private var title: String = ""
  @State private var notes: String = ""

  @State private var selectedProjectId: String = ""
  @State private var projectQuery: String = ""
  @State private var showingProjectPicker: Bool = false

  @FocusState private var titleFocused: Bool

  @AppStorage("quickCaptureRecentProjectIds") private var recentProjectsData: String = ""

  private var activeProjects: [Project] {
    vm.projects.filter { ($0.archived ?? false) == false }
  }

  private var selectedProjectTitle: String {
    activeProjects.first(where: { $0.id == selectedProjectId })?.title ?? ""
  }

  private var recentProjectIds: [String] {
    guard let data = recentProjectsData.data(using: .utf8),
          let ids = try? JSONDecoder().decode([String].self, from: data) else {
      return []
    }
    return ids
  }

  private var projectSuggestions: [Project] {
    let q = projectQuery.trimmingCharacters(in: .whitespacesAndNewlines)

    // If empty, show recents first, then the current selection, then alphabetically.
    if q.isEmpty {
      var projects: [Project] = []

      let recent = recentProjectIds.compactMap { id in
        activeProjects.first(where: { $0.id == id })
      }
      projects.append(contentsOf: recent)

      if let selected = activeProjects.first(where: { $0.id == selectedProjectId }),
         !projects.contains(where: { $0.id == selected.id }) {
        projects.append(selected)
      }

      let remaining = activeProjects
        .filter { p in !projects.contains(where: { $0.id == p.id }) }
        .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }

      projects.append(contentsOf: remaining)
      return Array(projects.prefix(8))
    }

    // Fuzzy search.
    let tokens = q.split(separator: " ").map(String.init)
    let scored: [(Project, Int)] = activeProjects.compactMap { p in
      guard let s = FuzzyMatcher.score(queryTokens: tokens, target: p.title) else { return nil }
      return (p, s)
    }

    return scored
      .sorted { $0.1 > $1.1 }
      .map { $0.0 }
      .prefix(8)
      .map { $0 }
  }

  var body: some View {
    VStack(spacing: 12) {
      HStack(spacing: 8) {
        Image(systemName: "bolt.circle.fill")
          .font(.title2)
          .foregroundStyle(.linearGradient(
            colors: [.yellow, .orange],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
          ))
        Text("Quick Capture")
          .font(.headline)
          .fontWeight(.bold)

        Spacer()

        Text(vm.quickCaptureHotkeyMode == 0 ? "⌘⇧Space" : "⌥Space")
          .font(.system(size: 11, design: .monospaced))
          .foregroundStyle(.tertiary)
      }

      TextField("What needs to be done?", text: $title)
        .textFieldStyle(.roundedBorder)
        .font(.body)
        .focused($titleFocused)
        .onSubmit { submit() }

      VStack(alignment: .leading, spacing: 8) {
        HStack(spacing: 8) {
          ZStack(alignment: .leading) {
            if projectQuery.isEmpty {
              Text(selectedProjectTitle.isEmpty ? "Project" : selectedProjectTitle)
                .foregroundStyle(.secondary)
                .padding(.leading, 8)
            }

            TextField("", text: $projectQuery)
              .textFieldStyle(.roundedBorder)
              .font(.footnote)
              .onTapGesture {
                showingProjectPicker = true
              }
              .onChange(of: projectQuery) { _ in
                showingProjectPicker = true
              }
          }
          .frame(width: 180)

          TextField("Notes (optional)", text: $notes)
            .textFieldStyle(.roundedBorder)
            .font(.footnote)
            .onSubmit { submit() }

          Button(action: submit) {
            Image(systemName: "arrow.up.circle.fill")
              .font(.title2)
              .foregroundStyle(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                               ? Color.secondary : Color.accentColor)
          }
          .buttonStyle(.plain)
          .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
          .keyboardShortcut(.defaultAction)
        }

        if showingProjectPicker {
          VStack(alignment: .leading, spacing: 0) {
            ForEach(projectSuggestions) { p in
              Button {
                selectProject(p)
              } label: {
                HStack {
                  Text(p.title)
                    .font(.system(size: 12))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                  Spacer()
                  if p.id == selectedProjectId {
                    Image(systemName: "checkmark")
                      .font(.system(size: 11, weight: .semibold))
                      .foregroundStyle(.secondary)
                  }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
              }
              .buttonStyle(.plain)

              if p.id != projectSuggestions.last?.id {
                Divider()
              }
            }
          }
          .background(
            RoundedRectangle(cornerRadius: 10)
              .fill(Color(NSColor.controlBackgroundColor))
          )
          .overlay(
            RoundedRectangle(cornerRadius: 10)
              .stroke(Color.primary.opacity(0.08), lineWidth: 1)
          )
        }
      }
    }
    .padding(16)
    .background(
      RoundedRectangle(cornerRadius: 16)
        .fill(.ultraThinMaterial)
    )
    .overlay(
      RoundedRectangle(cornerRadius: 16)
        .stroke(Color.primary.opacity(0.1), lineWidth: 1)
    )
    .shadow(color: .black.opacity(0.2), radius: 20, y: 10)
    .onAppear {
      selectedProjectId = vm.selectedProjectId
      if !activeProjects.contains(where: { $0.id == selectedProjectId }) {
        selectedProjectId = activeProjects.first?.id ?? ""
      }
      projectQuery = ""
      titleFocused = true
    }
    .onExitCommand { onDismiss() }
  }

  private func selectProject(_ project: Project) {
    selectedProjectId = project.id
    projectQuery = ""
    showingProjectPicker = false

    // Persist as a recent.
    var ids = recentProjectIds
    ids.removeAll { $0 == project.id }
    ids.insert(project.id, at: 0)
    ids = Array(ids.prefix(8))

    if let data = try? JSONEncoder().encode(ids),
       let s = String(data: data, encoding: .utf8) {
      recentProjectsData = s
    }
  }

  private func submit() {
    let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return }

    let prevProject = vm.selectedProjectId
    vm.selectedProjectId = selectedProjectId

    vm.submitTaskToLobs(
      title: trimmed,
      notes: notes.isEmpty ? nil : notes,
      autoPush: true
    )

    vm.selectedProjectId = prevProject

    title = ""
    notes = ""
    projectQuery = ""
    showingProjectPicker = false
    onDismiss()
  }
}
