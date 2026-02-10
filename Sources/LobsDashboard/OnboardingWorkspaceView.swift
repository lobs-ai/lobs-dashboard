import SwiftUI

struct OnboardingWorkspaceView: View {
  let initialWorkspace: String
  let onBack: () -> Void
  let onContinue: (String) -> Void

  @State private var workspacePath: String
  @State private var error: String? = nil

  init(initialWorkspace: String, onBack: @escaping () -> Void, onContinue: @escaping (String) -> Void) {
    self.initialWorkspace = initialWorkspace
    self.onBack = onBack
    self.onContinue = onContinue
    self._workspacePath = State(initialValue: initialWorkspace)
  }

  var body: some View {
    VStack(spacing: 28) {
      Spacer()

      VStack(spacing: 10) {
        Text("Create Your Workspace")
          .font(.system(size: 28, weight: .semibold))
        Text("Where should Lobs store its files? We’ll put core repos and projects here.")
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
          TextField("~/lobs", text: $workspacePath)
            .textFieldStyle(.plain)
            .font(.system(size: 14, design: .monospaced))
            .padding(10)
            .background(Theme.cardBg)
            .cornerRadius(8)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.border, lineWidth: 1))

          Button(action: chooseFolder) {
            Image(systemName: "folder")
              .font(.system(size: 14))
              .foregroundColor(.primary)
              .frame(width: 36, height: 36)
          }
          .buttonStyle(.plain)
          .background(Theme.cardBg)
          .cornerRadius(8)
          .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.border, lineWidth: 1))
        }

        Text("Default: ~/lobs (we’ll create it if needed)")
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

      HStack(spacing: 12) {
        Button(action: onBack) {
          Text("Back")
            .font(.system(size: 14, weight: .medium))
            .foregroundColor(.primary)
            .frame(width: 120)
            .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
        .background(Theme.cardBg)
        .cornerRadius(8)

        Button(action: validateAndContinue) {
          Text("Next")
            .font(.system(size: 14, weight: .medium))
            .foregroundColor(.white)
            .frame(width: 120)
            .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
        .background(Theme.accent)
        .cornerRadius(8)
      }
      .padding(.bottom, 60)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Theme.bg)
  }

  private func validateAndContinue() {
    let expanded = expandTilde(workspacePath)
      .trimmingCharacters(in: .whitespacesAndNewlines)

    guard !expanded.isEmpty else {
      error = "Workspace path cannot be empty."
      return
    }

    do {
      try FileManager.default.createDirectory(atPath: expanded, withIntermediateDirectories: true)
      // Create a few standard subfolders (core repos are cloned later).
      try FileManager.default.createDirectory(atPath: (expanded as NSString).appendingPathComponent("projects"), withIntermediateDirectories: true)
    } catch {
      self.error = "Failed to create workspace: \(error.localizedDescription)"
      return
    }

    error = nil
    onContinue(expanded)
  }

  private func chooseFolder() {
    let panel = NSOpenPanel()
    panel.canChooseFiles = false
    panel.canChooseDirectories = true
    panel.canCreateDirectories = true
    panel.message = "Choose your Lobs workspace folder"
    panel.prompt = "Select"

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
}

#Preview {
  OnboardingWorkspaceView(initialWorkspace: NSHomeDirectory() + "/lobs", onBack: {}, onContinue: { _ in })
    .frame(width: 800, height: 600)
}
