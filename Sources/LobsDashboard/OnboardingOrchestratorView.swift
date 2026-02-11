import SwiftUI

struct OnboardingOrchestratorView: View {
  @EnvironmentObject private var wizard: OnboardingWizardContext

  let workspacePath: String
  let onComplete: () -> Void
  var onSkip: (() -> Void)? = nil

  @State private var isWorking: Bool = false
  @State private var log: String = ""
  @State private var error: String? = nil
  @State private var statusText: String = "Unknown"
  @State private var runOnLogin: Bool = true

  private var orchestratorURL: URL {
    URL(fileURLWithPath: workspacePath).appendingPathComponent("lobs-orchestrator")
  }

  private var launchAgentLabel: String { "com.lobs.orchestrator" }

  var body: some View {
    VStack(spacing: 24) {
      Spacer()

      VStack(spacing: 10) {
        Text("Start Orchestrator")
          .font(.system(size: 28, weight: .semibold))
        Text("The orchestrator monitors your control repo and runs tasks with OpenClaw.")
          .font(.system(size: 14))
          .foregroundColor(.secondary)
          .multilineTextAlignment(.center)
          .frame(maxWidth: 620)
      }

      VStack(alignment: .leading, spacing: 14) {
        HStack(spacing: 10) {
          Text("Status:")
            .font(.system(size: 13, weight: .semibold))
          Text(statusText)
            .font(.system(size: 13))
            .foregroundColor(statusText.contains("Running") ? .green : (statusText.contains("Starting") ? .orange : .secondary))
          Spacer()

          Toggle("Run on login", isOn: $runOnLogin)
            .toggleStyle(.switch)
            .labelsHidden()
          Text("Run on login")
            .font(.system(size: 13))
            .foregroundColor(.secondary)
        }

        if let error {
          Text(error)
            .font(.system(size: 13))
            .foregroundColor(.red)
        }

        if !log.isEmpty {
          ScrollView {
            Text(log)
              .font(.system(size: 11, design: .monospaced))
              .foregroundColor(.secondary)
              .textSelection(.enabled)
              .frame(maxWidth: .infinity, alignment: .leading)
          }
          .frame(height: 220)
          .padding(12)
          .background(Theme.cardBg)
          .cornerRadius(8)
          .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.border, lineWidth: 1))
        }
      }
      .frame(width: 640)

      Spacer()

      HStack(spacing: 12) {
        Button(action: { Task { await setupAndStart() } }) {
          Text(isWorking ? "Starting…" : "Start")
            .font(.system(size: 14, weight: .medium))
            .foregroundColor(.white)
            .frame(width: 120)
            .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
        .background(Theme.accent)
        .cornerRadius(8)
        .disabled(isWorking)

        Button(action: { Task { await refreshStatus() } }) {
          Text("Refresh")
            .font(.system(size: 14, weight: .medium))
            .foregroundColor(.primary)
            .frame(width: 120)
            .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
        .background(Theme.cardBg)
        .cornerRadius(8)
        .disabled(isWorking)

        if statusText.contains("Running") {
          Text("Running — use Next")
            .font(.system(size: 12))
            .foregroundColor(.secondary)
        }
      }
      .padding(.bottom, 20)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Theme.bg)
    .onAppear {
      wizard.configureNext(title: "Next", enabled: statusText.contains("Running")) {
        onComplete()
      }
      wizard.configureSkip(shown: true, title: "Skip for now", enabled: true) {
        onSkip?() ?? onComplete()
      }

      Task { await refreshStatus() }
    }
    .onChange(of: statusText) { _ in
      wizard.updateNextEnabled(statusText.contains("Running"))
    }
  }

  private func setupAndStart() async {
    await MainActor.run {
      isWorking = true
      error = nil
      log = ""
      statusText = "Starting…"
    }

    // 1) Ensure python venv + deps (best-effort; orchestrator repo defines requirements.txt)
    let venvRes = await Shell.envAsync("python3", ["-m", "venv", ".venv"], cwd: orchestratorURL)
    let pipRes = await Shell.envAsync("/bin/bash", ["-lc", "source .venv/bin/activate && pip install -r requirements.txt"], cwd: orchestratorURL)

    // 2) Install/start via LaunchAgent (preferred so it survives app quit)
    let plistRes = await writeLaunchAgentPlist()
    let loadRes = await bootstrapLaunchAgentIfNeeded()
    let kickRes = await Shell.envAsync("launchctl", ["kickstart", "-k", "gui/\(uid())/\(launchAgentLabel)"])

    await MainActor.run {
      log = [
        "[venv] exit=\(venvRes.exitCode)",
        venvRes.stdout, venvRes.stderr,
        "[pip] exit=\(pipRes.exitCode)",
        pipRes.stdout, pipRes.stderr,
        "[plist] \(plistRes)",
        "[bootstrap] exit=\(loadRes.exitCode)",
        loadRes.stdout, loadRes.stderr,
        "[kickstart] exit=\(kickRes.exitCode)",
        kickRes.stdout, kickRes.stderr
      ].filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.joined(separator: "\n")
    }

    await refreshStatus()

    await MainActor.run {
      isWorking = false
      if !statusText.contains("Running") {
        error = "Failed to start orchestrator. Check the log above."
      }
    }
  }

  private func refreshStatus() async {
    let res = await Shell.envAsync("launchctl", ["print", "gui/\(uid())/\(launchAgentLabel)"])
    await MainActor.run {
      if res.ok {
        statusText = res.stdout.contains("state = running") ? "Running ✓" : "Installed"
      } else {
        statusText = "Not installed"
      }
    }
  }

  private func uid() -> String {
    // This runs quickly; used for launchctl domain.
    // If it fails, default to current user id 501-ish? but just return empty.
    // NOTE: openclaw targets macOS; in previews this may differ.
    let res = try? Shell.run("/usr/bin/id", ["-u"])
    let s = res?.stdout.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return s.isEmpty ? "" : s
  }

  private func writeLaunchAgentPlist() async -> String {
    let fm = FileManager.default
    let agentsDir = fm.homeDirectoryForCurrentUser.appendingPathComponent("Library/LaunchAgents")
    let plistURL = agentsDir.appendingPathComponent("\(launchAgentLabel).plist")

    do {
      try fm.createDirectory(at: agentsDir, withIntermediateDirectories: true)

      let logsDir = fm.homeDirectoryForCurrentUser
        .appendingPathComponent(".openclaw")
        .appendingPathComponent("logs")
      _ = try? fm.createDirectory(at: logsDir, withIntermediateDirectories: true)
      let logURL = logsDir.appendingPathComponent("lobs-orchestrator.log")

      let script = "cd \"\(orchestratorURL.path)\" && source .venv/bin/activate && python3 main.py >> \"\(logURL.path)\" 2>&1"

      let plist = """
      <?xml version=\"1.0\" encoding=\"UTF-8\"?>
      <!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">
      <plist version=\"1.0\">
      <dict>
        <key>Label</key>
        <string>\(launchAgentLabel)</string>
        <key>ProgramArguments</key>
        <array>
          <string>/bin/bash</string>
          <string>-lc</string>
          <string>\(script)</string>
        </array>
        <key>RunAtLoad</key>
        <\(runOnLogin ? "true" : "false")/>
        <key>KeepAlive</key>
        <true/>
      </dict>
      </plist>
      """

      try plist.write(to: plistURL, atomically: true, encoding: .utf8)
      return "Wrote \(plistURL.path)"
    } catch {
      return "Failed to write LaunchAgent plist: \(error.localizedDescription)"
    }
  }

  private func bootstrapLaunchAgentIfNeeded() async -> Shell.Result {
    // launchctl bootstrap fails if already loaded; in that case, do a bootout+bootstrap.
    let domain = "gui/\(uid())"
    let plistPath = FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent("Library/LaunchAgents")
      .appendingPathComponent("\(launchAgentLabel).plist").path

    let boot = await Shell.envAsync("launchctl", ["bootstrap", domain, plistPath])
    if boot.ok { return boot }

    _ = await Shell.envAsync("launchctl", ["bootout", domain, launchAgentLabel])
    return await Shell.envAsync("launchctl", ["bootstrap", domain, plistPath])
  }
}

#Preview {
  OnboardingOrchestratorView(workspacePath: LobsPaths.defaultWorkspace, onComplete: {})
    .environmentObject(OnboardingWizardContext())
    .frame(width: 800, height: 600)
}
