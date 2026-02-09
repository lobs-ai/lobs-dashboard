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

  /// Run a git command off the main thread. Returns the result asynchronously.
  static func runAsync(_ args: [String], cwd: URL, env: [String: String] = [:]) async throws -> Result {
    try await withCheckedThrowingContinuation { continuation in
      DispatchQueue.global(qos: .userInitiated).async {
        do {
          let result = try run(args, cwd: cwd, env: env)
          continuation.resume(returning: result)
        } catch {
          continuation.resume(throwing: error)
        }
      }
    }
  }
  
  // MARK: - Enhanced Error Handling
  
  /// Run a git command with enhanced error handling and user-friendly messages
  static func runWithErrorHandling(_ args: [String], cwd: URL, env: [String: String] = [:]) -> GitOperationResult {
    do {
      let result = try run(args, cwd: cwd, env: env)
      
      if result.ok {
        return .success(output: result.stdout)
      } else {
        let error = GitError.parse(stderr: result.stderr, exitCode: result.exitCode)
        logGitError(command: args.joined(separator: " "), error: error, stderr: result.stderr)
        return .failure(error: error, output: result.stdout)
      }
    } catch {
      let gitError = GitError.unknownError(error.localizedDescription)
      logGitError(command: args.joined(separator: " "), error: gitError, stderr: error.localizedDescription)
      return .failure(error: gitError)
    }
  }
  
  /// Run a git command asynchronously with enhanced error handling
  static func runAsyncWithErrorHandling(_ args: [String], cwd: URL, env: [String: String] = [:]) async -> GitOperationResult {
    await withCheckedContinuation { continuation in
      DispatchQueue.global(qos: .userInitiated).async {
        let result = runWithErrorHandling(args, cwd: cwd, env: env)
        continuation.resume(returning: result)
      }
    }
  }
  
  /// Retry a git operation with exponential backoff
  static func runWithRetry(
    _ args: [String],
    cwd: URL,
    env: [String: String] = [:],
    maxRetries: Int = 3,
    initialDelay: TimeInterval = 1.0
  ) async -> GitOperationResult {
    var attempt = 0
    var delay = initialDelay
    
    while attempt < maxRetries {
      let result = await runAsyncWithErrorHandling(args, cwd: cwd, env: env)
      
      if result.success {
        return result
      }
      
      // Only retry if the error is retryable
      guard let error = result.error, error.isRetryable else {
        return result
      }
      
      attempt += 1
      if attempt < maxRetries {
        print("Git operation failed (attempt \(attempt)/\(maxRetries)), retrying in \(delay)s...")
        try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        delay *= 2 // Exponential backoff
      }
    }
    
    // Return the last result after exhausting retries
    return await runAsyncWithErrorHandling(args, cwd: cwd, env: env)
  }
  
  // MARK: - Logging
  
  /// Log git errors for debugging
  private static func logGitError(command: String, error: GitError, stderr: String) {
    print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
    print("GIT ERROR")
    print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
    print("Command: git \(command)")
    print("Type: \(error.technicalMessage)")
    print("User Message: \(error.errorDescription ?? "Unknown error")")
    print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
    print("Raw stderr:")
    print(stderr)
    print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
  }
}
