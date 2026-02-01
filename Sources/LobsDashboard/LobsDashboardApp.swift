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
          // Ensure the app becomes key so keyboard input goes to fields.
          NSApp.activate(ignoringOtherApps: true)
          // Set app icon from bundled resource
          if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "png"),
             let img = NSImage(contentsOf: url) {
            NSApplication.shared.applicationIconImage = img
          }
        }
    }
    // Set a reasonable initial window size; the `.frame(minWidth/minHeight)` only
    // constrains resizing and does not guarantee the initial window dimensions.
    .defaultSize(width: 1200, height: 800)
  }
}
