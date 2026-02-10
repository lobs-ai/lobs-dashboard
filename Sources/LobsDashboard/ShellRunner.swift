import Foundation

/// Generic async shell runner used by onboarding and setup flows.
///
/// This is a lightweight wrapper around `Process` that executes commands via
/// `/bin/bash -lc` so that user shell PATH and command composition works.
struct ShellRunner {
  static func run(
    _ command: String,
    in directory: String? = nil
  ) async throws -> (stdout: String, stderr: String, code: Int32) {
    try await withCheckedThrowingContinuation { continuation in
      DispatchQueue.global(qos: .userInitiated).async {
        do {
          let proc = Process()
          proc.executableURL = URL(fileURLWithPath: "/bin/bash")
          proc.arguments = ["-lc", command]

          if let directory {
            proc.currentDirectoryURL = URL(fileURLWithPath: (directory as NSString).expandingTildeInPath)
          }

          proc.environment = ProcessInfo.processInfo.environment

          let out = Pipe()
          let err = Pipe()
          proc.standardOutput = out
          proc.standardError = err

          try proc.run()
          proc.waitUntilExit()

          let stdout = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
          let stderr = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""

          continuation.resume(returning: (stdout: stdout, stderr: stderr, code: proc.terminationStatus))
        } catch {
          continuation.resume(throwing: error)
        }
      }
    }
  }

  static func checkInstalled(_ command: String) async -> Bool {
    do {
      let res = try await run("/usr/bin/which \(command)")
      return res.code == 0 && !res.stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    } catch {
      return false
    }
  }
}
