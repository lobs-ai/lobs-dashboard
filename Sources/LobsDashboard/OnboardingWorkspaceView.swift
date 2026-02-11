import SwiftUI
import AppKit

struct OnboardingWorkspaceView: View {
  @EnvironmentObject private var wizard: OnboardingWizardContext

  let initialWorkspace: String
  let onComplete: (String) -> Void

  @State private var workspacePath: String
  @State private var error: String? = nil

  init(initialWorkspace: String, onComplete: @escaping (String) -> Void) {
    self.initialWorkspace = initialWorkspace
    self.onComplete = onComplete
    self._workspacePath = State(initialValue: initialWorkspace)
  }

  private var canProceed: Bool {
    !workspacePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  var body: some View {
    VStack(spacing: 28) {
      Spacer()

      VStack(spacing: 10) {
        Text("Create Your Workspace")
          .font(.system(size: 28, weight: .semibold))
        Text("Where should Lobs store its files? We'll put core repos and projects here.")
          .font(.system(size: 14))
          .foregroundColor(.secondary)
          .multilineTextAlignment(.center)
          .frame(maxWidth: 560)
      }

      VStack(alignment: .leading, spacing: 12) {
        Text("Workspace Folder")
          .font(.system(size: 12, weight: .medium))
          .foregroundColor(.secondary)

        HStack(spacing: 8) {
          TextField("~/Library/Application Support/Lobs", text: $workspacePath)
            .textFieldStyle(.plain)
            .font(.system(size: 14, design: .monospaced))
            .padding(10)
            .background(Theme.cardBg)
            .cornerRadius(8)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.border, lineWidth: 1))

          Button(action: chooseFolder) {
            Text("Browse")
              .font(.system(size: 13, weight: .medium))
              .foregroundColor(.primary)
              .frame(width: 84, height: 36)
          }
          .buttonStyle(.plain)
          .background(Theme.cardBg)
          .cornerRadius(8)
          .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.border, lineWidth: 1))
        }

        Text("Default: ~/Library/Application Support/Lobs (no permissions needed)")
          .font(.system(size: 12))
          .foregroundColor(.secondary)
      }
      .frame(width: 560)
      .padding(20)
      .background(Theme.cardBg)
      .cornerRadius(12)
      .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.border, lineWidth: 1))

      if let error {
        Text(error)
          .font(.system(size: 13))
          .foregroundColor(.red)
          .frame(maxWidth: 560, alignment: .leading)
      }

      Spacer()
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Theme.bg)
    .onAppear {
      wizard.configureNext(title: "Next", enabled: canProceed) {
        validateAndComplete()
      }
      wizard.configureSkip(shown: false)
    }
    .onChange(of: workspacePath) { _ in
      wizard.updateNextEnabled(canProceed)
    }
  }

  private func validateAndComplete() {
    let expanded = expandTilde(workspacePath)
      .trimmingCharacters(in: .whitespacesAndNewlines)

    guard !expanded.isEmpty else {
      error = "Workspace path cannot be empty."
      return
    }

    do {
      try FileManager.default.createDirectory(atPath: expanded, withIntermediateDirectories: true)

      if !isWritableDirectory(expanded) {
        error = "Workspace folder is not writable: \(expanded)"
        return
      }

      let requiredBytes: Int64 = 1_000_000_000 // ~1 GB
      if let available = availableCapacityBytes(at: expanded), available < requiredBytes {
        error = "Not enough free space in workspace volume (need ~1GB available)."
        return
      }

      try FileManager.default.createDirectory(atPath: (expanded as NSString).appendingPathComponent("projects"), withIntermediateDirectories: true)
    } catch {
      self.error = "Failed to create workspace: \(error.localizedDescription)"
      return
    }

    error = nil
    onComplete(expanded)
  }

  private func chooseFolder() {
    let panel = NSOpenPanel()
    panel.canChooseFiles = false
    panel.canChooseDirectories = true
    panel.canCreateDirectories = true
    panel.message = "Choose your Lobs workspace folder"
    panel.prompt = "Select"

    // Start in an app-specific location instead of home root to avoid broad folder probing.
    let expanded = expandTilde(workspacePath).trimmingCharacters(in: .whitespacesAndNewlines)
    let fallback = (NSHomeDirectory() as NSString).appendingPathComponent("lobs")
    let start = expanded.isEmpty ? fallback : expanded
    panel.directoryURL = URL(fileURLWithPath: start)

    if panel.runModal() == .OK, let url = panel.url {
      workspacePath = url.path
    }
  }

  private func expandTilde(_ s: String) -> String {
    if s.hasPrefix("~") {
      return NSHomeDirectory() + s.dropFirst()
    }
    return s
  }

  private func isWritableDirectory(_ path: String) -> Bool {
    var isDir: ObjCBool = false
    guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue else { return false }

    let testFile = (path as NSString).appendingPathComponent(".lobs_write_test_\(UUID().uuidString)")
    do {
      try Data().write(to: URL(fileURLWithPath: testFile), options: .atomic)
      try FileManager.default.removeItem(atPath: testFile)
      return true
    } catch {
      return false
    }
  }

  private func availableCapacityBytes(at path: String) -> Int64? {
    let url = URL(fileURLWithPath: path)
    if let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]),
       let cap = values.volumeAvailableCapacityForImportantUsage {
      return cap
    }

    if let attrs = try? FileManager.default.attributesOfFileSystem(forPath: path),
       let free = attrs[.systemFreeSize] as? NSNumber {
      return free.int64Value
    }

    return nil
  }
}

#Preview {
  OnboardingWorkspaceView(initialWorkspace: LobsPaths.defaultWorkspace, onComplete: { _ in })
    .environmentObject(OnboardingWizardContext())
    .frame(width: 800, height: 600)
}
