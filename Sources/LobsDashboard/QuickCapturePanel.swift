import AppKit
import SwiftUI

// MARK: - Quick Capture Panel (Global Hotkey — Task E1F2A3B4-1002)

/// A floating panel that appears with Cmd+Shift+Space to quickly capture a task.
final class QuickCapturePanel {
  static let shared = QuickCapturePanel()

  private var panel: NSPanel?
  private var globalMonitor: Any?
  private var localMonitor: Any?
  private weak var vm: AppViewModel?

  func setup(vm: AppViewModel) {
    self.vm = vm
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
    let mode = vm?.quickCaptureHotkeyMode ?? 1
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
    hostingView.frame = NSRect(x: 0, y: 0, width: 480, height: 200)

    if panel == nil {
      let p = NSPanel(
        contentRect: NSRect(x: 0, y: 0, width: 480, height: 200),
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

  private var activeProjects: [Project] {
    vm.projects.filter { ($0.archived ?? false) == false }
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
        .onSubmit { submit() }

      HStack(spacing: 8) {
        Picker("Project", selection: $selectedProjectId) {
          ForEach(activeProjects) { p in
            Text(p.title).tag(p.id)
          }
        }
        .labelsHidden()
        .frame(width: 150)

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
    }
    .onExitCommand { onDismiss() }
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
    onDismiss()
  }
}
