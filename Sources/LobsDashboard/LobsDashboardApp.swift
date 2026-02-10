import AppKit
import SwiftUI

@main
struct LobsDashboardApp: App {
  @StateObject private var vm = AppViewModel()
  @StateObject private var orchestrator = OrchestratorManager()
  @NSApplicationDelegateAdaptor(LobsDashboardAppDelegate.self) private var appDelegate

  var body: some Scene {
    WindowGroup {
      Group {
        if vm.needsOnboarding {
          OnboardingView()
            .environmentObject(vm)
            .environmentObject(orchestrator)
        } else {
          ContentView()
            .environmentObject(vm)
            .environmentObject(orchestrator)
            .frame(minWidth: 1100, minHeight: 720)
        }
      }
      .onAppear {
        // Keep orchestrator manager pointed at the same workspace used during onboarding.
        let onboardingState = OnboardingStateManager.load()
        if let ws = onboardingState.workspace, !ws.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
          orchestrator.workspacePath = ws
        }
        orchestrator.controlRepoURL = vm.repoURL
        orchestrator.startMonitoring()

        // Register global quick capture hotkey (⌘⇧Space)
        QuickCapturePanel.shared.setup(vm: vm)

        // Menu bar widget for ambient awareness
        syncMenuBarWidget()

        // Ensure the app becomes key so keyboard input goes to fields.
        NSApp.activate(ignoringOtherApps: true)

        // Request notification permissions for worker event alerts
        vm.requestNotificationPermissions()

        // Set app icon from bundled resource.
        // NOTE: This project is SwiftPM-based, so resources are accessed via `Bundle.module`.
        // Prefer the rounded variant so the Dock icon matches typical macOS icon shape.
        let iconUrl = Bundle.module.url(forResource: "AppIconRounded", withExtension: "png")
          ?? Bundle.module.url(forResource: "AppIcon", withExtension: "png")
        if let url = iconUrl,
           let img = NSImage(contentsOf: url) {
          NSApplication.shared.applicationIconImage = img
        }

        // Enable macOS native spell checking globally for all text views.
        // NSSpellChecker is the system spell checker; enabling continuous
        // spell checking and automatic spelling correction covers all
        // NSTextView-backed fields (TextField with axis: .vertical, TextEditor).
        NSSpellChecker.shared.automaticallyIdentifiesLanguages = true
        // Enable continuous spell checking on all NSTextView instances via
        // swizzling the default: when a new NSTextView appears, the system
        // respects the user's global preference. We nudge it here.
        UserDefaults.standard.set(true, forKey: "NSAllowsContinuousSpellChecking")
        UserDefaults.standard.set(true, forKey: "WebContinuousSpellCheckingEnabled")
      }
      .onReceive(vm.$config) { _ in
        // Keep the menu bar widget in sync with user settings changes.
        syncMenuBarWidget()
        orchestrator.controlRepoURL = vm.repoURL
      }
    }
    // Set a reasonable initial window size; the `.frame(minWidth/minHeight)` only
    // constrains resizing and does not guarantee the initial window dimensions.
    .defaultSize(width: 1200, height: 800)
    .commands {
      CommandGroup(replacing: .appSettings) {
        Button("Settings...") {
          NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        }
        .keyboardShortcut(",", modifiers: .command)
      }
    }

    // Settings Window
    Settings {
      SettingsView()
        .environmentObject(vm)
        .environmentObject(orchestrator)
    }
  }

  private func syncMenuBarWidget() {
    if vm.menuBarWidgetEnabled {
      appDelegate.menuBar.attach(viewModel: vm)
    } else {
      appDelegate.menuBar.detach()
    }
  }
}
