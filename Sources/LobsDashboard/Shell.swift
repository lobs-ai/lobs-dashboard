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
    env: [String: String] = [:]
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

    try proc.run()
    proc.waitUntilExit()

    let stdout = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    let stderr = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""

    return Result(exitCode: proc.terminationStatus, stdout: stdout, stderr: stderr)
  }

  static func runAsync(
    _ launchPath: String,
    _ args: [String] = [],
    cwd: URL? = nil,
    env: [String: String] = [:]
  ) async -> Result {
    await withCheckedContinuation { continuation in
      DispatchQueue.global(qos: .userInitiated).async {
        do {
          let res = try run(launchPath, args, cwd: cwd, env: env)
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
    env: [String: String] = [:]
  ) async -> Result {
    await runAsync("/usr/bin/env", [command] + args, cwd: cwd, env: env)
  }

  static func which(_ command: String) async -> String? {
    let res = await envAsync("which", [command])
    guard res.ok else { return nil }
    let path = res.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    return path.isEmpty ? nil : path
  }
}
