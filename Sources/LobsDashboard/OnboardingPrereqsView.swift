import SwiftUI

struct OnboardingPrereqsView: View {
  @EnvironmentObject private var wizard: OnboardingWizardContext

  let onComplete: () -> Void

  private let commandTimeoutSeconds: Double = 5

  @State private var isChecking: Bool = false

  @State private var gitOK: Bool = false
  @State private var nodeOK: Bool = false
  @State private var ghOK: Bool = false
  @State private var apiKeyOK: Bool = false

  @State private var gitDetail: String = ""
  @State private var nodeDetail: String = ""
  @State private var ghDetail: String = ""
  @State private var apiKeyDetail: String = ""

  @State private var gitError: String? = nil
  @State private var nodeError: String? = nil
  @State private var ghError: String? = nil
  @State private var apiKeyError: String? = nil

  @State private var gitExpanded: Bool = false
  @State private var nodeExpanded: Bool = false
  @State private var ghExpanded: Bool = false
  @State private var apiExpanded: Bool = false

  @State private var apiKeyInput: String = ""

  private var allOK: Bool { gitOK && nodeOK && ghOK && apiKeyOK }

  var body: some View {
    VStack(spacing: 28) {
      Spacer()

      VStack(spacing: 10) {
        Text("Prerequisites")
          .font(.system(size: 28, weight: .semibold))
        Text("We’ll check a few tools Lobs needs. Fix anything missing, then click Refresh.")
          .font(.system(size: 14))
          .foregroundColor(.secondary)
          .multilineTextAlignment(.center)
          .frame(maxWidth: 560)
      }

      VStack(alignment: .leading, spacing: 12) {
        prereqDisclosure(
          title: "Git installed",
          ok: gitOK,
          detail: gitDetail,
          error: gitError,
          expanded: $gitExpanded,
          help: gitHelp
        )

        prereqDisclosure(
          title: "Node.js 18+",
          ok: nodeOK,
          detail: nodeDetail,
          error: nodeError,
          expanded: $nodeExpanded,
          help: nodeHelp
        )

        prereqDisclosure(
          title: "GitHub CLI (gh) authed",
          ok: ghOK,
          detail: ghDetail,
          error: ghError,
          expanded: $ghExpanded,
          help: ghHelp
        )

        prereqDisclosure(
          title: "Anthropic/OpenRouter API key",
          ok: apiKeyOK,
          detail: apiKeyDetail,
          error: apiKeyError,
          expanded: $apiExpanded,
          help: apiHelp
        )
      }
      .frame(width: 600)
      .padding(20)
      .background(Theme.cardBg)
      .cornerRadius(12)
      .overlay(
        RoundedRectangle(cornerRadius: 12).stroke(Theme.border, lineWidth: 1)
      )

      Spacer()

      Button(action: { Task { await refresh() } }) {
        Text(isChecking ? "Checking…" : "Refresh")
          .font(.system(size: 14, weight: .medium))
          .foregroundColor(.primary)
          .frame(width: 140)
          .padding(.vertical, 10)
      }
      .buttonStyle(.plain)
      .background(Theme.cardBg)
      .cornerRadius(8)
      .disabled(isChecking)
      .padding(.bottom, 20)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Theme.bg)
    .onAppear {
      wizard.configureNext(title: "Next", enabled: allOK) {
        onComplete()
      }
      wizard.configureSkip(shown: false)
      Task { await refresh() }
    }
    .onChange(of: allOK) { ok in
      wizard.updateNextEnabled(ok)
    }
    .onChange(of: apiKeyInput) { _ in
      // Allow "prompting" for an API key to satisfy this check.
      let trimmed = apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
      if !trimmed.isEmpty {
        apiKeyOK = true
        apiKeyDetail = "Provided (you’ll use this during OpenClaw config)"
        apiKeyError = nil
      }
    }
  }

  private func prereqDisclosure(
    title: String,
    ok: Bool,
    detail: String,
    error: String?,
    expanded: Binding<Bool>,
    @ViewBuilder help: () -> some View
  ) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(spacing: 12) {
        Image(systemName: ok ? "checkmark.circle.fill" : "xmark.circle.fill")
          .foregroundColor(ok ? .green : .red)
          .frame(width: 18)

        VStack(alignment: .leading, spacing: 2) {
          Text(title)
            .font(.system(size: 14, weight: .medium))

          Text(detail.isEmpty ? (ok ? "OK" : "Missing") : detail)
            .font(.system(size: 12))
            .foregroundColor(.secondary)
        }

        Spacer()

        if !ok {
          Button(action: { expanded.wrappedValue.toggle() }) {
            Text(expanded.wrappedValue ? "Hide" : "Fix")
              .font(.system(size: 12, weight: .medium))
              .foregroundColor(Theme.accent)
          }
          .buttonStyle(.plain)
        }
      }

      if let error, !error.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        Text(error)
          .font(.system(size: 12, design: .monospaced))
          .foregroundColor(.red)
          .textSelection(.enabled)
      }

      if !ok && expanded.wrappedValue {
        help()
          .padding(.leading, 30)
          .padding(.top, 4)
      }

      Divider().opacity(0.6)
    }
  }

  private var gitHelp: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Install Git")
        .font(.system(size: 12, weight: .semibold))

      Text("On macOS, Git is installed with Xcode Command Line Tools.")
        .font(.system(size: 12))
        .foregroundColor(.secondary)

      Text("xcode-select --install")
        .font(.system(size: 12, design: .monospaced))
        .textSelection(.enabled)
        .padding(8)
        .background(Theme.bg.opacity(0.35))
        .cornerRadius(8)

      Link("Apple developer tools", destination: URL(string: "https://developer.apple.com/xcode/resources/")!)
        .font(.system(size: 12))
    }
  }

  private var nodeHelp: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Install Node.js (18 or newer)")
        .font(.system(size: 12, weight: .semibold))

      Text("We recommend Node 18+.")
        .font(.system(size: 12))
        .foregroundColor(.secondary)

      HStack(spacing: 12) {
        Link("nodejs.org", destination: URL(string: "https://nodejs.org/")!)
          .font(.system(size: 12))
        Link("nvm", destination: URL(string: "https://github.com/nvm-sh/nvm")!)
          .font(.system(size: 12))
      }

      Text("node --version")
        .font(.system(size: 12, design: .monospaced))
        .textSelection(.enabled)
        .padding(8)
        .background(Theme.bg.opacity(0.35))
        .cornerRadius(8)
    }
  }

  private var ghHelp: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Install + authenticate GitHub CLI")
        .font(.system(size: 12, weight: .semibold))

      Link("cli.github.com", destination: URL(string: "https://cli.github.com/")!)
        .font(.system(size: 12))

      Text("gh auth login")
        .font(.system(size: 12, design: .monospaced))
        .textSelection(.enabled)
        .padding(8)
        .background(Theme.bg.opacity(0.35))
        .cornerRadius(8)

      Text("gh auth status")
        .font(.system(size: 12, design: .monospaced))
        .textSelection(.enabled)
        .padding(8)
        .background(Theme.bg.opacity(0.35))
        .cornerRadius(8)
    }
  }

  private var apiHelp: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text("Add an API key")
        .font(.system(size: 12, weight: .semibold))

      Text("You can either set an environment variable, or paste a key here to proceed (you’ll enter it again during OpenClaw config).")
        .font(.system(size: 12))
        .foregroundColor(.secondary)

      VStack(alignment: .leading, spacing: 6) {
        Text("Paste key")
          .font(.system(size: 12, weight: .medium))
          .foregroundColor(.secondary)

        SecureField("sk-…", text: $apiKeyInput)
          .textFieldStyle(.plain)
          .font(.system(size: 13, design: .monospaced))
          .padding(10)
          .background(Theme.cardBg)
          .cornerRadius(8)
          .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.border, lineWidth: 1))
      }

      VStack(alignment: .leading, spacing: 6) {
        Text("Environment variables")
          .font(.system(size: 12, weight: .medium))
          .foregroundColor(.secondary)

        Text("ANTHROPIC_API_KEY=…\nOPENROUTER_API_KEY=…")
          .font(.system(size: 12, design: .monospaced))
          .textSelection(.enabled)
          .padding(8)
          .background(Theme.bg.opacity(0.35))
          .cornerRadius(8)
      }

      HStack(spacing: 12) {
        Link("Anthropic keys", destination: URL(string: "https://console.anthropic.com/settings/keys")!)
          .font(.system(size: 12))
        Link("OpenRouter keys", destination: URL(string: "https://openrouter.ai/keys")!)
          .font(.system(size: 12))
      }
    }
  }

  private func refresh() async {
    await MainActor.run {
      isChecking = true
      gitError = nil
      nodeError = nil
      ghError = nil
      apiKeyError = nil

      // Default details while checking.
      gitDetail = "Checking…"
      nodeDetail = "Checking…"
      ghDetail = "Checking…"
      apiKeyDetail = "Checking…"
    }

    // Git
    do {
      let gitPath = await Shell.which("git")
      if gitPath == nil {
        await MainActor.run {
          gitOK = false
          gitDetail = "Not found in PATH"
          gitExpanded = true
        }
      } else {
        let res = await Shell.envAsync("git", ["--version"], timeoutSeconds: commandTimeoutSeconds)
        await MainActor.run {
          gitOK = res.ok
          gitDetail = res.ok ? res.stdout.trimmingCharacters(in: .whitespacesAndNewlines) : "Git command failed"
          gitError = res.ok ? nil : cleanError(res)
          gitExpanded = !res.ok
        }
      }
    }

    // Node
    do {
      let nodePath = await Shell.which("node")
      if nodePath == nil {
        await MainActor.run {
          nodeOK = false
          nodeDetail = "Not found in PATH"
          nodeExpanded = true
        }
      } else {
        let res = await Shell.envAsync("node", ["--version"], timeoutSeconds: commandTimeoutSeconds)
        let ver = res.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        let ok = res.ok && nodeVersionAtLeast18(ver)
        await MainActor.run {
          nodeOK = ok
          nodeDetail = res.ok ? "Detected \(ver.isEmpty ? "(unknown)" : ver)" : "Node command failed"
          nodeError = (res.ok && ok) ? nil : (!res.ok ? cleanError(res) : "Node must be version 18 or newer")
          nodeExpanded = !ok
        }
      }
    }

    // GitHub CLI
    do {
      let ghPath = await Shell.which("gh")
      if ghPath == nil {
        await MainActor.run {
          ghOK = false
          ghDetail = "Not found in PATH"
          ghExpanded = true
        }
      } else {
        let res = await Shell.envAsync("gh", ["auth", "status"], timeoutSeconds: commandTimeoutSeconds)
        let ok = res.ok
        await MainActor.run {
          ghOK = ok
          ghDetail = ok ? "Authenticated" : "Not authenticated"
          ghError = ok ? nil : cleanError(res)
          ghExpanded = !ok
        }
      }
    }

    // API key
    do {
      let env = ProcessInfo.processInfo.environment
      let anthropic = (env["ANTHROPIC_API_KEY"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
      let openrouter = (env["OPENROUTER_API_KEY"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

      var foundDetail: String? = nil
      if !anthropic.isEmpty {
        foundDetail = "Detected ANTHROPIC_API_KEY in environment"
      } else if !openrouter.isEmpty {
        foundDetail = "Detected OPENROUTER_API_KEY in environment"
      }

      // Best-effort check OpenClaw config if OpenClaw is installed.
      if foundDetail == nil {
        let openclawPath = await Shell.which("openclaw")
        if openclawPath != nil {
          let a = await Shell.envAsync("openclaw", ["config", "get", "auth.anthropicApiKey", "--no-color"], timeoutSeconds: commandTimeoutSeconds)
          if a.ok && !looksEmptyConfigValue(a.stdout) {
            foundDetail = "Detected Anthropic key in OpenClaw config"
          }

          if foundDetail == nil {
            let o = await Shell.envAsync("openclaw", ["config", "get", "auth.openrouterApiKey", "--no-color"], timeoutSeconds: commandTimeoutSeconds)
            if o.ok && !looksEmptyConfigValue(o.stdout) {
              foundDetail = "Detected OpenRouter key in OpenClaw config"
            }
          }
        }
      }

      let trimmedInput = apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
      let ok = (foundDetail != nil) || !trimmedInput.isEmpty

      await MainActor.run {
        apiKeyOK = ok
        apiKeyDetail = foundDetail ?? (trimmedInput.isEmpty ? "Not found" : "Provided (you’ll use this during OpenClaw config)")
        apiExpanded = !ok
      }
    }

    await MainActor.run {
      isChecking = false
    }
  }

  private func cleanError(_ res: Shell.Result) -> String {
    let stderr = res.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
    if !stderr.isEmpty { return stderr }
    let stdout = res.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    if !stdout.isEmpty { return stdout }
    return "Command failed (exit code \(res.exitCode))"
  }

  private func looksEmptyConfigValue(_ s: String) -> Bool {
    let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
    if t.isEmpty { return true }
    if t == "null" { return true }
    if t == "(null)" { return true }
    if t.lowercased() == "undefined" { return true }
    return false
  }

  private func nodeVersionAtLeast18(_ v: String) -> Bool {
    // v like "v20.11.0" or "20.11.0"
    let cleaned = v.trimmingCharacters(in: .whitespacesAndNewlines)
      .trimmingCharacters(in: CharacterSet(charactersIn: "v"))
    let parts = cleaned.split(separator: ".")
    guard let majorStr = parts.first, let major = Int(majorStr) else { return false }
    return major >= 18
  }
}

#Preview {
  OnboardingPrereqsView(onComplete: {})
    .environmentObject(OnboardingWizardContext())
    .frame(width: 900, height: 650)
}
