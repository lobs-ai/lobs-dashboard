import Foundation
import SwiftUI

@MainActor
final class OrchestratorManager: ObservableObject {
  enum RuntimeStatus: Equatable {
    case unknown
    case starting
    case running(pid: Int)
    case stopped
    case error(message: String)

    var label: String {
      switch self {
      case .unknown: return "Unknown"
      case .starting: return "Starting…"
      case .running: return "Running"
      case .stopped: return "Stopped"
      case .error: return "Error"
      }
    }

    var isRunning: Bool {
      if case .running = self { return true }
      return false
    }

    var indicatorColor: Color {
      switch self {
      case .running: return .green
      case .starting: return .yellow
      case .stopped: return .red
      case .error: return .orange
      case .unknown: return .secondary
      }
    }
  }

  @Published private(set) var status: RuntimeStatus = .unknown
  @Published private(set) var uptimeText: String = "—"
  @Published private(set) var lastLogText: String = ""
  @Published var runOnLogin: Bool = true

  /// lobs-control repo path (used to read state files that the orchestrator writes).
  var controlRepoURL: URL? = nil

  /// Workspace containing the orchestrator repo.
  var workspacePath: String = LobsPaths.defaultWorkspace {
    didSet {
      workspacePath = (workspacePath as NSString).expandingTildeInPath
    }
  }

  private let launchAgentLabel = "com.lobs.orchestrator"
  private var monitorTask: Task<Void, Never>? = nil

  private var orchestratorURL: URL {
    URL(fileURLWithPath: workspacePath).appendingPathComponent("lobs-orchestrator")
  }

  func startMonitoring() {
    if monitorTask != nil { return }
    monitorTask = Task { [weak self] in
      guard let self else { return }
      while !Task.isCancelled {
        await self.refreshStatusAndLogs()
        try? await Task.sleep(nanoseconds: 3_000_000_000)
      }
    }
  }

  func stopMonitoring() {
    monitorTask?.cancel()
    monitorTask = nil
  }

  func start() async {
    status = .starting

    // Best-effort: ensure requirements are installed.
    _ = await Shell.envAsync("python3", ["-m", "venv", ".venv"], cwd: orchestratorURL)
    _ = await Shell.envAsync("/bin/bash", ["-lc", "source .venv/bin/activate && pip install -r requirements.txt"], cwd: orchestratorURL)

    _ = await writeLaunchAgentPlist(runAtLoad: runOnLogin)
    _ = await bootstrapLaunchAgentIfNeeded()
    _ = await Shell.envAsync("launchctl", ["kickstart", "-k", "gui/\(uid())/\(launchAgentLabel)"])

    await refreshStatusAndLogs()
  }

  func stop() async {
    _ = await Shell.envAsync("launchctl", ["bootout", "gui/\(uid())", launchAgentLabel])
    await refreshStatusAndLogs()
  }

  func restart() async {
    status = .starting
    _ = await Shell.envAsync("launchctl", ["bootout", "gui/\(uid())", launchAgentLabel])
    _ = await bootstrapLaunchAgentIfNeeded()
    _ = await Shell.envAsync("launchctl", ["kickstart", "-k", "gui/\(uid())/\(launchAgentLabel)"])
    await refreshStatusAndLogs()
  }

  func setRunOnLogin(_ enabled: Bool) async {
    runOnLogin = enabled
    _ = await writeLaunchAgentPlist(runAtLoad: enabled)
    // Reload to apply.
    _ = await Shell.envAsync("launchctl", ["bootout", "gui/\(uid())", launchAgentLabel])
    _ = await bootstrapLaunchAgentIfNeeded()
    await refreshStatusAndLogs()
  }

  // MARK: - Status / logs

  func refreshStatusAndLogs() async {
    await refreshStatus()
    await refreshUptime()
    await refreshLogs()
  }

  private func refreshStatus() async {
    let res = await Shell.envAsync("launchctl", ["print", "gui/\(uid())/\(launchAgentLabel)"])
    guard res.ok else {
      status = .stopped
      return
    }

    let out = res.stdout
    if out.contains("state = running") {
      if let pid = parsePID(fromLaunchctlPrint: out) {
        status = .running(pid: pid)
      } else {
        status = .running(pid: -1)
      }
    } else if out.contains("state = waiting") || out.contains("state = starting") {
      status = .starting
    } else {
      // Installed but not running.
      status = .stopped
    }
  }

  private func refreshUptime() async {
    guard case .running(let pid) = status, pid > 0 else {
      uptimeText = "—"
      return
    }

    let ps = await Shell.envAsync("ps", ["-p", "\(pid)", "-o", "lstart="])
    guard ps.ok else {
      uptimeText = "—"
      return
    }

    let raw = ps.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let start = parsePSStart(raw) else {
      uptimeText = "—"
      return
    }

    uptimeText = formatUptime(since: start)
  }

  private func refreshLogs() async {
    let text = readRecentOrchestratorLogs(maxLines: 50)
    lastLogText = text
  }

  // MARK: - LaunchAgent helpers

  private func uid() -> String {
    let res = try? Shell.run("/usr/bin/id", ["-u"])
    let s = res?.stdout.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return s.isEmpty ? "" : s
  }

  private func writeLaunchAgentPlist(runAtLoad: Bool) async -> String {
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
        <\(runAtLoad ? "true" : "false")/>
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
    let domain = "gui/\(uid())"
    let plistPath = FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent("Library/LaunchAgents")
      .appendingPathComponent("\(launchAgentLabel).plist").path

    let boot = await Shell.envAsync("launchctl", ["bootstrap", domain, plistPath])
    if boot.ok { return boot }

    _ = await Shell.envAsync("launchctl", ["bootout", domain, launchAgentLabel])
    return await Shell.envAsync("launchctl", ["bootstrap", domain, plistPath])
  }

  // MARK: - Parsing / formatting

  private func parsePID(fromLaunchctlPrint s: String) -> Int? {
    // launchctl print output often contains: "pid = 123"
    guard let r = s.range(of: "pid = ") else { return nil }
    let tail = s[r.upperBound...]
    let digits = tail.prefix { $0.isNumber }
    return Int(digits)
  }

  private func parsePSStart(_ s: String) -> Date? {
    // Example: "Mon Jan  8 12:34:56 2024"
    let fmt = DateFormatter()
    fmt.locale = Locale(identifier: "en_US_POSIX")
    fmt.timeZone = TimeZone.current
    fmt.dateFormat = "EEE MMM d HH:mm:ss yyyy"

    // ps can emit two spaces for single-digit day; DateFormatter w/ "d" should still parse.
    let normalized = s.replacingOccurrences(of: "  ", with: " ")
    return fmt.date(from: normalized)
  }

  private func formatUptime(since start: Date) -> String {
    let dt = Date().timeIntervalSince(start)
    if dt < 0 { return "—" }

    let total = Int(dt)
    let days = total / 86_400
    let hours = (total % 86_400) / 3_600
    let mins = (total % 3_600) / 60

    if days > 0 {
      return "\(days)d \(hours)h \(mins)m"
    }
    if hours > 0 {
      return "\(hours)h \(mins)m"
    }
    return "\(mins)m"
  }

  private func readRecentOrchestratorLogs(maxLines: Int) -> String {
    let fm = FileManager.default
    let logsDir = fm.homeDirectoryForCurrentUser
      .appendingPathComponent(".openclaw")
      .appendingPathComponent("logs")

    var candidates: [URL] = []

    if fm.fileExists(atPath: logsDir.path) {
      if let items = try? fm.contentsOfDirectory(at: logsDir, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles]) {
        candidates.append(contentsOf: items.filter { $0.pathExtension.lowercased() == "log" })
      }
    }

    // Fallback to legacy path used by older onboarding.
    let legacy = LobsPaths.appSupport.appendingPathComponent("orchestrator.log")
    if fm.fileExists(atPath: legacy.path) {
      candidates.append(legacy)
    }

    guard !candidates.isEmpty else { return "" }

    let newest = candidates.max { a, b in
      let da = (try? a.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
      let db = (try? b.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
      return da < db
    } ?? candidates[0]

    guard let content = try? String(contentsOf: newest, encoding: .utf8) else { return "" }

    let lines = content.split(separator: "\n", omittingEmptySubsequences: false)
    if lines.count <= maxLines {
      return content
    }

    let tail = lines.suffix(maxLines).joined(separator: "\n")
    return String(tail)
  }
}
