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

  /// Server URL for API calls (loaded from AppConfig)
  var serverURL: String = "http://localhost:8000"

  private var monitorTask: Task<Void, Never>? = nil

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
    // Start via API - orchestrator is now part of the server
    await apiCall(path: "/api/orchestrator/resume", method: "POST")
    await refreshStatusAndLogs()
  }

  func stop() async {
    // Pause via API
    await apiCall(path: "/api/orchestrator/pause", method: "POST")
    await refreshStatusAndLogs()
  }

  func restart() async {
    // Restart = pause + resume
    await stop()
    try? await Task.sleep(nanoseconds: 500_000_000) // 0.5s
    await start()
  }

  func setRunOnLogin(_ enabled: Bool) async {
    runOnLogin = enabled
    // This setting is now deprecated (orchestrator runs as part of server)
    // Keep the property for UI compatibility but don't act on it
  }

  // MARK: - Status / logs

  func refreshStatusAndLogs() async {
    await refreshStatus()
    await refreshUptime()
    await refreshLogs()
  }

  private func refreshStatus() async {
    // GET /api/orchestrator/status
    guard let url = URL(string: serverURL)?.appendingPathComponent("/api/orchestrator/status") else {
      status = .error(message: "Invalid server URL")
      return
    }
    
    do {
      let (data, response) = try await URLSession.shared.data(from: url)
      guard let httpResponse = response as? HTTPURLResponse else {
        status = .error(message: "Invalid response")
        return
      }
      
      if httpResponse.statusCode == 200 {
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
          let running = json["running"] as? Bool ?? false
          let paused = json["paused"] as? Bool ?? false
          
          if running && !paused {
            // Extract PID if available
            let pid = json["pid"] as? Int ?? -1
            status = .running(pid: pid)
          } else if paused {
            status = .stopped
          } else {
            status = .stopped
          }
        } else {
          status = .unknown
        }
      } else {
        status = .error(message: "Server returned \(httpResponse.statusCode)")
      }
    } catch {
      status = .error(message: error.localizedDescription)
    }
  }

  private func refreshUptime() async {
    // GET /api/orchestrator/status for uptime info
    guard let url = URL(string: serverURL)?.appendingPathComponent("/api/orchestrator/status") else {
      uptimeText = "—"
      return
    }
    
    do {
      let (data, _) = try await URLSession.shared.data(from: url)
      if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
         let uptimeSeconds = json["uptime"] as? Double {
        uptimeText = formatUptime(seconds: Int(uptimeSeconds))
      } else if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                let startTimeString = json["startTime"] as? String,
                let startTime = ISO8601DateFormatter().date(from: startTimeString) {
        uptimeText = formatUptime(since: startTime)
      } else {
        uptimeText = "—"
      }
    } catch {
      uptimeText = "—"
    }
  }

  private func refreshLogs() async {
    // Logs are now managed by the server
    // For now, we'll just show a placeholder
    lastLogText = "Logs are managed by the server. Check server logs for details."
  }

  // MARK: - API helpers
  
  private func apiCall(path: String, method: String) async {
    guard let url = URL(string: serverURL)?.appendingPathComponent(path) else {
      return
    }
    
    var request = URLRequest(url: url)
    request.httpMethod = method
    
    do {
      _ = try await URLSession.shared.data(for: request)
    } catch {
      print("⚠️ API call failed: \(error.localizedDescription)")
    }
  }

  // MARK: - Formatting

  private func formatUptime(since start: Date) -> String {
    let dt = Date().timeIntervalSince(start)
    return formatUptime(seconds: Int(dt))
  }
  
  private func formatUptime(seconds total: Int) -> String {
    if total < 0 { return "—" }

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
}
