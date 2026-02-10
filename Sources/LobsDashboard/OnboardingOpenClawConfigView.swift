import SwiftUI

struct OnboardingOpenClawConfigView: View {
  let workspacePath: String
  let onBack: () -> Void
  let onContinue: () -> Void

  enum Provider: String, CaseIterable, Identifiable {
    case anthropic
    case openrouter

    var id: String { rawValue }

    var displayName: String {
      switch self {
      case .anthropic: return "Anthropic"
      case .openrouter: return "OpenRouter"
      }
    }

    var flagName: String {
      switch self {
      case .anthropic: return "--anthropic-api-key"
      case .openrouter: return "--openrouter-api-key"
      }
    }

    var authChoice: String {
      switch self {
      case .anthropic: return "anthropic-api-key"
      case .openrouter: return "openrouter-api-key"
      }
    }
  }

  @State private var provider: Provider = .anthropic
  @State private var apiKey: String = ""

  @State private var isRunning: Bool = false
  @State private var log: String = ""
  @State private var error: String? = nil
  @State private var success: Bool = false

  private var openclawWorkspace: String {
    URL(fileURLWithPath: workspacePath).appendingPathComponent("lobs-workspace").path
  }

  var body: some View {
    VStack(spacing: 24) {
      Spacer()

      VStack(spacing: 10) {
        Text("Configure OpenClaw")
          .font(.system(size: 28, weight: .semibold))
        Text("Add your API key and initialize the OpenClaw gateway + local workspace.")
          .font(.system(size: 14))
          .foregroundColor(.secondary)
          .multilineTextAlignment(.center)
          .frame(maxWidth: 600)
      }

      VStack(alignment: .leading, spacing: 14) {
        HStack(spacing: 12) {
          Text("Provider")
            .font(.system(size: 12, weight: .medium))
            .foregroundColor(.secondary)
          Picker("Provider", selection: $provider) {
            ForEach(Provider.allCases) { p in
              Text(p.displayName).tag(p)
            }
          }
          .pickerStyle(.segmented)
        }

        VStack(alignment: .leading, spacing: 6) {
          Text("API Key")
            .font(.system(size: 12, weight: .medium))
            .foregroundColor(.secondary)

          SecureField("Paste your key", text: $apiKey)
            .textFieldStyle(.plain)
            .font(.system(size: 14, design: .monospaced))
            .padding(10)
            .background(Theme.cardBg)
            .cornerRadius(8)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.border, lineWidth: 1))

          Text("We’ll pass this to OpenClaw’s onboarding wizard (non-interactive).")
            .font(.system(size: 12))
            .foregroundColor(.secondary)
        }

        if let error {
          Text(error)
            .font(.system(size: 13))
            .foregroundColor(.red)
        }

        if success {
          HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
            Text("OpenClaw configured")
              .font(.system(size: 13))
          }
        }

        if !log.isEmpty {
          ScrollView {
            Text(log)
              .font(.system(size: 11, design: .monospaced))
              .foregroundColor(.secondary)
              .textSelection(.enabled)
              .frame(maxWidth: .infinity, alignment: .leading)
          }
          .frame(height: 200)
          .padding(12)
          .background(Theme.cardBg)
          .cornerRadius(8)
          .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.border, lineWidth: 1))
        }
      }
      .frame(width: 600)

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
        .disabled(isRunning)

        Button(action: { Task { await runOnboarding() } }) {
          Text(isRunning ? "Configuring…" : "Configure")
            .font(.system(size: 14, weight: .medium))
            .foregroundColor(.white)
            .frame(width: 120)
            .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
        .background(Theme.accent)
        .cornerRadius(8)
        .disabled(isRunning || apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        .opacity(apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.5 : 1.0)

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
        .disabled(!success)
        .opacity(success ? 1.0 : 0.5)
      }
      .padding(.bottom, 60)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Theme.bg)
  }

  private func runOnboarding() async {
    await MainActor.run {
      isRunning = true
      error = nil
      success = false
      log = ""
    }

    // Ensure base config exists and points at our workspace.
    _ = await Shell.envAsync("openclaw", ["setup", "--non-interactive", "--workspace", openclawWorkspace, "--mode", "local", "--no-color"])

    // Run gateway+auth onboarding in non-interactive mode.
    let args: [String] = [
      "onboard",
      "--non-interactive",
      "--mode",
      "local",
      "--workspace",
      openclawWorkspace,
      "--install-daemon",
      "--skip-ui",
      "--skip-channels",
      "--skip-skills",
      "--auth-choice",
      provider.authChoice,
      provider.flagName,
      apiKey
    ]

    let res = await Shell.envAsync("openclaw", args + ["--no-color"])

    await MainActor.run {
      log = (res.stdout + "\n" + res.stderr).trimmingCharacters(in: .whitespacesAndNewlines)
      isRunning = false
    }

    if res.ok {
      // Best-effort set default model to Sonnet.
      _ = await Shell.envAsync("openclaw", ["config", "set", "agents.defaults.model", "sonnet", "--no-color"])
      await MainActor.run { success = true }
    } else {
      await MainActor.run {
        error = "OpenClaw onboarding failed. You can retry, or run `openclaw onboard` in Terminal for an interactive setup." 
      }
    }
  }
}

#Preview {
  OnboardingOpenClawConfigView(workspacePath: NSHomeDirectory() + "/lobs", onBack: {}, onContinue: {})
    .frame(width: 800, height: 600)
}
