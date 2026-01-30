import Foundation

struct Git {
  struct Result {
    var exitCode: Int32
    var stdout: String
    var stderr: String

    var ok: Bool { exitCode == 0 }
  }

  static func run(_ args: [String], cwd: URL) throws -> Result {
    let proc = Process()
    proc.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    proc.arguments = ["git"] + args
    proc.currentDirectoryURL = cwd

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
