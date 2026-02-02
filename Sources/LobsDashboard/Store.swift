import Foundation

final class LobsControlStore {
  let repoRoot: URL

  init(repoRoot: URL) {
    self.repoRoot = repoRoot
  }

  private var tasksURL: URL { repoRoot.appendingPathComponent("state/tasks.json") }
  private var tasksDirURL: URL { repoRoot.appendingPathComponent("state/tasks") }
  private var archiveDirURL: URL { repoRoot.appendingPathComponent("state/tasks-archive") }

  private var projectsURL: URL { repoRoot.appendingPathComponent("state/projects.json") }
  private var researchDirURL: URL { repoRoot.appendingPathComponent("state/research") }

  private var trackerDirURL: URL { repoRoot.appendingPathComponent("state/tracker") }

  private func trackerItemsDirURL(projectId: String) -> URL {
    trackerDirURL.appendingPathComponent(projectId).appendingPathComponent("items")
  }

  private func tilesDirURL(projectId: String) -> URL {
    researchDirURL.appendingPathComponent(projectId).appendingPathComponent("tiles")
  }

  private func requestsDirURL(projectId: String) -> URL {
    researchDirURL.appendingPathComponent(projectId).appendingPathComponent("requests")
  }

  private func decoder() -> JSONDecoder {
    let d = JSONDecoder()
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
      throw DecodingError.dataCorruptedError(in: container, debugDescription: "Cannot decode date: \(str)")
    }
    return d
  }

  private func encoder() -> JSONEncoder {
    let e = JSONEncoder()
    e.outputFormatting = [.prettyPrinted, .sortedKeys]
    e.dateEncodingStrategy = .iso8601
    return e
  }

  private func taskFileURL(taskId: String) -> URL {
    tasksDirURL.appendingPathComponent("\(taskId).json")
  }

  // MARK: - Projects

  func loadProjects() throws -> ProjectsFile {
    let fm = FileManager.default

    // If missing, synthesize a default project (in-memory) but do not write until user creates/edits.
    guard fm.fileExists(atPath: projectsURL.path) else {
      let now = Date()
      return ProjectsFile(
        schemaVersion: 1,
        generatedAt: now,
        projects: [Project(id: "default", title: "Default", createdAt: now, updatedAt: now, notes: nil, archived: false)]
      )
    }

    let data = try Data(contentsOf: projectsURL)
    return try decoder().decode(ProjectsFile.self, from: data)
  }

  func saveProjects(_ file: ProjectsFile) throws {
    var file = file
    file.generatedAt = Date()

    try FileManager.default.createDirectory(
      at: projectsURL.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )

    let data = try encoder().encode(file)
    try data.write(to: projectsURL, options: [.atomic])
  }

  func renameProject(id: String, newTitle: String) throws {
    var file = try loadProjects()
    guard let idx = file.projects.firstIndex(where: { $0.id == id }) else { return }
    file.projects[idx].title = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
    file.projects[idx].updatedAt = Date()
    try saveProjects(file)
  }

  func updateProjectNotes(id: String, notes: String?) throws {
    var file = try loadProjects()
    guard let idx = file.projects.firstIndex(where: { $0.id == id }) else { return }
    let clean = notes?.trimmingCharacters(in: .whitespacesAndNewlines)
    file.projects[idx].notes = (clean?.isEmpty == true) ? nil : clean
    file.projects[idx].updatedAt = Date()
    try saveProjects(file)
  }

  func deleteProject(id: String) throws {
    var file = try loadProjects()
    file.projects.removeAll { $0.id == id }
    try saveProjects(file)
  }

  func archiveProject(id: String) throws {
    var file = try loadProjects()
    guard let idx = file.projects.firstIndex(where: { $0.id == id }) else { return }
    file.projects[idx].archived = true
    file.projects[idx].updatedAt = Date()
    try saveProjects(file)
  }

  // MARK: - Tasks

  func loadTasks() throws -> TasksFile {
    // Prefer per-task files if the directory exists.
    if FileManager.default.fileExists(atPath: tasksDirURL.path) {
      let items = try FileManager.default.contentsOfDirectory(
        at: tasksDirURL,
        includingPropertiesForKeys: nil,
        options: [.skipsHiddenFiles]
      )

      let dec = decoder()
      var tasks: [DashboardTask] = []

      for url in items where url.pathExtension.lowercased() == "json" {
        let data = try Data(contentsOf: url)
        let t = try dec.decode(DashboardTask.self, from: data)
        tasks.append(t)
      }

      // Stable ordering (nice UX)
      // Respect manual sortOrder first, then fall back to creation time.
      tasks.sort { (a, b) in
        if a.status.rawValue != b.status.rawValue { return a.status.rawValue < b.status.rawValue }
        let oa = a.sortOrder ?? Int.max
        let ob = b.sortOrder ?? Int.max
        if oa != ob { return oa < ob }
        if a.createdAt != b.createdAt { return a.createdAt > b.createdAt }
        return a.updatedAt > b.updatedAt
      }

      return TasksFile(schemaVersion: 0, generatedAt: Date(), tasks: tasks)
    }

    // Fallback: legacy single file.
    let data = try Data(contentsOf: tasksURL)
    return try decoder().decode(TasksFile.self, from: data)
  }

  func saveTasks(_ file: TasksFile) throws {
    // If per-task directory exists, write each task to its own file.
    if FileManager.default.fileExists(atPath: tasksDirURL.path) {
      try FileManager.default.createDirectory(
        at: tasksDirURL,
        withIntermediateDirectories: true
      )

      let enc = encoder()
      for task in file.tasks {
        let data = try enc.encode(task)
        try data.write(to: taskFileURL(taskId: task.id), options: [.atomic])
      }

      // Keep legacy tasks.json updated too (helps older tooling).
      var legacy = file
      legacy.generatedAt = Date()
      let legacyData = try enc.encode(legacy)
      try FileManager.default.createDirectory(
        at: tasksURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
      )
      try legacyData.write(to: tasksURL, options: [.atomic])
      return
    }

    // Legacy mode
    var file = file
    file.generatedAt = Date()

    let data = try encoder().encode(file)

    try FileManager.default.createDirectory(
      at: tasksURL.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )

    try data.write(to: tasksURL, options: [.atomic])
  }

  func readArtifact(relativePath: String) throws -> String {
    let url = repoRoot.appendingPathComponent(relativePath)
    return try String(contentsOf: url, encoding: .utf8)
  }

  func setStatus(taskId: String, status: TaskStatus) throws {
    if FileManager.default.fileExists(atPath: tasksDirURL.path) {
      let url = taskFileURL(taskId: taskId)
      let data = try Data(contentsOf: url)
      var task = try decoder().decode(DashboardTask.self, from: data)
      task.status = status
      task.updatedAt = Date()
      let out = try encoder().encode(task)
      try out.write(to: url, options: [.atomic])
      return
    }

    var file = try loadTasks()
    guard let idx = file.tasks.firstIndex(where: { $0.id == taskId }) else { return }
    file.tasks[idx].status = status
    file.tasks[idx].updatedAt = Date()
    try saveTasks(file)
  }

  func setWorkState(taskId: String, workState: WorkState?) throws {
    if FileManager.default.fileExists(atPath: tasksDirURL.path) {
      let url = taskFileURL(taskId: taskId)
      let data = try Data(contentsOf: url)
      var task = try decoder().decode(DashboardTask.self, from: data)
      task.workState = workState
      task.updatedAt = Date()
      let out = try encoder().encode(task)
      try out.write(to: url, options: [.atomic])
      return
    }

    var file = try loadTasks()
    guard let idx = file.tasks.firstIndex(where: { $0.id == taskId }) else { return }
    file.tasks[idx].workState = workState
    file.tasks[idx].updatedAt = Date()
    try saveTasks(file)
  }

  func setReviewState(taskId: String, reviewState: ReviewState?) throws {
    if FileManager.default.fileExists(atPath: tasksDirURL.path) {
      let url = taskFileURL(taskId: taskId)
      let data = try Data(contentsOf: url)
      var task = try decoder().decode(DashboardTask.self, from: data)
      task.reviewState = reviewState
      task.updatedAt = Date()
      let out = try encoder().encode(task)
      try out.write(to: url, options: [.atomic])
      return
    }

    var file = try loadTasks()
    guard let idx = file.tasks.firstIndex(where: { $0.id == taskId }) else { return }
    file.tasks[idx].reviewState = reviewState
    file.tasks[idx].updatedAt = Date()
    try saveTasks(file)
  }

  func setSortOrder(taskId: String, sortOrder: Int?) throws {
    if FileManager.default.fileExists(atPath: tasksDirURL.path) {
      let url = taskFileURL(taskId: taskId)
      guard FileManager.default.fileExists(atPath: url.path) else { return }
      let data = try Data(contentsOf: url)
      var task = try decoder().decode(DashboardTask.self, from: data)
      task.sortOrder = sortOrder
      task.updatedAt = Date()
      let out = try encoder().encode(task)
      try out.write(to: url, options: [.atomic])
      return
    }
  }

  func setTitleAndNotes(taskId: String, title: String, notes: String?) throws {
    let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
    let cleanNotes = notes?.trimmingCharacters(in: .whitespacesAndNewlines)

    if FileManager.default.fileExists(atPath: tasksDirURL.path) {
      let url = taskFileURL(taskId: taskId)
      let data = try Data(contentsOf: url)
      var task = try decoder().decode(DashboardTask.self, from: data)
      task.title = cleanTitle.isEmpty ? task.title : cleanTitle
      task.notes = (cleanNotes?.isEmpty == true) ? nil : cleanNotes
      task.updatedAt = Date()
      let out = try encoder().encode(task)
      try out.write(to: url, options: [.atomic])
      return
    }

    var file = try loadTasks()
    guard let idx = file.tasks.firstIndex(where: { $0.id == taskId }) else { return }
    if !cleanTitle.isEmpty { file.tasks[idx].title = cleanTitle }
    file.tasks[idx].notes = (cleanNotes?.isEmpty == true) ? nil : cleanNotes
    file.tasks[idx].updatedAt = Date()
    try saveTasks(file)
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
  ) throws -> DashboardTask {
    let now = Date()
    let task = DashboardTask(
      id: id,
      title: title,
      status: status,
      owner: owner,
      createdAt: now,
      updatedAt: now,
      workState: workState,
      reviewState: reviewState,
      projectId: projectId,
      artifactPath: nil,
      notes: notes?.isEmpty == true ? nil : notes
    )

    if FileManager.default.fileExists(atPath: tasksDirURL.path) {
      try FileManager.default.createDirectory(at: tasksDirURL, withIntermediateDirectories: true)
      let out = try encoder().encode(task)
      try out.write(to: taskFileURL(taskId: task.id), options: [.atomic])
      return task
    }

    var file = try loadTasks()
    file.tasks.append(task)
    try saveTasks(file)
    return task
  }

  func saveExistingTask(_ task: DashboardTask) throws {
    if FileManager.default.fileExists(atPath: tasksDirURL.path) {
      let url = taskFileURL(taskId: task.id)
      let data = try encoder().encode(task)
      try data.write(to: url, options: [.atomic])
      return
    }

    var file = try loadTasks()
    if let idx = file.tasks.firstIndex(where: { $0.id == task.id }) {
      file.tasks[idx] = task
    }
    try saveTasks(file)
  }

  func deleteTask(taskId: String) throws {
    if FileManager.default.fileExists(atPath: tasksDirURL.path) {
      let url = taskFileURL(taskId: taskId)
      if FileManager.default.fileExists(atPath: url.path) {
        try FileManager.default.removeItem(at: url)
      }
      return
    }

    // Legacy mode: remove from tasks.json
    var file = try loadTasks()
    file.tasks.removeAll { $0.id == taskId }
    try saveTasks(file)
  }

  func deleteResearchData(projectId: String) throws {
    let dir = researchDirURL.appendingPathComponent(projectId)
    if FileManager.default.fileExists(atPath: dir.path) {
      try FileManager.default.removeItem(at: dir)
    }
  }

  func deleteTrackerData(projectId: String) throws {
    let dir = trackerDirURL.appendingPathComponent(projectId)
    if FileManager.default.fileExists(atPath: dir.path) {
      try FileManager.default.removeItem(at: dir)
    }
  }

  func archiveTask(taskId: String) throws {
    // Per-file mode: move the task JSON into state/tasks-archive/
    if FileManager.default.fileExists(atPath: tasksDirURL.path) {
      let src = taskFileURL(taskId: taskId)
      if !FileManager.default.fileExists(atPath: src.path) { return }
      try FileManager.default.createDirectory(at: archiveDirURL, withIntermediateDirectories: true)
      let dst = archiveDirURL.appendingPathComponent("\(taskId).json")
      // Replace if exists
      _ = try? FileManager.default.removeItem(at: dst)
      try FileManager.default.moveItem(at: src, to: dst)
      return
    }

    // Legacy mode: remove from tasks.json
    var file = try loadTasks()
    file.tasks.removeAll { $0.id == taskId }
    try saveTasks(file)
  }

  func archiveCompleted(olderThanDays days: Int) throws {
    guard days > 0 else { return }
    if !FileManager.default.fileExists(atPath: tasksDirURL.path) { return }

    let items = try FileManager.default.contentsOfDirectory(
      at: tasksDirURL,
      includingPropertiesForKeys: nil,
      options: [.skipsHiddenFiles]
    )

    let dec = decoder()
    let cutoff = Date().addingTimeInterval(TimeInterval(-days * 24 * 3600))

    for url in items where url.pathExtension.lowercased() == "json" {
      let data = try Data(contentsOf: url)
      let t = try dec.decode(DashboardTask.self, from: data)
      if t.status.rawValue == "completed" && t.updatedAt < cutoff {
        try archiveTask(taskId: t.id)
      }
    }
  }

  // MARK: - Inbox (Design Docs)

  private var artifactsDirURL: URL { repoRoot.appendingPathComponent("artifacts") }
  private var inboxDirURL: URL { repoRoot.appendingPathComponent("inbox") }
  private var inboxResponsesDirURL: URL {
    repoRoot.appendingPathComponent("state").appendingPathComponent("inbox-responses")
  }

  func loadInboxItems() throws -> [InboxItem] {
    var items: [InboxItem] = []
    let fm = FileManager.default

    // Scan both artifacts/ and inbox/ directories
    let dirs: [(URL, String)] = [
      (inboxDirURL, "inbox"),
      (artifactsDirURL, "artifacts"),
    ]

    for (dir, prefix) in dirs {
      guard fm.fileExists(atPath: dir.path) else { continue }
      let files = try fm.contentsOfDirectory(
        at: dir,
        includingPropertiesForKeys: [.contentModificationDateKey],
        options: [.skipsHiddenFiles]
      )

      for fileURL in files {
        let ext = fileURL.pathExtension.lowercased()
        guard ext == "md" || ext == "txt" || ext == "markdown" else { continue }

        let filename = fileURL.lastPathComponent
        // Skip README files
        guard filename.lowercased() != "readme.md" else { continue }

        let content = try String(contentsOf: fileURL, encoding: .utf8)
        let attrs = try fm.attributesOfItem(atPath: fileURL.path)
        let modDate = (attrs[.modificationDate] as? Date) ?? Date()

        // Derive title from first heading or filename
        let title = extractTitle(from: content, filename: filename)
        let summary = extractSummary(from: content)

        let item = InboxItem(
          id: "\(prefix)/\(filename)",
          title: title,
          filename: filename,
          relativePath: "\(prefix)/\(filename)",
          content: content,
          modifiedAt: modDate,
          isRead: false,
          summary: summary
        )
        items.append(item)
      }
    }

    // Sort by modification date, newest first
    items.sort { $0.modifiedAt > $1.modifiedAt }
    return items
  }

  func loadInboxResponses() throws -> [InboxResponse] {
    guard FileManager.default.fileExists(atPath: inboxResponsesDirURL.path) else { return [] }

    var out: [InboxResponse] = []
    let dec = decoder()

    guard let e = FileManager.default.enumerator(at: inboxResponsesDirURL, includingPropertiesForKeys: nil) else {
      return []
    }

    for case let url as URL in e {
      guard url.pathExtension.lowercased() == "json" else { continue }
      let data = try Data(contentsOf: url)
      // Skip files that are in the newer thread format (have messages array, no response field)
      if let r = try? dec.decode(InboxResponse.self, from: data) {
        out.append(r)
      }
    }

    out.sort { $0.updatedAt > $1.updatedAt }
    return out
  }

  func loadInboxResponse(docId: String) throws -> InboxResponse? {
    let url = inboxResponsesDirURL
      .appendingPathComponent(docId)
      .appendingPathExtension("json")
    guard FileManager.default.fileExists(atPath: url.path) else { return nil }
    let data = try Data(contentsOf: url)
    return try decoder().decode(InboxResponse.self, from: data)
  }

  @discardableResult
  func saveInboxResponse(docId: String, response: String) throws -> InboxResponse {
    let now = Date()
    var existing = try loadInboxResponse(docId: docId)

    if existing == nil {
      existing = InboxResponse(
        id: UUID().uuidString,
        docId: docId,
        response: response,
        createdAt: now,
        updatedAt: now
      )
    } else {
      existing!.response = response
      existing!.updatedAt = now
    }

    let url = inboxResponsesDirURL
      .appendingPathComponent(docId)
      .appendingPathExtension("json")

    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(),
      withIntermediateDirectories: true,
      attributes: nil
    )

    let data = try encoder().encode(existing!)
    try data.write(to: url, options: [.atomic])
    return existing!
  }

  // MARK: - Inbox Threads (threaded conversations)

  func loadInboxThread(docId: String) throws -> InboxThread? {
    // Sanitize docId for filesystem (replace / with _)
    let safeId = docId.replacingOccurrences(of: "/", with: "_")
    let url = inboxResponsesDirURL
      .appendingPathComponent(safeId)
      .appendingPathExtension("json")
    guard FileManager.default.fileExists(atPath: url.path) else { return nil }
    let data = try Data(contentsOf: url)

    // Try loading as InboxThread first, fall back to legacy InboxResponse
    if let thread = try? decoder().decode(InboxThread.self, from: data) {
      return thread
    }

    // Migrate legacy InboxResponse to thread format
    if let legacy = try? decoder().decode(InboxResponse.self, from: data),
       !legacy.response.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      let msg = InboxThreadMessage(
        id: UUID().uuidString,
        author: "rafe",
        text: legacy.response,
        createdAt: legacy.createdAt
      )
      let thread = InboxThread(
        id: legacy.id,
        docId: legacy.docId,
        messages: [msg],
        createdAt: legacy.createdAt,
        updatedAt: legacy.updatedAt
      )
      // Save migrated thread
      try saveInboxThread(thread)
      return thread
    }

    return nil
  }

  func loadAllInboxThreads() throws -> [String: InboxThread] {
    guard FileManager.default.fileExists(atPath: inboxResponsesDirURL.path) else { return [:] }
    var result: [String: InboxThread] = [:]

    guard let e = FileManager.default.enumerator(at: inboxResponsesDirURL, includingPropertiesForKeys: nil) else {
      return [:]
    }

    for case let url as URL in e {
      guard url.pathExtension.lowercased() == "json" else { continue }
      let data = try Data(contentsOf: url)

      // Try thread format first
      if let thread = try? decoder().decode(InboxThread.self, from: data) {
        result[thread.docId] = thread
        continue
      }

      // Migrate legacy
      if let legacy = try? decoder().decode(InboxResponse.self, from: data),
         !legacy.response.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        let msg = InboxThreadMessage(
          id: UUID().uuidString,
          author: "rafe",
          text: legacy.response,
          createdAt: legacy.createdAt
        )
        let thread = InboxThread(
          id: legacy.id,
          docId: legacy.docId,
          messages: [msg],
          createdAt: legacy.createdAt,
          updatedAt: legacy.updatedAt
        )
        result[thread.docId] = thread
      }
    }

    return result
  }

  func saveInboxThread(_ thread: InboxThread) throws {
    let safeId = thread.docId.replacingOccurrences(of: "/", with: "_")
    let url = inboxResponsesDirURL
      .appendingPathComponent(safeId)
      .appendingPathExtension("json")

    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(),
      withIntermediateDirectories: true,
      attributes: nil
    )

    let data = try encoder().encode(thread)
    try data.write(to: url, options: [.atomic])
  }

  private func extractTitle(from content: String, filename: String) -> String {
    // Look for first markdown heading
    for line in content.split(separator: "\n", omittingEmptySubsequences: true) {
      let trimmed = line.trimmingCharacters(in: .whitespaces)
      if trimmed.hasPrefix("# ") {
        return String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces)
      }
    }
    // Fall back to filename without extension, prettified
    let base = (filename as NSString).deletingPathExtension
    return base.replacingOccurrences(of: "-", with: " ").capitalized
  }

  private func extractSummary(from content: String) -> String {
    // Skip headings, get first meaningful paragraph
    var lines: [String] = []
    var charCount = 0
    for line in content.split(separator: "\n", omittingEmptySubsequences: false) {
      let trimmed = line.trimmingCharacters(in: .whitespaces)
      if trimmed.hasPrefix("#") { continue }
      if trimmed.isEmpty && lines.isEmpty { continue }
      if trimmed.isEmpty && !lines.isEmpty { break } // end of first paragraph
      lines.append(trimmed)
      charCount += trimmed.count
      if charCount > 200 { break }
    }
    let result = lines.joined(separator: " ")
    if result.count > 200 {
      return String(result.prefix(200)) + "…"
    }
    return result
  }

  // MARK: - Research Document (doc-based)

  private func researchDocURL(projectId: String) -> URL {
    researchDirURL.appendingPathComponent(projectId).appendingPathComponent("doc.md")
  }

  private func researchSourcesURL(projectId: String) -> URL {
    researchDirURL.appendingPathComponent(projectId).appendingPathComponent("sources.json")
  }

  func loadResearchDoc(projectId: String) throws -> String {
    let url = researchDocURL(projectId: projectId)
    guard FileManager.default.fileExists(atPath: url.path) else { return "" }
    return try String(contentsOf: url, encoding: .utf8)
  }

  func saveResearchDoc(projectId: String, content: String) throws {
    let dir = researchDirURL.appendingPathComponent(projectId)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let url = researchDocURL(projectId: projectId)
    try content.write(to: url, atomically: true, encoding: .utf8)
  }

  func loadResearchSources(projectId: String) throws -> [ResearchSource] {
    let url = researchSourcesURL(projectId: projectId)
    guard FileManager.default.fileExists(atPath: url.path) else { return [] }
    let data = try Data(contentsOf: url)
    let file = try decoder().decode(ResearchSourcesFile.self, from: data)
    return file.sources
  }

  func saveResearchSources(projectId: String, sources: [ResearchSource]) throws {
    let dir = researchDirURL.appendingPathComponent(projectId)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let url = researchSourcesURL(projectId: projectId)
    let file = ResearchSourcesFile(sources: sources)
    let data = try encoder().encode(file)
    try data.write(to: url, options: [.atomic])
  }

  /// One-time migration: convert tiles to doc.md + sources.json.
  func migrateResearchTilesToDoc(projectId: String) throws {
    let tiles = try loadTiles(projectId: projectId)
    guard !tiles.isEmpty else { return }

    // Check if already migrated
    let docURL = researchDocURL(projectId: projectId)
    if FileManager.default.fileExists(atPath: docURL.path) { return }

    var markdown = ""
    var sources: [ResearchSource] = []

    // Group by type
    let findings = tiles.filter { $0.type == .finding }
    let notes = tiles.filter { $0.type == .note }
    let links = tiles.filter { $0.type == .link }
    let comparisons = tiles.filter { $0.type == .comparison }

    if !findings.isEmpty {
      markdown += "## Findings\n\n"
      for tile in findings {
        markdown += "### \(tile.title)\n\n"
        if let claim = tile.claim { markdown += "\(claim)\n\n" }
        if let evidence = tile.evidence, !evidence.isEmpty {
          markdown += "**Evidence:**\n"
          for e in evidence { markdown += "- \(e)\n" }
          markdown += "\n"
        }
        if let confidence = tile.confidence {
          markdown += "_Confidence: \(Int(confidence * 100))%_\n\n"
        }
      }
    }

    if !comparisons.isEmpty {
      markdown += "## Comparisons\n\n"
      for tile in comparisons {
        markdown += "### \(tile.title)\n\n"
        if let options = tile.options {
          for opt in options {
            markdown += "**\(opt.name)**\n"
            if let pros = opt.pros { for p in pros { markdown += "- ✅ \(p)\n" } }
            if let cons = opt.cons { for c in cons { markdown += "- ❌ \(c)\n" } }
            if let cost = opt.cost { markdown += "- 💰 Cost: \(cost)\n" }
            if let notes = opt.notes { markdown += "- 📝 \(notes)\n" }
            markdown += "\n"
          }
        }
      }
    }

    if !notes.isEmpty {
      markdown += "## Notes\n\n"
      for tile in notes {
        markdown += "### \(tile.title)\n\n"
        if let content = tile.content { markdown += "\(content)\n\n" }
      }
    }

    // Extract sources from link tiles
    for tile in links {
      if let url = tile.url {
        sources.append(ResearchSource(
          id: tile.id,
          url: url,
          title: tile.title,
          tags: tile.tags,
          addedAt: tile.createdAt
        ))
      }
      // Also add link summaries to doc
      if markdown.isEmpty || !links.isEmpty {
        if links.first?.id == tile.id { markdown += "## Sources\n\n" }
        markdown += "- [\(tile.title)](\(tile.url ?? ""))"
        if let summary = tile.summary { markdown += " — \(summary)" }
        markdown += "\n"
      }
    }

    try saveResearchDoc(projectId: projectId, content: markdown)
    if !sources.isEmpty {
      try saveResearchSources(projectId: projectId, sources: sources)
    }
  }

  // MARK: - Research Tiles (legacy)

  func loadTiles(projectId: String) throws -> [ResearchTile] {
    let dir = tilesDirURL(projectId: projectId)
    guard FileManager.default.fileExists(atPath: dir.path) else { return [] }

    let items = try FileManager.default.contentsOfDirectory(
      at: dir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
    )

    let dec = decoder()
    var tiles: [ResearchTile] = []
    for url in items where url.pathExtension.lowercased() == "json" {
      do {
        let data = try Data(contentsOf: url)
        let tile = try dec.decode(ResearchTile.self, from: data)
        tiles.append(tile)
      } catch {
        // Skip individual bad tiles instead of failing the entire load
        print("[LobsStore] Skipping tile \(url.lastPathComponent): \(error.localizedDescription)")
        continue
      }
    }
    tiles.sort { $0.createdAt > $1.createdAt }
    return tiles
  }

  func saveTile(_ tile: ResearchTile) throws {
    let dir = tilesDirURL(projectId: tile.projectId)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let url = dir.appendingPathComponent("\(tile.id).json")
    let data = try encoder().encode(tile)
    try data.write(to: url, options: [.atomic])
  }

  func deleteTile(projectId: String, tileId: String) throws {
    let url = tilesDirURL(projectId: projectId).appendingPathComponent("\(tileId).json")
    if FileManager.default.fileExists(atPath: url.path) {
      try FileManager.default.removeItem(at: url)
    }
  }

  // MARK: - Research Requests

  func loadRequests(projectId: String) throws -> [ResearchRequest] {
    let dir = requestsDirURL(projectId: projectId)
    guard FileManager.default.fileExists(atPath: dir.path) else { return [] }

    let items = try FileManager.default.contentsOfDirectory(
      at: dir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
    )

    let dec = decoder()
    var requests: [ResearchRequest] = []
    for url in items where url.pathExtension.lowercased() == "json" {
      do {
        let data = try Data(contentsOf: url)
        let req = try dec.decode(ResearchRequest.self, from: data)
        requests.append(req)
      } catch {
        print("[LobsStore] Skipping request \(url.lastPathComponent): \(error.localizedDescription)")
        continue
      }
    }
    requests.sort { $0.createdAt > $1.createdAt }
    return requests
  }

  func saveRequest(_ request: ResearchRequest) throws {
    let dir = requestsDirURL(projectId: request.projectId)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let url = dir.appendingPathComponent("\(request.id).json")
    let data = try encoder().encode(request)
    try data.write(to: url, options: [.atomic])
  }

  func deleteRequest(projectId: String, requestId: String) throws {
    let url = requestsDirURL(projectId: projectId).appendingPathComponent("\(requestId).json")
    if FileManager.default.fileExists(atPath: url.path) {
      try FileManager.default.removeItem(at: url)
    }
  }

  // MARK: - Tracker Items

  func loadTrackerItems(projectId: String) throws -> [TrackerItem] {
    let dir = trackerItemsDirURL(projectId: projectId)
    guard FileManager.default.fileExists(atPath: dir.path) else { return [] }

    let items = try FileManager.default.contentsOfDirectory(
      at: dir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
    )

    let dec = decoder()
    var trackerItems: [TrackerItem] = []
    for url in items where url.pathExtension.lowercased() == "json" {
      do {
        let data = try Data(contentsOf: url)
        let item = try dec.decode(TrackerItem.self, from: data)
        trackerItems.append(item)
      } catch {
        print("[LobsStore] Skipping tracker item \(url.lastPathComponent): \(error.localizedDescription)")
        continue
      }
    }
    trackerItems.sort { $0.createdAt < $1.createdAt }
    return trackerItems
  }

  func saveTrackerItem(_ item: TrackerItem) throws {
    let dir = trackerItemsDirURL(projectId: item.projectId)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let url = dir.appendingPathComponent("\(item.id).json")
    let data = try encoder().encode(item)
    try data.write(to: url, options: [.atomic])
  }

  func deleteTrackerItem(projectId: String, itemId: String) throws {
    let url = trackerItemsDirURL(projectId: projectId).appendingPathComponent("\(itemId).json")
    if FileManager.default.fileExists(atPath: url.path) {
      try FileManager.default.removeItem(at: url)
    }
  }

  // MARK: - Tracker Requests

  private func trackerRequestsDirURL(projectId: String) -> URL {
    trackerDirURL.appendingPathComponent(projectId).appendingPathComponent("requests")
  }

  func loadTrackerRequests(projectId: String) throws -> [ResearchRequest] {
    let dir = trackerRequestsDirURL(projectId: projectId)
    guard FileManager.default.fileExists(atPath: dir.path) else { return [] }

    let items = try FileManager.default.contentsOfDirectory(
      at: dir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
    )

    let dec = decoder()
    var requests: [ResearchRequest] = []
    for url in items where url.pathExtension.lowercased() == "json" {
      do {
        let data = try Data(contentsOf: url)
        let req = try dec.decode(ResearchRequest.self, from: data)
        requests.append(req)
      } catch {
        print("[LobsStore] Skipping tracker request \(url.lastPathComponent): \(error.localizedDescription)")
        continue
      }
    }
    requests.sort { $0.createdAt > $1.createdAt }
    return requests
  }

  func saveTrackerRequest(_ request: ResearchRequest) throws {
    let dir = trackerRequestsDirURL(projectId: request.projectId)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let url = dir.appendingPathComponent("\(request.id).json")
    let data = try encoder().encode(request)
    try data.write(to: url, options: [.atomic])
  }

  func deleteTrackerRequest(projectId: String, requestId: String) throws {
    let url = trackerRequestsDirURL(projectId: projectId).appendingPathComponent("\(requestId).json")
    if FileManager.default.fileExists(atPath: url.path) {
      try FileManager.default.removeItem(at: url)
    }
  }

  // MARK: - Task Templates

  private var templatesDirURL: URL {
    repoRoot.appendingPathComponent("state").appendingPathComponent("templates")
  }

  func loadTemplates() throws -> [TaskTemplate] {
    let dir = templatesDirURL
    guard FileManager.default.fileExists(atPath: dir.path) else { return [] }

    let items = try FileManager.default.contentsOfDirectory(
      at: dir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
    )

    let dec = decoder()
    var templates: [TaskTemplate] = []
    for url in items where url.pathExtension.lowercased() == "json" {
      do {
        let data = try Data(contentsOf: url)
        let t = try dec.decode(TaskTemplate.self, from: data)
        templates.append(t)
      } catch {
        continue
      }
    }
    templates.sort { $0.name.lowercased() < $1.name.lowercased() }
    return templates
  }

  func saveTemplate(_ template: TaskTemplate) throws {
    try FileManager.default.createDirectory(at: templatesDirURL, withIntermediateDirectories: true)
    let url = templatesDirURL.appendingPathComponent("\(template.id).json")
    let data = try encoder().encode(template)
    try data.write(to: url, options: [.atomic])
  }

  func deleteTemplate(id: String) throws {
    let url = templatesDirURL.appendingPathComponent("\(id).json")
    if FileManager.default.fileExists(atPath: url.path) {
      try FileManager.default.removeItem(at: url)
    }
  }

  // MARK: - Worker Status

  func loadWorkerStatus() throws -> WorkerStatus? {
    let url = repoRoot
      .appendingPathComponent("state")
      .appendingPathComponent("worker-status.json")
    guard FileManager.default.fileExists(atPath: url.path) else { return nil }
    let data = try Data(contentsOf: url)
    return try decoder().decode(WorkerStatus.self, from: data)
  }

  func loadWorkerHistory() throws -> WorkerHistory? {
    let url = repoRoot
      .appendingPathComponent("state")
      .appendingPathComponent("worker-history.json")
    guard FileManager.default.fileExists(atPath: url.path) else { return nil }
    let data = try Data(contentsOf: url)
    return try decoder().decode(WorkerHistory.self, from: data)
  }

  // MARK: - Text Dumps

  private var textDumpsDir: URL {
    repoRoot.appendingPathComponent("state").appendingPathComponent("text-dumps")
  }

  func saveTextDump(_ dump: TextDump) throws {
    try FileManager.default.createDirectory(at: textDumpsDir, withIntermediateDirectories: true)
    let url = textDumpsDir.appendingPathComponent("\(dump.id).json")
    let data = try encoder().encode(dump)
    try data.write(to: url)
  }

  func loadTextDumps() throws -> [TextDump] {
    let dir = textDumpsDir
    guard FileManager.default.fileExists(atPath: dir.path) else { return [] }
    let files = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
    return try files
      .filter { $0.pathExtension == "json" }
      .map { try decoder().decode(TextDump.self, from: Data(contentsOf: $0)) }
      .sorted { $0.createdAt > $1.createdAt }
  }

  // MARK: - Project README

  private func projectReadmeURL(projectId: String) -> URL {
    repoRoot
      .appendingPathComponent("state")
      .appendingPathComponent("projects")
      .appendingPathComponent(projectId)
      .appendingPathComponent("README.md")
  }

  func loadProjectReadme(projectId: String) throws -> String? {
    let url = projectReadmeURL(projectId: projectId)
    guard FileManager.default.fileExists(atPath: url.path) else { return nil }
    return try String(contentsOf: url, encoding: .utf8)
  }

  func saveProjectReadme(projectId: String, content: String) throws {
    let url = projectReadmeURL(projectId: projectId)
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.isEmpty {
      // Remove file if content is empty
      if FileManager.default.fileExists(atPath: url.path) {
        try FileManager.default.removeItem(at: url)
      }
    } else {
      try content.write(to: url, atomically: true, encoding: .utf8)
    }
  }
}

