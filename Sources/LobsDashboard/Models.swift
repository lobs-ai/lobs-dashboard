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

  var artifactPath: String?
  var notes: String?
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
