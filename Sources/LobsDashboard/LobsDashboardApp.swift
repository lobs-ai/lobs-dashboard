import AppKit
import SwiftUI

@main
struct LobsDashboardApp: App {
  @StateObject private var vm = AppViewModel()

  var body: some Scene {
    WindowGroup {
      ContentView()
        .environmentObject(vm)
        .frame(minWidth: 900, minHeight: 600)
        .onAppear {
          // Ensure the app becomes key so keyboard input goes to fields.
          NSApp.activate(ignoringOtherApps: true)
        }
    }
  }
}
