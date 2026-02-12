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

/// Task shape/type classification for filtering by work mode.
enum TaskShape: String, Codable, Hashable, CaseIterable {
  case deep = "deep"           // Deep work — focused, uninterrupted effort
  case shallow = "shallow"     // Quick tasks, emails, admin
  case creative = "creative"   // Design, brainstorming, open-ended
  case waiting = "waiting"     // Blocked on someone/something external
  case admin = "admin"         // Organizational, process, logistics
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

  // Custom decoding to handle legacy tasks missing createdAt or owner
  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)

    id = try container.decode(String.self, forKey: .id)
    title = try container.decode(String.self, forKey: .title)
    status = try container.decode(TaskStatus.self, forKey: .status)
    updatedAt = try container.decode(Date.self, forKey: .updatedAt)

    // Default owner to "lobs" if missing (legacy tasks)
    owner = (try? container.decode(TaskOwner.self, forKey: .owner)) ?? .lobs

    // Default createdAt to updatedAt if missing (legacy tasks)
    createdAt = (try? container.decode(Date.self, forKey: .createdAt)) ?? updatedAt

    // Optional fields
    workState = try? container.decode(WorkState.self, forKey: .workState)
    reviewState = try? container.decode(ReviewState.self, forKey: .reviewState)
    projectId = try? container.decode(String.self, forKey: .projectId)
    artifactPath = try? container.decode(String.self, forKey: .artifactPath)
    notes = try? container.decode(String.self, forKey: .notes)
    startedAt = try? container.decode(Date.self, forKey: .startedAt)
    finishedAt = try? container.decode(Date.self, forKey: .finishedAt)
    sortOrder = try? container.decode(Int.self, forKey: .sortOrder)
    blockedBy = try? container.decode([String].self, forKey: .blockedBy)
    pinned = try? container.decode(Bool.self, forKey: .pinned)
    shape = try? container.decode(TaskShape.self, forKey: .shape)
    githubIssueNumber = try? container.decode(Int.self, forKey: .githubIssueNumber)
  }

  private enum CodingKeys: String, CodingKey {
    case id, title, status, owner, createdAt, updatedAt
    case workState, reviewState, projectId, artifactPath, notes
    case startedAt, finishedAt, sortOrder, blockedBy, pinned, shape, githubIssueNumber
  }

  // Memberwise initializer for creating tasks programmatically
  init(
    id: String,
    title: String,
    status: TaskStatus,
    owner: TaskOwner,
    createdAt: Date,
    updatedAt: Date,
    workState: WorkState? = nil,
    reviewState: ReviewState? = nil,
    projectId: String? = nil,
    artifactPath: String? = nil,
    notes: String? = nil,
    startedAt: Date? = nil,
    finishedAt: Date? = nil,
    sortOrder: Int? = nil,
    blockedBy: [String]? = nil,
    pinned: Bool? = nil,
    shape: TaskShape? = nil,
    githubIssueNumber: Int? = nil
  ) {
    self.id = id
    self.title = title
    self.status = status
    self.owner = owner
    self.createdAt = createdAt
    self.updatedAt = updatedAt
    self.workState = workState
    self.reviewState = reviewState
    self.projectId = projectId
    self.artifactPath = artifactPath
    self.notes = notes
    self.startedAt = startedAt
    self.finishedAt = finishedAt
    self.sortOrder = sortOrder
    self.blockedBy = blockedBy
    self.pinned = pinned
    self.shape = shape
    self.githubIssueNumber = githubIssueNumber
  }

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

  /// Lightweight time tracking
  var startedAt: Date?
  var finishedAt: Date?

  /// Manual sort order within a column (lower = higher priority)
  var sortOrder: Int?

  /// Task IDs this task is blocked by. When all blockers complete, the task auto-unblocks.
  var blockedBy: [String]?

  /// Whether this task is pinned/starred (floats to top of its column).
  var pinned: Bool?

  /// Work shape/type for filtering (deep work, shallow, creative, admin, waiting).
  var shape: TaskShape?

  /// GitHub issue number (when project syncMode is .github).
  var githubIssueNumber: Int?
}

enum ProjectType: String, Codable, CaseIterable, Hashable {
  case kanban
  case research
  case tracker
}

/// Tracking mode for project task storage.
enum TrackingMode: String, Codable, CaseIterable, Hashable {
  case local   // Tasks stored in local JSON files
  case github  // Tasks synced with GitHub Issues
}

/// GitHub configuration for project tracking.
struct GitHubProjectConfig: Codable, Hashable {
  var repo: String             // GitHub repo in 'owner/repo' format
  var labelFilter: [String]?   // Optional labels to filter issues
  
  // Legacy support for old format
  enum CodingKeys: String, CodingKey {
    case repo
    case labelFilter
    case owner      // legacy
    case repoName = "repoName"  // legacy
    case accessToken  // legacy
    case syncLabels   // legacy
  }
  
  init(repo: String, labelFilter: [String]? = nil) {
    self.repo = repo
    self.labelFilter = labelFilter
  }
  
  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    
    // Try new format first
    if let repo = try? container.decode(String.self, forKey: .repo) {
      self.repo = repo
      self.labelFilter = try? container.decode([String].self, forKey: .labelFilter)
    }
    // Fall back to legacy format
    else if let owner = try? container.decode(String.self, forKey: .owner),
            let repoName = try? container.decode(String.self, forKey: .repoName) {
      self.repo = "\(owner)/\(repoName)"
      // Map legacy syncLabels to labelFilter
      self.labelFilter = try? container.decode([String].self, forKey: .syncLabels)
    } else {
      throw DecodingError.dataCorruptedError(
        forKey: .repo,
        in: container,
        debugDescription: "Missing required 'repo' field or legacy 'owner'/'repoName' fields"
      )
    }
  }
  
  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(repo, forKey: .repo)
    try container.encodeIfPresent(labelFilter, forKey: .labelFilter)
  }
}

/// Legacy type alias for backward compatibility
typealias SyncMode = TrackingMode
typealias GitHubConfig = GitHubProjectConfig

struct Project: Codable, Identifiable, Hashable {
  var id: String
  var title: String
  var createdAt: Date
  var updatedAt: Date
  var notes: String?
  var archived: Bool?
  var type: ProjectType?

  /// Manual sort order (lower = higher in list). Nil means unsorted (append to end).
  var sortOrder: Int?

  /// Tracking mode for task storage (local JSON or GitHub Issues). Defaults to local.
  var tracking: TrackingMode?
  
  /// GitHub configuration (required when tracking is .github).
  var github: GitHubProjectConfig?
  
  // Legacy field support for backward compatibility
  var syncMode: TrackingMode? {
    get { tracking }
    set { tracking = newValue }
  }
  
  var githubConfig: GitHubProjectConfig? {
    get { github }
    set { github = newValue }
  }

  /// Resolved type (defaults to kanban for backwards compatibility).
  var resolvedType: ProjectType { type ?? .kanban }

  /// Resolved tracking mode (defaults to local for backwards compatibility).
  var resolvedTracking: TrackingMode { tracking ?? .local }
  
  /// Legacy accessor for backward compatibility
  var resolvedSyncMode: TrackingMode { resolvedTracking }
  
  enum CodingKeys: String, CodingKey {
    case id, title, createdAt, updatedAt, notes, archived, type, sortOrder
    case tracking, github
    case syncMode, githubConfig  // legacy keys
  }
  
  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    
    id = try container.decode(String.self, forKey: .id)
    title = try container.decode(String.self, forKey: .title)
    createdAt = try container.decode(Date.self, forKey: .createdAt)
    updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    notes = try? container.decode(String.self, forKey: .notes)
    archived = try? container.decode(Bool.self, forKey: .archived)
    type = try? container.decode(ProjectType.self, forKey: .type)
    sortOrder = try? container.decode(Int.self, forKey: .sortOrder)
    
    // Try new format first, fall back to legacy
    tracking = try? container.decode(TrackingMode.self, forKey: .tracking)
      ?? (try? container.decode(TrackingMode.self, forKey: .syncMode))
    
    github = try? container.decode(GitHubProjectConfig.self, forKey: .github)
      ?? (try? container.decode(GitHubProjectConfig.self, forKey: .githubConfig))
  }
  
  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    
    try container.encode(id, forKey: .id)
    try container.encode(title, forKey: .title)
    try container.encode(createdAt, forKey: .createdAt)
    try container.encode(updatedAt, forKey: .updatedAt)
    try container.encodeIfPresent(notes, forKey: .notes)
    try container.encodeIfPresent(archived, forKey: .archived)
    try container.encodeIfPresent(type, forKey: .type)
    try container.encodeIfPresent(sortOrder, forKey: .sortOrder)
    try container.encodeIfPresent(tracking, forKey: .tracking)
    try container.encodeIfPresent(github, forKey: .github)
  }
  
  init(id: String, title: String, createdAt: Date, updatedAt: Date, notes: String? = nil, archived: Bool? = nil, type: ProjectType? = nil, sortOrder: Int? = nil, tracking: TrackingMode? = nil, github: GitHubProjectConfig? = nil) {
    self.id = id
    self.title = title
    self.createdAt = createdAt
    self.updatedAt = updatedAt
    self.notes = notes
    self.archived = archived
    self.type = type
    self.sortOrder = sortOrder
    self.tracking = tracking
    self.github = github
  }
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
  case completed
  case blocked
}

/// Priority level for research requests.
enum ResearchPriority: String, Codable, Hashable, CaseIterable {
  case low
  case normal
  case high
  case urgent
}

/// A single expected deliverable artifact for a research request.
struct RequestDeliverable: Codable, Identifiable, Hashable {
  var id: String
  var kind: String       // e.g. "markdown", "bullet-summary", "links-list", "comparison-table"
  var label: String      // human description, e.g. "Main research document"
  var fulfilled: Bool    // whether the artifact has been produced

  static let commonKinds: [(String, String)] = [
    ("markdown", "Markdown document"),
    ("bullet-summary", "Bullet summary"),
    ("links-list", "Links / sources list"),
    ("comparison-table", "Comparison table"),
    ("implementation-plan", "Implementation plan"),
    ("custom", "Custom"),
  ]
}

/// A snapshot of a request prompt at a point in time (for edit versioning).
struct RequestEditVersion: Codable, Identifiable, Hashable {
  var id: String          // "v1", "v2", etc.
  var prompt: String
  var editedAt: Date
  var editedBy: String?   // "rafe" or "lobs"
}

struct ResearchRequest: Codable, Identifiable, Hashable {
  var id: String
  var projectId: String
  var tileId: String?       // If attached to a specific tile
  var prompt: String
  var status: ResearchRequestStatus
  var response: String?
  var author: String?       // who created the request
  var priority: ResearchPriority?  // nil defaults to .normal
  var deliverables: [RequestDeliverable]?  // expected output artifacts
  var editHistory: [RequestEditVersion]?   // version history of prompt edits
  var parentRequestId: String?   // if this was split from another request
  var assignedWorker: String?    // worker assignment (e.g. "lobs")
  var createdAt: Date
  var updatedAt: Date

  /// Resolved priority (defaults to .normal if nil)
  var resolvedPriority: ResearchPriority { priority ?? .normal }

  /// Whether all declared deliverables are fulfilled.
  var allDeliverablesFulfilled: Bool {
    guard let dels = deliverables, !dels.isEmpty else { return true }
    return dels.allSatisfy { $0.fulfilled }
  }

  /// Number of fulfilled deliverables vs total.
  var deliverableProgress: (fulfilled: Int, total: Int) {
    guard let dels = deliverables else { return (0, 0) }
    return (dels.filter { $0.fulfilled }.count, dels.count)
  }

  /// Current version number based on edit history.
  var currentVersion: Int {
    (editHistory?.count ?? 0) + 1
  }

  enum CodingKeys: String, CodingKey {
    case id, projectId, tileId, prompt, status, response, author, priority
    case deliverables, editHistory, parentRequestId, assignedWorker
    case createdAt, updatedAt
  }

  init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    id = try c.decode(String.self, forKey: .id)
    projectId = try c.decodeIfPresent(String.self, forKey: .projectId) ?? "unknown"
    tileId = try c.decodeIfPresent(String.self, forKey: .tileId)
    prompt = try c.decode(String.self, forKey: .prompt)
    status = try c.decode(ResearchRequestStatus.self, forKey: .status)
    response = try c.decodeIfPresent(String.self, forKey: .response)
    author = try c.decodeIfPresent(String.self, forKey: .author)
    priority = try c.decodeIfPresent(ResearchPriority.self, forKey: .priority)
    deliverables = try c.decodeIfPresent([RequestDeliverable].self, forKey: .deliverables)
    editHistory = try c.decodeIfPresent([RequestEditVersion].self, forKey: .editHistory)
    parentRequestId = try c.decodeIfPresent(String.self, forKey: .parentRequestId)
    assignedWorker = try c.decodeIfPresent(String.self, forKey: .assignedWorker)
    createdAt = try c.decode(Date.self, forKey: .createdAt)
    updatedAt = try c.decode(Date.self, forKey: .updatedAt)
  }

  init(id: String, projectId: String, tileId: String? = nil, prompt: String, status: ResearchRequestStatus, response: String? = nil, author: String? = nil, priority: ResearchPriority? = nil, deliverables: [RequestDeliverable]? = nil, editHistory: [RequestEditVersion]? = nil, parentRequestId: String? = nil, assignedWorker: String? = nil, createdAt: Date, updatedAt: Date) {
    self.id = id
    self.projectId = projectId
    self.tileId = tileId
    self.prompt = prompt
    self.status = status
    self.response = response
    self.author = author
    self.priority = priority
    self.deliverables = deliverables
    self.editHistory = editHistory
    self.parentRequestId = parentRequestId
    self.assignedWorker = assignedWorker
    self.createdAt = createdAt
    self.updatedAt = updatedAt
  }
}

// MARK: - Research Document (doc-based storage)

struct ResearchSource: Codable, Identifiable, Hashable {
  var id: String
  var url: String
  var title: String
  var tags: [String]?
  var addedAt: Date
}

struct ResearchSourcesFile: Codable {
  var sources: [ResearchSource]
}

/// A research deliverable document from the `docs/` directory.
struct ResearchDeliverable: Identifiable, Hashable {
  var id: String           // filename
  var filename: String
  var title: String
  var requestIdPrefix: String?  // first 8 chars of request UUID if present
  var modifiedAt: Date
  var content: String
}

// MARK: - Inbox Item (Design Docs)

struct InboxItem: Identifiable, Hashable {
  var id: String          // e.g. "inbox/foo.md" or "artifacts/bar.md"
  var title: String       // derived from filename or first heading
  var filename: String
  var relativePath: String
  /// Content for the document. This may initially be a short preview for performance.
  var content: String
  /// True when `content` is only a preview/truncated snapshot and the full document
  /// should be loaded on-demand (e.g. when selected).
  var contentIsTruncated: Bool
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

// MARK: - Inbox Read State (repo-backed)

/// Repo-backed read/seen state for inbox items.
///
/// Stored in the control repo so it survives reinstall/reclone across machines.
struct InboxReadStateFile: Codable, Hashable {
  var schemaVersion: Int
  var generatedAt: Date
  var readItemIds: [String]
  var lastSeenThreadCounts: [String: Int]
}

// MARK: - Inbox Thread (threaded conversations per document)

enum InboxTriageStatus: String, Codable, Hashable, CaseIterable {
  case needsResponse = "needs_response"
  case pending = "pending"
  case resolved = "resolved"

  var displayName: String {
    switch self {
    case .needsResponse: return "Needs Response"
    case .pending: return "Pending"
    case .resolved: return "Resolved"
    }
  }

  var iconName: String {
    switch self {
    case .needsResponse: return "exclamationmark.bubble.fill"
    case .pending: return "clock.fill"
    case .resolved: return "checkmark.circle.fill"
    }
  }

  var color: String {
    switch self {
    case .needsResponse: return "orange"
    case .pending: return "blue"
    case .resolved: return "green"
    }
  }
}

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
  var triageStatus: InboxTriageStatus = .needsResponse
  var createdAt: Date
  var updatedAt: Date

  // Custom decoder to provide default for triageStatus on legacy data
  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(String.self, forKey: .id)
    docId = try container.decode(String.self, forKey: .docId)
    messages = try container.decode([InboxThreadMessage].self, forKey: .messages)
    triageStatus = (try? container.decode(InboxTriageStatus.self, forKey: .triageStatus)) ?? .needsResponse
    createdAt = try container.decode(Date.self, forKey: .createdAt)
    updatedAt = try container.decode(Date.self, forKey: .updatedAt)
  }

  init(id: String, docId: String, messages: [InboxThreadMessage], triageStatus: InboxTriageStatus = .needsResponse, createdAt: Date, updatedAt: Date) {
    self.id = id
    self.docId = docId
    self.messages = messages
    self.triageStatus = triageStatus
    self.createdAt = createdAt
    self.updatedAt = updatedAt
  }
}

// MARK: - Task Templates

struct TaskTemplateItem: Codable, Identifiable, Hashable {
  var id: String
  var title: String
  var notes: String?
}

struct TaskTemplate: Codable, Identifiable, Hashable {
  var id: String
  var name: String
  var description: String?
  var items: [TaskTemplateItem]
  var createdAt: Date
  var updatedAt: Date
}

// MARK: - Text Dump (bulk text → tasks)

enum TextDumpStatus: String, Codable, Hashable {
  case pending
  case processing
  case completed
}

struct TextDump: Codable, Identifiable, Hashable {
  var id: String
  var projectId: String
  var text: String
  var status: TextDumpStatus
  var taskIds: [String]?   // IDs of tasks created from this dump
  var createdAt: Date
  var updatedAt: Date
}

// MARK: - Worker Status

struct WorkerStatus: Codable {
  var active: Bool
  var workerId: String?
  var startedAt: Date?
  var currentTask: String?
  var tasksCompleted: Int?
  var lastHeartbeat: Date?
  var endedAt: Date?

  // Live run details (optional; written by worker-register)
  var currentProject: String?
  var taskLog: [WorkerTaskLogEntry]?

  // Optional live token counters (if workers start recording them)
  var inputTokens: Int?
  var outputTokens: Int?
}

// MARK: - Worker History

struct WorkerTaskLogEntry: Codable {
  var task: String?
  var project: String?
  var completedAt: Date?
}

struct WorkerHistoryRun: Codable, Identifiable {
  var workerId: String?
  var startedAt: Date?
  var endedAt: Date?
  var tasksCompleted: Int?
  var timeoutReason: String?
  var model: String?

  /// Optional token split (if recorded by the worker).
  var inputTokens: Int?
  var outputTokens: Int?

  /// Total tokens used in this worker run (optional).
  var totalTokens: Int?

  /// Total cost (USD) for this worker run (optional).
  var totalCostUSD: Double?

  /// Optional: lightweight list of tasks completed during the run.
  var taskLog: [WorkerTaskLogEntry]?

  /// Commit SHAs pushed during this run (for auditability).
  var commitSHAs: [String]?

  /// Files modified during this run (for auditability).
  var filesModified: [String]?

  /// GitHub compare URL for changes in this run (if available).
  var githubCompareURL: String?

  var id: String { "\(workerId ?? "unknown")-\(startedAt?.timeIntervalSince1970 ?? 0)" }
}

struct WorkerHistory: Codable {
  var runs: [WorkerHistoryRun]
}

// MARK: - Agent Status

struct AgentStats: Codable {
  var tasksCompleted: Int?
  var tasksFailed: Int?
  var avgDurationSeconds: Int?
  var lastWeekCompleted: Int?
}

struct AgentStatus: Codable, Identifiable {
  var agentType: String
  var status: String  // idle|working|thinking|finalizing
  var activity: String?
  var thinking: String?
  var currentTaskId: String?
  var currentProjectId: String?
  var lastActiveAt: Date?
  var lastCompletedTaskId: String?
  var lastCompletedAt: Date?
  var stats: AgentStats?

  var id: String { agentType }

  var displayName: String { agentType.capitalized }

  var emoji: String {
    switch agentType {
    case "programmer": return "\u{1F527}"
    case "architect": return "\u{1F3D7}"
    case "researcher": return "\u{1F52C}"
    case "reviewer": return "\u{1F50D}"
    case "writer": return "\u{270D}\u{FE0F}"
    default: return "\u{1F916}"
    }
  }

  var isActive: Bool { status != "idle" }
}

// MARK: - Main Session Usage

struct MainSessionSnapshot: Codable, Identifiable {
  var timestamp: Date?
  var inputTokens: Int?
  var outputTokens: Int?
  var totalTokens: Int?
  var model: String?
  var costUSD: Double?
  var deltaInputTokens: Int?
  var deltaOutputTokens: Int?
  var deltaCostUSD: Double?

  var id: String { "\(timestamp?.timeIntervalSince1970 ?? 0)" }
}

struct MainSessionDailySummary: Codable {
  var inputTokens: Int
  var outputTokens: Int
  var costUSD: Double
  var snapshotCount: Int
}

struct MainSessionUsage: Codable {
  var snapshots: [MainSessionSnapshot]
  var dailySummaries: [String: MainSessionDailySummary]
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

// MARK: - Notifications

enum NotificationType: String, Codable {
  case reminder = "reminder"
  case blocker = "blocker"
  case error = "error"
  case success = "success"
  case info = "info"
  case warning = "warning"

  var displayName: String {
    switch self {
    case .reminder: return "Reminder"
    case .blocker: return "Blocker"
    case .error: return "Error"
    case .success: return "Success"
    case .info: return "Info"
    case .warning: return "Warning"
    }
  }

  var iconName: String {
    switch self {
    case .reminder: return "bell.fill"
    case .blocker: return "hand.raised.fill"
    case .error: return "xmark.circle.fill"
    case .success: return "checkmark.circle.fill"
    case .info: return "info.circle.fill"
    case .warning: return "exclamationmark.triangle.fill"
    }
  }

  var priority: NotificationPriority {
    switch self {
    case .reminder, .blocker, .error:
      return .high
    case .warning:
      return .medium
    case .success, .info:
      return .low
    }
  }
}

enum NotificationPriority: Int, Codable {
  case low = 0
  case medium = 1
  case high = 2
}

struct DashboardNotification: Identifiable, Codable {
  var id: String
  var type: NotificationType
  var message: String
  var createdAt: Date
  var dismissed: Bool

  init(id: String = UUID().uuidString, type: NotificationType, message: String, createdAt: Date = Date(), dismissed: Bool = false) {
    self.id = id
    self.type = type
    self.message = message
    self.createdAt = createdAt
    self.dismissed = dismissed
  }
}

struct NotificationPreferences: Codable {
  var enabledTypes: Set<String> // Set of NotificationType.rawValue
  var batchLowPriority: Bool
  var batchIntervalSeconds: Int // How long to wait before showing batched notifications

  static var `default`: NotificationPreferences {
    NotificationPreferences(
      enabledTypes: Set(NotificationType.allCases.map { $0.rawValue }),
      batchLowPriority: true,
      batchIntervalSeconds: 30
    )
  }
}

extension NotificationType: CaseIterable {}
