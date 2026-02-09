import SwiftUI

// MARK: - Theme (shared palette)

// Theme is defined in Theme.swift
private typealias OTheme = Theme

// MARK: - Project Drop Delegate

private struct ProjectDropDelegate: DropDelegate {
  let targetId: String
  @Binding var draggingId: String?
  let vm: AppViewModel

  func validateDrop(info: DropInfo) -> Bool { true }

  func performDrop(info: DropInfo) -> Bool {
    guard let fromId = draggingId, fromId != targetId else { return false }
    vm.reorderProject(fromId: fromId, beforeId: targetId)
    draggingId = nil
    return true
  }

  func dropEntered(info: DropInfo) {}

  func dropExited(info: DropInfo) {}

  func dropUpdated(info: DropInfo) -> DropProposal? {
    DropProposal(operation: .move)
  }
}

// MARK: - Overview View

struct OverviewView: View {
  @ObservedObject var vm: AppViewModel
  var onSelectProject: (String) -> Void
  var onOpenInbox: ((String?) -> Void)? = nil
  var onOpenAIUsage: (() -> Void)? = nil

  @State private var detailTask: DashboardTask? = nil
  @State private var showDetailedStats: Bool = false
  @State private var showTimeline: Bool = false
  @State private var draggingProjectId: String? = nil
  @State private var showCreateProject: Bool = false
  @State private var showAllCompletedThisWeekSheet: Bool = false
  @State private var showAllActiveTasksSheet: Bool = false
  @State private var showAllResearchRequestsSheet: Bool = false

  private var allTasks: [DashboardTask] { vm.tasks }

  private var activeProjects: [Project] {
    vm.sortedActiveProjects
  }

  /// Helper to check if a task belongs to an archived project
  private func isTaskFromArchivedProject(_ task: DashboardTask) -> Bool {
    let projectId = task.projectId ?? "default"
    let project = vm.projects.first(where: { $0.id == projectId })
    return project?.archived == true
  }

  // Stats
  private var activeTasks: Int {
    allTasks.filter { $0.status == .active }.count
  }

  private var completedThisWeek: Int {
    // Use calendar week (Monday–Sunday) to match detailed stats view
    let calendar = Calendar.current
    var comps = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date())
    comps.weekday = 2 // Monday
    let weekStart = calendar.date(from: comps) ?? Date()
    let weekEnd = calendar.date(byAdding: .day, value: 7, to: weekStart) ?? Date()
    return allTasks.filter { task in
      guard task.status == .completed && !isTaskFromArchivedProject(task) else { return false }
      let completionDate = task.finishedAt ?? task.updatedAt
      return completionDate >= weekStart && completionDate < weekEnd
    }.count
  }

  /// Open research request counts per project (cached by AppViewModel).
  private var researchRequestCountsByProject: [String: Int] {
    Dictionary(uniqueKeysWithValues: vm.overviewResearchStatsByProject.map { ($0.key, $0.value.openRequests) })
  }

  /// Total (all statuses) research request counts per project (cached by AppViewModel).
  private var totalResearchRequestCountsByProject: [String: Int] {
    Dictionary(uniqueKeysWithValues: vm.overviewResearchStatsByProject.map { ($0.key, $0.value.totalRequests) })
  }

  /// Research deliverable counts per project (cached by AppViewModel).
  private var researchDeliverableCountsByProject: [String: Int] {
    Dictionary(uniqueKeysWithValues: vm.overviewResearchStatsByProject.map { ($0.key, $0.value.deliverables) })
  }

  private var openResearchRequests: Int {
    vm.overviewOpenResearchRequests.count
  }

  private var blockedTasks: Int {
    allTasks.filter { $0.workState == .blocked }.count
  }

  private var inboxTasks: Int {
    allTasks.filter { $0.status == .inbox }.count
  }

  /// Stale tasks: active/inbox tasks with no updates in >7 days.
  private var staleTasks: Int {
    let cutoff = Date().addingTimeInterval(-7 * 86400)
    return allTasks.filter { t in
      (t.status == .active || t.status == .inbox) && t.updatedAt < cutoff
    }.count
  }

  /// Inbox items needing attention (unread docs or unread follow-ups).
  private var inboxNeedsAttentionCount: Int {
    vm.unreadInboxCount
  }

  // MARK: - Section Data (Active / Research / Done This Week)

  /// All active tasks across all projects, sorted by most recently updated.
  private var activeTasksList: [DashboardTask] {
    allTasks.filter { $0.status == .active }
      .sorted { $0.updatedAt > $1.updatedAt }
  }

  /// All open research requests across all research projects (cached by AppViewModel).
  private var openResearchRequestsList: [ResearchRequest] {
    vm.overviewOpenResearchRequests
  }

  /// Tasks completed this week.
  private var completedThisWeekTasks: [DashboardTask] {
    let calendar = Calendar.current
    var comps = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date())
    comps.weekday = 2 // Monday
    let weekStart = calendar.date(from: comps) ?? Date()
    let weekEnd = calendar.date(byAdding: .day, value: 7, to: weekStart) ?? Date()
    return allTasks.filter { task in
      guard task.status == .completed && !isTaskFromArchivedProject(task) else { return false }
      let completionDate = task.finishedAt ?? task.updatedAt
      return completionDate >= weekStart && completionDate < weekEnd
    }
    .sorted { ($0.finishedAt ?? $0.updatedAt) > ($1.finishedAt ?? $1.updatedAt) }
  }

  // MARK: - Activity Feed

  fileprivate enum ActivityEvent: Identifiable {
    case taskCompleted(DashboardTask)
    case inboxItem(InboxItem)
    case workerRun(WorkerHistoryRun)

    var id: String {
      switch self {
      case .taskCompleted(let t):
        return "task-completed-\(t.id)-\(t.updatedAt.timeIntervalSince1970)"
      case .inboxItem(let item):
        return "inbox-\(item.id)-\(item.modifiedAt.timeIntervalSince1970)"
      case .workerRun(let run):
        return "worker-\(run.id)"
      }
    }

    var date: Date {
      switch self {
      case .taskCompleted(let t):
        return t.updatedAt
      case .inboxItem(let item):
        return item.modifiedAt
      case .workerRun(let run):
        return run.endedAt ?? run.startedAt ?? Date.distantPast
      }
    }
  }

  /// Reverse-chronological activity feed (last 7 days).
  /// Uses state timestamps (tasks/inbox/worker history) as a lightweight proxy for git history.
  private var activityFeed: [ActivityEvent] {
    let weekAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()

    var events: [ActivityEvent] = []

    // Task completed
    for t in allTasks where t.status == .completed {
      let completionDate = t.finishedAt ?? t.updatedAt
      if completionDate >= weekAgo {
        events.append(.taskCompleted(t))
      }
    }

    // New/updated inbox items (docs/artifacts)
    for item in vm.inboxItems where item.modifiedAt >= weekAgo {
      events.append(.inboxItem(item))
    }

    // Worker ran
    if let runs = vm.workerHistory?.runs {
      for run in runs {
        let d = run.endedAt ?? run.startedAt
        if let d, d >= weekAgo {
          events.append(.workerRun(run))
        }
      }
    }

    return events
      .sorted { $0.date > $1.date }
      .prefix(25)
      .map { $0 }
  }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 24) {
        headerSection
        statsSection
        velocitySection
        detailedStatsSection
        workerStatusSection
        syncStatusSection
        projectCardsSection
        columnsSection
        inboxColumnsSection
      }
      .padding(24)
    }
    .background(OTheme.boardBg)
    .onAppear {
      // Ensure cached research stats exist even if the user lands on Overview first.
      vm.refreshOverviewResearchStats()
    }
    .sheet(item: $detailTask) { task in
      OverviewTaskDetailSheet(task: task, vm: vm)
        .frame(minWidth: 480, minHeight: 500)
    }
    .sheet(isPresented: $showTimeline) {
      TimelineSheetView(tasks: vm.tasks, projects: vm.projects)
        .frame(minWidth: 900, minHeight: 600)
    }
    .sheet(isPresented: $showAllActiveTasksSheet) {
      OverviewTaskListSheet(
        title: "Active Tasks",
        subtitle: "All active tasks across projects",
        tasks: activeTasksList,
        vm: vm,
        showTimestamp: false,
        onTapTask: { task in
          vm.selectTask(task)
          detailTask = task
        }
      )
      .frame(minWidth: 560, minHeight: 620)
    }
    .sheet(isPresented: $showAllCompletedThisWeekSheet) {
      OverviewTaskListSheet(
        title: "Done This Week",
        subtitle: "Completed tasks updated this week",
        tasks: completedThisWeekTasks,
        vm: vm,
        showTimestamp: true,
        onTapTask: { task in
          vm.selectTask(task)
          detailTask = task
        }
      )
      .frame(minWidth: 560, minHeight: 620)
    }
    .sheet(isPresented: $showAllResearchRequestsSheet) {
      OverviewResearchRequestListSheet(
        title: "Open Research Requests",
        requests: openResearchRequestsList,
        projects: vm.projects,
        onSelectProject: { projectId in
          onSelectProject(projectId)
        }
      )
      .frame(minWidth: 600, minHeight: 620)
    }
  }

  private var headerSection: some View {
    HStack(spacing: 10) {
      Image(systemName: "house.fill")
        .font(.title2)
        .foregroundStyle(.linearGradient(
          colors: [.blue, .purple],
          startPoint: .topLeading,
          endPoint: .bottomTrailing
        ))
      Text("Overview")
        .font(.title2)
        .fontWeight(.bold)
      Spacer()
    }
    .padding(.bottom, 4)
  }

  private var statsSection: some View {
    HStack(alignment: .top) {
      StatsRow(
        activeTasks: activeTasks,
        completedThisWeek: completedThisWeek,
        openResearchRequests: openResearchRequests,
        blockedTasks: blockedTasks,
        inboxTasks: inboxTasks,
        staleTasks: staleTasks,
        inboxNeedsAttentionCount: inboxNeedsAttentionCount,
        workerHistory: vm.workerHistory,
        mainSessionUsage: vm.mainSessionUsage
      )
      Spacer()
      aiUsageButton
      timelineButton
      detailedStatsButton
    }
  }

  private var aiUsageButton: some View {
    Button {
      onOpenAIUsage?()
    } label: {
      HStack(spacing: 4) {
        Image(systemName: "chart.line.uptrend.xyaxis")
          .font(.footnote)
        Text("AI Usage")
          .font(.footnote)
      }
      .padding(.horizontal, 10)
      .padding(.vertical, 6)
      .background(OTheme.subtle)
      .clipShape(RoundedRectangle(cornerRadius: 8))
    }
    .buttonStyle(.plain)
  }

  private var timelineButton: some View {
    Button {
      showTimeline = true
    } label: {
      HStack(spacing: 4) {
        Image(systemName: "calendar")
          .font(.footnote)
        Text("Timeline")
          .font(.footnote)
      }
      .padding(.horizontal, 10)
      .padding(.vertical, 6)
      .background(OTheme.subtle)
      .clipShape(RoundedRectangle(cornerRadius: 8))
    }
    .buttonStyle(.plain)
  }

  private var detailedStatsButton: some View {
    Button {
      withAnimation(.easeInOut(duration: 0.2)) {
        showDetailedStats.toggle()
      }
    } label: {
      HStack(spacing: 4) {
        Image(systemName: showDetailedStats ? "chart.bar.fill" : "chart.bar")
          .font(.footnote)
        Text(showDetailedStats ? "Hide Stats" : "Detailed Stats")
          .font(.footnote)
      }
      .padding(.horizontal, 10)
      .padding(.vertical, 6)
      .background(showDetailedStats ? Color.accentColor.opacity(0.15) : OTheme.subtle)
      .clipShape(RoundedRectangle(cornerRadius: 8))
    }
    .buttonStyle(.plain)
  }

  private var velocitySection: some View {
    VelocityChartView(tasks: allTasks)
  }

  @ViewBuilder
  private var detailedStatsSection: some View {
    if showDetailedStats {
      DetailedStatsView(tasks: allTasks, projects: activeProjects, researchRequestCountsByProject: researchRequestCountsByProject)
        .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .top)))
        .clipped()
    }
  }

  @ViewBuilder
  private var workerStatusSection: some View {
    if let ws = vm.workerStatus {
      let stale = isWorkerStatusStale(ws)
      WorkerStatusCard(
        status: ws,
        history: vm.workerHistory,
        canRequestWorker: (!ws.active || stale) && !vm.workerRequestPending,
        workerRequested: vm.workerRequestPending,
        onRequestWorker: { vm.requestWorker() },
        tasks: allTasks
      )
    }
  }

  @ViewBuilder
  private var syncStatusSection: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        Image(systemName: "arrow.triangle.2.circlepath")
          .foregroundStyle(.blue)
        Text("Sync Status")
          .font(.headline)
          .fontWeight(.bold)
        Spacer()
        if vm.pendingChangesCount > 0 {
          Text("\(vm.pendingChangesCount) pending")
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
              Capsule()
                .fill(Color.orange.opacity(0.2))
            )
        }
      }

      VStack(alignment: .leading, spacing: 8) {
        if let lastPush = vm.lastSuccessfulPushAt {
          HStack {
            Text("Last sync:")
              .foregroundStyle(.secondary)
            Text(lastPush, style: .relative)
              .foregroundStyle(.primary)
            Text("ago")
              .foregroundStyle(.secondary)
          }
          .font(.callout)
        }

        if let error = vm.lastPushError, !error.isEmpty {
          HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
              .foregroundStyle(.red)
            Text(error)
              .font(.callout)
              .foregroundStyle(.red)
          }
          .padding(8)
          .background(
            RoundedRectangle(cornerRadius: 6)
              .fill(Color.red.opacity(0.1))
          )
        }

        if vm.syncBlockedByUncommitted {
          VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
              Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
              Text("Sync blocked by uncommitted changes")
                .font(.callout)
                .foregroundStyle(.orange)
            }

            Text("Commit or discard local changes to resume syncing.")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
          .padding(8)
          .background(
            RoundedRectangle(cornerRadius: 6)
              .fill(Color.orange.opacity(0.1))
          )
        }
      }
    }
    .padding(16)
    .background(
      RoundedRectangle(cornerRadius: OTheme.cardRadius)
        .fill(OTheme.cardBg)
    )
    .overlay(
      RoundedRectangle(cornerRadius: OTheme.cardRadius)
        .strokeBorder(Color.primary.opacity(0.1), lineWidth: 1)
    )
  }

  private func isWorkerStatusStale(_ status: WorkerStatus) -> Bool {
    // If the worker looks active but hasn't emitted a heartbeat recently, treat the status as stale.
    // This prevents the UI from getting stuck in "running" when the worker crashed or was killed.
    guard status.active else { return false }
    let cutoff: TimeInterval = 10 * 60
    if let hb = status.lastHeartbeat {
      return Date().timeIntervalSince(hb) > cutoff
    }
    if let started = status.startedAt {
      return Date().timeIntervalSince(started) > cutoff
    }
    return false
  }

  private var projectCardsSection: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Projects")
        .font(.headline)
        .fontWeight(.bold)

      LazyVGrid(columns: [
        GridItem(.flexible(minimum: 280, maximum: .infinity), spacing: 16),
        GridItem(.flexible(minimum: 280, maximum: .infinity), spacing: 16),
        GridItem(.flexible(minimum: 280, maximum: .infinity), spacing: 16)
      ], spacing: 16) {
        ForEach(activeProjects) { project in
          ProjectCard(
            project: project,
            tasks: allTasks.filter { ($0.projectId ?? "default") == project.id },
            lastCommitAt: vm.projectLastCommitAt[project.id],
            researchRequestCount: researchRequestCountsByProject[project.id] ?? 0,
            totalResearchRequestCount: totalResearchRequestCountsByProject[project.id] ?? 0,
            researchDeliverableCount: researchDeliverableCountsByProject[project.id] ?? 0,
            wipLimit: vm.wipLimitActive,
            onTap: { onSelectProject(project.id) }
          )
          .onDrag {
            draggingProjectId = project.id
            return NSItemProvider(object: project.id as NSString)
          }
          .onDrop(of: [.text], delegate: ProjectDropDelegate(
            targetId: project.id,
            draggingId: $draggingProjectId,
            vm: vm
          ))
        }

        Button { showCreateProject = true } label: {
          VStack(spacing: 8) {
            Image(systemName: "plus.circle")
              .font(.system(size: 24))
              .foregroundStyle(.secondary)
            Text("New Project")
              .font(.callout)
              .fontWeight(.medium)
              .foregroundStyle(.secondary)
          }
          .frame(maxWidth: .infinity, minHeight: 160, maxHeight: 160)
          .contentShape(Rectangle())
          .background(
            RoundedRectangle(cornerRadius: OTheme.cardRadius)
              .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [6, 4]))
              .foregroundStyle(Color.secondary.opacity(0.3))
          )
        }
        .buttonStyle(.plain)
      }
      .sheet(isPresented: $showCreateProject) {
        CreateProjectSheet(vm: vm)
      }
    }
  }

  private var columnsSection: some View {
    HStack(alignment: .top, spacing: 16) {
      activeTasksColumn
      researchRequestsColumn
      completedThisWeekColumn
    }
  }

  private var activeTasksColumn: some View {
    OverviewSectionColumn(
      title: "Active",
      icon: "flame.fill",
      color: .orange,
      badgeCount: activeTasksList.count
    ) {
      if activeTasksList.isEmpty {
        Text("No active tasks")
          .font(.footnote)
          .foregroundStyle(.secondary)
          .padding(.vertical, 20)
          .frame(maxWidth: .infinity)
      } else {
        let snapshotLimit = 5
        let visible = Array(activeTasksList.prefix(snapshotLimit))
        ForEach(Array(visible.enumerated()), id: \.element.id) { idx, task in
          OverviewTaskRow(task: task, projectName: vm.projects.first(where: { $0.id == (task.projectId ?? "default") })?.title, onTap: {
            vm.selectTask(task)
            detailTask = task
          })
          if idx < visible.count - 1 {
            Divider().padding(.leading, 32)
          }
        }
        if activeTasksList.count > snapshotLimit {
          Divider().padding(.leading, 32)
          Button {
            showAllActiveTasksSheet = true
          } label: {
            Text("View all \(activeTasksList.count) active tasks →")
              .font(.footnote)
              .foregroundStyle(Color.orange)
              .frame(maxWidth: .infinity, alignment: .center)
              .padding(.vertical, 8)
          }
          .buttonStyle(.plain)
        }
      }
    }
  }

  private var researchRequestsColumn: some View {
    OverviewSectionColumn(
      title: "Research",
      icon: "magnifyingglass",
      color: .purple,
      badgeCount: openResearchRequestsList.count
    ) {
      if openResearchRequestsList.isEmpty {
        Text("No open research requests")
          .font(.footnote)
          .foregroundStyle(.secondary)
          .padding(.vertical, 20)
          .frame(maxWidth: .infinity)
      } else {
        let snapshotLimit = 5
        let visible = Array(openResearchRequestsList.prefix(snapshotLimit))
        ForEach(Array(visible.enumerated()), id: \.element.id) { idx, req in
          OverviewResearchRow(request: req, projectName: vm.projects.first(where: { $0.id == req.projectId })?.title, onTap: {
            onSelectProject(req.projectId)
          })
          if idx < visible.count - 1 {
            Divider().padding(.leading, 32)
          }
        }
        if openResearchRequestsList.count > snapshotLimit {
          Divider().padding(.leading, 32)
          Button {
            showAllResearchRequestsSheet = true
          } label: {
            Text("View all \(openResearchRequestsList.count) requests →")
              .font(.footnote)
              .foregroundStyle(.purple)
              .frame(maxWidth: .infinity, alignment: .center)
              .padding(.vertical, 8)
          }
          .buttonStyle(.plain)
        }
      }
    }
  }

  private var completedThisWeekColumn: some View {
    OverviewSectionColumn(
      title: "Done This Week",
      icon: "checkmark.circle.fill",
      color: .green,
      badgeCount: completedThisWeekTasks.count
    ) {
      if completedThisWeekTasks.isEmpty {
        Text("Nothing completed this week")
          .font(.footnote)
          .foregroundStyle(.secondary)
          .padding(.vertical, 20)
          .frame(maxWidth: .infinity)
      } else {
        let snapshotLimit = 5
        let visible = Array(completedThisWeekTasks.prefix(snapshotLimit))

        ForEach(Array(visible.enumerated()), id: \.element.id) { idx, task in
          OverviewTaskRow(task: task, projectName: vm.projects.first(where: { $0.id == (task.projectId ?? "default") })?.title, showTimestamp: true, onTap: {
            vm.selectTask(task)
            detailTask = task
          })
          if idx < visible.count - 1 {
            Divider().padding(.leading, 32)
          }
        }

        if completedThisWeekTasks.count > snapshotLimit {
          Divider().padding(.leading, 32)
          Button {
            showAllCompletedThisWeekSheet = true
          } label: {
            Text("View all \(completedThisWeekTasks.count) completed →")
              .font(.footnote)
              .foregroundStyle(Color.green)
              .frame(maxWidth: .infinity, alignment: .center)
              .padding(.vertical, 8)
          }
          .buttonStyle(.plain)
        }
      }
    }
  }

  @ViewBuilder
  private var inboxColumnsSection: some View {
    if !vm.inboxItems.isEmpty || vm.unreadInboxCount > 0 {
      HStack(alignment: .top, spacing: 16) {
        inboxColumn
        Color.clear.frame(maxWidth: .infinity)
        Color.clear.frame(maxWidth: .infinity)
      }
    }
  }

  private var inboxColumn: some View {
    OverviewSectionColumn(
      title: "Inbox",
      icon: "tray.full.fill",
      color: .blue,
      badgeCount: vm.unreadInboxCount
    ) {
      if vm.inboxItems.isEmpty {
        Text("No inbox items")
          .font(.footnote)
          .foregroundStyle(.secondary)
          .padding(.vertical, 20)
          .frame(maxWidth: .infinity)
      } else {
        let sortedItems = vm.inboxItems.sorted { a, b in
          let aNeeds = !a.isRead || vm.unreadFollowupCount(docId: a.id) > 0
          let bNeeds = !b.isRead || vm.unreadFollowupCount(docId: b.id) > 0
          if aNeeds != bNeeds { return aNeeds }
          return a.modifiedAt > b.modifiedAt
        }
        let snapshotLimit = 5
        let visible = Array(sortedItems.prefix(snapshotLimit))

        ForEach(Array(visible.enumerated()), id: \.element.id) { idx, item in
          InboxRow(item: item, unreadFollowups: vm.unreadFollowupCount(docId: item.id), onTap: {
            vm.markInboxItemRead(item)
            if let onOpenInbox {
              onOpenInbox(item.id)
            }
          })
          if idx < visible.count - 1 {
            Divider().padding(.leading, 36)
          }
        }

        if sortedItems.count > snapshotLimit {
          Divider().padding(.leading, 36)
          Button {
            if let onOpenInbox { onOpenInbox(nil) }
          } label: {
            Text("View all \(sortedItems.count) inbox items →")
              .font(.footnote)
              .foregroundStyle(.blue)
              .frame(maxWidth: .infinity, alignment: .center)
              .padding(.vertical, 8)
          }
          .buttonStyle(.plain)
        }
      }
    }
  }
}

// MARK: - Stats Row

private struct StatsRow: View {
  let activeTasks: Int
  let completedThisWeek: Int
  let openResearchRequests: Int
  let blockedTasks: Int
  let inboxTasks: Int
  let staleTasks: Int
  let inboxNeedsAttentionCount: Int
  var workerHistory: WorkerHistory? = nil
  var mainSessionUsage: MainSessionUsage? = nil

  private var weeklyRuns: [WorkerHistoryRun] {
    guard let history = workerHistory else { return [] }
    let startOfWeek = mondayStartOfWeek()
    return history.runs.filter { run in
      let d = run.endedAt ?? run.startedAt
      guard let d else { return false }
      return d >= startOfWeek
    }
  }

  private func mondayStartOfWeek() -> Date {
    // Keep week boundaries consistent with the Overview "Done This Week" section (Monday–Sunday).
    let calendar = Calendar.current
    var comps = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date())
    comps.weekday = 2 // Monday
    return calendar.date(from: comps) ?? Date()
  }

  private var weeklyWorkerSpend: Double {
    weeklyRuns.reduce(0.0) { total, run in
      total + (run.totalCostUSD ?? 0)
    }
  }

  private var weeklyWorkerTokens: Int {
    weeklyRuns.reduce(0) { total, run in
      let totalForRun = run.totalTokens ?? ((run.inputTokens ?? 0) + (run.outputTokens ?? 0))
      return total + totalForRun
    }
  }

  /// Main session usage for the current week from daily summaries.
  private var weeklyMainSpend: Double {
    guard let usage = mainSessionUsage else { return 0 }
    let startOfWeek = mondayStartOfWeek()
    let df = DateFormatter()
    df.dateFormat = "yyyy-MM-dd"
    return usage.dailySummaries.filter { key, _ in
      guard let date = df.date(from: key) else { return false }
      return date >= startOfWeek
    }.values.reduce(0.0) { $0 + $1.costUSD }
  }

  private var weeklyMainTokens: Int {
    guard let usage = mainSessionUsage else { return 0 }
    let startOfWeek = mondayStartOfWeek()
    let df = DateFormatter()
    df.dateFormat = "yyyy-MM-dd"
    return usage.dailySummaries.filter { key, _ in
      guard let date = df.date(from: key) else { return false }
      return date >= startOfWeek
    }.values.reduce(0) { $0 + $1.inputTokens + $1.outputTokens }
  }

  private var weeklySpend: Double { weeklyWorkerSpend + weeklyMainSpend }
  private var weeklyTokens: Int { weeklyWorkerTokens + weeklyMainTokens }

  var body: some View {
    HStack(spacing: 16) {
      StatCard(label: "Active Tasks", value: "\(activeTasks)", icon: "flame.fill", color: .orange)
      StatCard(label: "Research Requests", value: "\(openResearchRequests)", icon: "magnifyingglass", color: .purple)
      StatCard(label: "Done This Week", value: "\(completedThisWeek)", icon: "checkmark.circle.fill", color: .green)
      if blockedTasks > 0 {
        StatCard(label: "Blocked", value: "\(blockedTasks)", icon: "exclamationmark.octagon.fill", color: .red)
      }
      if inboxTasks > 0 {
        StatCard(label: "Inbox Tasks", value: "\(inboxTasks)", icon: "tray.full.fill", color: .blue)
      }
      if inboxNeedsAttentionCount > 0 {
        StatCard(label: "Inbox", value: "\(inboxNeedsAttentionCount)", icon: "envelope.badge", color: .red)
      }
      if staleTasks > 0 {
        StatCard(label: "Stale", value: "\(staleTasks)", icon: "exclamationmark.triangle.fill", color: .orange)
      }
      if weeklyTokens > 0 {
        StatCard(label: "Total Tokens", value: formatTokenCount(weeklyTokens), icon: "cpu", color: .indigo)
      }
      if weeklySpend > 0 {
        StatCard(label: "AI Spend (Week)", value: "~$\(String(format: "%.2f", weeklySpend))", icon: "dollarsign.circle.fill", color: .mint)
      }
    }
  }
}

private struct StatCard: View {
  let label: String
  let value: String
  let icon: String
  let color: Color

  var body: some View {
    VStack(spacing: 8) {
      HStack(spacing: 6) {
        Image(systemName: icon)
          .font(.footnote)
          .foregroundStyle(color)
        Text(label)
          .font(.footnote)
          .foregroundStyle(.secondary)
          .lineLimit(1)
      }
      Text(value)
        .font(.title)
        .fontWeight(.bold)
        .foregroundStyle(color)
    }
    .frame(minWidth: 120)
    .padding(.horizontal, 16)
    .padding(.vertical, 14)
    .background(OTheme.cardBg)
    .clipShape(RoundedRectangle(cornerRadius: OTheme.cardRadius))
    .overlay(
      RoundedRectangle(cornerRadius: OTheme.cardRadius)
        .stroke(OTheme.border, lineWidth: 0.5)
    )
  }
}

// MARK: - Project Card

private struct ProjectCard: View {
  let project: Project
  let tasks: [DashboardTask]
  var lastCommitAt: Date? = nil
  var researchRequestCount: Int = 0
  var totalResearchRequestCount: Int = 0
  var researchDeliverableCount: Int = 0
  var wipLimit: Int = 0
  let onTap: () -> Void

  @State private var isHovering = false

  private var activeCount: Int { tasks.filter { $0.status == .active }.count }
  private var completedCount: Int { tasks.filter { $0.status == .completed }.count }
  private var inboxCount: Int { tasks.filter { $0.status == .inbox }.count }
  private var blockedCount: Int { tasks.filter { $0.workState == .blocked }.count }
  private var totalCount: Int { tasks.count }

  private var lastActivity: Date? {
    tasks.map(\.updatedAt).max()
  }

  // Mini health metrics (7-day window)
  private var createdLast7Days: Int {
    let cutoff = Date().addingTimeInterval(-7 * 86400)
    return tasks.filter { $0.createdAt >= cutoff }.count
  }

  private var completedLast7Days: Int {
    let cutoff = Date().addingTimeInterval(-7 * 86400)
    return tasks.filter { t in
      guard t.status == .completed else { return false }
      let finished = t.finishedAt ?? t.updatedAt
      return finished >= cutoff
    }.count
  }

  private var avgCompletionTime: TimeInterval? {
    let durations: [TimeInterval] = tasks.compactMap { t in
      guard t.status == .completed else { return nil }
      let finished = t.finishedAt ?? t.updatedAt
      let started = t.startedAt ?? t.createdAt
      let dt = finished.timeIntervalSince(started)
      guard dt > 0 else { return nil }
      return dt
    }
    guard !durations.isEmpty else { return nil }
    return durations.reduce(0, +) / Double(durations.count)
  }

  private var blockedRatio: Double {
    let denom = Double(tasks.filter { $0.status != .completed }.count)
    guard denom > 0 else { return 0 }
    return Double(blockedCount) / denom
  }

  private func formatDuration(_ seconds: TimeInterval) -> String {
    if seconds >= 2 * 86400 {
      return String(format: "%.1fd", seconds / 86400)
    }
    if seconds >= 2 * 3600 {
      return String(format: "%.1fh", seconds / 3600)
    }
    if seconds >= 120 {
      return "\(Int(seconds / 60))m"
    }
    return "<1m"
  }

  /// Health indicator based on blocked ratio and staleness.
  private var health: Health {
    // Research projects: base health on deliverables and requests
    if project.resolvedType == .research {
      if researchDeliverableCount > 0 || totalResearchRequestCount > 0 { return .good }
      return .neutral
    }
    if totalCount == 0 { return .neutral }
    if blockedCount > 0 { return .warning }
    let stale = tasks.filter {
      $0.status == .active && Date().timeIntervalSince($0.updatedAt) > 7 * 86400
    }
    if !stale.isEmpty { return .warning }
    if completedCount > 0 { return .good }
    return .neutral
  }

  private enum Health {
    case good, neutral, warning

    var color: Color {
      switch self {
      case .good: return .green
      case .neutral: return .gray
      case .warning: return .orange
      }
    }

    var icon: String {
      switch self {
      case .good: return "heart.fill"
      case .neutral: return "minus.circle"
      case .warning: return "exclamationmark.triangle.fill"
      }
    }
  }

  var body: some View {
    Button(action: onTap) {
      VStack(alignment: .leading, spacing: 12) {
        // Title row
        HStack(spacing: 8) {
          Image(systemName: overviewProjectTypeIcon(project.resolvedType))
            .font(.body)
            .foregroundStyle(overviewProjectTypeColor(project.resolvedType))

          Text(project.title)
            .font(.callout)
            .fontWeight(.bold)
            .lineLimit(1)

          if project.syncMode == .github {
            Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
              .font(.caption)
              .foregroundStyle(.blue)
              .help("Synced with GitHub Issues")
          }

          Spacer()

          // Health indicator
          Image(systemName: health.icon)
            .font(.footnote)
            .foregroundStyle(health.color)

          // Type badge
          Text(project.resolvedType.rawValue.capitalized)
            .font(.system(size: 11, weight: .medium))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(overviewProjectTypeColor(project.resolvedType).opacity(0.15))
            .foregroundStyle(overviewProjectTypeColor(project.resolvedType))
            .clipShape(Capsule())
        }

        // Counts
        HStack(spacing: 12) {
          // Research projects show deliverables + requests instead of task columns.
          if project.resolvedType == .research {
            if researchDeliverableCount > 0 {
              CountBadge(label: "Docs", count: researchDeliverableCount, color: .blue)
            }
            if researchRequestCount > 0 {
              CountBadge(label: "Open", count: researchRequestCount, color: .purple)
            }
            let completedResearch = totalResearchRequestCount - researchRequestCount
            if completedResearch > 0 {
              CountBadge(label: "Done", count: completedResearch, color: .green)
            }
          } else {
            CountBadge(label: "Active", count: activeCount, color: .orange)
            if wipLimit > 0 && activeCount > wipLimit {
              Text("WIP")
                .font(.system(size: 11, weight: .bold))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.orange.opacity(0.2))
                .foregroundStyle(.orange)
                .clipShape(Capsule())
            }
            CountBadge(label: "Done", count: completedCount, color: .green)
            if researchRequestCount > 0 {
              CountBadge(label: "Research", count: researchRequestCount, color: .purple)
            }
          }
          if inboxCount > 0 {
            CountBadge(label: "Inbox", count: inboxCount, color: .blue)
          }
          if blockedCount > 0 {
            CountBadge(label: "Blocked", count: blockedCount, color: .red)
          }
          Spacer()
          if project.resolvedType != .research {
            Text("\(totalCount) total")
              .font(.footnote)
              .foregroundStyle(.tertiary)
          }
        }

        // Mini dashboard
        if project.resolvedType != .research || lastCommitAt != nil {
          VStack(alignment: .leading, spacing: 6) {
            if project.resolvedType != .research {
              HStack(spacing: 12) {
                Text("In 7d: \(createdLast7Days)")
                Text("Out 7d: \(completedLast7Days)")
                if let avgCompletionTime {
                  Text("Avg: \(formatDuration(avgCompletionTime))")
                }
                Text(String(format: "Blocked: %.0f%%", blockedRatio * 100))
                Spacer()
              }
              .font(.footnote)
              .foregroundStyle(.tertiary)
              .lineLimit(1)
            }

            if let git = lastCommitAt {
              HStack(spacing: 4) {
                Image(systemName: "arrow.triangle.2.circlepath")
                  .font(.system(size: 11))
                  .foregroundStyle(.tertiary)
                Text("Git: \(relativeTime(git))")
                  .font(.footnote)
                  .foregroundStyle(.tertiary)
              }
            }
          }
        }

        // Last activity
        if let last = lastActivity {
          HStack(spacing: 4) {
            Image(systemName: "clock")
              .font(.system(size: 11))
              .foregroundStyle(.tertiary)
            Text("Last activity: \(relativeTime(last))")
              .font(.footnote)
              .foregroundStyle(.tertiary)
          }
        }

        // Notes preview
        if let notes = project.notes, !notes.isEmpty {
          Text(notes)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .lineLimit(2)
        }
      }
      .padding(16)
      .frame(maxWidth: .infinity, minHeight: 160, maxHeight: 160, alignment: .topLeading)
      .contentShape(Rectangle())
      .background(
        RoundedRectangle(cornerRadius: OTheme.cardRadius)
          .fill(OTheme.cardBg)
          .shadow(color: .black.opacity(isHovering ? 0.08 : 0.03), radius: isHovering ? 8 : 4, y: 2)
      )
      .overlay(
        RoundedRectangle(cornerRadius: OTheme.cardRadius)
          .stroke(isHovering ? Color.accentColor.opacity(0.3) : OTheme.border, lineWidth: isHovering ? 1.5 : 0.5)
      )
      .scaleEffect(isHovering ? 1.01 : 1.0)
      .animation(.easeOut(duration: 0.15), value: isHovering)
    }
    .buttonStyle(.plain)
    .onHover { h in isHovering = h }
  }
}

private struct CountBadge: View {
  let label: String
  let count: Int
  let color: Color

  var body: some View {
    HStack(spacing: 3) {
      Circle()
        .fill(color)
        .frame(width: 5, height: 5)
      Text("\(count) \(label)")
        .font(.footnote)
        .foregroundStyle(.secondary)
    }
  }
}

// MARK: - Activity Feed Rows

private struct ActivityEventRow: View {
  @ObservedObject var vm: AppViewModel
  let event: OverviewView.ActivityEvent
  let onOpenTask: (DashboardTask) -> Void
  let onOpenInbox: (String?) -> Void

  @State private var isHovering = false

  var body: some View {
    Button {
      switch event {
      case .taskCompleted(let t):
        onOpenTask(t)
      case .inboxItem(let item):
        onOpenInbox(item.id)
      case .workerRun:
        break
      }
    } label: {
      HStack(spacing: 10) {
        icon
          .font(.footnote)
          .frame(width: 24)

        VStack(alignment: .leading, spacing: 2) {
          Text(title)
            .font(.footnote)
            .fontWeight(.medium)
            .lineLimit(1)

          Text(subtitle)
            .font(.system(size: 11))
            .foregroundStyle(.tertiary)
            .lineLimit(1)
        }

        Spacer()

        Text(relativeTime(event.date))
          .font(.system(size: 11))
          .foregroundStyle(.tertiary)
      }
      .padding(.horizontal, 12)
      .padding(.vertical, 8)
      .background(isHovering ? OTheme.subtle : Color.clear)
    }
    .buttonStyle(.plain)
    .disabled(!isClickable)
    .onHover { h in isHovering = h }
  }

  private var isClickable: Bool {
    switch event {
    case .workerRun:
      return false
    default:
      return true
    }
  }

  private var title: String {
    switch event {
    case .taskCompleted(let t):
      return "Completed: \(t.title)"
    case .inboxItem(let item):
      return "Inbox: \(item.title)"
    case .workerRun:
      return "Worker ran"
    }
  }

  private var subtitle: String {
    switch event {
    case .taskCompleted(let t):
      let projectId = t.projectId ?? "default"
      let projectName = vm.projects.first(where: { $0.id == projectId })?.title ?? projectId
      return "\(projectName) · \(t.owner.rawValue)"
    case .inboxItem(let item):
      return item.summary
    case .workerRun(let run):
      let tasks = run.tasksCompleted ?? 0
      let dur = formatDuration(start: run.startedAt, end: run.endedAt)
      return "\(tasks) task(s) · \(dur)"
    }
  }

  @ViewBuilder
  private var icon: some View {
    switch event {
    case .taskCompleted:
      Image(systemName: "checkmark.circle.fill")
        .foregroundStyle(.green)
    case .inboxItem:
      Image(systemName: "tray.circle.fill")
        .foregroundStyle(.blue)
    case .workerRun:
      Image(systemName: "gearshape.2.fill")
        .foregroundStyle(.purple)
    }
  }

  private func formatDuration(start: Date?, end: Date?) -> String {
    guard let start, let end else { return "" }
    let s = max(0, end.timeIntervalSince(start))
    if s < 60 { return "\(Int(s))s" }
    if s < 3600 { return "\(Int(s/60))m" }
    return String(format: "%.1fh", s/3600)
  }
}

// MARK: - Inbox Row

private struct InboxRow: View {
  let item: InboxItem
  var unreadFollowups: Int = 0
  let onTap: () -> Void

  @State private var isHovering = false

  /// Whether this item needs attention (unread doc or has unread follow-up replies).
  private var needsAttention: Bool {
    !item.isRead || unreadFollowups > 0
  }

  var body: some View {
    Button(action: onTap) {
      HStack(spacing: 10) {
        Image(systemName: needsAttention ? "doc.text.fill" : "doc.text")
          .font(.footnote)
          .foregroundStyle(needsAttention ? (unreadFollowups > 0 ? Color.purple : Color.blue) : .secondary)
          .frame(width: 24)

        VStack(alignment: .leading, spacing: 2) {
          Text(item.title)
            .font(.footnote)
            .fontWeight(needsAttention ? .semibold : .regular)
            .lineLimit(1)

          HStack(spacing: 6) {
            Text(item.summary)
              .font(.footnote)
              .foregroundStyle(.secondary)
              .lineLimit(1)

            if unreadFollowups > 0 {
              HStack(spacing: 3) {
                Image(systemName: "bubble.left.and.bubble.right.fill")
                  .font(.system(size: 9))
                Text("+\(unreadFollowups)")
                  .font(.system(size: 10, weight: .semibold))
              }
              .padding(.horizontal, 5)
              .padding(.vertical, 2)
              .background(Color.purple.opacity(0.12))
              .foregroundStyle(.purple)
              .clipShape(Capsule())
            }
          }
        }

        Spacer()

        Text(relativeTime(item.modifiedAt))
          .font(.system(size: 11))
          .foregroundStyle(.tertiary)
      }
      .padding(.horizontal, 12)
      .padding(.vertical, 8)
      .background(isHovering ? OTheme.subtle : Color.clear)
    }
    .buttonStyle(.plain)
    .onHover { h in isHovering = h }
  }
}

// MARK: - Overview Section Column

/// A scrollable column with a header for the three-section overview layout.
private struct OverviewSectionColumn<Content: View>: View {
  let title: String
  let icon: String
  let color: Color
  var badgeCount: Int = 0
  @ViewBuilder let content: () -> Content

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(spacing: 6) {
        Image(systemName: icon)
          .font(.footnote)
          .foregroundStyle(color)
        Text(title)
          .font(.headline)
          .fontWeight(.bold)
        if badgeCount > 0 {
          Text("\(badgeCount)")
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.12))
            .clipShape(Capsule())
        }
      }

      ScrollView {
        VStack(spacing: 0) {
          content()
        }
      }
      .frame(maxHeight: 500)
      .background(OTheme.cardBg)
      .clipShape(RoundedRectangle(cornerRadius: OTheme.cardRadius))
      .overlay(
        RoundedRectangle(cornerRadius: OTheme.cardRadius)
          .stroke(OTheme.border, lineWidth: 0.5)
      )
    }
    .frame(minWidth: 0, maxWidth: .infinity)
  }
}

// MARK: - Overview Task Row

/// A compact task row for the overview sections (active / done this week).
private struct OverviewTaskRow: View {
  let task: DashboardTask
  var projectName: String? = nil
  var showTimestamp: Bool = false
  let onTap: () -> Void

  @State private var isHovering = false

  var body: some View {
    Button(action: onTap) {
      HStack(spacing: 10) {
        // Status indicator
        Circle()
          .fill(task.status == .completed ? Color.green : Color.orange)
          .frame(width: 8, height: 8)

        VStack(alignment: .leading, spacing: 2) {
          Text(task.title)
            .font(.footnote)
            .fontWeight(.medium)
            .lineLimit(1)

          HStack(spacing: 6) {
            if let name = projectName {
              Text(name)
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
            }
            if let ws = task.workState, ws == .blocked {
              Text("blocked")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.red)
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(Color.red.opacity(0.1))
                .clipShape(Capsule())
            }
          }
        }

        Spacer()

        if showTimestamp {
          Text(relativeTime(task.updatedAt))
            .font(.system(size: 11))
            .foregroundStyle(.tertiary)
        }
      }
      .padding(.horizontal, 12)
      .padding(.vertical, 8)
      .background(isHovering ? OTheme.subtle : Color.clear)
    }
    .buttonStyle(.plain)
    .onHover { h in isHovering = h }
  }
}

// MARK: - Overview Research Row

/// A compact research request row for the overview research section.
private struct OverviewResearchRow: View {
  let request: ResearchRequest
  var projectName: String? = nil
  let onTap: () -> Void

  @State private var isHovering = false

  var body: some View {
    Button(action: onTap) {
      HStack(spacing: 10) {
        // Status indicator
        Circle()
          .fill(request.status == .inProgress ? Color.blue : Color.purple)
          .frame(width: 8, height: 8)

        VStack(alignment: .leading, spacing: 2) {
          Text(request.prompt)
            .font(.footnote)
            .fontWeight(.medium)
            .lineLimit(2)

          HStack(spacing: 6) {
            if let name = projectName {
              Text(name)
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
            }
            Text(request.status == .inProgress ? "in progress" : "open")
              .font(.system(size: 10, weight: .medium))
              .foregroundStyle(request.status == .inProgress ? Color.blue : Color.purple)
              .padding(.horizontal, 4)
              .padding(.vertical, 1)
              .background((request.status == .inProgress ? Color.blue : Color.purple).opacity(0.1))
              .clipShape(Capsule())
            if let priority = request.priority, priority == .high || priority == .urgent {
              Text(priority.rawValue)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.red)
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(Color.red.opacity(0.1))
                .clipShape(Capsule())
            }
          }
        }

        Spacer()

        Text(relativeTime(request.createdAt))
          .font(.system(size: 11))
          .foregroundStyle(.tertiary)
      }
      .padding(.horizontal, 12)
      .padding(.vertical, 8)
      .background(isHovering ? OTheme.subtle : Color.clear)
    }
    .buttonStyle(.plain)
    .onHover { h in isHovering = h }
  }
}

// MARK: - Overview Task Detail Sheet

/// A lightweight detail sheet shown when clicking a task from the Overview screen.
/// This avoids navigating away from the home screen.
private struct OverviewTaskDetailSheet: View {
  let task: DashboardTask
  @ObservedObject var vm: AppViewModel

  @Environment(\.dismiss) private var dismiss
  @State private var editTitle: String = ""
  @State private var editNotes: String = ""

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      // Header
      HStack(spacing: 10) {
        statusIcon
          .font(.title3)
        VStack(alignment: .leading, spacing: 2) {
          Text(task.title)
            .font(.title3)
            .fontWeight(.bold)
          HStack(spacing: 6) {
            OverviewDetailTag(text: task.owner.rawValue, color: .purple)
            OverviewDetailTag(text: task.status.rawValue.replacingOccurrences(of: "_", with: " "), color: .blue)
            if let ws = task.workState {
              OverviewDetailTag(text: ws.rawValue.replacingOccurrences(of: "_", with: " "), color: .indigo)
            }
            if let rs = task.reviewState {
              OverviewDetailTag(text: rs.rawValue.replacingOccurrences(of: "_", with: " "), color: .green)
            }
          }
        }
        Spacer()
        Button { dismiss() } label: {
          Image(systemName: "xmark.circle.fill")
            .font(.title3)
            .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
      }
      .padding(20)

      Divider()

      ScrollView {
        VStack(alignment: .leading, spacing: 16) {
          // Editable title
          VStack(alignment: .leading, spacing: 4) {
            Text("Title")
              .font(.footnote)
              .foregroundStyle(.secondary)
            TextField("Title", text: $editTitle)
              .textFieldStyle(.roundedBorder)
              .onAppear {
                editTitle = task.title
                editNotes = task.notes ?? ""
              }
          }

          // Editable notes
          VStack(alignment: .leading, spacing: 4) {
            Text("Notes")
              .font(.footnote)
              .foregroundStyle(.secondary)
            SpellCheckingTextEditor(text: $editNotes, onSubmit: {
              vm.editTask(taskId: task.id, title: editTitle, notes: editNotes.isEmpty ? nil : editNotes, autoPush: true)
              dismiss()
            })
              .frame(minHeight: 90, maxHeight: 160)
              .overlay(
                RoundedRectangle(cornerRadius: 8)
                  .stroke(OTheme.border, lineWidth: 0.5)
              )
              .help("Enter to save, Shift+Enter for newline")
          }

          // Project info
          if let projectId = task.projectId {
            HStack(spacing: 6) {
              Image(systemName: "folder")
                .font(.footnote)
                .foregroundStyle(.secondary)
              Text(vm.projects.first(where: { $0.id == projectId })?.title ?? projectId)
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
          }

          // Timestamps
          VStack(alignment: .leading, spacing: 4) {
            Text("Created: \(task.createdAt.formatted())")
              .font(.system(size: 11))
              .foregroundStyle(.tertiary)
            Text("Updated: \(task.updatedAt.formatted())")
              .font(.system(size: 11))
              .foregroundStyle(.tertiary)
          }

          Divider()

          // Actions
          HStack(spacing: 8) {
            Button {
              vm.editTask(taskId: task.id, title: editTitle, notes: editNotes.isEmpty ? nil : editNotes, autoPush: true)
              dismiss()
            } label: {
              Label("Save", systemImage: "square.and.arrow.down")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)

            Button {
              dismiss()
              // Navigate to the board for full context
              vm.selectedProjectId = task.projectId ?? "default"
              vm.showOverview = false
              vm.selectTask(task)
            } label: {
              Label("Open in Board", systemImage: "rectangle.split.3x1")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            Spacer()
          }
        }
        .padding(20)
      }
    }
    .background(OTheme.bg)
  }

  @ViewBuilder
  private var statusIcon: some View {
    switch task.status {
    case .active:
      Image(systemName: "bolt.circle.fill").foregroundStyle(.orange)
    case .completed:
      Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
    case .inbox:
      Image(systemName: "tray.circle.fill").foregroundStyle(.blue)
    case .rejected:
      Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
    case .waitingOn:
      Image(systemName: "clock.circle.fill").foregroundStyle(.yellow)
    case .other:
      Image(systemName: "questionmark.circle.fill").foregroundStyle(.gray)
    }
  }
}

private struct OverviewDetailTag: View {
  let text: String
  let color: Color

  var body: some View {
    Text(text)
      .font(.system(size: 11, weight: .medium))
      .padding(.horizontal, 7)
      .padding(.vertical, 3)
      .background(color.opacity(0.12))
      .foregroundStyle(color)
      .clipShape(Capsule())
  }
}

// MARK: - Detailed Stats View

private struct DetailedStatsView: View {
  let tasks: [DashboardTask]
  let projects: [Project]
  var researchRequestCountsByProject: [String: Int] = [:]

  /// Week offset: 0 = current week, -1 = last week, etc.
  @State private var weekOffset: Int = 0

  private let calendar = Calendar.current

  private var totalOpenResearchRequests: Int {
    researchRequestCountsByProject.values.reduce(0, +)
  }

  /// Start of the selected week (Monday).
  private var weekStart: Date {
    let now = Date()
    let shifted = calendar.date(byAdding: .weekOfYear, value: weekOffset, to: now) ?? now
    var comps = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: shifted)
    comps.weekday = 2 // Monday
    return calendar.date(from: comps) ?? shifted
  }

  /// End of the selected week (Sunday 23:59:59).
  private var weekEnd: Date {
    calendar.date(byAdding: .day, value: 7, to: weekStart) ?? weekStart
  }

  /// Human-readable week label.
  private var weekLabel: String {
    if weekOffset == 0 { return "This Week" }
    if weekOffset == -1 { return "Last Week" }
    let df = DateFormatter()
    df.dateFormat = "MMM d"
    let start = df.string(from: weekStart)
    let end = df.string(from: calendar.date(byAdding: .day, value: 6, to: weekStart) ?? weekStart)
    return "\(start) – \(end)"
  }

  private var isCurrentWeek: Bool { weekOffset == 0 }

  /// Tasks completed during the selected week.
  private var completedThisWeek: [DashboardTask] {
    tasks.filter { task in
      guard task.status == .completed else { return false }
      let completionDate = task.finishedAt ?? task.updatedAt
      return completionDate >= weekStart && completionDate < weekEnd
    }
  }

  /// Tasks created during the selected week.
  private var createdThisWeek: [DashboardTask] {
    tasks.filter { $0.createdAt >= weekStart && $0.createdAt < weekEnd }
  }

  /// Tasks updated during the selected week.
  private var updatedThisWeek: [DashboardTask] {
    tasks.filter { $0.updatedAt >= weekStart && $0.updatedAt < weekEnd }
  }

  // Status breakdown (all-time for context)
  private var statusBreakdown: [(String, Int, Color)] {
    let active = tasks.filter { $0.status == .active || $0.status == .waitingOn }.count
    let completed = tasks.filter { $0.status == .completed }.count
    let inbox = tasks.filter { $0.status == .inbox }.count
    let rejected = tasks.filter { $0.status == .rejected }.count
    return [
      ("Active", active, .orange),
      ("Completed", completed, .green),
      ("Inbox", inbox, .blue),
      ("Rejected", rejected, .red),
    ].filter { $0.1 > 0 }
  }

  // Tasks per project (name, total, active, completed, research requests, isResearch)
  private var tasksPerProject: [(String, Int, Int, Int, Int, Bool)] {
    projects.map { project in
      let projectTasks = tasks.filter { ($0.projectId ?? "default") == project.id }
      let active = projectTasks.filter { $0.status == .active }.count
      let completed = projectTasks.filter { $0.status == .completed }.count
      let research = researchRequestCountsByProject[project.id] ?? 0
      let isResearch = project.resolvedType == .research
      return (project.title, projectTasks.count, active, completed, research, isResearch)
    }
    .sorted { $0.1 > $1.1 }
  }

  // Weekly per-project completions
  private var weeklyCompletionsByProject: [(String, Int)] {
    var counts: [String: Int] = [:]
    for task in completedThisWeek {
      let projectId = task.projectId ?? "default"
      let name = projects.first(where: { $0.id == projectId })?.title ?? projectId
      counts[name, default: 0] += 1
    }
    return counts.sorted { $0.value > $1.value }
  }

  // Completion rate (all-time)
  private var completionRate: Double {
    let completable = tasks.filter { $0.status == .completed || $0.status == .active || $0.status == .waitingOn }
    guard !completable.isEmpty else { return 0 }
    let completed = completable.filter { $0.status == .completed }.count
    return Double(completed) / Double(completable.count)
  }

  // Average time to complete (days) — for tasks completed this week
  private var avgCompletionDaysThisWeek: Double? {
    let completed = completedThisWeek
    guard !completed.isEmpty else { return nil }
    let totalDays = completed.reduce(0.0) { sum, task in
      let started = task.startedAt ?? task.createdAt
      return sum + task.updatedAt.timeIntervalSince(started) / 86400
    }
    return totalDays / Double(completed.count)
  }

  // Owner breakdown (active tasks)
  private var ownerBreakdown: [(String, Int)] {
    var counts: [String: Int] = [:]
    for task in tasks where task.status == .active {
      counts[task.owner.rawValue, default: 0] += 1
    }
    return counts.sorted { $0.value > $1.value }
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      // Header with week navigation
      HStack(spacing: 12) {
        Image(systemName: "chart.bar.xaxis")
          .font(.title3)
          .foregroundStyle(.purple)
        Text("Detailed Statistics")
          .font(.headline)
          .fontWeight(.bold)

        Spacer()

        // Week navigation
        HStack(spacing: 8) {
          Button {
            withAnimation(.easeInOut(duration: 0.2)) { weekOffset -= 1 }
          } label: {
            Image(systemName: "chevron.left")
              .font(.footnote.weight(.semibold))
              .padding(6)
              .background(OTheme.subtle)
              .clipShape(Circle())
          }
          .buttonStyle(.plain)

          Text(weekLabel)
            .font(.callout)
            .fontWeight(.semibold)
            .frame(minWidth: 120)
            .animation(.none, value: weekOffset)

          Button {
            withAnimation(.easeInOut(duration: 0.2)) { weekOffset += 1 }
          } label: {
            Image(systemName: "chevron.right")
              .font(.footnote.weight(.semibold))
              .padding(6)
              .background(isCurrentWeek ? OTheme.subtle.opacity(0.3) : OTheme.subtle)
              .clipShape(Circle())
          }
          .buttonStyle(.plain)
          .disabled(isCurrentWeek)

          if weekOffset != 0 {
            Button {
              withAnimation(.easeInOut(duration: 0.2)) { weekOffset = 0 }
            } label: {
              Text("Today")
                .font(.footnote.weight(.medium))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.accentColor.opacity(0.12))
                .foregroundStyle(Color.accentColor)
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
          }
        }
      }

      // Weekly summary metrics
      HStack(spacing: 16) {
        MetricCard(
          title: "Completed",
          value: "\(completedThisWeek.count)",
          icon: "checkmark.circle.fill",
          color: .green
        )
        MetricCard(
          title: "Created",
          value: "\(createdThisWeek.count)",
          icon: "plus.circle.fill",
          color: .blue
        )
        MetricCard(
          title: "Updated",
          value: "\(updatedThisWeek.count)",
          icon: "arrow.triangle.2.circlepath",
          color: .orange
        )
        if let avgDays = avgCompletionDaysThisWeek {
          MetricCard(
            title: "Avg Completion",
            value: avgDays < 1 ? String(format: "%.0fh", avgDays * 24) : String(format: "%.1fd", avgDays),
            icon: "clock",
            color: .orange
          )
        }
        MetricCard(
          title: "Completion Rate",
          value: String(format: "%.0f%%", completionRate * 100),
          icon: "percent",
          color: .green
        )
        if totalOpenResearchRequests > 0 {
          MetricCard(
            title: "Research Requests",
            value: "\(totalOpenResearchRequests)",
            icon: "magnifyingglass",
            color: .purple
          )
        }
      }

      HStack(alignment: .top, spacing: 24) {
        // Weekly completions by project
        VStack(alignment: .leading, spacing: 10) {
          Text("Completed This Week")
            .font(.callout)
            .fontWeight(.semibold)

          if weeklyCompletionsByProject.isEmpty {
            Text("No completions this week")
              .font(.footnote)
              .foregroundStyle(.secondary)
              .padding(.vertical, 8)
          } else {
            ForEach(weeklyCompletionsByProject, id: \.0) { name, count in
              HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 3)
                  .fill(Color.green)
                  .frame(width: 4, height: 16)
                Text(name)
                  .font(.callout)
                  .lineLimit(1)
                Spacer()
                Text("\(count)")
                  .font(.callout)
                  .fontWeight(.medium)
                  .monospacedDigit()
              }
            }

            Divider()

            // List individual completed tasks
            ForEach(completedThisWeek.sorted(by: { $0.updatedAt > $1.updatedAt }).prefix(10), id: \.id) { task in
              HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                  .font(.system(size: 10))
                  .foregroundStyle(.green)
                Text(task.title)
                  .font(.footnote)
                  .lineLimit(1)
                Spacer()
                if let started = task.startedAt {
                  let dur = task.updatedAt.timeIntervalSince(started)
                  Text(formatWeekDuration(dur))
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                }
              }
            }
          }
        }
        .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(OTheme.cardBg)
        .clipShape(RoundedRectangle(cornerRadius: OTheme.cardRadius))
        .overlay(
          RoundedRectangle(cornerRadius: OTheme.cardRadius)
            .stroke(OTheme.border, lineWidth: 0.5)
        )

        // Status breakdown (all-time snapshot)
        VStack(alignment: .leading, spacing: 10) {
          Text("Tasks by Status")
            .font(.callout)
            .fontWeight(.semibold)

          ForEach(statusBreakdown, id: \.0) { label, count, color in
            HStack(spacing: 8) {
              RoundedRectangle(cornerRadius: 3)
                .fill(color)
                .frame(width: 4, height: 16)
              Text(label)
                .font(.callout)
                .frame(width: 80, alignment: .leading)
              GeometryReader { geo in
                RoundedRectangle(cornerRadius: 3)
                  .fill(color.opacity(0.3))
                  .frame(width: tasks.isEmpty ? 0 : geo.size.width * CGFloat(count) / CGFloat(tasks.count))
              }
              .frame(height: 16)
              Text("\(count)")
                .font(.callout)
                .fontWeight(.medium)
                .monospacedDigit()
                .frame(width: 30, alignment: .trailing)
            }
          }

          Divider()

          // Tasks per project
          Text("Tasks per Project")
            .font(.callout)
            .fontWeight(.semibold)

          ForEach(tasksPerProject, id: \.0) { name, total, active, completed, research, isResearch in
            VStack(alignment: .leading, spacing: 4) {
              HStack {
                Text(name)
                  .font(.callout)
                  .lineLimit(1)
                Spacer()
                Text("\(total)")
                  .font(.callout)
                  .fontWeight(.medium)
                  .monospacedDigit()
              }
              HStack(spacing: 4) {
                if !isResearch {
                  if completed > 0 {
                    Text("\(completed) done")
                      .font(.system(size: 11))
                      .foregroundStyle(.green)
                  }
                  if active > 0 {
                    Text("\(active) active")
                      .font(.system(size: 11))
                      .foregroundStyle(.orange)
                  }
                }
                if research > 0 {
                  Text("\(research) research")
                    .font(.system(size: 11))
                    .foregroundStyle(.purple)
                }
              }
            }
            Divider()
          }
        }
        .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(OTheme.cardBg)
        .clipShape(RoundedRectangle(cornerRadius: OTheme.cardRadius))
        .overlay(
          RoundedRectangle(cornerRadius: OTheme.cardRadius)
            .stroke(OTheme.border, lineWidth: 0.5)
        )

        // Owner breakdown
        VStack(alignment: .leading, spacing: 16) {
          VStack(alignment: .leading, spacing: 8) {
            Text("Active by Owner")
              .font(.callout)
              .fontWeight(.semibold)

            if ownerBreakdown.isEmpty {
              Text("No active tasks")
                .font(.footnote)
                .foregroundStyle(.secondary)
            } else {
              ForEach(ownerBreakdown, id: \.0) { owner, count in
                HStack {
                  Text(owner.capitalized)
                    .font(.callout)
                  Spacer()
                  Text("\(count)")
                    .font(.callout)
                    .fontWeight(.medium)
                    .monospacedDigit()
                }
              }
            }
          }

          Divider()

          // Created this week list
          VStack(alignment: .leading, spacing: 8) {
            Text("Created This Week")
              .font(.callout)
              .fontWeight(.semibold)

            if createdThisWeek.isEmpty {
              Text("No tasks created this week")
                .font(.footnote)
                .foregroundStyle(.secondary)
            } else {
              ForEach(createdThisWeek.sorted(by: { $0.createdAt > $1.createdAt }).prefix(8), id: \.id) { task in
                HStack(spacing: 6) {
                  Image(systemName: "plus.circle.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.blue)
                  Text(task.title)
                    .font(.footnote)
                    .lineLimit(1)
                  Spacer()
                  Text(task.status.rawValue)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                }
              }
            }
          }
        }
        .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(OTheme.cardBg)
        .clipShape(RoundedRectangle(cornerRadius: OTheme.cardRadius))
        .overlay(
          RoundedRectangle(cornerRadius: OTheme.cardRadius)
            .stroke(OTheme.border, lineWidth: 0.5)
        )
      }
    }
    .padding(16)
    .background(OTheme.boardBg.opacity(0.5))
    .clipShape(RoundedRectangle(cornerRadius: OTheme.cardRadius))
    .overlay(
      RoundedRectangle(cornerRadius: OTheme.cardRadius)
        .stroke(OTheme.border, lineWidth: 0.5)
    )
  }
}

private func formatWeekDuration(_ seconds: TimeInterval) -> String {
  let totalMinutes = Int(seconds / 60)
  if totalMinutes < 60 { return "\(totalMinutes)m" }
  let hours = totalMinutes / 60
  let mins = totalMinutes % 60
  if hours < 24 { return mins > 0 ? "\(hours)h \(mins)m" : "\(hours)h" }
  let days = hours / 24
  return "\(days)d"
}

private struct MetricCard: View {
  let title: String
  let value: String
  let icon: String
  let color: Color

  var body: some View {
    VStack(spacing: 6) {
      HStack(spacing: 4) {
        Image(systemName: icon)
          .font(.system(size: 11))
          .foregroundStyle(color)
        Text(title)
          .font(.footnote)
          .foregroundStyle(.secondary)
      }
      Text(value)
        .font(.title2)
        .fontWeight(.bold)
        .foregroundStyle(color)
    }
    .frame(minWidth: 100)
    .padding(.horizontal, 14)
    .padding(.vertical, 12)
    .background(OTheme.cardBg)
    .clipShape(RoundedRectangle(cornerRadius: OTheme.cardRadius))
    .overlay(
      RoundedRectangle(cornerRadius: OTheme.cardRadius)
        .stroke(OTheme.border, lineWidth: 0.5)
    )
  }
}

// MARK: - Project Type Helpers (Overview)

private func overviewProjectTypeIcon(_ type: ProjectType) -> String {
  switch type {
  case .kanban: return "rectangle.split.3x1"
  case .research: return "doc.text.magnifyingglass"
  case .tracker: return "checklist"
  }
}

private func overviewProjectTypeColor(_ type: ProjectType) -> Color {
  switch type {
  case .kanban: return .blue
  case .research: return .orange
  case .tracker: return .cyan
  }
}

// MARK: - Worker Status Card

struct WorkerStatusCard: View {
  let status: WorkerStatus
  var history: WorkerHistory? = nil
  var canRequestWorker: Bool = false
  var workerRequested: Bool = false
  var onRequestWorker: (() -> Void)? = nil
  var tasks: [DashboardTask] = []
  @State private var showHistory = false
  @State private var showLiveDetails = false
  @State private var showUsageDetail = false
  @State private var selectedUsagePeriod: UsagePeriod = .today
  
  /// Extract task ID from filename (e.g., "ABCD1234-5678-90AB-CDEF-1234567890AB.json" -> "ABCD1234-5678-90AB-CDEF-1234567890AB")
  private func taskIdFromFilename(_ filename: String) -> String? {
    guard filename.hasSuffix(".json") else { return nil }
    return String(filename.dropLast(5))
  }
  
  /// Look up task title from filename or raw task string
  private func resolveTaskDisplay(_ taskString: String?) -> String? {
    guard let taskString = taskString else { return nil }
    
    // If it starts with "research:" or doesn't look like a filename, return as-is
    if taskString.lowercased().hasPrefix("research:") || !taskString.contains("-") || !taskString.hasSuffix(".json") {
      return taskString
    }
    
    // Try to extract task ID and look up the actual task
    guard let taskId = taskIdFromFilename(taskString),
          let task = tasks.first(where: { $0.id == taskId }) else {
      return taskString
    }
    
    return task.title
  }

  enum UsagePeriod: String, CaseIterable {
    case today = "Today"
    case thisWeek = "Week"
    case thisMonth = "Month"
    case allTime = "All"

    func includes(_ date: Date) -> Bool {
      let cal = Calendar.current
      switch self {
      case .today:
        return cal.isDateInToday(date)
      case .thisWeek:
        let start = cal.dateInterval(of: .weekOfYear, for: Date())?.start ?? Date.distantPast
        return date >= start
      case .thisMonth:
        let start = cal.dateInterval(of: .month, for: Date())?.start ?? Date.distantPast
        return date >= start
      case .allTime:
        return true
      }
    }
  }

  private var isActive: Bool {
    guard status.active else { return false }
    // Defensive: if the status file claims "active" but we also have an endedAt,
    // treat it as inactive.
    if status.endedAt != nil { return false }

    // If the last heartbeat is stale, treat the worker as not running.
    // This prevents the dashboard from showing a phantom worker when a worker
    // crashes or fails to write an end marker.
    let cutoff: TimeInterval = 10 * 60
    if let hb = status.lastHeartbeat {
      return Date().timeIntervalSince(hb) <= cutoff
    }
    if let started = status.startedAt {
      return Date().timeIntervalSince(started) <= cutoff
    }
    return false
  }

  private var isStale: Bool {
    status.active && !isActive
  }

  // isStale is derived from the effective active state (see above).

  private var runningDuration: String? {
    guard let started = status.startedAt else { return nil }
    let seconds = Date().timeIntervalSince(started)
    let minutes = Int(seconds / 60)
    if minutes < 60 { return "\(minutes)m" }
    let hours = minutes / 60
    let mins = minutes % 60
    return mins > 0 ? "\(hours)h \(mins)m" : "\(hours)h"
  }

  var body: some View {
    HStack(spacing: 14) {
      // Status indicator
      ZStack {
        Circle()
          .fill(isStale ? Color.orange.opacity(0.15) : (isActive ? Color.green.opacity(0.15) : Color.gray.opacity(0.1)))
          .frame(width: 40, height: 40)
        Image(systemName: isStale ? "exclamationmark.triangle.fill" : (isActive ? "bolt.fill" : "moon.zzz.fill"))
          .font(.system(size: 18))
          .foregroundStyle(isStale ? .orange : (isActive ? .green : .secondary))
      }

      VStack(alignment: .leading, spacing: 4) {
        HStack(spacing: 6) {
          Text("Lobs Worker")
            .font(.callout)
            .fontWeight(.semibold)

          // Status pill
          Text(isStale ? "Stale" : (isActive ? "Active" : "Idle"))
            .font(.system(size: 11, weight: .semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(
              isStale
                ? Color.orange.opacity(0.15)
                : (isActive ? Color.green.opacity(0.15) : Color.gray.opacity(0.1))
            )
            .foregroundStyle(
              isStale
                ? .orange
                : (isActive ? .green : .secondary)
            )
            .clipShape(Capsule())
        }

        if isActive {
          VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
              if let task = status.currentTask, let displayTask = resolveTaskDisplay(task) {
                let isResearch = task.lowercased().hasPrefix("research:")
                HStack(spacing: 4) {
                  Image(systemName: isResearch ? "magnifyingglass" : "hammer.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(isResearch ? .purple : .secondary)
                  Text(displayTask)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                }
              }

              if let completed = status.tasksCompleted, completed > 0 {
                HStack(spacing: 4) {
                  Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.green)
                  Text("\(completed) done")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }
              }

              if let duration = runningDuration {
                HStack(spacing: 4) {
                  Image(systemName: "clock")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                  Text(duration)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }
              }

              if let heartbeat = status.lastHeartbeat {
                Text("· \(relativeTime(heartbeat))")
                  .font(.footnote)
                  .foregroundStyle(.tertiary)
              }
            }

            // Expandable live details
            if (status.currentProject != nil) || (status.taskLog?.isEmpty == false) || (status.inputTokens != nil) || (status.outputTokens != nil) {
              Button {
                withAnimation(.easeInOut(duration: 0.2)) { showLiveDetails.toggle() }
              } label: {
                HStack(spacing: 6) {
                  Image(systemName: showLiveDetails ? "chevron.down" : "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                  Text("Live details")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                }
              }
              .buttonStyle(.plain)

              if showLiveDetails {
                VStack(alignment: .leading, spacing: 6) {
                  if let p = status.currentProject, !p.isEmpty {
                    Text("Project: \(p)")
                      .font(.system(size: 11))
                      .foregroundStyle(.tertiary)
                  }
                  if let inTok = status.inputTokens, let outTok = status.outputTokens {
                    Text("Tokens: \(formatTokenCount(inTok + outTok))")
                      .font(.system(size: 11).monospacedDigit())
                      .foregroundStyle(.tertiary)
                  }
                  if let log = status.taskLog, !log.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                      Text("This run:")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                      ForEach(Array(log.suffix(5).enumerated()), id: \.offset) { _, e in
                        let displayTask = resolveTaskDisplay(e.task) ?? e.task ?? "(task)"
                        Text("• \(displayTask)")
                          .font(.system(size: 11))
                          .foregroundStyle(.tertiary)
                          .lineLimit(1)
                      }
                    }
                  }
                }
                .padding(.top, 2)
              }
            }
          }
        } else {
          // Idle state: show completion summary if available
          HStack(spacing: 12) {
            if let completed = status.tasksCompleted, completed > 0 {
              HStack(spacing: 4) {
                Image(systemName: "checkmark.circle.fill")
                  .font(.system(size: 10))
                  .foregroundStyle(.green)
                Text("Completed \(completed) task\(completed == 1 ? "" : "s")")
                  .font(.footnote)
                  .foregroundStyle(.secondary)
              }
            }

            // Show session duration if we have start and end times
            if let started = status.startedAt, let ended = status.endedAt {
              let duration = ended.timeIntervalSince(started)
              let minutes = Int(duration / 60)
              HStack(spacing: 4) {
                Image(systemName: "clock")
                  .font(.system(size: 10))
                  .foregroundStyle(.secondary)
                Text(minutes < 60
                  ? "in \(max(1, minutes))m"
                  : "in \(minutes / 60)h \(minutes % 60)m")
                  .font(.footnote)
                  .foregroundStyle(.secondary)
              }
            }

            if let heartbeat = status.lastHeartbeat {
              Text("· \(relativeTime(heartbeat))")
                .font(.footnote)
                .foregroundStyle(.tertiary)
            }
          }
        }
      }

      Spacer()

      // Request Worker button (only when idle)
      if !isActive {
        if workerRequested {
          HStack(spacing: 4) {
            Image(systemName: "checkmark.circle.fill")
              .font(.footnote)
              .foregroundStyle(.green)
            Text("Requested")
              .font(.footnote)
              .fontWeight(.medium)
              .foregroundStyle(.green)
          }
          .padding(.horizontal, 12)
          .padding(.vertical, 6)
          .background(Color.green.opacity(0.1))
          .clipShape(Capsule())
        } else if canRequestWorker {
          Button {
            onRequestWorker?()
          } label: {
            HStack(spacing: 4) {
              Image(systemName: "play.circle.fill")
                .font(.footnote)
              Text("Request Worker")
                .font(.footnote)
                .fontWeight(.medium)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.accentColor.opacity(0.12))
            .foregroundStyle(Color.accentColor)
            .clipShape(Capsule())
          }
          .buttonStyle(.plain)
          .keyboardShortcut("w", modifiers: [.command])
          .help("Request a worker (⌘W)")
        }
      }
    }
    .padding(14)
    .background(
      RoundedRectangle(cornerRadius: OTheme.cardRadius)
        .fill(OTheme.cardBg)
    )
    .overlay(
      RoundedRectangle(cornerRadius: OTheme.cardRadius)
        .stroke(isActive ? Color.green.opacity(0.2) : OTheme.border, lineWidth: isActive ? 1.5 : 0.5)
    )

    // Per-project usage breakdown
    if let history = history, !history.runs.isEmpty {
      // Project breakdown removed (simplified token tracking)
    }

    // Recent runs history + usage summary
    if let history = history, !history.runs.isEmpty {
      let runsWithEnd = history.runs.filter { $0.endedAt != nil }
      let filteredRuns = runsWithEnd.filter { run in
        guard let ended = run.endedAt else { return false }
        return selectedUsagePeriod.includes(ended)
      }
      let periodTokens = filteredRuns.reduce(0) { total, run in
        let totalForRun = run.totalTokens ?? ((run.inputTokens ?? 0) + (run.outputTokens ?? 0))
        return total + totalForRun
      }
      let periodSpend = filteredRuns.reduce(0.0) { $0 + ($1.totalCostUSD ?? 0) }
      let avgTokens = filteredRuns.isEmpty ? 0 : Int(Double(periodTokens) / Double(filteredRuns.count))
      let avgSpend = filteredRuns.isEmpty ? 0.0 : (periodSpend / Double(filteredRuns.count))

      VStack(alignment: .leading, spacing: 0) {
        HStack(spacing: 10) {
          Button {
            withAnimation(.easeInOut(duration: 0.2)) { showHistory.toggle() }
          } label: {
            HStack(spacing: 6) {
              Image(systemName: showHistory ? "chevron.down" : "chevron.right")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
              Text("Recent Runs")
                .font(.footnote)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)
            }
          }
          .buttonStyle(.plain)

          HStack(spacing: 4) {
            ForEach(UsagePeriod.allCases, id: \.self) { p in
              Button {
                withAnimation(.easeInOut(duration: 0.15)) { selectedUsagePeriod = p }
              } label: {
                Text(p.rawValue)
                  .font(.system(size: 11, weight: selectedUsagePeriod == p ? .semibold : .regular))
                  .foregroundStyle(selectedUsagePeriod == p ? .primary : .secondary)
                  .padding(.horizontal, 10)
                  .padding(.vertical, 4)
                  .background(selectedUsagePeriod == p ? Color.primary.opacity(0.1) : Color.clear)
                  .clipShape(Capsule())
              }
              .buttonStyle(.plain)
            }
          }

          Spacer()

          if periodTokens > 0 {
            HStack(spacing: 10) {
              HStack(spacing: 4) {
                Image(systemName: "cpu")
                  .font(.system(size: 10))
                  .foregroundStyle(.purple.opacity(0.8))
                Text(formatTokenCount(periodTokens))
                  .font(.system(size: 11, weight: .medium).monospacedDigit())
                  .foregroundStyle(.secondary)
              }
              if periodSpend > 0 {
                Text("$\(periodSpend, specifier: "%.2f")")
                  .font(.system(size: 11, weight: .medium).monospacedDigit())
                  .foregroundStyle(.secondary)
              }
              Button("Details") { showUsageDetail = true }
                .font(.system(size: 11, weight: .medium))
                .buttonStyle(.plain)
            }
          }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)

        if periodTokens > 0, filteredRuns.count > 0 {
          Text("Avg/run: \(formatTokenCount(avgTokens)) tok, $\(avgSpend, specifier: "%.2f")")
            .font(.system(size: 10).monospacedDigit())
            .foregroundStyle(.tertiary)
            .padding(.horizontal, 14)
            .padding(.bottom, 6)
        }

        if showHistory {
          Divider().padding(.horizontal, 14)
          VStack(alignment: .leading, spacing: 6) {
            ForEach(history.runs.suffix(10).reversed()) { run in
              WorkerHistoryRow(run: run)
            }
          }
          .padding(.horizontal, 14)
          .padding(.vertical, 10)
        }
      }
      .background(
        RoundedRectangle(cornerRadius: OTheme.cardRadius)
          .fill(OTheme.cardBg)
      )
      .overlay(
        RoundedRectangle(cornerRadius: OTheme.cardRadius)
          .stroke(OTheme.border, lineWidth: 0.5)
      )
      .sheet(isPresented: $showUsageDetail) {
        WorkerUsageDetailSheet(
          history: history,
          period: selectedUsagePeriod,
          tasks: tasks
        )
        .frame(minWidth: 560, minHeight: 520)
      }
    }
  }
}

// MARK: - Worker Project Usage Breakdown
// Removed: simplified AI usage tracking to per-run totals only.

private struct WorkerHistoryRow: View {
  let run: WorkerHistoryRun
  @State private var expanded = false

  private var hasTaskDetails: Bool {
    // Show expand chevron if there's task log, commits, files, or compare URL
    if let log = run.taskLog, !log.isEmpty { return true }
    if let commits = run.commitSHAs, !commits.isEmpty { return true }
    if let files = run.filesModified, !files.isEmpty { return true }
    if run.githubCompareURL != nil { return true }
    return false
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      // Main row (clickable if has task details)
      Button {
        if hasTaskDetails {
          withAnimation(.easeInOut(duration: 0.15)) { expanded.toggle() }
        }
      } label: {
        HStack(spacing: 10) {
          // Expand indicator
          if hasTaskDetails {
            Image(systemName: expanded ? "chevron.down" : "chevron.right")
              .font(.system(size: 8, weight: .semibold))
              .foregroundStyle(.tertiary)
              .frame(width: 10)
          } else {
            Spacer().frame(width: 10)
          }

          // Tasks count
          HStack(spacing: 4) {
            Image(systemName: "checkmark.circle.fill")
              .font(.system(size: 10))
              .foregroundStyle(run.tasksCompleted ?? 0 > 0 ? .green : .secondary)
            Text("\(run.tasksCompleted ?? 0)")
              .font(.footnote.monospacedDigit())
              .foregroundStyle(.secondary)
          }
          .frame(width: 36, alignment: .leading)

          // Duration
          if let started = run.startedAt, let ended = run.endedAt {
            let minutes = Int(ended.timeIntervalSince(started) / 60)
            HStack(spacing: 4) {
              Image(systemName: "clock")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
              Text(minutes < 60
                ? "\(max(1, minutes))m"
                : "\(minutes / 60)h \(minutes % 60)m")
                .font(.footnote.monospacedDigit())
                .foregroundStyle(.secondary)
            }
            .frame(width: 50, alignment: .leading)
          }

          // Timestamp
          if let ended = run.endedAt {
            Text(relativeTime(ended))
              .font(.footnote)
              .foregroundStyle(.tertiary)
          }

          // Tokens for the run
          if let inTok = run.inputTokens, let outTok = run.outputTokens, (inTok + outTok) > 0 {
            HStack(spacing: 3) {
              Image(systemName: "arrow.down.right.and.arrow.up.left")
                .font(.system(size: 9))
                .foregroundStyle(.purple.opacity(0.7))
              Text("\(formatTokenCount(inTok))/\(formatTokenCount(outTok))")
                .font(.system(size: 11, weight: .medium).monospacedDigit())
                .foregroundStyle(.purple.opacity(0.7))
            }
            .frame(width: 90, alignment: .leading)
            .help("Input/Output tokens")
          } else if let tokens = run.totalTokens, tokens > 0 {
            HStack(spacing: 2) {
              Image(systemName: "cpu")
                .font(.system(size: 9))
                .foregroundStyle(.purple.opacity(0.7))
              Text(formatTokenCount(tokens))
                .font(.footnote.monospacedDigit())
                .foregroundStyle(.purple.opacity(0.7))
            }
            .frame(width: 70, alignment: .leading)
          }

          // Cost (optional per-run total)
          if let cost = run.totalCostUSD, cost > 0 {
            HStack(spacing: 2) {
              Text("$\(cost, specifier: "%.2f")")
                .font(.footnote.monospacedDigit())
                .foregroundStyle(.secondary)
            }
            .frame(width: 60, alignment: .leading)
          }

          // Project tags from task log
          if let log = run.taskLog, !log.isEmpty {
            let projects = Array(Set(log.compactMap { $0.project })).sorted()
            if !projects.isEmpty {
              HStack(spacing: 3) {
                ForEach(projects.prefix(3), id: \.self) { proj in
                  Text(proj)
                    .font(.system(size: 9, weight: .medium))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Color.accentColor.opacity(0.1))
                    .foregroundStyle(.secondary)
                    .clipShape(Capsule())
                }
                if projects.count > 3 {
                  Text("+\(projects.count - 3)")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
                }
              }
            }
          }

          if run.timeoutReason != nil {
            Image(systemName: "exclamationmark.triangle.fill")
              .font(.system(size: 10))
              .foregroundStyle(.orange)
              .help("Session timed out")
          }

          Spacer()
        }
      }
      .buttonStyle(.plain)

      // Expanded task detail rows
      if expanded, let log = run.taskLog, !log.isEmpty {
        VStack(alignment: .leading, spacing: 2) {
          ForEach(Array(log.enumerated()), id: \.offset) { _, entry in
            HStack(spacing: 8) {
              Spacer().frame(width: 20)
              Image(systemName: "arrow.turn.down.right")
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)

              Text(entry.task ?? "Unknown task")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)

              Spacer()

              if let proj = entry.project {
                Text(proj)
                  .font(.system(size: 9, weight: .medium))
                  .padding(.horizontal, 4)
                  .padding(.vertical, 1)
                  .background(Color.accentColor.opacity(0.08))
                  .foregroundStyle(.tertiary)
                  .clipShape(Capsule())
              }

              // (Per-task token/cost fields removed; per-run totals only)

            }
            .padding(.vertical, 2)
          }
        }
        .padding(.top, 4)
        .padding(.bottom, 2)
      }

      // Audit details (commits, files, compare link)
      if expanded {
        VStack(alignment: .leading, spacing: 6) {
          // Commits pushed
          if let commits = run.commitSHAs, !commits.isEmpty {
            HStack(spacing: 8) {
              Spacer().frame(width: 20)
              Image(systemName: "arrow.triangle.branch")
                .font(.system(size: 9))
                .foregroundStyle(.purple)
              Text("Commits: \(commits.count)")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

              // Show first few commit SHAs
              HStack(spacing: 4) {
                ForEach(commits.prefix(3), id: \.self) { sha in
                  Text(String(sha.prefix(7)))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(Color.purple.opacity(0.08))
                    .clipShape(Capsule())
                }
                if commits.count > 3 {
                  Text("+\(commits.count - 3)")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
                }
              }
            }
            .padding(.vertical, 2)
          }

          // Files modified
          if let files = run.filesModified, !files.isEmpty {
            HStack(spacing: 8) {
              Spacer().frame(width: 20)
              Image(systemName: "doc.text")
                .font(.system(size: 9))
                .foregroundStyle(.orange)
              Text("Files: \(files.count)")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

              // Show first few files
              HStack(spacing: 4) {
                ForEach(files.prefix(3), id: \.self) { file in
                  Text(URL(fileURLWithPath: file).lastPathComponent)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(Color.orange.opacity(0.08))
                    .clipShape(Capsule())
                }
                if files.count > 3 {
                  Text("+\(files.count - 3)")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
                }
              }
            }
            .padding(.vertical, 2)
          }

          // GitHub compare link
          if let compareURL = run.githubCompareURL {
            HStack(spacing: 8) {
              Spacer().frame(width: 20)
              Image(systemName: "link")
                .font(.system(size: 9))
                .foregroundStyle(.blue)
              Link("View changes on GitHub", destination: URL(string: compareURL)!)
                .font(.system(size: 11))
                .foregroundStyle(.blue)
            }
            .padding(.vertical, 2)
          }
        }
        .padding(.top, 2)
        .padding(.bottom, 4)
      }
    }
  }
}

// MARK: - Token Count Formatter

private func formatTokenCount(_ tokens: Int) -> String {
  if tokens >= 1_000_000 {
    return String(format: "%.1fM", Double(tokens) / 1_000_000)
  } else if tokens >= 1_000 {
    return String(format: "%.0fK", Double(tokens) / 1_000)
  }
  return "\(tokens)"
}

// MARK: - Timeline / Gantt-lite

private struct TimelineSheetView: View {
  let tasks: [DashboardTask]
  let projects: [Project]

  @Environment(\.dismiss) private var dismiss

  @State private var selectedProjectId: String = "all"
  @State private var daysBack: Int = 14

  private var filteredTasks: [DashboardTask] {
    let now = Date()
    let cutoff = now.addingTimeInterval(TimeInterval(-daysBack) * 86400)
    return tasks.filter { t in
      let pid = t.projectId ?? "default"
      if selectedProjectId != "all" && pid != selectedProjectId { return false }
      // Include tasks that intersect the window.
      let end = (t.status == .completed ? (t.finishedAt ?? t.updatedAt) : now)
      return end >= cutoff
    }
    .sorted { a, b in
      let aEnd = (a.status == .completed ? (a.finishedAt ?? a.updatedAt) : Date())
      let bEnd = (b.status == .completed ? (b.finishedAt ?? b.updatedAt) : Date())
      if aEnd != bEnd { return aEnd > bEnd }
      return a.createdAt > b.createdAt
    }
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        Text("Timeline")
          .font(.title2)
          .fontWeight(.bold)
        Spacer()
        Button("Done") { dismiss() }
          .keyboardShortcut(.defaultAction)
      }

      HStack(spacing: 12) {
        Picker("Project", selection: $selectedProjectId) {
          Text("All").tag("all")
          ForEach(projects.filter { !($0.archived ?? false) }) { p in
            Text(p.title).tag(p.id)
          }
        }
        .pickerStyle(.menu)

        Picker("Range", selection: $daysBack) {
          Text("7d").tag(7)
          Text("14d").tag(14)
          Text("30d").tag(30)
        }
        .pickerStyle(.segmented)
        .frame(maxWidth: 200)

        Spacer()

        Text("Showing \\(filteredTasks.count) tasks")
          .font(.footnote)
          .foregroundStyle(.secondary)
      }

      // Explanation and legend
      VStack(alignment: .leading, spacing: 6) {
        Text("Each bar shows a task's lifespan — from creation to completion (or now if still open). Longer bars mean longer-lived tasks.")
          .font(.footnote)
          .foregroundStyle(.secondary)

        HStack(spacing: 16) {
          TimelineLegendItem(color: .green.opacity(0.8), label: "Completed")
          TimelineLegendItem(color: .orange.opacity(0.8), label: "Active")
          TimelineLegendItem(color: .red.opacity(0.8), label: "Blocked")
          TimelineLegendItem(color: .gray.opacity(0.6), label: "Other")
        }
      }

      TimelineChart(tasks: filteredTasks)
    }
    .padding(20)
  }
}

private struct TimelineChart: View {
  let tasks: [DashboardTask]

  private var domain: (min: Date, max: Date) {
    let now = Date()
    let starts = tasks.map { $0.createdAt }
    let ends = tasks.map { t in
      t.status == .completed ? (t.finishedAt ?? t.updatedAt) : now
    }
    let minD = (starts.min() ?? now)
    let maxD = (ends.max() ?? now)
    // Avoid zero-width domain
    if maxD <= minD {
      return (minD.addingTimeInterval(-86400), maxD.addingTimeInterval(86400))
    }
    return (minD, maxD)
  }

  var body: some View {
    GeometryReader { geo in
      let width = max(1, geo.size.width - 180)
      let minD = domain.min
      let maxD = domain.max
      let span = max(1, maxD.timeIntervalSince(minD))

      ScrollView {
        LazyVStack(alignment: .leading, spacing: 8) {
          ForEach(tasks) { task in
            TimelineRow(task: task, minDate: minD, span: span, barWidth: width)
              .frame(height: 22)
          }
        }
        .padding(.top, 6)
        .padding(.bottom, 6)
      }
    }
    .background(OTheme.cardBg)
    .clipShape(RoundedRectangle(cornerRadius: OTheme.cardRadius))
    .overlay(
      RoundedRectangle(cornerRadius: OTheme.cardRadius)
        .stroke(OTheme.border, lineWidth: 0.5)
    )
  }
}

private struct TimelineRow: View {
  let task: DashboardTask
  let minDate: Date
  let span: TimeInterval
  let barWidth: CGFloat

  private var endDate: Date {
    if task.status == .completed { return task.finishedAt ?? task.updatedAt }
    return Date()
  }

  private var barColor: Color {
    if task.status == .completed { return .green.opacity(0.8) }
    if task.workState == .blocked { return .red.opacity(0.8) }
    if task.status == .active { return .orange.opacity(0.8) }
    return .gray.opacity(0.6)
  }

  var body: some View {
    HStack(spacing: 10) {
      Text(task.title)
        .font(.footnote)
        .foregroundStyle(.primary)
        .lineLimit(1)
        .frame(width: 170, alignment: .leading)

      ZStack(alignment: .leading) {
        RoundedRectangle(cornerRadius: 6)
          .fill(Color.secondary.opacity(0.08))
          .frame(height: 12)

        let startX = CGFloat(task.createdAt.timeIntervalSince(minDate) / span) * barWidth
        let endX = CGFloat(endDate.timeIntervalSince(minDate) / span) * barWidth
        let w = max(3, endX - startX)

        RoundedRectangle(cornerRadius: 6)
          .fill(barColor)
          .frame(width: w, height: 12)
          .offset(x: startX)
      }
      .frame(width: barWidth, height: 12)
    }
  }
}

private struct TimelineLegendItem: View {
  let color: Color
  let label: String

  var body: some View {
    HStack(spacing: 5) {
      RoundedRectangle(cornerRadius: 3)
        .fill(color)
        .frame(width: 14, height: 8)
      Text(label)
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
    }
  }
}

// MARK: - Overview "View All" Sheets

private struct OverviewTaskListSheet: View {
  let title: String
  let subtitle: String?
  let tasks: [DashboardTask]
  @ObservedObject var vm: AppViewModel
  let showTimestamp: Bool
  let onTapTask: (DashboardTask) -> Void

  @Environment(\.dismiss) private var dismiss

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack(alignment: .top) {
        VStack(alignment: .leading, spacing: 2) {
          Text(title)
            .font(.title3)
            .fontWeight(.bold)
          if let subtitle {
            Text(subtitle)
              .font(.footnote)
              .foregroundStyle(.secondary)
          }
        }
        Spacer()
        Button { dismiss() } label: {
          Image(systemName: "xmark.circle.fill")
            .font(.title3)
            .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
      }
      .padding(20)

      Divider()

      ScrollView {
        VStack(spacing: 0) {
          ForEach(Array(tasks.enumerated()), id: \.element.id) { idx, task in
            OverviewTaskRow(
              task: task,
              projectName: vm.projects.first(where: { $0.id == (task.projectId ?? "default") })?.title,
              showTimestamp: showTimestamp,
              onTap: {
                dismiss()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                  onTapTask(task)
                }
              }
            )
            if idx < tasks.count - 1 {
              Divider().padding(.leading, 32)
            }
          }
        }
        .padding(.vertical, 6)
      }
    }
    .background(OTheme.boardBg)
  }
}

private struct OverviewResearchRequestListSheet: View {
  let title: String
  let requests: [ResearchRequest]
  let projects: [Project]
  let onSelectProject: (String) -> Void

  @Environment(\.dismiss) private var dismiss

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack(alignment: .top) {
        VStack(alignment: .leading, spacing: 2) {
          Text(title)
            .font(.title3)
            .fontWeight(.bold)
          Text("\(requests.count) open")
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
        Spacer()
        Button { dismiss() } label: {
          Image(systemName: "xmark.circle.fill")
            .font(.title3)
            .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
      }
      .padding(20)

      Divider()

      ScrollView {
        VStack(spacing: 0) {
          ForEach(Array(requests.enumerated()), id: \.element.id) { idx, req in
            OverviewResearchRow(
              request: req,
              projectName: projects.first(where: { $0.id == req.projectId })?.title,
              onTap: {
                dismiss()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                  onSelectProject(req.projectId)
                }
              }
            )
            if idx < requests.count - 1 {
              Divider().padding(.leading, 32)
            }
          }
        }
        .padding(.vertical, 6)
      }
    }
    .background(OTheme.boardBg)
  }
}

// MARK: - Relative Time Helper

private func relativeTime(_ date: Date) -> String {
  let now = Date()
  let seconds = now.timeIntervalSince(date)
  if seconds < 0 { return "just now" } // future date — treat as now
  if seconds < 60 { return "just now" }
  let minutes = Int(seconds / 60)
  if minutes < 60 { return "\(minutes)m ago" }
  let hours = Int(seconds / 3600)
  if hours < 24 { return "\(hours)h ago" }
  let days = Int(seconds / 86400)
  if days < 30 { return "\(days)d ago" }
  let months = Int(seconds / 2_592_000)
  return "\(months)mo ago"
}
