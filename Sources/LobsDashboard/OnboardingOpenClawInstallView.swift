import SwiftUI

struct OnboardingOpenClawInstallView: View {
  let onBack: () -> Void
  let onContinue: () -> Void

  @State private var isInstalling: Bool = false
  @State private var logLines: [String] = []
  @State private var error: String? = nil
  @State private var installedVersion: String? = nil
  @State private var npmAvailable: Bool = true

  var body: some View {
    VStack(spacing: 28) {
      Spacer()

      VStack(spacing: 10) {
        Text("Install OpenClaw")
          .font(.system(size: 28, weight: .semibold))
        Text("OpenClaw is the runtime that powers your Lobs worker.")
          .font(.system(size: 14))
          .foregroundColor(.secondary)
          .multilineTextAlignment(.center)
          .frame(maxWidth: 560)
      }

      VStack(alignment: .leading, spacing: 12) {
        Text("Command")
          .font(.system(size: 12, weight: .medium))
          .foregroundColor(.secondary)

        Text("npm install -g openclaw")
          .font(.system(size: 13, design: .monospaced))
          .textSelection(.enabled)
          .padding(12)
          .frame(maxWidth: .infinity, alignment: .leading)
          .background(Theme.cardBg)
          .cornerRadius(8)
          .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.border, lineWidth: 1))

        if let installedVersion {
          HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
            Text("Detected: \(installedVersion)").font(.system(size: 13))
          }
        }

        if let error {
          Text(error)
            .font(.system(size: 13))
            .foregroundColor(.red)
        }

        if !npmAvailable {
          VStack(alignment: .leading, spacing: 6) {
            Text("npm was not found in PATH.")
              .font(.system(size: 13))
              .foregroundColor(.red)
            Text("Install Node.js (18+) from https://nodejs.org, then restart Terminal / re-open the app.")
              .font(.system(size: 12))
              .foregroundColor(.secondary)
          }
        }

        if !logLines.isEmpty {
          ScrollView {
            Text(logLines.joined(separator: "\n"))
              .font(.system(size: 11, design: .monospaced))
              .foregroundColor(.secondary)
              .textSelection(.enabled)
              .frame(maxWidth: .infinity, alignment: .leading)
          }
          .frame(height: 160)
          .padding(12)
          .background(Theme.cardBg)
          .cornerRadius(8)
          .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.border, lineWidth: 1))
        }
      }
      .frame(width: 560)

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
        .disabled(isInstalling)

        Button(action: { Task { await installIfNeeded() } }) {
          Text(isInstalling ? "Installing…" : (installedVersion == nil ? "Install" : "Reinstall"))
            .font(.system(size: 14, weight: .medium))
            .foregroundColor(.white)
            .frame(width: 120)
            .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
        .background(Theme.accent)
        .cornerRadius(8)
        .disabled(isInstalling || !npmAvailable)
        .opacity((isInstalling || !npmAvailable) ? 0.5 : 1.0)

        Button(action: onContinue) {
          Text("Next")
            .font(.system(size: 14, weight: .medium))
            .foregroundColor(.white)
            .frame(width: 120)
            .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
        .background(Theme.accent)
        .cornerRadius(8)
        .disabled(installedVersion == nil)
        .opacity(installedVersion == nil ? 0.5 : 1.0)
      }
      .padding(.bottom, 60)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Theme.bg)
    .onAppear {
      Task {
        await detectPrereqs()
        await detectVersion()
      }
    }
  }

  private func detectPrereqs() async {
    let npmPath = await Shell.which("npm")
    await MainActor.run {
      npmAvailable = (npmPath != nil)
    }
  }

  private func detectVersion() async {
    let res = await Shell.envAsync("openclaw", ["--version", "--no-color"])
    if res.ok {
      await MainActor.run {
        installedVersion = res.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        error = nil
      }
    } else {
      await MainActor.run {
        installedVersion = nil
      }
    }
  }

  private func installIfNeeded() async {
    await detectVersion()
    // If already installed, we still allow a reinstall via the button.
    await install()
  }

  private func install() async {
    await MainActor.run {
      isInstalling = true
      error = nil
      logLines = []
    }

    // Run install.
    let res = await Shell.envAsync("npm", ["install", "-g", "openclaw"])

    await MainActor.run {
      logLines = (res.stdout + "\n" + res.stderr)
        .split(separator: "\n").map(String.init)
      isInstalling = false
    }

    await detectVersion()

    if installedVersion == nil {
      await MainActor.run {
        let stderr = res.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        if !stderr.isEmpty {
          error = "Install failed: \(stderr)"
        } else {
          error = "Install did not succeed. If you use a Node version manager, ensure your global npm bin is on PATH."
        }
      }
    }
  }
}

#Preview {
  OnboardingOpenClawInstallView(onBack: {}, onContinue: {})
    .frame(width: 800, height: 600)
}
