import Foundation

/// Git operation errors with user-friendly messages
enum GitError: Error, LocalizedError {
  case networkUnreachable
  case authenticationFailed
  case mergeConflict
  case repositoryNotFound
  case permissionDenied
  case invalidRepository
  case uncommittedChanges
  case remoteRejected
  case unknownError(String)
  
  /// User-friendly error message
  var errorDescription: String? {
    switch self {
    case .networkUnreachable:
      return "Unable to connect. Check your internet connection."
    case .authenticationFailed:
      return "Authentication failed. Check your SSH keys or credentials."
    case .mergeConflict:
      return "Sync conflict detected. Local and remote changes conflict."
    case .repositoryNotFound:
      return "Repository not found. Check the URL."
    case .permissionDenied:
      return "Permission denied. Check your repository access."
    case .invalidRepository:
      return "Invalid repository. The directory is not a git repository."
    case .uncommittedChanges:
      return "You have uncommitted changes that would be overwritten."
    case .remoteRejected:
      return "Push rejected. The remote has newer changes."
    case .unknownError(let message):
      return "Git error: \(message)"
    }
  }
  
  /// Detailed technical message for logging
  var technicalMessage: String {
    switch self {
    case .networkUnreachable:
      return "Network unreachable - could not connect to remote"
    case .authenticationFailed:
      return "Authentication failed - invalid credentials or SSH key"
    case .mergeConflict:
      return "Merge conflict - conflicting changes between local and remote"
    case .repositoryNotFound:
      return "Repository not found - invalid URL or repository deleted"
    case .permissionDenied:
      return "Permission denied - insufficient access rights"
    case .invalidRepository:
      return "Invalid repository - not a git repository"
    case .uncommittedChanges:
      return "Uncommitted changes - would be overwritten by operation"
    case .remoteRejected:
      return "Remote rejected - push failed due to newer remote commits"
    case .unknownError(let message):
      return "Unknown error: \(message)"
    }
  }
  
  /// Whether this error is recoverable with retry
  var isRetryable: Bool {
    switch self {
    case .networkUnreachable, .remoteRejected:
      return true
    case .authenticationFailed, .mergeConflict, .repositoryNotFound, 
         .permissionDenied, .invalidRepository, .uncommittedChanges, .unknownError:
      return false
    }
  }
  
  /// Whether this error suggests pull-before-push
  var suggestsPull: Bool {
    switch self {
    case .remoteRejected, .mergeConflict:
      return true
    default:
      return false
    }
  }
  
  /// Parse git output to determine error type
  static func parse(stderr: String, exitCode: Int32) -> GitError {
    let lower = stderr.lowercased()
    
    // Network errors
    if lower.contains("could not resolve host") ||
       lower.contains("failed to connect") ||
       lower.contains("network is unreachable") ||
       lower.contains("temporary failure in name resolution") {
      return .networkUnreachable
    }
    
    // Authentication errors
    if lower.contains("permission denied (publickey)") ||
       lower.contains("authentication failed") ||
       lower.contains("could not read from remote repository") ||
       lower.contains("fatal: unable to access") && lower.contains("401") {
      return .authenticationFailed
    }
    
    // Repository not found
    if lower.contains("repository not found") ||
       lower.contains("repository '") && lower.contains("' not found") ||
       lower.contains("fatal: unable to access") && lower.contains("404") {
      return .repositoryNotFound
    }
    
    // Permission denied
    if lower.contains("permission denied") ||
       lower.contains("fatal: unable to access") && lower.contains("403") {
      return .permissionDenied
    }
    
    // Merge conflicts
    if lower.contains("conflict") ||
       lower.contains("merge conflict") ||
       lower.contains("automatic merge failed") {
      return .mergeConflict
    }
    
    // Invalid repository
    if lower.contains("not a git repository") ||
       lower.contains("fatal: not a git repository") {
      return .invalidRepository
    }
    
    // Uncommitted changes
    if lower.contains("would be overwritten") ||
       lower.contains("your local changes to the following files would be overwritten") {
      return .uncommittedChanges
    }
    
    // Remote rejected
    if lower.contains("rejected") ||
       lower.contains("failed to push") ||
       lower.contains("! [rejected]") ||
       lower.contains("updates were rejected") {
      return .remoteRejected
    }
    
    // Unknown error
    return .unknownError(stderr.trimmingCharacters(in: .whitespacesAndNewlines))
  }
}

/// Result type for git operations with retry support
struct GitOperationResult {
  var success: Bool
  var output: String
  var error: GitError?
  var canRetry: Bool
  var suggestsPull: Bool
  
  static func success(output: String) -> GitOperationResult {
    GitOperationResult(
      success: true,
      output: output,
      error: nil,
      canRetry: false,
      suggestsPull: false
    )
  }
  
  static func failure(error: GitError, output: String = "") -> GitOperationResult {
    GitOperationResult(
      success: false,
      output: output,
      error: error,
      canRetry: error.isRetryable,
      suggestsPull: error.suggestsPull
    )
  }
}
