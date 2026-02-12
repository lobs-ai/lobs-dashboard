import Foundation
import AppKit

/// Smart polling manager with differential refresh and adaptive intervals.
/// Only fetches data when the cache is stale, and can pause/resume based on app state.
@MainActor
final class PollingManager {
  private let api: APIService
  private let cache: CacheManager
  
  // Active polling tasks (one per data type)
  private var timers: [String: Task<Void, Never>] = [:]
  
  // MARK: - Polling Intervals (seconds)
  
  var tasksPollInterval: TimeInterval = 5     // Tasks: every 5s
  var workerPollInterval: TimeInterval = 3    // Worker status: every 3s
  var agentsPollInterval: TimeInterval = 5    // Agents: every 5s
  var inboxPollInterval: TimeInterval = 15    // Inbox: every 15s
  var documentsPollInterval: TimeInterval = 30 // Docs: every 30s
  var projectsPollInterval: TimeInterval = 30  // Projects: every 30s
  
  // MARK: - Error Backoff State
  
  private var errorBackoffIntervals: [String: TimeInterval] = [:]
  private let maxBackoffInterval: TimeInterval = 60  // Max 60s backoff
  
  // MARK: - Paused State
  
  private var isPaused: Bool = false
  
  init(api: APIService, cache: CacheManager) {
    self.api = api
    self.cache = cache
    setupAppStateMonitoring()
  }
  
  // MARK: - App State Monitoring
  
  private func setupAppStateMonitoring() {
    // Pause polling when app becomes inactive
    NotificationCenter.default.addObserver(
      forName: NSApplication.willResignActiveNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      self?.pause()
    }
    
    // Resume polling when app becomes active
    NotificationCenter.default.addObserver(
      forName: NSApplication.didBecomeActiveNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      self?.resume()
    }
  }
  
  // MARK: - Start/Stop All
  
  func startAll() {
    startTasksPolling()
    startWorkerStatusPolling()
    startAgentStatusesPolling()
    startInboxPolling()
    startDocumentsPolling()
    startProjectsPolling()
  }
  
  func stopAll() {
    timers.values.forEach { $0.cancel() }
    timers.removeAll()
    errorBackoffIntervals.removeAll()
  }
  
  func pause() {
    isPaused = true
    stopAll()
  }
  
  func resume() {
    guard isPaused else { return }
    isPaused = false
    startAll()
    // Do an immediate refresh on resume
    Task {
      await refreshStaleData()
    }
  }
  
  // MARK: - Individual Polling Methods
  
  func startTasksPolling() {
    startPolling(
      key: "tasks",
      interval: tasksPollInterval,
      isStale: { [weak self] in self?.cache.isTasksStale() ?? true },
      fetch: { [weak self] in try await self?.fetchTasks() }
    )
  }
  
  func startWorkerStatusPolling() {
    startPolling(
      key: "worker_status",
      interval: workerPollInterval,
      isStale: { [weak self] in self?.cache.isWorkerStatusStale() ?? true },
      fetch: { [weak self] in try await self?.fetchWorkerStatus() }
    )
  }
  
  func startAgentStatusesPolling() {
    startPolling(
      key: "agent_statuses",
      interval: agentsPollInterval,
      isStale: { [weak self] in self?.cache.isAgentStatusesStale() ?? true },
      fetch: { [weak self] in try await self?.fetchAgentStatuses() }
    )
  }
  
  func startInboxPolling() {
    startPolling(
      key: "inbox",
      interval: inboxPollInterval,
      isStale: { [weak self] in self?.cache.isInboxStale() ?? true },
      fetch: { [weak self] in try await self?.fetchInbox() }
    )
  }
  
  func startDocumentsPolling() {
    startPolling(
      key: "documents",
      interval: documentsPollInterval,
      isStale: { [weak self] in self?.cache.isDocumentsStale() ?? true },
      fetch: { [weak self] in try await self?.fetchDocuments() }
    )
  }
  
  func startProjectsPolling() {
    startPolling(
      key: "projects",
      interval: projectsPollInterval,
      isStale: { [weak self] in self?.cache.isProjectsStale() ?? true },
      fetch: { [weak self] in try await self?.fetchProjects() }
    )
  }
  
  // MARK: - Generic Polling Loop
  
  private func startPolling(
    key: String,
    interval: TimeInterval,
    isStale: @escaping () -> Bool,
    fetch: @escaping () async throws -> Void
  ) {
    // Cancel existing timer if any
    timers[key]?.cancel()
    
    timers[key] = Task { [weak self] in
      guard let self = self else { return }
      
      // Immediate fetch if stale
      if isStale() {
        await self.poll(key: key, fetch: fetch)
      }
      
      // Polling loop
      while !Task.isCancelled {
        let effectiveInterval = self.getEffectiveInterval(key: key, baseInterval: interval)
        try? await Task.sleep(nanoseconds: UInt64(effectiveInterval * 1_000_000_000))
        
        guard !Task.isCancelled else { break }
        guard !self.isPaused else { continue }
        
        if isStale() {
          await self.poll(key: key, fetch: fetch)
        }
      }
    }
  }
  
  private func poll(key: String, fetch: @escaping () async throws -> Void) async {
    do {
      try await fetch()
      // Success: reset error backoff
      errorBackoffIntervals.removeValue(forKey: key)
    } catch {
      // Error: apply exponential backoff
      applyErrorBackoff(key: key)
      print("⚠️ [poll:\(key)] Failed: \(error)")
    }
  }
  
  // MARK: - Error Backoff
  
  private func applyErrorBackoff(key: String) {
    let currentBackoff = errorBackoffIntervals[key] ?? 0
    let newBackoff = min(currentBackoff == 0 ? 5 : currentBackoff * 2, maxBackoffInterval)
    errorBackoffIntervals[key] = newBackoff
  }
  
  private func getEffectiveInterval(key: String, baseInterval: TimeInterval) -> TimeInterval {
    if let backoff = errorBackoffIntervals[key], backoff > 0 {
      return baseInterval + backoff
    }
    return baseInterval
  }
  
  // MARK: - Fetch Methods (Differential Updates)
  
  private func fetchTasks() async throws {
    let file = try await api.loadTasks()
    cache.updateTasks(file.tasks)
  }
  
  private func fetchProjects() async throws {
    let file = try await api.loadProjects()
    cache.updateProjects(file.projects)
  }
  
  private func fetchInbox() async throws {
    let items = try await api.loadInboxItems()
    cache.updateInboxItems(items)
  }
  
  private func fetchDocuments() async throws {
    let docs = try await api.loadAgentDocuments()
    cache.updateDocuments(docs)
  }
  
  private func fetchWorkerStatus() async throws {
    let status = try await api.loadWorkerStatus()
    cache.updateWorkerStatus(status)
    
    // Also fetch worker history (less frequently)
    if cache.isWorkerHistoryStale() {
      let history = try await api.loadWorkerHistory()
      cache.updateWorkerHistory(history)
    }
  }
  
  private func fetchAgentStatuses() async throws {
    let statuses = try await api.loadAgentStatuses()
    cache.updateAgentStatuses(statuses)
  }
  
  // MARK: - Project-Specific Polling
  
  func startResearchPolling(projectId: String) {
    startPolling(
      key: "research_\(projectId)",
      interval: 30,
      isStale: { [weak self] in
        guard let self = self else { return true }
        return self.cache.isResearchDocStale(projectId)
          || self.cache.isResearchSourcesStale(projectId)
          || self.cache.isResearchRequestsStale(projectId)
      },
      fetch: { [weak self] in
        guard let self = self else { return }
        try await self.fetchResearchData(projectId: projectId)
      }
    )
  }
  
  func stopResearchPolling(projectId: String) {
    let key = "research_\(projectId)"
    timers[key]?.cancel()
    timers.removeValue(forKey: key)
  }
  
  private func fetchResearchData(projectId: String) async throws {
    // Fetch research doc
    if cache.isResearchDocStale(projectId) {
      let doc = try await api.loadResearchDoc(projectId: projectId)
      cache.updateResearchDoc(projectId, content: doc)
    }
    
    // Fetch sources
    if cache.isResearchSourcesStale(projectId) {
      let sources = try await api.loadResearchSources(projectId: projectId)
      cache.updateResearchSources(projectId, sources: sources)
    }
    
    // Fetch requests
    if cache.isResearchRequestsStale(projectId) {
      let requests = try await api.loadResearchRequests(projectId: projectId)
      cache.updateResearchRequests(projectId, requests: requests)
    }
  }
  
  func startTrackerPolling(projectId: String) {
    startPolling(
      key: "tracker_\(projectId)",
      interval: 30,
      isStale: { [weak self] in self?.cache.isTrackerItemsStale(projectId) ?? true },
      fetch: { [weak self] in
        guard let self = self else { return }
        let items = try await self.api.loadTrackerItems(projectId: projectId)
        self.cache.updateTrackerItems(projectId, items: items)
      }
    )
  }
  
  func stopTrackerPolling(projectId: String) {
    let key = "tracker_\(projectId)"
    timers[key]?.cancel()
    timers.removeValue(forKey: key)
  }
  
  // MARK: - Force Refresh
  
  /// Force refresh all stale data immediately (ignores poll intervals).
  func refreshStaleData() async {
    await withTaskGroup(of: Void.self) { group in
      if cache.isTasksStale() {
        group.addTask { [weak self] in
          try? await self?.fetchTasks()
        }
      }
      
      if cache.isProjectsStale() {
        group.addTask { [weak self] in
          try? await self?.fetchProjects()
        }
      }
      
      if cache.isInboxStale() {
        group.addTask { [weak self] in
          try? await self?.fetchInbox()
        }
      }
      
      if cache.isDocumentsStale() {
        group.addTask { [weak self] in
          try? await self?.fetchDocuments()
        }
      }
      
      if cache.isWorkerStatusStale() {
        group.addTask { [weak self] in
          try? await self?.fetchWorkerStatus()
        }
      }
      
      if cache.isAgentStatusesStale() {
        group.addTask { [weak self] in
          try? await self?.fetchAgentStatuses()
        }
      }
    }
  }
}
