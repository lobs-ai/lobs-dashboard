import Foundation

/// Validates and initializes the control repository structure
final class ControlRepoValidator {
  
  // MARK: - Types
  
  struct ValidationResult {
    var isValid: Bool
    var issues: [Issue]
    var created: [String]  // Paths that were created during initialization
    
    init(isValid: Bool = true, issues: [Issue] = [], created: [String] = []) {
      self.isValid = isValid
      self.issues = issues
      self.created = created
    }
  }
  
  enum Issue: Equatable {
    case missingDirectory(String)
    case missingFile(String)
    case invalidJson(String, Error)
    case created(String)  // Informational: path was created
    
    var description: String {
      switch self {
      case .missingDirectory(let path):
        return "Missing directory: \(path)"
      case .missingFile(let path):
        return "Missing file: \(path)"
      case .invalidJson(let path, let error):
        return "Invalid JSON in \(path): \(error.localizedDescription)"
      case .created(let path):
        return "Created: \(path)"
      }
    }
    
    static func == (lhs: Issue, rhs: Issue) -> Bool {
      switch (lhs, rhs) {
      case (.missingDirectory(let a), .missingDirectory(let b)),
           (.missingFile(let a), .missingFile(let b)),
           (.created(let a), .created(let b)):
        return a == b
      case (.invalidJson(let pathA, _), .invalidJson(let pathB, _)):
        return pathA == pathB
      default:
        return false
      }
    }
  }
  
  // MARK: - Validation
  
  /// Validate the control repository structure without making changes
  func validate(repoPath: String) -> ValidationResult {
    let fm = FileManager.default
    let repoURL = URL(fileURLWithPath: repoPath)
    
    var issues: [Issue] = []
    
    // Check state directory
    let stateURL = repoURL.appendingPathComponent("state")
    if !fm.fileExists(atPath: stateURL.path) {
      issues.append(.missingDirectory("state"))
    }
    
    // Check state/tasks directory
    let tasksURL = stateURL.appendingPathComponent("tasks")
    if !fm.fileExists(atPath: tasksURL.path) {
      issues.append(.missingDirectory("state/tasks"))
    }
    
    // Check state/projects.json
    let projectsURL = stateURL.appendingPathComponent("projects.json")
    if !fm.fileExists(atPath: projectsURL.path) {
      issues.append(.missingFile("state/projects.json"))
    } else {
      // Validate JSON structure
      do {
        let data = try Data(contentsOf: projectsURL)
        _ = try JSONSerialization.jsonObject(with: data)
      } catch {
        issues.append(.invalidJson("state/projects.json", error))
      }
    }
    
    // Check state/worker-status.json
    let workerStatusURL = stateURL.appendingPathComponent("worker-status.json")
    if !fm.fileExists(atPath: workerStatusURL.path) {
      issues.append(.missingFile("state/worker-status.json"))
    } else {
      // Validate JSON structure
      do {
        let data = try Data(contentsOf: workerStatusURL)
        _ = try JSONSerialization.jsonObject(with: data)
      } catch {
        issues.append(.invalidJson("state/worker-status.json", error))
      }
    }
    
    let isValid = issues.isEmpty
    return ValidationResult(isValid: isValid, issues: issues, created: [])
  }
  
  // MARK: - Initialization
  
  /// Initialize the control repository structure, creating missing files and directories
  func initialize(repoPath: String) -> ValidationResult {
    let fm = FileManager.default
    let repoURL = URL(fileURLWithPath: repoPath)
    
    var issues: [Issue] = []
    var created: [String] = []
    
    // Create state directory if missing
    let stateURL = repoURL.appendingPathComponent("state")
    if !fm.fileExists(atPath: stateURL.path) {
      do {
        try fm.createDirectory(at: stateURL, withIntermediateDirectories: true)
        created.append("state")
        issues.append(.created("state"))
      } catch {
        issues.append(.missingDirectory("state"))
      }
    }
    
    // Create state/tasks directory if missing
    let tasksURL = stateURL.appendingPathComponent("tasks")
    if !fm.fileExists(atPath: tasksURL.path) {
      do {
        try fm.createDirectory(at: tasksURL, withIntermediateDirectories: true)
        created.append("state/tasks")
        issues.append(.created("state/tasks"))
      } catch {
        issues.append(.missingDirectory("state/tasks"))
      }
    }
    
    // Create state/projects.json if missing
    let projectsURL = stateURL.appendingPathComponent("projects.json")
    if !fm.fileExists(atPath: projectsURL.path) {
      do {
        let defaultProjects = createDefaultProjectsJSON()
        try defaultProjects.write(to: projectsURL, atomically: true, encoding: .utf8)
        created.append("state/projects.json")
        issues.append(.created("state/projects.json"))
      } catch {
        issues.append(.missingFile("state/projects.json"))
      }
    } else {
      // Validate existing JSON
      do {
        let data = try Data(contentsOf: projectsURL)
        _ = try JSONSerialization.jsonObject(with: data)
      } catch {
        issues.append(.invalidJson("state/projects.json", error))
      }
    }
    
    // Create state/worker-status.json if missing
    let workerStatusURL = stateURL.appendingPathComponent("worker-status.json")
    if !fm.fileExists(atPath: workerStatusURL.path) {
      do {
        let defaultStatus = createDefaultWorkerStatusJSON()
        try defaultStatus.write(to: workerStatusURL, atomically: true, encoding: .utf8)
        created.append("state/worker-status.json")
        issues.append(.created("state/worker-status.json"))
      } catch {
        issues.append(.missingFile("state/worker-status.json"))
      }
    } else {
      // Validate existing JSON
      do {
        let data = try Data(contentsOf: workerStatusURL)
        _ = try JSONSerialization.jsonObject(with: data)
      } catch {
        issues.append(.invalidJson("state/worker-status.json", error))
      }
    }
    
    // Only mark as valid if no errors (created items don't count as errors)
    let hasErrors = issues.contains { issue in
      switch issue {
      case .created:
        return false
      default:
        return true
      }
    }
    
    let isValid = !hasErrors
    return ValidationResult(isValid: isValid, issues: issues, created: created)
  }
  
  // MARK: - Default Content Generation
  
  private func createDefaultProjectsJSON() -> String {
    let now = ISO8601DateFormatter().string(from: Date())
    
    return """
    {
      "projects": [
        {
          "id": "default",
          "title": "Default",
          "sortOrder": 0,
          "archived": false,
          "createdAt": "\(now)",
          "updatedAt": "\(now)"
        }
      ]
    }
    """
  }
  
  private func createDefaultWorkerStatusJSON() -> String {
    return """
    {
      "active": false,
      "currentTask": null,
      "lastHeartbeat": null
    }
    """
  }
}
