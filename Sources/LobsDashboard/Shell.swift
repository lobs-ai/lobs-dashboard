import Foundation

/// Simple shell/process runner for onboarding and tooling checks.
enum Shell {
  struct Result {
    var exitCode: Int32
    var stdout: String
    var stderr: String

    var ok: Bool { exitCode == 0 }
  }

  static func run(
    _ launchPath: String,
    _ args: [String] = [],
    cwd: URL? = nil,
    env: [String: String] = [:],
    timeoutSeconds: Double? = nil
  ) throws -> Result {
    let proc = Process()
    proc.executableURL = URL(fileURLWithPath: launchPath)
    proc.arguments = args
    proc.currentDirectoryURL = cwd

    var merged = ProcessInfo.processInfo.environment
    for (k, v) in env { merged[k] = v }
    proc.environment = merged

    let out = Pipe()
    let err = Pipe()
    proc.standardOutput = out
    proc.standardError = err

    var didTimeout = false
    var timer: DispatchSourceTimer? = nil

    if let timeoutSeconds, timeoutSeconds > 0 {
      let t = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .userInitiated))
      t.schedule(deadline: .now() + timeoutSeconds)
      t.setEventHandler {
        if proc.isRunning {
          didTimeout = true
          proc.terminate()
        }
      }
      t.resume()
      timer = t
    }

    try proc.run()
    proc.waitUntilExit()
    timer?.cancel()

    let stdout = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    let stderrRaw = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    let stderr = didTimeout ? (stderrRaw + (stderrRaw.isEmpty ? "" : "\n") + "Timed out after \(timeoutSeconds ?? 0)s") : stderrRaw

    return Result(exitCode: didTimeout ? 124 : proc.terminationStatus, stdout: stdout, stderr: stderr)
  }

  static func runAsync(
    _ launchPath: String,
    _ args: [String] = [],
    cwd: URL? = nil,
    env: [String: String] = [:],
    timeoutSeconds: Double? = nil
  ) async -> Result {
    await withCheckedContinuation { continuation in
      DispatchQueue.global(qos: .userInitiated).async {
        do {
          let res = try run(launchPath, args, cwd: cwd, env: env, timeoutSeconds: timeoutSeconds)
          continuation.resume(returning: res)
        } catch {
          continuation.resume(returning: Result(exitCode: 1, stdout: "", stderr: String(describing: error)))
        }
      }
    }
  }

  /// Runs a command via /usr/bin/env so PATH resolution works.
  static func envAsync(
    _ command: String,
    _ args: [String] = [],
    cwd: URL? = nil,
    env: [String: String] = [:],
    timeoutSeconds: Double? = nil
  ) async -> Result {
    await runAsync("/usr/bin/env", [command] + args, cwd: cwd, env: env, timeoutSeconds: timeoutSeconds)
  }

  static func which(_ command: String) async -> String? {
    let res = await envAsync("which", [command])
    guard res.ok else { return nil }
    let path = res.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    return path.isEmpty ? nil : path
  }
}
