import SwiftUI

struct OnboardingPrereqsView: View {
  @EnvironmentObject private var wizard: OnboardingWizardContext

  let onComplete: () -> Void

  private let commandTimeoutSeconds: Double = 5

  @State private var isChecking: Bool = false

  @State private var gitOK: Bool = false
  @State private var nodeOK: Bool = false
  @State private var ghOK: Bool = false
  @State private var pythonOK: Bool = false

  @State private var gitDetail: String = ""
  @State private var nodeDetail: String = ""
  @State private var ghDetail: String = ""
  @State private var pythonDetail: String = ""

  @State private var gitError: String? = nil
  @State private var nodeError: String? = nil
  @State private var ghError: String? = nil
  @State private var pythonError: String? = nil

  @State private var gitExpanded: Bool = false
  @State private var nodeExpanded: Bool = false
  @State private var ghExpanded: Bool = false
  @State private var pythonExpanded: Bool = false

  private var allOK: Bool { gitOK && nodeOK && ghOK && pythonOK }

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
          title: "Python 3.10+",
          ok: pythonOK,
          detail: pythonDetail,
          error: pythonError,
          expanded: $pythonExpanded,
          help: pythonHelp
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

  private var pythonHelp: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Install Python 3.10+")
        .font(.system(size: 12, weight: .semibold))

      Text("The orchestrator uses Python. We require Python 3.10 or newer.")
        .font(.system(size: 12))
        .foregroundColor(.secondary)

      HStack(spacing: 12) {
        Link("python.org", destination: URL(string: "https://www.python.org/downloads/")!)
          .font(.system(size: 12))
        Link("Homebrew", destination: URL(string: "https://brew.sh")!)
          .font(.system(size: 12))
      }

      Text("python3 --version")
        .font(.system(size: 12, design: .monospaced))
        .textSelection(.enabled)
        .padding(8)
        .background(Theme.bg.opacity(0.35))
        .cornerRadius(8)
    }
  }

  private func refresh() async {
    await MainActor.run {
      isChecking = true
      gitError = nil
      nodeError = nil
      ghError = nil
      pythonError = nil

      // Default details while checking.
      gitDetail = "Checking…"
      nodeDetail = "Checking…"
      ghDetail = "Checking…"
      pythonDetail = "Checking…"
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

    // Python
    do {
      let pyPath = await Shell.which("python3")
      if pyPath == nil {
        await MainActor.run {
          pythonOK = false
          pythonDetail = "Not found in PATH"
          pythonExpanded = true
        }
      } else {
        let res = await Shell.envAsync("python3", ["--version"], timeoutSeconds: commandTimeoutSeconds)
        let ver = (res.stdout.isEmpty ? res.stderr : res.stdout).trimmingCharacters(in: .whitespacesAndNewlines)
        let ok = res.ok && pythonVersionAtLeast3_10(ver)
        await MainActor.run {
          pythonOK = ok
          pythonDetail = res.ok ? "Detected \(ver.isEmpty ? \"(unknown)\" : ver)" : "python3 command failed"
          pythonError = (res.ok && ok) ? nil : (!res.ok ? cleanError(res) : "Python must be version 3.10 or newer")
          pythonExpanded = !ok
        }
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

  private func nodeVersionAtLeast18(_ v: String) -> Bool {
    // v like "v20.11.0" or "20.11.0"
    let cleaned = v.trimmingCharacters(in: .whitespacesAndNewlines)
      .trimmingCharacters(in: CharacterSet(charactersIn: "v"))
    let parts = cleaned.split(separator: ".")
    guard let majorStr = parts.first, let major = Int(majorStr) else { return false }
    return major >= 18
  }

  private func pythonVersionAtLeast3_10(_ v: String) -> Bool {
    // "Python 3.11.7" or "3.11.7"
    let trimmed = v.trimmingCharacters(in: .whitespacesAndNewlines)
    let cleaned = trimmed.hasPrefix("Python ") ? String(trimmed.dropFirst("Python ".count)) : trimmed
    let parts = cleaned.split(separator: ".")
    guard parts.count >= 2,
          let major = Int(parts[0]),
          let minor = Int(parts[1]) else { return false }
    if major > 3 { return true }
    if major < 3 { return false }
    return minor >= 10
  }
}

#Preview {
  OnboardingPrereqsView(onComplete: {})
    .environmentObject(OnboardingWizardContext())
    .frame(width: 900, height: 650)
}
