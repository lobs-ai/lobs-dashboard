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

  private func tilesDirURL(projectId: String) -> URL {
    researchDirURL.appendingPathComponent(projectId).appendingPathComponent("tiles")
  }

  private func requestsDirURL(projectId: String) -> URL {
    researchDirURL.appendingPathComponent(projectId).appendingPathComponent("requests")
  }

  private func decoder() -> JSONDecoder {
    let d = JSONDecoder()
    d.dateDecodingStrategy = .iso8601
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
      // Prefer creation time over edit time so edits don't reshuffle the list.
      tasks.sort { (a, b) in
        if a.status.rawValue != b.status.rawValue { return a.status.rawValue < b.status.rawValue }
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
        var t = task
        t.updatedAt = Date()
        let data = try enc.encode(t)
        try data.write(to: taskFileURL(taskId: t.id), options: [.atomic])
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

  // MARK: - Research Tiles

  func loadTiles(projectId: String) throws -> [ResearchTile] {
    let dir = tilesDirURL(projectId: projectId)
    guard FileManager.default.fileExists(atPath: dir.path) else { return [] }

    let items = try FileManager.default.contentsOfDirectory(
      at: dir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
    )

    let dec = decoder()
    var tiles: [ResearchTile] = []
    for url in items where url.pathExtension.lowercased() == "json" {
      let data = try Data(contentsOf: url)
      let tile = try dec.decode(ResearchTile.self, from: data)
      tiles.append(tile)
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
      let data = try Data(contentsOf: url)
      let req = try dec.decode(ResearchRequest.self, from: data)
      requests.append(req)
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
}

