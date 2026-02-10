import SwiftUI

struct OnboardingOpenClawConfigView: View {
  let workspacePath: String
  let onBack: () -> Void
  let onContinue: () -> Void

  enum Provider: String, CaseIterable, Identifiable {
    case anthropic
    case openrouter
    case openai

    var id: String { rawValue }

    var displayName: String {
      switch self {
      case .anthropic: return "Anthropic"
      case .openrouter: return "OpenRouter"
      case .openai: return "OpenAI"
      }
    }

    var configKeyPath: String {
      switch self {
      case .anthropic: return "auth.anthropicApiKey"
      case .openrouter: return "auth.openrouterApiKey"
      case .openai: return "auth.openaiApiKey"
      }
    }

    /// Provider id used by `openclaw models status --probe-provider <id>`.
    var probeProviderID: String {
      switch self {
      case .anthropic: return "anthropic"
      case .openrouter: return "openrouter"
      case .openai: return "openai"
      }
    }

    var defaultModels: [String] {
      switch self {
      case .anthropic:
        return [
          "claude-sonnet-4",
          "claude-opus-4",
          "claude-haiku-4"
        ]
      case .openrouter:
        // Curated list of commonly-used OpenRouter model IDs.
        return [
          "openrouter/anthropic/claude-3.5-sonnet",
          "openrouter/anthropic/claude-3.5-haiku",
          "openrouter/openai/gpt-4o-mini",
          "openrouter/openai/gpt-4o",
          "openrouter/google/gemini-2.0-flash",
          "openrouter/meta-llama/llama-3.1-70b-instruct"
        ]
      case .openai:
        return [
          "gpt-4o-mini",
          "gpt-4o",
          "gpt-4.1-mini"
        ]
      }
    }
  }

  @State private var provider: Provider = .anthropic
  @State private var apiKey: String = ""
  @State private var showApiKey: Bool = false
  @State private var defaultModel: String = "claude-sonnet-4"

  @State private var isRunning: Bool = false
  @State private var isTesting: Bool = false
  @State private var log: String = ""
  @State private var error: String? = nil
  @State private var success: Bool = false
  @State private var testOK: Bool = false

  private var openclawWorkspace: String {
    URL(fileURLWithPath: workspacePath).appendingPathComponent("lobs-workspace").path
  }

  private var canRun: Bool {
    !isRunning && !isTesting && !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  var body: some View {
    VStack(spacing: 24) {
      Spacer()

      VStack(spacing: 10) {
        Text("Configure OpenClaw")
          .font(.system(size: 28, weight: .semibold))
        Text("Add your API key and set a default model.")
          .font(.system(size: 14))
          .foregroundColor(.secondary)
          .multilineTextAlignment(.center)
          .frame(maxWidth: 600)
      }

      VStack(alignment: .leading, spacing: 14) {
        VStack(alignment: .leading, spacing: 8) {
          Text("API Provider")
            .font(.system(size: 12, weight: .medium))
            .foregroundColor(.secondary)

          Picker("Provider", selection: $provider) {
            ForEach(Provider.allCases) { p in
              Text(p.displayName).tag(p)
            }
          }
          .pickerStyle(.popUpButton)
          .onChange(of: provider) { _, newProvider in
            // Reset model to provider default list.
            defaultModel = newProvider.defaultModels.first ?? ""
            testOK = false
            success = false
            error = nil
          }
        }

        VStack(alignment: .leading, spacing: 6) {
          Text("API Key")
            .font(.system(size: 12, weight: .medium))
            .foregroundColor(.secondary)

          HStack(spacing: 10) {
            Group {
              if showApiKey {
                TextField("Paste your key", text: $apiKey)
              } else {
                SecureField("Paste your key", text: $apiKey)
              }
            }
            .textFieldStyle(.plain)
            .font(.system(size: 14, design: .monospaced))

            Button(action: { showApiKey.toggle() }) {
              Image(systemName: showApiKey ? "eye.slash" : "eye")
                .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .help(showApiKey ? "Hide" : "Show")
          }
          .padding(10)
          .background(Theme.cardBg)
          .cornerRadius(8)
          .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.border, lineWidth: 1))

          Text("Stored in OpenClaw’s standard config location.")
            .font(.system(size: 12))
            .foregroundColor(.secondary)
        }

        VStack(alignment: .leading, spacing: 6) {
          Text("Default Model")
            .font(.system(size: 12, weight: .medium))
            .foregroundColor(.secondary)

          Picker("Default Model", selection: $defaultModel) {
            ForEach(provider.defaultModels, id: \.self) { m in
              Text(m).tag(m)
            }
          }
          .pickerStyle(.popUpButton)
          .frame(maxWidth: .infinity, alignment: .leading)

          Text("This is the model OpenClaw will use by default.")
            .font(.system(size: 12))
            .foregroundColor(.secondary)
        }

        if let error {
          Text(error)
            .font(.system(size: 13))
            .foregroundColor(.red)
        }

        if testOK {
          HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
            Text("Connection OK")
              .font(.system(size: 13))
          }
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
        .disabled(isRunning || isTesting)

        Button(action: { Task { await testConnection() } }) {
          Text(isTesting ? "Testing…" : "Test Connection")
            .font(.system(size: 14, weight: .medium))
            .foregroundColor(.white)
            .frame(width: 160)
            .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
        .background(Theme.accent)
        .cornerRadius(8)
        .disabled(!canRun)
        .opacity(canRun ? 1.0 : 0.5)

        Button(action: { Task { await configure() } }) {
          Text(isRunning ? "Saving…" : "Save")
            .font(.system(size: 14, weight: .medium))
            .foregroundColor(.white)
            .frame(width: 120)
            .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
        .background(Theme.accent)
        .cornerRadius(8)
        .disabled(!canRun || !testOK)
        .opacity((canRun && testOK) ? 1.0 : 0.5)

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
    .onAppear {
      // Ensure default model is valid for initial provider.
      defaultModel = provider.defaultModels.first ?? defaultModel
    }
  }

  private func cleanError(_ res: Shell.Result) -> String {
    let stderr = res.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
    if !stderr.isEmpty { return stderr }
    let stdout = res.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    if !stdout.isEmpty { return stdout }
    return "Command failed (exit code \(res.exitCode))"
  }

  private func writeConfigValues() async -> Bool {
    // Ensure base config exists and points at our workspace.
    _ = await Shell.envAsync(
      "openclaw",
      ["setup", "--non-interactive", "--workspace", openclawWorkspace, "--mode", "local", "--no-color"]
    )

    let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmedKey.isEmpty {
      await MainActor.run { error = "API key is required." }
      return false
    }

    // Store key.
    let keyRes = await Shell.envAsync(
      "openclaw",
      ["config", "set", provider.configKeyPath, trimmedKey, "--no-color"]
    )
    if !keyRes.ok {
      await MainActor.run { error = cleanError(keyRes) }
      return false
    }

    // Workspace + model.
    _ = await Shell.envAsync(
      "openclaw",
      ["config", "set", "agents.defaults.workspace", openclawWorkspace, "--no-color"]
    )

    let modelRes = await Shell.envAsync(
      "openclaw",
      ["models", "set", defaultModel, "--no-color"]
    )

    if !modelRes.ok {
      await MainActor.run { error = cleanError(modelRes) }
      return false
    }

    return true
  }

  private func testConnection() async {
    await MainActor.run {
      isTesting = true
      error = nil
      testOK = false
      success = false
      log = ""
    }

    let ok = await writeConfigValues()
    if !ok {
      await MainActor.run { isTesting = false }
      return
    }

    // Live probe against the selected provider.
    let res = await Shell.envAsync(
      "openclaw",
      [
        "models",
        "status",
        "--probe",
        "--probe-provider",
        provider.probeProviderID,
        "--probe-max-tokens",
        "8",
        "--plain",
        "--no-color"
      ]
    )

    await MainActor.run {
      log = (res.stdout + "\n" + res.stderr).trimmingCharacters(in: .whitespacesAndNewlines)
      isTesting = false
    }

    if res.ok {
      await MainActor.run {
        testOK = true
        error = nil
      }
    } else {
      await MainActor.run {
        testOK = false
        error = "Invalid API key (or provider unavailable). Please check your key and try again.\n\n\(cleanError(res))"
      }
    }
  }

  private func configure() async {
    await MainActor.run {
      isRunning = true
      error = nil
      success = false
    }

    let ok = await writeConfigValues()
    await MainActor.run { isRunning = false }

    if !ok {
      return
    }

    // Require a successful probe before proceeding.
    await testConnection()
    if testOK {
      await MainActor.run { success = true }
    }
  }
}

#Preview {
  OnboardingOpenClawConfigView(workspacePath: NSHomeDirectory() + "/lobs", onBack: {}, onContinue: {})
    .frame(width: 800, height: 600)
}
