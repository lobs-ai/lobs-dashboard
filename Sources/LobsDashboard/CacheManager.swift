import Foundation

/// In-memory cache manager with TTL-based staleness checking.
/// All data access must happen on MainActor to ensure thread-safety.
@MainActor
final class CacheManager: ObservableObject {
  // MARK: - Cached Data
  
  @Published private(set) var projects: [Project] = []
  @Published private(set) var tasks: [DashboardTask] = []
  @Published private(set) var inboxItems: [InboxItem] = []
  @Published private(set) var documents: [AgentDocument] = []
  @Published private(set) var workerStatus: WorkerStatus?
  @Published private(set) var workerHistory: WorkerHistory?
  @Published private(set) var agentStatuses: [String: AgentStatus] = [:]
  @Published private(set) var templates: [TaskTemplate] = []
  
  // Per-project caches
  private var researchDocs: [String: String] = [:]  // projectId -> content
  private var researchSources: [String: [ResearchSource]] = [:]
  private var researchRequests: [String: [ResearchRequest]] = [:]
  private var trackerItems: [String: [TrackerItem]] = [:]
  
  // MARK: - Timestamps for Staleness Tracking
  
  private var lastFetched: [String: Date] = [:]
  
  // Cache keys
  private enum CacheKey {
    static let projects = "projects"
    static let tasks = "tasks"
    static let inbox = "inbox"
    static let documents = "documents"
    static let workerStatus = "worker_status"
    static let workerHistory = "worker_history"
    static let agentStatuses = "agent_statuses"
    static let templates = "templates"
    
    static func researchDoc(_ projectId: String) -> String { "research_doc_\(projectId)" }
    static func researchSources(_ projectId: String) -> String { "research_sources_\(projectId)" }
    static func researchRequests(_ projectId: String) -> String { "research_requests_\(projectId)" }
    static func trackerItems(_ projectId: String) -> String { "tracker_items_\(projectId)" }
  }
  
  // MARK: - Configurable TTLs (seconds)
  
  var projectsTTL: TimeInterval = 30
  var tasksTTL: TimeInterval = 10      // Tasks change frequently
  var inboxTTL: TimeInterval = 30
  var documentsTTL: TimeInterval = 60
  var workerTTL: TimeInterval = 5      // Worker status needs to be fresh
  var agentsTTL: TimeInterval = 10
  var templatesTTL: TimeInterval = 120  // Rarely change
  var researchTTL: TimeInterval = 30
  var trackerTTL: TimeInterval = 30
  
  // MARK: - Staleness Checking
  
  /// Check if a cache entry is stale based on its TTL.
  func isStale(_ key: String, ttl: TimeInterval) -> Bool {
    guard let lastFetch = lastFetched[key] else {
      return true  // Never fetched = stale
    }
    return Date().timeIntervalSince(lastFetch) > ttl
  }
  
  func isProjectsStale() -> Bool { isStale(CacheKey.projects, ttl: projectsTTL) }
  func isTasksStale() -> Bool { isStale(CacheKey.tasks, ttl: tasksTTL) }
  func isInboxStale() -> Bool { isStale(CacheKey.inbox, ttl: inboxTTL) }
  func isDocumentsStale() -> Bool { isStale(CacheKey.documents, ttl: documentsTTL) }
  func isWorkerStatusStale() -> Bool { isStale(CacheKey.workerStatus, ttl: workerTTL) }
  func isWorkerHistoryStale() -> Bool { isStale(CacheKey.workerHistory, ttl: workerTTL) }
  func isAgentStatusesStale() -> Bool { isStale(CacheKey.agentStatuses, ttl: agentsTTL) }
  func isTemplatesStale() -> Bool { isStale(CacheKey.templates, ttl: templatesTTL) }
  
  func isResearchDocStale(_ projectId: String) -> Bool {
    isStale(CacheKey.researchDoc(projectId), ttl: researchTTL)
  }
  
  func isResearchSourcesStale(_ projectId: String) -> Bool {
    isStale(CacheKey.researchSources(projectId), ttl: researchTTL)
  }
  
  func isResearchRequestsStale(_ projectId: String) -> Bool {
    isStale(CacheKey.researchRequests(projectId), ttl: researchTTL)
  }
  
  func isTrackerItemsStale(_ projectId: String) -> Bool {
    isStale(CacheKey.trackerItems(projectId), ttl: trackerTTL)
  }
  
  // MARK: - Cache Invalidation
  
  /// Force a specific cache entry to be stale (will be refreshed on next poll).
  func invalidate(_ key: String) {
    lastFetched.removeValue(forKey: key)
  }
  
  func invalidateProjects() { invalidate(CacheKey.projects) }
  func invalidateTasks() { invalidate(CacheKey.tasks) }
  func invalidateInbox() { invalidate(CacheKey.inbox) }
  func invalidateDocuments() { invalidate(CacheKey.documents) }
  func invalidateWorkerStatus() { invalidate(CacheKey.workerStatus) }
  func invalidateWorkerHistory() { invalidate(CacheKey.workerHistory) }
  func invalidateAgentStatuses() { invalidate(CacheKey.agentStatuses) }
  func invalidateTemplates() { invalidate(CacheKey.templates) }
  
  func invalidateResearchDoc(_ projectId: String) {
    invalidate(CacheKey.researchDoc(projectId))
  }
  
  func invalidateResearchSources(_ projectId: String) {
    invalidate(CacheKey.researchSources(projectId))
  }
  
  func invalidateResearchRequests(_ projectId: String) {
    invalidate(CacheKey.researchRequests(projectId))
  }
  
  func invalidateTrackerItems(_ projectId: String) {
    invalidate(CacheKey.trackerItems(projectId))
  }
  
  /// Force all caches to be stale.
  func invalidateAll() {
    lastFetched.removeAll()
  }
  
  // MARK: - Cache Updates
  
  func updateProjects(_ newProjects: [Project]) {
    projects = newProjects
    lastFetched[CacheKey.projects] = Date()
  }
  
  func updateTasks(_ newTasks: [DashboardTask]) {
    tasks = newTasks
    lastFetched[CacheKey.tasks] = Date()
  }
  
  func updateInboxItems(_ newItems: [InboxItem]) {
    inboxItems = newItems
    lastFetched[CacheKey.inbox] = Date()
  }
  
  func updateDocuments(_ newDocuments: [AgentDocument]) {
    documents = newDocuments
    lastFetched[CacheKey.documents] = Date()
  }
  
  func updateWorkerStatus(_ status: WorkerStatus?) {
    workerStatus = status
    lastFetched[CacheKey.workerStatus] = Date()
  }
  
  func updateWorkerHistory(_ history: WorkerHistory?) {
    workerHistory = history
    lastFetched[CacheKey.workerHistory] = Date()
  }
  
  func updateAgentStatuses(_ statuses: [String: AgentStatus]) {
    agentStatuses = statuses
    lastFetched[CacheKey.agentStatuses] = Date()
  }
  
  func updateTemplates(_ newTemplates: [TaskTemplate]) {
    templates = newTemplates
    lastFetched[CacheKey.templates] = Date()
  }
  
  func updateResearchDoc(_ projectId: String, content: String?) {
    if let content = content {
      researchDocs[projectId] = content
    } else {
      researchDocs.removeValue(forKey: projectId)
    }
    lastFetched[CacheKey.researchDoc(projectId)] = Date()
  }
  
  func updateResearchSources(_ projectId: String, sources: [ResearchSource]) {
    researchSources[projectId] = sources
    lastFetched[CacheKey.researchSources(projectId)] = Date()
  }
  
  func updateResearchRequests(_ projectId: String, requests: [ResearchRequest]) {
    researchRequests[projectId] = requests
    lastFetched[CacheKey.researchRequests(projectId)] = Date()
  }
  
  func updateTrackerItems(_ projectId: String, items: [TrackerItem]) {
    trackerItems[projectId] = items
    lastFetched[CacheKey.trackerItems(projectId)] = Date()
  }
  
  // MARK: - Per-Project Data Access
  
  func getResearchDoc(_ projectId: String) -> String? {
    researchDocs[projectId]
  }
  
  func getResearchSources(_ projectId: String) -> [ResearchSource] {
    researchSources[projectId] ?? []
  }
  
  func getResearchRequests(_ projectId: String) -> [ResearchRequest] {
    researchRequests[projectId] ?? []
  }
  
  func getTrackerItems(_ projectId: String) -> [TrackerItem] {
    trackerItems[projectId] ?? []
  }
  
  // MARK: - Optimistic Updates
  
  /// Update a single task in the cache (optimistic update before server confirms).
  func updateTask(_ taskId: String, update: (inout DashboardTask) -> Void) {
    if let index = tasks.firstIndex(where: { $0.id == taskId }) {
      var updatedTask = tasks[index]
      update(&updatedTask)
      updatedTask.updatedAt = Date()
      tasks[index] = updatedTask
    }
  }
  
  /// Remove a task from the cache (optimistic delete).
  func removeTask(_ taskId: String) {
    tasks.removeAll { $0.id == taskId }
  }
  
  /// Add a task to the cache (optimistic create).
  func addTask(_ task: DashboardTask) {
    tasks.append(task)
  }
  
  /// Update a single project in the cache.
  func updateProject(_ projectId: String, update: (inout Project) -> Void) {
    if let index = projects.firstIndex(where: { $0.id == projectId }) {
      var updatedProject = projects[index]
      update(&updatedProject)
      updatedProject.updatedAt = Date()
      projects[index] = updatedProject
    }
  }
  
  /// Remove a project from the cache.
  func removeProject(_ projectId: String) {
    projects.removeAll { $0.id == projectId }
  }
  
  /// Update a single inbox item in the cache.
  func updateInboxItem(_ itemId: String, update: (inout InboxItem) -> Void) {
    if let index = inboxItems.firstIndex(where: { $0.id == itemId }) {
      var updatedItem = inboxItems[index]
      update(&updatedItem)
      inboxItems[index] = updatedItem
    }
  }
  
  /// Update a single research request in the cache.
  func updateResearchRequest(_ projectId: String, requestId: String, update: (inout ResearchRequest) -> Void) {
    guard var requests = researchRequests[projectId] else { return }
    if let index = requests.firstIndex(where: { $0.id == requestId }) {
      var updatedRequest = requests[index]
      update(&updatedRequest)
      updatedRequest.updatedAt = Date()
      requests[index] = updatedRequest
      researchRequests[projectId] = requests
    }
  }
  
  /// Update a single tracker item in the cache.
  func updateTrackerItem(_ projectId: String, itemId: String, update: (inout TrackerItem) -> Void) {
    guard var items = trackerItems[projectId] else { return }
    if let index = items.firstIndex(where: { $0.id == itemId }) {
      var updatedItem = items[index]
      update(&updatedItem)
      updatedItem.updatedAt = Date()
      items[index] = updatedItem
      trackerItems[projectId] = items
    }
  }
}
