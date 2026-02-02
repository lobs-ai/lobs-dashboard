import Foundation

enum TaskStatus: Hashable, Codable {
  case inbox
  case active
  case completed
  case rejected
  case waitingOn
  case other(String)

  var rawValue: String {
    switch self {
    case .inbox: return "inbox"
    case .active: return "active"
    case .completed: return "completed"
    case .rejected: return "rejected"
    case .waitingOn: return "waiting_on"
    case .other(let value): return value
    }
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    let value = try container.decode(String.self)
    switch value {
    case "inbox": self = .inbox
    case "active": self = .active
    case "completed": self = .completed
    case "rejected": self = .rejected
    case "waiting_on": self = .waitingOn
    default: self = .other(value)
    }
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(rawValue)
  }
}

enum WorkState: Hashable, Codable {
  case notStarted
  case inProgress
  case blocked
  case other(String)

  var rawValue: String {
    switch self {
    case .notStarted: return "not_started"
    case .inProgress: return "in_progress"
    case .blocked: return "blocked"
    case .other(let value): return value
    }
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    let value = try container.decode(String.self)
    switch value {
    case "not_started": self = .notStarted
    case "in_progress": self = .inProgress
    case "blocked": self = .blocked
    default: self = .other(value)
    }
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(rawValue)
  }
}

enum ReviewState: Hashable, Codable {
  case pending
  case approved
  case changesRequested
  case rejected
  case other(String)

  var rawValue: String {
    switch self {
    case .pending: return "pending"
    case .approved: return "approved"
    case .changesRequested: return "changes_requested"
    case .rejected: return "rejected"
    case .other(let value): return value
    }
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    let value = try container.decode(String.self)
    switch value {
    case "pending": self = .pending
    case "approved": self = .approved
    case "changes_requested": self = .changesRequested
    case "rejected": self = .rejected
    default: self = .other(value)
    }
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(rawValue)
  }
}

enum TaskOwner: Hashable, Codable {
  case lobs
  case rafe
  case other(String)

  var rawValue: String {
    switch self {
    case .lobs: return "lobs"
    case .rafe: return "rafe"
    case .other(let value): return value
    }
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    let value = try container.decode(String.self)
    switch value {
    case "lobs": self = .lobs
    case "rafe": self = .rafe
    default: self = .other(value)
    }
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(rawValue)
  }
}

struct DashboardTask: Codable, Identifiable, Hashable {
  var id: String
  var title: String

  /// Workflow status for the task itself (drives the Kanban columns: inbox/active/waiting_on/completed/etc).
  ///
  /// Important: `status=completed` means the task is done from a workflow perspective.
  /// It does *not* imply the artifact has been approved.
  var status: TaskStatus

  var owner: TaskOwner
  var createdAt: Date
  var updatedAt: Date

  // Optional fields (schema evolves)

  /// Whether work has started / is in progress / is blocked.
  var workState: WorkState?

  /// Review state for the produced artifact (pending/approved/changes_requested/etc).
  /// This is intentionally separate from `status` so you can approve without completing (or vice versa).
  var reviewState: ReviewState?

  /// Project/workstream this task belongs to. Missing implies "default".
  var projectId: String?

  var artifactPath: String?
  var notes: String?
}

enum ProjectType: String, Codable, CaseIterable, Hashable {
  case kanban
  case research
  case tracker
}

struct Project: Codable, Identifiable, Hashable {
  var id: String
  var title: String
  var createdAt: Date
  var updatedAt: Date
  var notes: String?
  var archived: Bool?
  var type: ProjectType?

  /// Resolved type (defaults to kanban for backwards compatibility).
  var resolvedType: ProjectType { type ?? .kanban }
}

// MARK: - Research Tile Types

enum ResearchTileType: String, Codable, CaseIterable, Hashable {
  case link
  case note
  case finding
  case comparison
}

enum ResearchTileStatus: String, Codable, Hashable {
  case active
  case archived
}

struct ResearchTile: Codable, Identifiable, Hashable {
  var id: String
  var projectId: String
  var type: ResearchTileType
  var title: String
  var tags: [String]?
  var status: ResearchTileStatus?
  var author: String?   // "rafe" or "lobs"
  var createdAt: Date
  var updatedAt: Date

  // Link tile fields
  var url: String?
  var summary: String?
  var snapshot: String?

  // Note tile fields
  var content: String?

  // Finding tile fields
  var claim: String?
  var confidence: Double?
  var evidence: [String]?
  var counterpoints: [String]?

  // Comparison tile fields
  var options: [ComparisonOption]?

  var resolvedStatus: ResearchTileStatus { status ?? .active }
}

struct ComparisonOption: Codable, Hashable {
  var name: String
  var pros: [String]?
  var cons: [String]?
  var cost: String?
  var risk: String?
  var notes: String?
}

// MARK: - Research Requests

enum ResearchRequestStatus: String, Codable, Hashable {
  case open
  case inProgress = "in_progress"
  case done
  case blocked
}

struct ResearchRequest: Codable, Identifiable, Hashable {
  var id: String
  var projectId: String
  var tileId: String?       // If attached to a specific tile
  var prompt: String
  var status: ResearchRequestStatus
  var response: String?
  var author: String?       // who created the request
  var createdAt: Date
  var updatedAt: Date
}

// MARK: - Inbox Item (Design Docs)

struct InboxItem: Identifiable, Hashable {
  var id: String          // e.g. "inbox/foo.md" or "artifacts/bar.md"
  var title: String       // derived from filename or first heading
  var filename: String
  var relativePath: String
  var content: String
  var modifiedAt: Date
  var isRead: Bool        // tracked locally
  var summary: String     // first ~200 chars or first paragraph
}

struct InboxResponse: Codable, Identifiable, Hashable {
  var id: String
  var docId: String
  var response: String
  var createdAt: Date
  var updatedAt: Date
}

// MARK: - Inbox Thread (threaded conversations per document)

struct InboxThreadMessage: Codable, Identifiable, Hashable {
  var id: String
  var author: String   // "rafe" or "lobs"
  var text: String
  var createdAt: Date
}

struct InboxThread: Codable, Identifiable, Hashable {
  var id: String       // same as docId
  var docId: String
  var messages: [InboxThreadMessage]
  var createdAt: Date
  var updatedAt: Date
}

struct ProjectsFile: Codable {
  var schemaVersion: Int
  var generatedAt: Date
  var projects: [Project]
}

struct TasksFile: Codable {
  var schemaVersion: Int
  var generatedAt: Date
  var tasks: [DashboardTask]
}

struct RemindersFile: Codable {
  var schemaVersion: Int
  var generatedAt: Date
  var reminders: [Reminder]
}

struct Reminder: Codable, Identifiable, Hashable {
  var id: String
  var title: String
  var dueAt: Date
}

// MARK: - Tracker Items

enum TrackerItemStatus: String, Codable, CaseIterable, Hashable {
  case notStarted = "not_started"
  case inProgress = "in_progress"
  case done
  case skipped
}

struct TrackerItem: Codable, Identifiable, Hashable {
  var id: String
  var projectId: String
  var title: String
  var status: TrackerItemStatus
  var difficulty: String?    // e.g. "Easy", "Medium", "Hard" or custom
  var tags: [String]?
  var notes: String?
  var links: [String]?
  var createdAt: Date
  var updatedAt: Date
}
