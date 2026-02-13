import Foundation

enum APIError: Error, LocalizedError {
  case invalidURL
  case invalidResponse
  case httpError(statusCode: Int, message: String)
  case decodingError(Error)
  case encodingError(Error)
  case networkError(Error)
  
  var errorDescription: String? {
    switch self {
    case .invalidURL:
      return "Invalid API URL"
    case .invalidResponse:
      return "Invalid API response"
    case .httpError(let code, let message):
      return "HTTP \(code): \(message)"
    case .decodingError(let error):
      return "JSON decoding failed: \(error.localizedDescription)"
    case .encodingError(let error):
      return "JSON encoding failed: \(error.localizedDescription)"
    case .networkError(let error):
      return "Network error: \(error.localizedDescription)"
    }
  }
}

/// API service that communicates with the lobs-server REST API.
/// Provides the same interface as LobsControlStore but uses HTTP instead of file I/O.
final class APIService {
  let baseURL: URL
  
  init(baseURL: URL) {
    self.baseURL = baseURL
  }
  
  convenience init(baseURLString: String = "http://localhost:8000") throws {
    guard let url = URL(string: baseURLString) else {
      throw APIError.invalidURL
    }
    self.init(baseURL: url)
  }
  
  // MARK: - HTTP Helpers
  
  private func decoder() -> JSONDecoder {
    let d = JSONDecoder()
    d.keyDecodingStrategy = .convertFromSnakeCase
    d.dateDecodingStrategy = .custom { decoder in
      let container = try decoder.singleValueContainer()
      let str = try container.decode(String.self)
      // Try standard ISO 8601 first
      let isoFormatter = ISO8601DateFormatter()
      isoFormatter.formatOptions = [.withInternetDateTime]
      if let date = isoFormatter.date(from: str) { return date }
      // Try with fractional seconds
      isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
      if let date = isoFormatter.date(from: str) { return date }
      // Try without timezone (server returns naive datetimes, assume UTC)
      let noTZ = DateFormatter()
      noTZ.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
      noTZ.timeZone = TimeZone(identifier: "UTC")
      if let date = noTZ.date(from: str) { return date }
      // Try without timezone with fractional seconds
      noTZ.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSSSS"
      if let date = noTZ.date(from: str) { return date }
      throw DecodingError.dataCorruptedError(in: container, debugDescription: "Cannot decode date: \(str)")
    }
    return d
  }
  
  private func encoder() -> JSONEncoder {
    let e = JSONEncoder()
    e.keyEncodingStrategy = .convertToSnakeCase
    e.dateEncodingStrategy = .iso8601
    return e
  }
  
  private func request<T: Decodable>(
    method: String,
    path: String,
    queryItems: [URLQueryItem]? = nil,
    body: (any Encodable)? = nil
  ) async throws -> T {
    var urlComponents = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
    urlComponents.queryItems = queryItems
    
    guard let url = urlComponents.url else {
      throw APIError.invalidURL
    }
    
    var req = URLRequest(url: url)
    req.httpMethod = method
    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
    req.setValue("application/json", forHTTPHeaderField: "Accept")
    
    if let body = body {
      do {
        req.httpBody = try encoder().encode(body)
      } catch {
        throw APIError.encodingError(error)
      }
    }
    
    let (data, response) = try await URLSession.shared.data(for: req)
    
    guard let httpResponse = response as? HTTPURLResponse else {
      throw APIError.invalidResponse
    }
    
    guard (200..<300).contains(httpResponse.statusCode) else {
      let message = String(data: data, encoding: .utf8) ?? "Unknown error"
      throw APIError.httpError(statusCode: httpResponse.statusCode, message: message)
    }
    
    do {
      return try decoder().decode(T.self, from: data)
    } catch {
      throw APIError.decodingError(error)
    }
  }
  
  private func requestVoid(
    method: String,
    path: String,
    queryItems: [URLQueryItem]? = nil,
    body: (any Encodable)? = nil
  ) async throws {
    var urlComponents = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
    urlComponents.queryItems = queryItems
    
    guard let url = urlComponents.url else {
      throw APIError.invalidURL
    }
    
    var req = URLRequest(url: url)
    req.httpMethod = method
    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
    
    if let body = body {
      do {
        req.httpBody = try encoder().encode(body)
      } catch {
        throw APIError.encodingError(error)
      }
    }
    
    let (_, response) = try await URLSession.shared.data(for: req)
    
    guard let httpResponse = response as? HTTPURLResponse else {
      throw APIError.invalidResponse
    }
    
    guard (200..<300).contains(httpResponse.statusCode) else {
      throw APIError.httpError(statusCode: httpResponse.statusCode, message: "Request failed")
    }
  }
  
  // MARK: - Projects
  
  func loadProjects() async throws -> ProjectsFile {
    let projects: [Project] = try await request(method: "GET", path: "/api/projects", queryItems: [
      URLQueryItem(name: "limit", value: "1000"),
      URLQueryItem(name: "archived", value: "false")
    ])
    
    // Ensure default project exists
    var allProjects = projects
    if !allProjects.contains(where: { $0.id == "default" }) {
      let now = Date()
      allProjects.insert(Project(
        id: "default",
        title: "Default",
        createdAt: now,
        updatedAt: now,
        notes: nil,
        archived: false
      ), at: 0)
    }
    
    return ProjectsFile(
      schemaVersion: 1,
      generatedAt: Date(),
      projects: allProjects
    )
  }
  
  func saveProjects(_ file: ProjectsFile) async throws {
    // The API doesn't have a bulk update endpoint, so we update each project individually
    // In practice, the dashboard updates projects one at a time anyway
    for project in file.projects {
      let update = ProjectUpdate(from: project)
      let _: Project = try await request(
        method: "PUT",
        path: "/api/projects/\(project.id)",
        body: update
      )
    }
  }
  
  func renameProject(id: String, newTitle: String) async throws {
    let update = ProjectUpdate(title: newTitle)
    let _: Project = try await request(
      method: "PUT",
      path: "/api/projects/\(id)",
      body: update
    )
  }
  
  func updateProjectNotes(id: String, notes: String?) async throws {
    let update = ProjectUpdate(notes: notes)
    let _: Project = try await request(
      method: "PUT",
      path: "/api/projects/\(id)",
      body: update
    )
  }
  
  // REMOVED: updateProjectSyncMode - no longer using GitHub sync
  // func updateProjectSyncMode(id: String, syncMode: SyncMode, githubConfig: GitHubConfig?) async throws { ... }
  
  func deleteProject(id: String) async throws {
    try await requestVoid(
      method: "DELETE",
      path: "/api/projects/\(id)"
    )
  }
  
  func archiveProject(id: String) async throws {
    let _: Project = try await request(
      method: "POST",
      path: "/api/projects/\(id)/archive"
    )
  }
  
  func createProject(id: String, title: String, type: ProjectType, notes: String?) async throws -> Project {
    let create = ProjectCreate(
      id: id,
      title: title,
      type: type.rawValue,
      notes: notes
    )
    
    return try await request(
      method: "POST",
      path: "/api/projects",
      body: create
    )
  }
  
  // MARK: - Tasks
  
  func loadTasks() async throws -> TasksFile {
    let tasks: [DashboardTask] = try await request(
      method: "GET",
      path: "/api/tasks",
      queryItems: [URLQueryItem(name: "limit", value: "1000")]
    )
    
    return TasksFile(
      schemaVersion: 0,
      generatedAt: Date(),
      tasks: tasks
    )
  }
  
  func loadLocalTasks() async throws -> [DashboardTask] {
    // In API mode, there's no distinction between local and remote tasks
    let tasks: [DashboardTask] = try await request(
      method: "GET",
      path: "/api/tasks",
      queryItems: [URLQueryItem(name: "limit", value: "1000")]
    )
    return tasks
  }
  
  func saveTasks(_ file: TasksFile) async throws {
    // The API doesn't have a bulk update endpoint
    // Individual task updates should use setStatus, setWorkState, etc.
    // This method is primarily used after batch operations, which we'll handle separately
  }
  
  func setStatus(taskId: String, status: TaskStatus) async throws {
    struct StatusUpdate: Codable {
      let status: String
    }
    let _: DashboardTask = try await request(
      method: "PATCH",
      path: "/api/tasks/\(taskId)/status",
      body: StatusUpdate(status: status.rawValue)
    )
  }
  
  func setWorkState(taskId: String, workState: WorkState?) async throws {
    struct WorkStateUpdate: Codable {
      let workState: String
      
      enum CodingKeys: String, CodingKey {
        case workState = "work_state"
      }
    }
    let _: DashboardTask = try await request(
      method: "PATCH",
      path: "/api/tasks/\(taskId)/work-state",
      body: WorkStateUpdate(workState: workState?.rawValue ?? "")
    )
  }
  
  func setReviewState(taskId: String, reviewState: ReviewState?) async throws {
    struct ReviewStateUpdate: Codable {
      let reviewState: String
      
      enum CodingKeys: String, CodingKey {
        case reviewState = "review_state"
      }
    }
    let _: DashboardTask = try await request(
      method: "PATCH",
      path: "/api/tasks/\(taskId)/review-state",
      body: ReviewStateUpdate(reviewState: reviewState?.rawValue ?? "")
    )
  }
  
  func setSortOrder(taskId: String, sortOrder: Int?) async throws {
    struct SortOrderUpdate: Codable {
      let sortOrder: Int?
      
      enum CodingKeys: String, CodingKey {
        case sortOrder = "sort_order"
      }
    }
    let update = TaskUpdateRequest(sortOrder: sortOrder)
    let _: DashboardTask = try await request(
      method: "PUT",
      path: "/api/tasks/\(taskId)",
      body: update
    )
  }
  
  func setTitleAndNotes(taskId: String, title: String, notes: String?) async throws {
    let update = TaskUpdateRequest(title: title, notes: notes)
    let _: DashboardTask = try await request(
      method: "PUT",
      path: "/api/tasks/\(taskId)",
      body: update
    )
  }
  
  func addTask(
    id: String = UUID().uuidString,
    title: String,
    owner: TaskOwner,
    status: TaskStatus,
    projectId: String? = nil,
    workState: WorkState? = .notStarted,
    reviewState: ReviewState? = .pending,
    notes: String?
  ) async throws -> DashboardTask {
    let create = TaskCreateRequest(
      id: id,
      title: title,
      status: status.rawValue,
      owner: owner.rawValue,
      workState: workState?.rawValue,
      reviewState: reviewState?.rawValue,
      projectId: projectId,
      notes: notes
    )
    
    return try await request(
      method: "POST",
      path: "/api/tasks",
      body: create
    )
  }
  
  func saveExistingTask(_ task: DashboardTask) async throws {
    let update = TaskUpdateRequest(from: task)
    let _: DashboardTask = try await request(
      method: "PUT",
      path: "/api/tasks/\(task.id)",
      body: update
    )
  }
  
  func deleteTask(taskId: String) async throws {
    try await requestVoid(
      method: "DELETE",
      path: "/api/tasks/\(taskId)"
    )
  }
  
  func archiveTask(taskId: String) async throws {
    let _: DashboardTask = try await request(
      method: "POST",
      path: "/api/tasks/\(taskId)/archive"
    )
  }
  
  func loadTaskArtifact(taskId: String) async throws -> String {
    struct ArtifactContent: Codable {
      let content: String
    }
    let artifact: ArtifactContent = try await request(
      method: "GET",
      path: "/api/tasks/\(taskId)/artifact"
    )
    return artifact.content
  }
  
  // MARK: - Inbox
  
  func loadInboxItems() async throws -> [InboxItem] {
    struct APIInboxItem: Decodable {
      let id: String
      let title: String?
      let filename: String?
      let relativePath: String?
      let content: String?
      let contentIsTruncated: Bool?
      let modifiedAt: Date?
      let isRead: Bool?
      let summary: String?
    }

    let items: [APIInboxItem] = try await request(
      method: "GET",
      path: "/api/inbox",
      queryItems: [URLQueryItem(name: "limit", value: "1000")]
    )

    return items.map { item in
      let fallbackContent = item.content ?? ""
      let fallbackTitle = item.title ?? item.filename ?? item.id
      return InboxItem(
        id: item.id,
        title: fallbackTitle,
        filename: item.filename ?? fallbackTitle,
        relativePath: item.relativePath ?? item.id,
        content: fallbackContent,
        contentIsTruncated: item.contentIsTruncated ?? false,
        modifiedAt: item.modifiedAt ?? .distantPast,
        isRead: item.isRead ?? false,
        summary: item.summary ?? String(fallbackContent.prefix(200))
      )
    }
  }
  
  func loadInboxThread(docId: String) async throws -> InboxThread? {
    struct ThreadResponse: Codable {
      let thread: InboxThread?
      let messages: [InboxThreadMessage]
    }
    
    let response: ThreadResponse = try await request(
      method: "GET",
      path: "/api/inbox/\(docId)/thread"
    )
    
    guard var thread = response.thread else {
      return nil
    }
    
    thread.messages = response.messages
    return thread
  }
  
  func saveInboxThread(_ thread: InboxThread) async throws -> InboxThread {
    // Save each message
    for message in thread.messages {
      struct MessageCreate: Codable {
        let id: String
        let threadId: String
        let author: String
        let text: String
        
        enum CodingKeys: String, CodingKey {
          case id
          case threadId = "thread_id"
          case author
          case text
        }
      }
      
      let create = MessageCreate(
        id: message.id,
        threadId: thread.id,
        author: message.author,
        text: message.text
      )
      
      let _: InboxThreadMessage = try await request(
        method: "POST",
        path: "/api/inbox/\(thread.docId)/thread/messages",
        body: create
      )
    }
    return thread
  }
  
  func loadAllInboxThreads() async throws -> [String: InboxThread] {
    // The API doesn't have a bulk threads endpoint
    // This would need to be implemented by loading threads for each inbox item
    // For now, return empty dict - threads are loaded on-demand
    return [:]
  }
  
  // MARK: - Agent Documents
  
  func loadAgentDocuments() async throws -> [AgentDocument] {
    return try await request(
      method: "GET",
      path: "/api/documents",
      queryItems: [URLQueryItem(name: "limit", value: "1000")]
    )
  }
  
  // MARK: - Worker Status
  
  func loadWorkerStatus() async throws -> WorkerStatus? {
    return try await request(
      method: "GET",
      path: "/api/worker/status"
    )
  }
  
  func loadWorkerHistory() async throws -> WorkerHistory? {
    let runs: [WorkerHistoryRun] = try await request(
      method: "GET",
      path: "/api/worker/history",
      queryItems: [URLQueryItem(name: "limit", value: "100")]
    )
    return WorkerHistory(runs: runs)
  }
  
  // MARK: - Agent Statuses
  
  func loadAgentStatuses() async throws -> [String: AgentStatus] {
    let agents: [AgentStatus] = try await request(
      method: "GET",
      path: "/api/agents",
      queryItems: [URLQueryItem(name: "limit", value: "100")]
    )
    
    var dict: [String: AgentStatus] = [:]
    for agent in agents {
      dict[agent.agentType] = agent
    }
    return dict
  }
  
  // MARK: - Templates
  
  func loadTemplates() async throws -> [TaskTemplate] {
    return try await request(
      method: "GET",
      path: "/api/templates",
      queryItems: [URLQueryItem(name: "limit", value: "100")]
    )
  }
  
  // MARK: - Research
  
  func loadResearchDoc(projectId: String) async throws -> String? {
    struct ResearchDocResponse: Codable {
      let projectId: String
      let content: String?
      
      enum CodingKeys: String, CodingKey {
        case projectId = "project_id"
        case content
      }
    }
    
    do {
      let doc: ResearchDocResponse = try await request(
        method: "GET",
        path: "/api/research/\(projectId)/doc"
      )
      return doc.content
    } catch APIError.httpError(statusCode: 404, _) {
      return nil
    }
  }
  
  func saveResearchDoc(projectId: String, content: String) async throws {
    struct ResearchDocUpdate: Codable {
      let content: String
    }
    
    struct ResearchDocResponse: Codable {
      let projectId: String
      let content: String?
      
      enum CodingKeys: String, CodingKey {
        case projectId = "project_id"
        case content
      }
    }
    
    let _: ResearchDocResponse = try await request(
      method: "PUT",
      path: "/api/research/\(projectId)/doc",
      body: ResearchDocUpdate(content: content)
    )
  }
  
  func loadResearchSources(projectId: String) async throws -> [ResearchSource] {
    return try await request(
      method: "GET",
      path: "/api/research/\(projectId)/sources",
      queryItems: [URLQueryItem(name: "limit", value: "1000")]
    )
  }
  
  func addResearchSource(projectId: String, source: ResearchSource) async throws {
    struct SourceCreate: Codable {
      let id: String
      let projectId: String
      let url: String
      let title: String
      let tags: [String]?
      let addedAt: Date
      
      enum CodingKeys: String, CodingKey {
        case id
        case projectId = "project_id"
        case url
        case title
        case tags
        case addedAt = "added_at"
      }
    }
    
    let create = SourceCreate(
      id: source.id,
      projectId: projectId,
      url: source.url,
      title: source.title,
      tags: source.tags,
      addedAt: source.addedAt
    )
    
    let _: ResearchSource = try await request(
      method: "POST",
      path: "/api/research/\(projectId)/sources",
      body: create
    )
  }
  
  func deleteResearchSource(projectId: String, sourceId: String) async throws {
    try await requestVoid(
      method: "DELETE",
      path: "/api/research/\(projectId)/sources/\(sourceId)"
    )
  }
  
  func loadResearchRequests(projectId: String) async throws -> [ResearchRequest] {
    return try await request(
      method: "GET",
      path: "/api/research/\(projectId)/requests",
      queryItems: [URLQueryItem(name: "limit", value: "1000")]
    )
  }
  
  func addResearchRequest(projectId: String, request: ResearchRequest) async throws {
    struct RequestCreate: Codable {
      let id: String
      let projectId: String
      let prompt: String
      let status: String
      let priority: String?
      
      enum CodingKeys: String, CodingKey {
        case id
        case projectId = "project_id"
        case prompt
        case status
        case priority
      }
    }
    
    let create = RequestCreate(
      id: request.id,
      projectId: projectId,
      prompt: request.prompt,
      status: request.status.rawValue,
      priority: request.priority?.rawValue
    )
    
    let _: ResearchRequest = try await self.request(
      method: "POST",
      path: "/api/research/\(projectId)/requests",
      body: create
    )
  }
  
  func updateResearchRequest(projectId: String, requestId: String, status: ResearchRequestStatus) async throws {
    struct RequestUpdate: Codable {
      let status: String
    }
    
    let _: ResearchRequest = try await request(
      method: "PUT",
      path: "/api/research/\(projectId)/requests/\(requestId)",
      body: RequestUpdate(status: status.rawValue)
    )
  }
  
  func deleteResearchRequest(projectId: String, requestId: String) async throws {
    try await requestVoid(
      method: "DELETE",
      path: "/api/research/\(projectId)/requests/\(requestId)"
    )
  }
  
  // MARK: - Tracker
  
  func loadTrackerItems(projectId: String) async throws -> [TrackerItem] {
    return try await request(
      method: "GET",
      path: "/api/tracker/\(projectId)/items",
      queryItems: [URLQueryItem(name: "limit", value: "1000")]
    )
  }
  
  func addTrackerItem(projectId: String, item: TrackerItem) async throws {
    struct ItemCreate: Codable {
      let id: String
      let projectId: String
      let title: String
      let status: String
      let difficulty: String?
      let tags: [String]?
      let notes: String?
      let links: [String]?
      
      enum CodingKeys: String, CodingKey {
        case id
        case projectId = "project_id"
        case title
        case status
        case difficulty
        case tags
        case notes
        case links
      }
    }
    
    let create = ItemCreate(
      id: item.id,
      projectId: projectId,
      title: item.title,
      status: item.status.rawValue,
      difficulty: item.difficulty,
      tags: item.tags,
      notes: item.notes,
      links: item.links
    )
    
    let _: TrackerItem = try await request(
      method: "POST",
      path: "/api/tracker/\(projectId)/items",
      body: create
    )
  }
  
  func updateTrackerItem(projectId: String, itemId: String, item: TrackerItem) async throws {
    struct ItemUpdate: Codable {
      let title: String?
      let status: String?
      let difficulty: String?
      let tags: [String]?
      let notes: String?
      let links: [String]?
    }
    
    let update = ItemUpdate(
      title: item.title,
      status: item.status.rawValue,
      difficulty: item.difficulty,
      tags: item.tags,
      notes: item.notes,
      links: item.links
    )
    
    let _: TrackerItem = try await request(
      method: "PUT",
      path: "/api/tracker/\(projectId)/items/\(itemId)",
      body: update
    )
  }
  
  func deleteTrackerItem(projectId: String, itemId: String) async throws {
    try await requestVoid(
      method: "DELETE",
      path: "/api/tracker/\(projectId)/items/\(itemId)"
    )
  }
  
  // MARK: - Text Dumps
  
  func loadTextDumps() async throws -> [TextDump] {
    return try await request(
      method: "GET",
      path: "/api/text-dumps",
      queryItems: [URLQueryItem(name: "limit", value: "100")]
    )
  }
  
  func createTextDump(content: String, source: String?, context: String?) async throws -> TextDump {
    struct DumpCreate: Codable {
      let id: String
      let content: String
      let source: String?
      let context: String?
      let status: String
    }
    
    let create = DumpCreate(
      id: UUID().uuidString,
      content: content,
      source: source,
      context: context,
      status: "pending"
    )
    
    return try await request(
      method: "POST",
      path: "/api/text-dumps",
      body: create
    )
  }
  
  func saveTextDump(_ dump: TextDump) async throws {
    struct DumpUpdate: Codable {
      let projectId: String
      let text: String
      let status: String
      let taskIds: [String]?
      
      enum CodingKeys: String, CodingKey {
        case projectId = "project_id"
        case text
        case status
        case taskIds = "task_ids"
      }
    }
    
    let update = DumpUpdate(
      projectId: dump.projectId,
      text: dump.text,
      status: dump.status.rawValue,
      taskIds: dump.taskIds
    )
    
    let _: TextDump = try await request(
      method: "PUT",
      path: "/api/text-dumps/\(dump.id)",
      body: update
    )
  }
  
  // MARK: - Templates
  
  func saveTemplate(_ template: TaskTemplate) async throws {
    struct TemplateUpdate: Codable {
      let id: String
      let name: String
      let description: String?
      let items: [TaskTemplateItem]
    }
    
    let update = TemplateUpdate(
      id: template.id,
      name: template.name,
      description: template.description,
      items: template.items
    )
    
    let _: TaskTemplate = try await request(
      method: "PUT",
      path: "/api/templates/\(template.id)",
      body: update
    )
  }
  
  func deleteTemplate(id: String) async throws {
    try await requestVoid(
      method: "DELETE",
      path: "/api/templates/\(id)"
    )
  }
  
  // MARK: - Tiles
  
  func loadTiles(projectId: String) async throws -> [ResearchTile] {
    return try await request(
      method: "GET",
      path: "/api/tiles/\(projectId)",
      queryItems: [URLQueryItem(name: "limit", value: "1000")]
    )
  }
  
  func saveTile(_ tile: ResearchTile) async throws {
    struct TileUpdate: Codable {
      let id: String
      let projectId: String
      let type: String
      let title: String
      let tags: [String]?
      let status: String?
      let author: String?
      let url: String?
      let summary: String?
      let snapshot: String?
      let content: String?
      let claim: String?
      let confidence: Double?
      let evidence: [String]?
      let counterpoints: [String]?
      let options: [ComparisonOption]?
      
      enum CodingKeys: String, CodingKey {
        case id
        case projectId = "project_id"
        case type
        case title
        case tags
        case status
        case author
        case url
        case summary
        case snapshot
        case content
        case claim
        case confidence
        case evidence
        case counterpoints
        case options
      }
    }
    
    let update = TileUpdate(
      id: tile.id,
      projectId: tile.projectId,
      type: tile.type.rawValue,
      title: tile.title,
      tags: tile.tags,
      status: tile.status?.rawValue,
      author: tile.author,
      url: tile.url,
      summary: tile.summary,
      snapshot: tile.snapshot,
      content: tile.content,
      claim: tile.claim,
      confidence: tile.confidence,
      evidence: tile.evidence,
      counterpoints: tile.counterpoints,
      options: tile.options
    )
    
    let _: ResearchTile = try await request(
      method: "PUT",
      path: "/api/tiles/\(tile.projectId)/\(tile.id)",
      body: update
    )
  }
  
  func deleteTile(projectId: String, tileId: String) async throws {
    try await requestVoid(
      method: "DELETE",
      path: "/api/tiles/\(projectId)/\(tileId)"
    )
  }
  
  // MARK: - Requests (research requests)
  
  func saveRequest(_ request: ResearchRequest) async throws {
    try await updateResearchRequest(
      projectId: request.projectId,
      requestId: request.id,
      status: request.status
    )
  }
  
  // MARK: - Deliverables
  
  func loadResearchDeliverables(projectId: String) async throws -> [ResearchDeliverable] {
    struct DeliverableResponse: Codable {
      let projectId: String
      let filename: String
      let content: String
      let updatedAt: Date
      
      enum CodingKeys: String, CodingKey {
        case projectId = "project_id"
        case filename
        case content
        case updatedAt = "updated_at"
      }
    }
    
    do {
      let deliverables: [DeliverableResponse] = try await request(
        method: "GET",
        path: "/api/research/\(projectId)/deliverables",
        queryItems: [URLQueryItem(name: "limit", value: "1000")]
      )
      
      return deliverables.map { d in
        let base = (d.filename as NSString).deletingPathExtension
        let title = base.replacingOccurrences(of: "-", with: " ")
        let requestPrefix = d.filename.contains("-") ? String(d.filename.prefix(8)) : nil
        return ResearchDeliverable(
          id: d.filename,
          filename: d.filename,
          title: title,
          requestIdPrefix: requestPrefix,
          modifiedAt: d.updatedAt,
          content: d.content,
        )
      }
    } catch APIError.httpError(statusCode: 404, _) {
      return []
    }
  }
  
  func saveResearchDeliverable(projectId: String, filename: String, content: String) async throws {
    struct DeliverableUpdate: Codable {
      let filename: String
      let content: String
    }
    
    struct DeliverableResponse: Codable {
      let projectId: String
      let filename: String
      let content: String
      
      enum CodingKeys: String, CodingKey {
        case projectId = "project_id"
        case filename
        case content
      }
    }
    
    let _: DeliverableResponse = try await request(
      method: "PUT",
      path: "/api/research/\(projectId)/deliverables/\(filename)",
      body: DeliverableUpdate(filename: filename, content: content)
    )
  }
  
  // MARK: - Inbox responses
  
  func saveInboxResponse(docId: String, response: String) async throws -> InboxThread {
    struct ResponseCreate: Codable {
      let response: String
    }
    
    struct ThreadResponse: Codable {
      let thread: InboxThread?
      let messages: [InboxThreadMessage]
    }
    
    let result: ThreadResponse = try await request(
      method: "POST",
      path: "/api/inbox/\(docId)/response",
      body: ResponseCreate(response: response)
    )
    
    guard var thread = result.thread else {
      throw APIError.invalidResponse
    }
    
    thread.messages = result.messages
    return thread
  }
  
  // MARK: - Project README
  
  func saveProjectReadme(projectId: String, content: String) async throws {
    struct ReadmeUpdate: Codable {
      let content: String
    }
    
    struct ReadmeResponse: Codable {
      let projectId: String
      let content: String
      
      enum CodingKeys: String, CodingKey {
        case projectId = "project_id"
        case content
      }
    }
    
    let _: ReadmeResponse = try await request(
      method: "PUT",
      path: "/api/projects/\(projectId)/readme",
      body: ReadmeUpdate(content: content)
    )
  }
  
  // MARK: - Bulk delete operations
  
  func deleteResearchData(projectId: String) async throws {
    try await requestVoid(
      method: "DELETE",
      path: "/api/research/\(projectId)"
    )
  }
  
  func deleteTrackerData(projectId: String) async throws {
    let items = try await loadTrackerItems(projectId: projectId)
    for item in items {
      try await deleteTrackerItem(projectId: projectId, itemId: item.id)
    }
  }
  
  // MARK: - Agent Files
  
  func loadAgentFile(agentType: String, filename: String) async throws -> String? {
    struct AgentFileContent: Codable {
      let content: String
    }
    
    do {
      let response: AgentFileContent = try await request(
        method: "GET",
        path: "/api/agents/\(agentType)/files/\(filename)"
      )
      return response.content
    } catch APIError.httpError(statusCode: 404, _) {
      return nil
    }
  }
  
  func saveAgentFile(agentType: String, filename: String, content: String) async throws {
    struct AgentFileContent: Codable {
      let content: String
    }
    
    let _: AgentFileContent = try await request(
      method: "PUT",
      path: "/api/agents/\(agentType)/files/\(filename)",
      body: AgentFileContent(content: content)
    )
  }
  
  // MARK: - Tracker Requests
  
  func loadTrackerRequests(projectId: String) async throws -> [ResearchRequest] {
    return try await request(
      method: "GET",
      path: "/api/tracker/\(projectId)/requests",
      queryItems: [URLQueryItem(name: "limit", value: "1000")]
    )
  }
  
  func saveTrackerRequest(_ trackerRequest: ResearchRequest) async throws {
    struct RequestUpdate: Codable {
      let status: String
    }
    
    let _: ResearchRequest = try await request(
      method: "PUT",
      path: "/api/tracker/\(trackerRequest.projectId)/requests/\(trackerRequest.id)",
      body: RequestUpdate(status: trackerRequest.status.rawValue)
    )
  }
  
  func deleteTrackerRequest(projectId: String, requestId: String) async throws {
    try await requestVoid(
      method: "DELETE",
      path: "/api/tracker/\(projectId)/requests/\(requestId)"
    )
  }
  
  // MARK: - Inbox Read State
  
  func loadInboxReadState() throws -> InboxReadStateFile? {
    // Read state is now persisted server-side via is_read field
    // This method kept for compatibility but returns nil
    return nil
  }
  
  func saveInboxReadState(readItemIds: Set<String>, lastSeenThreadCounts: [String: Int]) async throws {
    // Bulk update read state on server
    try await requestVoid(
      method: "POST",
      path: "/api/inbox/read-state",
      body: Array(readItemIds)
    )
  }
  
  func markInboxItemRead(id: String) async throws {
    struct InboxItem: Codable {
      let id: String
      let title: String
      let isRead: Bool
      
      enum CodingKeys: String, CodingKey {
        case id
        case title
        case isRead = "is_read"
      }
    }
    
    let _: InboxItem = try await request(
      method: "PATCH",
      path: "/api/inbox/\(id)/read"
    )
  }
  
  // MARK: - Project Operations
  
  func unarchiveProject(id: String) async throws {
    let _: Project = try await request(
      method: "POST",
      path: "/api/projects/\(id)/unarchive"
    )
  }
  
  func syncGitHubProject(projectId: String) async throws {
    struct SyncResponse: Codable {
      let status: String
      let projectId: String
      let repo: String
      let issuesCount: Int
      
      enum CodingKeys: String, CodingKey {
        case status
        case projectId = "project_id"
        case repo
        case issuesCount = "issues_count"
      }
    }
    
    let _: SyncResponse = try await request(
      method: "POST",
      path: "/api/projects/\(projectId)/github-sync"
    )
  }
  
  // MARK: - Auto-Archive
  
  func archiveCompleted(olderThanDays days: Int) async throws {
    struct ArchiveResponse: Codable {
      let status: String
      let archivedCount: Int
      
      enum CodingKeys: String, CodingKey {
        case status
        case archivedCount = "archived_count"
      }
    }
    
    let _: ArchiveResponse = try await request(
      method: "POST",
      path: "/api/tasks/auto-archive",
      queryItems: [URLQueryItem(name: "older_than_days", value: String(days))]
    )
  }
  
  func archiveReadInboxItems(olderThanDays days: Int, readItemIds: Set<String>) async throws {
    // This would need a server endpoint similar to auto-archive tasks
    // For now, mark items as read server-side
    try await saveInboxReadState(readItemIds: readItemIds, lastSeenThreadCounts: [:])
  }
  
  func readArtifact(relativePath: String) throws -> String {
    // Artifacts are file-based and require a file server or static file serving
    // This feature is not critical for core functionality and can be added later
    // Implementation would need:
    // 1. Server endpoint: GET /api/artifacts/{path} that serves files from a configured directory
    // 2. Security: Path validation to prevent directory traversal attacks
    // 3. Content-Type detection for proper MIME types
    throw NSError(
      domain: "APIService",
      code: 501,
      userInfo: [NSLocalizedDescriptionKey: "Artifact reading not yet implemented in API mode. Artifacts are file-based and require additional server infrastructure."]
    )
  }
  
  // MARK: - Chat
  
  func fetchChatSessions() async throws -> [ChatSession] {
    return try await request(
      method: "GET",
      path: "/api/chat/sessions"
    )
  }
  
  func createChatSession(label: String) async throws -> ChatSession {
    struct SessionCreate: Codable {
      let label: String
    }
    
    return try await request(
      method: "POST",
      path: "/api/chat/sessions",
      body: SessionCreate(label: label)
    )
  }
  
  func fetchChatHistory(
    sessionKey: String,
    limit: Int = 100,
    before: String? = nil
  ) async throws -> [ChatMessage] {
    var queryItems = [
      URLQueryItem(name: "limit", value: String(limit))
    ]
    
    if let before = before {
      queryItems.append(URLQueryItem(name: "before", value: before))
    }
    
    return try await request(
      method: "GET",
      path: "/api/chat/sessions/\(sessionKey)/messages",
      queryItems: queryItems
    )
  }
  
  func sendChatMessage(sessionKey: String, content: String) async throws -> ChatMessage {
    struct MessageSend: Codable {
      let content: String
    }
    
    return try await request(
      method: "POST",
      path: "/api/chat/sessions/\(sessionKey)/messages",
      body: MessageSend(content: content)
    )
  }
}

// MARK: - Request/Response Models

private struct ProjectUpdate: Codable {
  let title: String?
  let notes: String?
  let archived: Bool?
  let type: String?
  let sortOrder: Int?
  let tracking: String?
  let githubRepo: String?
  let githubLabelFilter: [String]?
  
  init(
    title: String? = nil,
    notes: String? = nil,
    archived: Bool? = nil,
    type: String? = nil,
    sortOrder: Int? = nil,
    tracking: String? = nil,
    githubRepo: String? = nil,
    githubLabelFilter: [String]? = nil
  ) {
    self.title = title
    self.notes = notes
    self.archived = archived
    self.type = type
    self.sortOrder = sortOrder
    self.tracking = tracking
    self.githubRepo = githubRepo
    self.githubLabelFilter = githubLabelFilter
  }
  
  init(from project: Project) {
    self.title = project.title
    self.notes = project.notes
    self.archived = project.archived
    self.type = project.type?.rawValue
    self.sortOrder = project.sortOrder
    self.tracking = project.tracking?.rawValue
    self.githubRepo = project.github?.repo
    self.githubLabelFilter = project.github?.labelFilter
  }
  
  enum CodingKeys: String, CodingKey {
    case title
    case notes
    case archived
    case type
    case sortOrder = "sort_order"
    case tracking
    case githubRepo = "github_repo"
    case githubLabelFilter = "github_label_filter"
  }
}

private struct ProjectCreate: Codable {
  let id: String
  let title: String
  let type: String
  let notes: String?
  let archived: Bool
  let sortOrder: Int
  
  init(id: String, title: String, type: String, notes: String?) {
    self.id = id
    self.title = title
    self.type = type
    self.notes = notes
    self.archived = false
    self.sortOrder = 0
  }
  
  enum CodingKeys: String, CodingKey {
    case id
    case title
    case type
    case notes
    case archived
    case sortOrder = "sort_order"
  }
}

private struct TaskCreateRequest: Codable {
  let id: String
  let title: String
  let status: String
  let owner: String
  let workState: String?
  let reviewState: String?
  let projectId: String?
  let notes: String?
  
  enum CodingKeys: String, CodingKey {
    case id
    case title
    case status
    case owner
    case workState = "work_state"
    case reviewState = "review_state"
    case projectId = "project_id"
    case notes
  }
}

private struct TaskUpdateRequest: Codable {
  let title: String?
  let status: String?
  let owner: String?
  let workState: String?
  let reviewState: String?
  let projectId: String?
  let notes: String?
  let artifactPath: String?
  let startedAt: Date?
  let finishedAt: Date?
  let sortOrder: Int?
  let blockedBy: [String]?
  let pinned: Bool?
  let shape: String?
  let githubIssueNumber: Int?
  let agent: String?
  
  init(
    title: String? = nil,
    status: String? = nil,
    owner: String? = nil,
    workState: String? = nil,
    reviewState: String? = nil,
    projectId: String? = nil,
    notes: String? = nil,
    artifactPath: String? = nil,
    startedAt: Date? = nil,
    finishedAt: Date? = nil,
    sortOrder: Int? = nil,
    blockedBy: [String]? = nil,
    pinned: Bool? = nil,
    shape: String? = nil,
    githubIssueNumber: Int? = nil,
    agent: String? = nil
  ) {
    self.title = title
    self.status = status
    self.owner = owner
    self.workState = workState
    self.reviewState = reviewState
    self.projectId = projectId
    self.notes = notes
    self.artifactPath = artifactPath
    self.startedAt = startedAt
    self.finishedAt = finishedAt
    self.sortOrder = sortOrder
    self.blockedBy = blockedBy
    self.pinned = pinned
    self.shape = shape
    self.githubIssueNumber = githubIssueNumber
    self.agent = agent
  }
  
  init(from task: DashboardTask) {
    self.title = task.title
    self.status = task.status.rawValue
    self.owner = task.owner.rawValue
    self.workState = task.workState?.rawValue
    self.reviewState = task.reviewState?.rawValue
    self.projectId = task.projectId
    self.notes = task.notes
    self.artifactPath = task.artifactPath
    self.startedAt = task.startedAt
    self.finishedAt = task.finishedAt
    self.sortOrder = task.sortOrder
    self.blockedBy = task.blockedBy
    self.pinned = task.pinned
    self.shape = task.shape?.rawValue
    self.githubIssueNumber = task.githubIssueNumber
    self.agent = task.agent
  }
  
  enum CodingKeys: String, CodingKey {
    case title
    case status
    case owner
    case workState = "work_state"
    case reviewState = "review_state"
    case projectId = "project_id"
    case notes
    case artifactPath = "artifact_path"
    case startedAt = "started_at"
    case finishedAt = "finished_at"
    case sortOrder = "sort_order"
    case blockedBy = "blocked_by"
    case pinned
    case shape
    case githubIssueNumber = "github_issue_number"
    case agent
  }
}
