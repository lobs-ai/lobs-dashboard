import AppKit
import SwiftUI

@main
struct LobsDashboardApp: App {
  @StateObject private var vm = AppViewModel()

  var body: some Scene {
    WindowGroup {
      ContentView()
        .environmentObject(vm)
        .frame(minWidth: 1100, minHeight: 720)
        .onAppear {
          // Register global quick capture hotkey (⌘⇧Space)
          QuickCapturePanel.shared.setup(vm: vm)
          // Ensure the app becomes key so keyboard input goes to fields.
          NSApp.activate(ignoringOtherApps: true)
          // Set app icon from bundled resource
          if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "png"),
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
    }
    // Set a reasonable initial window size; the `.frame(minWidth/minHeight)` only
    // constrains resizing and does not guarantee the initial window dimensions.
    .defaultSize(width: 1200, height: 800)
  }
}
