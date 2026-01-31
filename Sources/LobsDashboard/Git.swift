import Foundation

struct Git {
  struct Result {
    var exitCode: Int32
    var stdout: String
    var stderr: String

    var ok: Bool { exitCode == 0 }
  }

  static func run(_ args: [String], cwd: URL, env: [String: String] = [:]) throws -> Result {
    let proc = Process()
    proc.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    proc.arguments = ["git"] + args
    proc.currentDirectoryURL = cwd

    // Merge env vars (callsite can override things like committer identity).
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

    return .init(exitCode: proc.terminationStatus, stdout: stdout, stderr: stderr)
  }
}
