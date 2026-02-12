import SwiftUI

// MARK: - Command Palette

/// Global command palette (⌘K) — search and navigation.
struct CommandPaletteView: View {
  @ObservedObject var vm: AppViewModel
  @Binding var isPresented: Bool
  
  // Callbacks for triggering ContentView state changes
  var onNewTask: (() -> Void)? = nil
  var onOpenInbox: ((String?) -> Void)? = nil
  var onOpenAIUsage: (() -> Void)? = nil
  
  @State private var searchText = ""
  @State private var selectedIndex = 0
  @FocusState private var searchFieldFocused: Bool
  
  // Recent selections (persisted)
  @AppStorage("commandPaletteRecents") private var recentsData = ""
  
  private var filterMode: FilterMode {
    if searchText.hasPrefix("#") { return .projects }
    if searchText.hasPrefix("@") { return .tasks }
    if searchText.hasPrefix("/") { return .docs }
    if searchText.hasPrefix("$") { return .inbox }
    return .all
  }
  
  private var queryText: String {
    if searchText.hasPrefix(">") {
      return String(searchText.dropFirst()).trimmingCharacters(in: .whitespaces)
    }
    if filterMode != .all, let first = searchText.first, first != " " {
      return String(searchText.dropFirst()).trimmingCharacters(in: .whitespaces)
    }
    return searchText.trimmingCharacters(in: .whitespaces)
  }
  
  private var results: [CommandResult] {
    var items: [CommandResult] = []
    
    // Home/Overview - always available in all mode
    if filterMode == .all {
      items.append(CommandResult(
        id: "nav:home",
        icon: "house.fill",
        title: "Home",
        subtitle: "Go to overview",
        category: "Navigation",
        action: {
          vm.showOverview = true
        }
      ))
    }
    
    // Projects
    if filterMode == .all || filterMode == .projects {
      items.append(contentsOf: projectResults())
    }
    
    // Tasks
    if filterMode == .all || filterMode == .tasks {
      items.append(contentsOf: taskResults())
    }
    
    // Research docs
    if filterMode == .all || filterMode == .docs {
      items.append(contentsOf: researchResults())
    }
    
    // Inbox items
    if filterMode == .all || filterMode == .inbox {
      items.append(contentsOf: inboxResults())
    }
    
    let parsed = PaletteQuery.parse(queryText)

    // Optional project filter (e.g. "in:dashboard")
    if let pf = parsed.projectFilter, !pf.isEmpty {
      items = items.filter { matchesProjectFilter($0, projectQuery: pf) }
    }

    // Filter and rank by query (multi-token)
    if !parsed.searchTokens.isEmpty {
      let recentIds = Set(loadRecentIds())
      items = items.compactMap { result -> (CommandResult, Int)? in
        guard let score = matchScore(result: result, queryTokens: parsed.searchTokens, recentIds: recentIds) else {
          return nil
        }
        return (result, score)
      }
      .sorted { (lhs, rhs) in lhs.1 > rhs.1 }
      .map { $0.0 }
    }

    // Add recent items when there's no search text (for all modes)
    if parsed.searchTokens.isEmpty {
      let recents = loadRecents()
      let filteredRecents = recents.filter { recent in
        switch filterMode {
        case .all: return true
        case .projects: return recent.id.hasPrefix("project:") || recent.id.hasPrefix("research:")
        case .tasks: return recent.id.hasPrefix("task:")
        case .docs: return recent.id.hasPrefix("research:")
        case .inbox: return recent.id.hasPrefix("inbox:")
        }
      }
      // Deduplicate by result ID
      let existingIds = Set(items.map { $0.id })
      let recentItems = filteredRecents.filter { !existingIds.contains($0.id) }
      items = recentItems + items
    }

    return Array(items.prefix(15)) // Limit to 15 results
  }
  
  var body: some View {
    VStack(spacing: 0) {
      // Search field
      HStack(spacing: 8) {
        Image(systemName: "magnifyingglass")
          .foregroundStyle(.secondary)
          .font(.system(size: 16))
        
        TextField("Search or type a command...", text: $searchText)
          .textFieldStyle(.plain)
          .font(.system(size: 15))
          .focused($searchFieldFocused)
          .onSubmit {
            executeSelectedResult()
          }
        
        if !searchText.isEmpty {
          Button {
            searchText = ""
            selectedIndex = 0
          } label: {
            Image(systemName: "xmark.circle.fill")
              .foregroundStyle(.secondary)
              .font(.system(size: 14))
          }
          .buttonStyle(.plain)
        }
      }
      .padding(.horizontal, 16)
      .padding(.vertical, 14)
      .background(Color(NSColor.controlBackgroundColor))
      
      Divider()
      
      // Results list
      if results.isEmpty {
        VStack(spacing: 12) {
          Image(systemName: "magnifyingglass")
            .font(.system(size: 32))
            .foregroundStyle(.tertiary)
          
          Text(queryText.isEmpty ? "Type to search" : "No results")
            .font(.system(size: 13))
            .foregroundStyle(.secondary)
          
          if queryText.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
              Text("Filter modes:")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.tertiary)
              
              HStack(spacing: 12) {
                FilterHint(prefix: "#", label: "Projects")
                FilterHint(prefix: "@", label: "Tasks")
              }
              HStack(spacing: 12) {
                FilterHint(prefix: "/", label: "Docs")
                FilterHint(prefix: "$", label: "Inbox")
              }
            }
            .padding(.top, 4)
          }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, 40)
      } else {
        ScrollView {
          ScrollViewReader { proxy in
            LazyVStack(spacing: 0) {
              ForEach(Array(results.enumerated()), id: \.element.id) { index, result in
                ResultRow(
                  result: result,
                  isSelected: index == selectedIndex,
                  onTap: {
                    selectedIndex = index
                    executeSelectedResult()
                  }
                )
                .id(result.id)
                
                if index < results.count - 1 {
                  Divider()
                    .padding(.leading, 48)
                }
              }
            }
            .onChange(of: selectedIndex) { newIndex in
              if newIndex >= 0 && newIndex < results.count {
                withAnimation(.easeOut(duration: 0.15)) {
                  proxy.scrollTo(results[newIndex].id, anchor: .center)
                }
              }
            }
          }
        }
        .frame(maxHeight: 320)
      }
    }
    .background(Color(NSColor.windowBackgroundColor))
    .onAppear {
      searchFieldFocused = true
    }
    .onChange(of: searchText) { _ in
      // Reset selection when query changes
      selectedIndex = 0
    }
    .background(
      KeyEventHandler(
        onArrowDown: {
          if selectedIndex < results.count - 1 {
            selectedIndex += 1
          }
        },
        onArrowUp: {
          if selectedIndex > 0 {
            selectedIndex -= 1
          }
        },
        onEscape: {
          withAnimation(.easeInOut(duration: 0.25)) {
            isPresented = false
          }
        }
      )
    )
  }
  
  // MARK: - Actions
  
  private func executeSelectedResult() {
    guard selectedIndex >= 0 && selectedIndex < results.count else { return }
    let result = results[selectedIndex]
    
    // Save to recents
    saveRecent(result)
    
    // Close palette first for snappy dismissal
    withAnimation(.easeInOut(duration: 0.25)) {
      isPresented = false
    }
    
    // Execute action AFTER dismissal animation completes (0.3s)
    // This prevents heavy view updates from interfering with the close animation
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
      result.action()
    }
    
    // Reset state after action executes
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
      searchText = ""
      selectedIndex = 0
    }
  }
  
  // MARK: - Result Generators
  
  private func projectResults() -> [CommandResult] {
    vm.sortedActiveProjects.map { project in
      let activeCount = vm.tasks.filter { $0.projectId == project.id && $0.status == .active }.count
      return CommandResult(
        id: "project:\(project.id)",
        icon: projectTypeIcon(project.resolvedType),
        title: project.title,
        subtitle: activeCount > 0 ? "\(activeCount) active task\(activeCount == 1 ? "" : "s")" : "No active tasks",
        category: "Projects",
        action: {
          vm.selectedProjectId = project.id
          vm.showOverview = false
        }
      )
    }
  }
  
  private func taskResults() -> [CommandResult] {
    let activeTasks = vm.tasks.filter { $0.status != .completed && $0.status != .rejected }
    return activeTasks.prefix(50).map { task in
      CommandResult(
        id: "task:\(task.id)",
        icon: taskStatusIcon(task.status),
        title: task.title,
        subtitle: statusLabel(task.status) + (task.projectId != nil ? " • \(projectTitle(task.projectId!))" : ""),
        category: "Tasks",
        action: {
          // Navigate to the task's project
          if let projectId = task.projectId {
            vm.selectedProjectId = projectId
            vm.showOverview = false
          }
          // Select the task
          vm.selectedTaskId = task.id
        }
      )
    }
  }
  
  private func researchResults() -> [CommandResult] {
    // Get all research projects
    let researchProjects = vm.projects.filter { $0.resolvedType == .research }
    
    var results: [CommandResult] = []
    
    // Add research projects as navigable items
    for project in researchProjects {
      results.append(CommandResult(
        id: "research:\(project.id)",
        icon: "doc.text",
        title: project.title,
        subtitle: "Research project",
        category: "Research",
        action: {
          vm.selectedProjectId = project.id
          vm.showOverview = false
        }
      ))
    }
    
    // Add research tiles (link, note, finding, comparison)
    let activeTiles = vm.researchTiles.filter { $0.resolvedStatus == .active }
    for tile in activeTiles {
      // Get project name for context
      let projectName = vm.projects.first(where: { $0.id == tile.projectId })?.title ?? "Unknown"
      
      // Icon based on tile type
      let icon: String
      let typeLabel: String
      switch tile.type {
      case .link:
        icon = "link"
        typeLabel = "Link"
      case .note:
        icon = "note.text"
        typeLabel = "Note"
      case .finding:
        icon = "lightbulb"
        typeLabel = "Finding"
      case .comparison:
        icon = "list.bullet.rectangle"
        typeLabel = "Comparison"
      }
      
      results.append(CommandResult(
        id: "tile:\(tile.id)",
        icon: icon,
        title: tile.title,
        subtitle: "\(typeLabel) in \(projectName)",
        category: "Research",
        action: {
          // Navigate to the project containing this tile
          vm.selectedProjectId = tile.projectId
          vm.showOverview = false
          // Note: Could add selectedTileId to vm if needed for direct navigation
        }
      ))
    }
    
    // Add research requests
    let activeRequests = vm.researchRequests.filter { $0.status != .completed && $0.status != .done }
    for request in activeRequests {
      // Get project name for context
      let projectName = vm.projects.first(where: { $0.id == request.projectId })?.title ?? "Unknown"
      
      // Icon and status label based on request status
      let icon: String
      let statusLabel: String
      switch request.status {
      case .open:
        icon = "doc.badge.plus"
        statusLabel = "Open"
      case .inProgress:
        icon = "gearshape"
        statusLabel = "In Progress"
      case .blocked:
        icon = "exclamationmark.triangle"
        statusLabel = "Blocked"
      default:
        icon = "doc.text"
        statusLabel = request.status.rawValue.capitalized
      }
      
      // Use first ~60 chars of prompt as title
      let title = request.prompt.count > 60
        ? String(request.prompt.prefix(60)) + "..."
        : request.prompt
      
      results.append(CommandResult(
        id: "request:\(request.id)",
        icon: icon,
        title: title,
        subtitle: "\(statusLabel) research request in \(projectName)",
        category: "Research",
        action: {
          // Navigate to the project containing this request
          vm.selectedProjectId = request.projectId
          vm.showOverview = false
          // Note: Could add selectedRequestId to vm if needed for direct navigation
        }
      ))
    }
    
    return results
  }
  
  private func inboxResults() -> [CommandResult] {
    let inboxItems = vm.inboxItems
    return inboxItems.prefix(20).map { item in
      CommandResult(
        id: "inbox:\(item.id)",
        icon: "doc.text",
        title: item.title,
        subtitle: "Inbox item • \(item.filename)",
        category: "Inbox",
        action: {
          // Open inbox view with this item selected
          onOpenInbox?(item.id)
        }
      )
    }
  }
  
  // MARK: - Fuzzy Matching & Ranking

  private func matchScore(result: CommandResult, queryTokens: [String], recentIds: Set<String>) -> Int? {
    // Score title and subtitle; allow matches in either.
    let titleScore = FuzzyMatcher.score(queryTokens: queryTokens, target: result.title)
    let subtitleScore = FuzzyMatcher.score(queryTokens: queryTokens, target: result.subtitle)

    let base = max(titleScore ?? Int.min, subtitleScore ?? Int.min)
    guard base != Int.min else {
      return nil
    }

    // Slight boost if this is a recent selection.
    let recentBoost = recentIds.contains(result.id) ? 120 : 0

    // Prefer title matches over subtitle-only matches.
    let titleBoost = (titleScore != nil) ? 40 : 0

    return base + recentBoost + titleBoost
  }

  private func matchesProjectFilter(_ result: CommandResult, projectQuery: String) -> Bool {
    let q = projectQuery.trimmingCharacters(in: .whitespacesAndNewlines)
    if q.isEmpty { return true }

    // Projects: match against their own title.
    if result.id.hasPrefix("project:") {
      return FuzzyMatcher.score(queryTokens: [q], target: result.title) != nil
    }

    // Research projects are also projects.
    if result.id.hasPrefix("research:") {
      return FuzzyMatcher.score(queryTokens: [q], target: result.title) != nil
    }

    // Tasks: match against the associated project title.
    if result.id.hasPrefix("task:") {
      let taskId = String(result.id.dropFirst(5))
      if let task = vm.tasks.first(where: { $0.id == taskId }),
         let pid = task.projectId {
        let pt = projectTitle(pid)
        return FuzzyMatcher.score(queryTokens: [q], target: pt) != nil
      }
      return false
    }

    // Inbox items: no project association.
    return false
  }

  private func loadRecentIds() -> [String] {
    guard !recentsData.isEmpty,
          let data = recentsData.data(using: .utf8),
          let ids = try? JSONDecoder().decode([String].self, from: data) else {
      return []
    }
    return ids
  }

  // MARK: - Recents Persistence
  
  private func loadRecents() -> [CommandResult] {
    guard !recentsData.isEmpty,
          let data = recentsData.data(using: .utf8),
          let ids = try? JSONDecoder().decode([String].self, from: data) else {
      return []
    }
    
    // Reconstruct results from IDs (limited to available data)
    var results: [CommandResult] = []
    
    for id in ids.prefix(5) { // Keep last 5 recents
      if id.hasPrefix("project:") {
        let projectId = String(id.dropFirst(8))
        if let project = vm.projects.first(where: { $0.id == projectId }) {
          let activeCount = vm.tasks.filter { $0.projectId == project.id && $0.status == .active }.count
          results.append(CommandResult(
            id: id,
            icon: projectTypeIcon(project.resolvedType),
            title: project.title,
            subtitle: activeCount > 0 ? "\(activeCount) active task\(activeCount == 1 ? "" : "s")" : "No active tasks",
            category: "Recent",
            action: {
              vm.selectedProjectId = project.id
              vm.showOverview = false
            }
          ))
        }
      } else if id.hasPrefix("task:") {
        let taskId = String(id.dropFirst(5))
        if let task = vm.tasks.first(where: { $0.id == taskId }) {
          results.append(CommandResult(
            id: id,
            icon: taskStatusIcon(task.status),
            title: task.title,
            subtitle: statusLabel(task.status) + (task.projectId != nil ? " • \(projectTitle(task.projectId!))" : ""),
            category: "Recent",
            action: {
              if let projectId = task.projectId {
                vm.selectedProjectId = projectId
                vm.showOverview = false
              }
              vm.selectedTaskId = task.id
            }
          ))
        }
      }
    }
    
    return results
  }
  
  private func saveRecent(_ result: CommandResult) {
    var ids = (try? JSONDecoder().decode([String].self, from: recentsData.data(using: .utf8) ?? Data())) ?? []
    
    // Remove if already exists (move to front)
    ids.removeAll { $0 == result.id }
    
    // Add to front
    ids.insert(result.id, at: 0)
    
    // Keep last 10
    ids = Array(ids.prefix(10))
    
    // Save
    if let data = try? JSONEncoder().encode(ids),
       let string = String(data: data, encoding: .utf8) {
      recentsData = string
    }
  }
  
  // MARK: - Helpers
  
  private func projectTitle(_ id: String) -> String {
    vm.projects.first(where: { $0.id == id })?.title ?? "Unknown"
  }
  
  private func statusLabel(_ status: TaskStatus) -> String {
    switch status {
    case .inbox: return "Inbox"
    case .active: return "Active"
    case .completed: return "Done"
    case .rejected: return "Rejected"
    case .waitingOn: return "Waiting"
    case .other(let s): return s.capitalized
    }
  }
  
  private func taskStatusIcon(_ status: TaskStatus) -> String {
    switch status {
    case .inbox: return "tray"
    case .active: return "circle"
    case .completed: return "checkmark.circle"
    case .rejected: return "xmark.circle"
    case .waitingOn: return "clock"
    case .other: return "circle"
    }
  }
}

// MARK: - Filter Mode

private enum FilterMode {
  case all
  case projects
  case tasks
  case docs
  case inbox
}

// MARK: - Command Result

struct CommandResult: Identifiable, Hashable {
  let id: String
  let icon: String
  let title: String
  let subtitle: String
  var category: String
  let action: () -> Void
  
  static func == (lhs: CommandResult, rhs: CommandResult) -> Bool {
    lhs.id == rhs.id
  }
  
  func hash(into hasher: inout Hasher) {
    hasher.combine(id)
  }
}

// MARK: - Result Row

private struct ResultRow: View {
  let result: CommandResult
  let isSelected: Bool
  let onTap: () -> Void
  
  @State private var isHovering = false
  
  var body: some View {
    HStack(spacing: 12) {
      // Icon
      Image(systemName: result.icon)
        .font(.system(size: 16))
        .foregroundStyle(isSelected ? .white : .secondary)
        .frame(width: 20)
      
      // Title & subtitle
      VStack(alignment: .leading, spacing: 2) {
        Text(result.title)
          .font(.system(size: 13))
          .foregroundStyle(isSelected ? .white : .primary)
          .lineLimit(1)
        
        Text(result.subtitle)
          .font(.system(size: 11))
          .foregroundStyle(isSelected ? .white.opacity(0.8) : .secondary)
          .lineLimit(1)
      }
      
      Spacer()
      
      // Category badge
      Text(result.category)
        .font(.system(size: 10, weight: .medium))
        .foregroundStyle(isSelected ? .white.opacity(0.7) : Color.secondary)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background((isSelected ? Color.white : Color.gray).opacity(isSelected ? 0.2 : 0.1))
        .clipShape(Capsule())
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 10)
    .background(isSelected ? Color.accentColor : (isHovering ? Color.primary.opacity(0.05) : Color.clear))
    .contentShape(Rectangle())
    .onTapGesture { onTap() }
    .onHover { hovering in
      isHovering = hovering
    }
    .animation(.easeOut(duration: 0.1), value: isSelected)
    .animation(.easeOut(duration: 0.1), value: isHovering)
  }
}

// MARK: - Filter Hint

private struct FilterHint: View {
  let prefix: String
  let label: String
  
  var body: some View {
    HStack(spacing: 4) {
      Text(prefix)
        .font(.system(size: 11, weight: .bold, design: .monospaced))
        .foregroundStyle(.white)
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .background(Color.accentColor)
        .clipShape(RoundedRectangle(cornerRadius: 3))
      
      Text(label)
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
    }
  }
}

// MARK: - Key Event Handler

/// Intercepts arrow keys and escape for navigation using local event monitor
private struct KeyEventHandler: NSViewRepresentable {
  let onArrowDown: () -> Void
  let onArrowUp: () -> Void
  let onEscape: () -> Void
  
  func makeNSView(context: Context) -> NSView {
    let view = NSView()
    
    // Store closures in coordinator
    context.coordinator.onArrowDown = onArrowDown
    context.coordinator.onArrowUp = onArrowUp
    context.coordinator.onEscape = onEscape
    
    // Install local event monitor
    context.coordinator.monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
      switch event.keyCode {
      case 125, 38: // down arrow / j
        if let handler = context.coordinator.onArrowDown {
          DispatchQueue.main.async {
            handler()
          }
        }
        return nil // consume event
      case 126, 40: // up arrow / k
        if let handler = context.coordinator.onArrowUp {
          DispatchQueue.main.async {
            handler()
          }
        }
        return nil // consume event
      case 53: // escape
        if let handler = context.coordinator.onEscape {
          DispatchQueue.main.async {
            handler()
          }
        }
        return nil // consume event
      default:
        return event
      }
    }
    
    return view
  }
  
  func updateNSView(_ nsView: NSView, context: Context) {
    // Update closures in coordinator
    context.coordinator.onArrowDown = onArrowDown
    context.coordinator.onArrowUp = onArrowUp
    context.coordinator.onEscape = onEscape
  }
  
  static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
    // Clean up event monitor
    if let monitor = coordinator.monitor {
      NSEvent.removeMonitor(monitor)
    }
  }
  
  func makeCoordinator() -> Coordinator {
    Coordinator()
  }
  
  class Coordinator {
    var monitor: Any?
    var onArrowDown: (() -> Void)?
    var onArrowUp: (() -> Void)?
    var onEscape: (() -> Void)?
  }
}

// MARK: - Helper Functions

func projectTypeIcon(_ type: ProjectType) -> String {
  switch type {
  case .kanban: return "square.grid.2x2"
  case .research: return "doc.text.magnifyingglass"
  case .tracker: return "list.bullet.clipboard"
  }
}

func projectTypeAccentColor(_ type: ProjectType) -> Color {
  switch type {
  case .kanban: return .blue
  case .research: return .purple
  case .tracker: return .green
  }
}

func shapeIcon(_ shape: TaskShape) -> String {
  switch shape {
  case .deep: return "🧠"
  case .shallow: return "⚡"
  case .creative: return "🎨"
  case .waiting: return "⏸️"
  case .admin: return "📋"
  }
}

func shapeLabel(_ shape: TaskShape) -> String {
  shape.rawValue.capitalized
}

func shapeColor(_ shape: TaskShape) -> Color {
  switch shape {
  case .deep: return .purple
  case .shallow: return .green
  case .creative: return .orange
  case .waiting: return .yellow
  case .admin: return .blue
  }
}

// MARK: - Agent Helpers

func availableAgentTypes() -> [(String, String, String)] {
  [
    ("programmer", "🛠️", "Code implementation, bug fixes"),
    ("researcher", "🔬", "Research and investigation"),
    ("reviewer", "🔍", "Code review and feedback"),
    ("writer", "✍️", "Documentation and writing"),
    ("architect", "🏗️", "System design and architecture")
  ]
}

func agentIcon(_ agent: String) -> String {
  switch agent.lowercased() {
  case "programmer": return "🛠️"
  case "researcher": return "🔬"
  case "reviewer": return "🔍"
  case "writer": return "✍️"
  case "architect": return "🏗️"
  default: return "🤖"
  }
}
