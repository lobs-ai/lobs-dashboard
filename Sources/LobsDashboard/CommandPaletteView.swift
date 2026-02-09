import SwiftUI

// MARK: - Command Palette

/// Global command palette (⌘K) — search, navigation, and quick actions.
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
    if searchText.hasPrefix(">") { return .actions }
    if searchText.hasPrefix("#") { return .projects }
    if searchText.hasPrefix("@") { return .tasks }
    if searchText.hasPrefix("/") { return .docs }
    if searchText.hasPrefix("$") { return .inbox }
    return .all
  }
  
  private var queryText: String {
    if filterMode != .all, let first = searchText.first, first != " " {
      return String(searchText.dropFirst()).trimmingCharacters(in: .whitespaces)
    }
    return searchText.trimmingCharacters(in: .whitespaces)
  }
  
  private var results: [CommandResult] {
    var items: [CommandResult] = []
    
    // Quick actions
    if filterMode == .all || filterMode == .actions {
      items.append(contentsOf: quickActions())
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
    
    // Filter and rank by query
    if !queryText.isEmpty {
      items = items.filter { fuzzyMatch(query: queryText, target: $0.title) != nil }
      items.sort { a, b in
        rankResult(a, query: queryText) > rankResult(b, query: queryText)
      }
    }
    
    // Add recent items if no query
    if queryText.isEmpty && filterMode == .all {
      let recents = loadRecents()
      // Deduplicate by result ID
      let existingIds = Set(items.map { $0.id })
      let recentItems = recents.filter { !existingIds.contains($0.id) }
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
                FilterHint(prefix: ">", label: "Actions")
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
    
    // Execute action
    result.action()
    
    // Close palette
    withAnimation(.easeInOut(duration: 0.25)) {
      isPresented = false
    }
    
    // Reset state for next time
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
      searchText = ""
      selectedIndex = 0
    }
  }
  
  // MARK: - Result Generators
  
  private func quickActions() -> [CommandResult] {
    [
      CommandResult(
        id: "action:new-task",
        icon: "plus.circle",
        title: "Create New Task",
        subtitle: "Add a new task to the current project",
        category: "Actions",
        action: {
          onNewTask?()
        }
      ),
      CommandResult(
        id: "action:request-worker",
        icon: "bolt.circle",
        title: "Request Worker",
        subtitle: "Request orchestrator to assign work",
        category: "Actions",
        action: {
          vm.requestWorker()
          vm.flashSuccess("Worker requested ⚡")
        }
      ),
      CommandResult(
        id: "action:refresh",
        icon: "arrow.clockwise",
        title: "Refresh / Sync",
        subtitle: "Pull latest changes from repository",
        category: "Actions",
        action: {
          vm.reload()
        }
      ),
      CommandResult(
        id: "action:overview",
        icon: "house",
        title: "Go to Overview",
        subtitle: "View all projects and stats",
        category: "Navigation",
        action: {
          vm.showOverview = true
        }
      ),
      CommandResult(
        id: "action:inbox",
        icon: "tray.full",
        title: "Open Inbox",
        subtitle: "View design docs and artifacts",
        category: "Navigation",
        action: {
          onOpenInbox?(nil)
        }
      ),
      CommandResult(
        id: "action:ai-usage",
        icon: "chart.bar",
        title: "AI Usage Stats",
        subtitle: "View worker usage and costs",
        category: "Navigation",
        action: {
          onOpenAIUsage?()
        }
      )
    ]
  }
  
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
    
    // TODO: Add research tiles/docs when we have access to them
    // For now, just show research projects
    
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
  
  /// Basic fuzzy match — returns match score if all query chars appear in order in target
  private func fuzzyMatch(query: String, target: String) -> Int? {
    let queryLower = query.lowercased()
    let targetLower = target.lowercased()
    
    var queryIndex = queryLower.startIndex
    var lastMatchIndex = targetLower.startIndex
    var score = 0
    
    for (targetIndex, targetChar) in targetLower.enumerated() {
      guard queryIndex < queryLower.endIndex else { break }
      
      if queryLower[queryIndex] == targetChar {
        // Consecutive matches get bonus
        if targetIndex > 0 && targetLower.index(targetLower.startIndex, offsetBy: targetIndex - 1) == lastMatchIndex {
          score += 5
        }
        score += 1
        lastMatchIndex = targetLower.index(targetLower.startIndex, offsetBy: targetIndex)
        queryIndex = queryLower.index(after: queryIndex)
      }
    }
    
    return queryIndex == queryLower.endIndex ? score : nil
  }
  
  /// Rank results: exact > recent > prefix > fuzzy
  private func rankResult(_ result: CommandResult, query: String) -> Int {
    let titleLower = result.title.lowercased()
    let queryLower = query.lowercased()
    
    // Exact match
    if titleLower == queryLower {
      return 10000
    }
    
    // Prefix match
    if titleLower.hasPrefix(queryLower) {
      return 1000 + (100 - query.count) // Prefer shorter prefixes
    }
    
    // Word boundary match (query matches start of a word)
    let words = titleLower.split(separator: " ")
    for word in words {
      if word.hasPrefix(queryLower) {
        return 500
      }
    }
    
    // Fuzzy match score
    return fuzzyMatch(query: query, target: result.title) ?? 0
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
      } else if id.hasPrefix("action:") {
        // Reconstruct quick actions
        if let action = quickActions().first(where: { $0.id == id }) {
          var recentAction = action
          recentAction.category = "Recent"
          results.append(recentAction)
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
  case actions
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
      case 125: // down arrow
        if let handler = context.coordinator.onArrowDown {
          DispatchQueue.main.async {
            handler()
          }
        }
        return nil // consume event
      case 126: // up arrow
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
