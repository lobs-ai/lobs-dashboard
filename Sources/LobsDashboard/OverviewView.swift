import SwiftUI

// MARK: - Theme (shared palette)

private enum OTheme {
  static let bg = Color(nsColor: .windowBackgroundColor)
  static let boardBg = Color(nsColor: .underPageBackgroundColor)
  static let cardBg = Color(nsColor: .controlBackgroundColor)
  static let accent = Color.accentColor
  static let subtle = Color.primary.opacity(0.06)
  static let border = Color.primary.opacity(0.08)
  static let cardRadius: CGFloat = 14
}

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

  @State private var detailTask: DashboardTask? = nil
  @State private var showInboxSheet: Bool = false
  @State private var pendingInboxItemId: String? = nil
  @State private var showDetailedStats: Bool = false
  @State private var draggingProjectId: String? = nil

  private var allTasks: [DashboardTask] { vm.tasks }

  private var activeProjects: [Project] {
    vm.sortedActiveProjects
  }

  // Stats
  private var activeTasks: Int {
    allTasks.filter { $0.status == .active }.count
  }

  private var completedThisWeek: Int {
    let weekAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
    return allTasks.filter { $0.status == .completed && $0.updatedAt >= weekAgo }.count
  }

  /// Open research request counts per project.
  private var researchRequestCountsByProject: [String: Int] {
    guard let repoURL = vm.repoURL else { return [:] }
    let store = LobsControlStore(repoRoot: repoURL)
    var counts: [String: Int] = [:]
    for project in activeProjects where project.resolvedType == .research {
      if let requests = try? store.loadRequests(projectId: project.id) {
        counts[project.id] = requests.filter { $0.status == .open || $0.status == .inProgress }.count
      }
    }
    return counts
  }

  private var openResearchRequests: Int {
    researchRequestCountsByProject.values.reduce(0, +)
  }

  private var blockedTasks: Int {
    allTasks.filter { $0.workState == .blocked }.count
  }

  private var inboxTasks: Int {
    allTasks.filter { $0.status == .inbox }.count
  }

  // Recent activity: tasks updated in the last 7 days, sorted by recency
  private var recentActivity: [DashboardTask] {
    let weekAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
    return allTasks
      .filter { $0.updatedAt >= weekAgo }
      .sorted { $0.updatedAt > $1.updatedAt }
      .prefix(15)
      .map { $0 }
  }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 24) {
        // Header
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

        // Quick stats
        HStack(alignment: .top) {
          StatsRow(
            activeTasks: activeTasks,
            completedThisWeek: completedThisWeek,
            openResearchRequests: openResearchRequests,
            blockedTasks: blockedTasks,
            inboxTasks: inboxTasks
          )
          Spacer()
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

        if showDetailedStats {
          DetailedStatsView(tasks: allTasks, projects: activeProjects)
            .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .top)))
            .clipped()
        }

        // Worker status
        if let ws = vm.workerStatus {
          WorkerStatusCard(status: ws)
        }

        // Project cards
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
                researchRequestCount: researchRequestCountsByProject[project.id] ?? 0,
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
          }
        }

        // Two-column layout: Recent Activity + Inbox
        HStack(alignment: .top, spacing: 24) {
          // Recent activity feed
          VStack(alignment: .leading, spacing: 12) {
            Text("Recent Activity")
              .font(.headline)
              .fontWeight(.bold)

            if recentActivity.isEmpty {
              Text("No recent activity")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.vertical, 20)
                .frame(maxWidth: .infinity)
            } else {
              ScrollView {
                VStack(spacing: 0) {
                  ForEach(Array(recentActivity.enumerated()), id: \.element.id) { idx, task in
                    ActivityRow(task: task, onTap: {
                      vm.selectTask(task)
                      detailTask = task
                    })
                    if idx < recentActivity.count - 1 {
                      Divider().padding(.leading, 36)
                    }
                  }
                }
              }
              .frame(maxHeight: 400)
              .background(OTheme.cardBg)
              .clipShape(RoundedRectangle(cornerRadius: OTheme.cardRadius))
              .overlay(
                RoundedRectangle(cornerRadius: OTheme.cardRadius)
                  .stroke(OTheme.border, lineWidth: 0.5)
              )
            }
          }
          .frame(minWidth: 0, maxWidth: .infinity)

          // Inbox items
          VStack(alignment: .leading, spacing: 12) {
            HStack {
              Text("Inbox")
                .font(.headline)
                .fontWeight(.bold)
              if vm.unreadInboxCount > 0 {
                Text("\(vm.unreadInboxCount)")
                  .font(.footnote)
                  .fontWeight(.bold)
                  .foregroundStyle(.white)
                  .padding(.horizontal, 6)
                  .padding(.vertical, 2)
                  .background(Color.blue)
                  .clipShape(Capsule())
              }
            }

            if vm.inboxItems.isEmpty {
              Text("No inbox items")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.vertical, 20)
                .frame(maxWidth: .infinity)
            } else {
              VStack(spacing: 0) {
                ForEach(Array(vm.inboxItems.prefix(8).enumerated()), id: \.element.id) { idx, item in
                  InboxRow(item: item, onTap: {
                    vm.markInboxItemRead(item)
                    pendingInboxItemId = item.id
                    showInboxSheet = true
                  })
                  if idx < min(vm.inboxItems.count, 8) - 1 {
                    Divider().padding(.leading, 36)
                  }
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
          .frame(minWidth: 0, maxWidth: .infinity)
        }
      }
      .padding(24)
    }
    .background(OTheme.boardBg)
    .sheet(item: $detailTask) { task in
      OverviewTaskDetailSheet(task: task, vm: vm)
        .frame(minWidth: 480, minHeight: 500)
    }
    .sheet(isPresented: $showInboxSheet) {
      InboxView(vm: vm, isPresented: $showInboxSheet, initialSelectedItemId: pendingInboxItemId)
        .frame(minWidth: 1000, minHeight: 650)
        .onDisappear { pendingInboxItemId = nil }
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

  var body: some View {
    HStack(spacing: 16) {
      StatCard(label: "Active Tasks", value: "\(activeTasks)", icon: "flame.fill", color: .orange)
      StatCard(label: "Completed This Week", value: "\(completedThisWeek)", icon: "checkmark.circle.fill", color: .green)
      StatCard(label: "Research Requests", value: "\(openResearchRequests)", icon: "magnifyingglass", color: .purple)
      if blockedTasks > 0 {
        StatCard(label: "Blocked", value: "\(blockedTasks)", icon: "exclamationmark.octagon.fill", color: .red)
      }
      if inboxTasks > 0 {
        StatCard(label: "Inbox", value: "\(inboxTasks)", icon: "tray.full.fill", color: .blue)
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
  var researchRequestCount: Int = 0
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

  /// Health indicator based on blocked ratio and staleness.
  private var health: Health {
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

        // Task counts
        HStack(spacing: 12) {
          CountBadge(label: "Active", count: activeCount, color: .orange)
          CountBadge(label: "Done", count: completedCount, color: .green)
          if researchRequestCount > 0 {
            CountBadge(label: "Research", count: researchRequestCount, color: .purple)
          }
          if inboxCount > 0 {
            CountBadge(label: "Inbox", count: inboxCount, color: .blue)
          }
          if blockedCount > 0 {
            CountBadge(label: "Blocked", count: blockedCount, color: .red)
          }
          Spacer()
          Text("\(totalCount) total")
            .font(.footnote)
            .foregroundStyle(.tertiary)
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
      .frame(maxWidth: .infinity, minHeight: 120, alignment: .leading)
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

// MARK: - Activity Row

private struct ActivityRow: View {
  let task: DashboardTask
  let onTap: () -> Void

  @State private var isHovering = false

  var body: some View {
    Button(action: onTap) {
      HStack(spacing: 10) {
        // Status icon
        statusIcon
          .font(.footnote)
          .frame(width: 24)

        VStack(alignment: .leading, spacing: 2) {
          Text(task.title)
            .font(.footnote)
            .fontWeight(.medium)
            .lineLimit(1)

          HStack(spacing: 6) {
            Text(task.owner.rawValue)
              .font(.system(size: 11, weight: .medium))
              .padding(.horizontal, 5)
              .padding(.vertical, 1)
              .background(Color.purple.opacity(0.1))
              .foregroundStyle(.purple)
              .clipShape(Capsule())

            Text(task.status.rawValue.replacingOccurrences(of: "_", with: " "))
              .font(.system(size: 11))
              .foregroundStyle(.tertiary)
          }
        }

        Spacer()

        Text(relativeTime(task.updatedAt))
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

  @ViewBuilder
  private var statusIcon: some View {
    switch task.status {
    case .active:
      Image(systemName: "bolt.circle.fill")
        .foregroundStyle(.orange)
    case .completed:
      Image(systemName: "checkmark.circle.fill")
        .foregroundStyle(.green)
    case .inbox:
      Image(systemName: "tray.circle.fill")
        .foregroundStyle(.blue)
    case .rejected:
      Image(systemName: "xmark.circle.fill")
        .foregroundStyle(.red)
    case .waitingOn:
      Image(systemName: "clock.circle.fill")
        .foregroundStyle(.yellow)
    case .other:
      Image(systemName: "questionmark.circle.fill")
        .foregroundStyle(.gray)
    }
  }
}

// MARK: - Inbox Row

private struct InboxRow: View {
  let item: InboxItem
  let onTap: () -> Void

  @State private var isHovering = false

  var body: some View {
    Button(action: onTap) {
      HStack(spacing: 10) {
        Image(systemName: item.isRead ? "doc.text" : "doc.text.fill")
          .font(.footnote)
          .foregroundStyle(item.isRead ? .secondary : Color.blue)
          .frame(width: 24)

        VStack(alignment: .leading, spacing: 2) {
          Text(item.title)
            .font(.footnote)
            .fontWeight(item.isRead ? .regular : .semibold)
            .lineLimit(1)

          Text(item.summary)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .lineLimit(1)
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
            TextField("Add notes…", text: $editNotes, axis: .vertical)
              .textFieldStyle(.roundedBorder)
              .lineLimit(6, reservesSpace: true)
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

  // Status breakdown
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

  // Tasks per project
  private var tasksPerProject: [(String, Int, Int, Int)] { // (name, total, active, completed)
    projects.map { project in
      let projectTasks = tasks.filter { ($0.projectId ?? "default") == project.id }
      let active = projectTasks.filter { $0.status == .active }.count
      let completed = projectTasks.filter { $0.status == .completed }.count
      return (project.title, projectTasks.count, active, completed)
    }
    .sorted { $0.1 > $1.1 }
  }

  // Completion rate
  private var completionRate: Double {
    let completable = tasks.filter { $0.status == .completed || $0.status == .active || $0.status == .waitingOn }
    guard !completable.isEmpty else { return 0 }
    let completed = completable.filter { $0.status == .completed }.count
    return Double(completed) / Double(completable.count)
  }

  // Average time to complete (days)
  private var avgCompletionDays: Double? {
    let completedTasks = tasks.filter { $0.status == .completed }
    guard !completedTasks.isEmpty else { return nil }
    let totalDays = completedTasks.reduce(0.0) { sum, task in
      sum + task.updatedAt.timeIntervalSince(task.createdAt) / 86400
    }
    return totalDays / Double(completedTasks.count)
  }

  // Most active projects (by tasks updated in last 14 days)
  private var mostActiveProjects: [(String, Int)] {
    let twoWeeksAgo = Calendar.current.date(byAdding: .day, value: -14, to: Date()) ?? Date()
    var counts: [String: Int] = [:]
    for task in tasks where task.updatedAt >= twoWeeksAgo {
      let projectId = task.projectId ?? "default"
      let name = projects.first(where: { $0.id == projectId })?.title ?? projectId
      counts[name, default: 0] += 1
    }
    return counts.sorted { $0.value > $1.value }.prefix(5).map { ($0.key, $0.value) }
  }

  // Owner breakdown
  private var ownerBreakdown: [(String, Int)] {
    var counts: [String: Int] = [:]
    for task in tasks where task.status == .active {
      counts[task.owner.rawValue, default: 0] += 1
    }
    return counts.sorted { $0.value > $1.value }
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      HStack(spacing: 8) {
        Image(systemName: "chart.bar.xaxis")
          .font(.title3)
          .foregroundStyle(.purple)
        Text("Detailed Statistics")
          .font(.headline)
          .fontWeight(.bold)
      }

      // Top metrics row
      HStack(spacing: 16) {
        MetricCard(
          title: "Total Tasks",
          value: "\(tasks.count)",
          icon: "list.bullet",
          color: .blue
        )
        MetricCard(
          title: "Completion Rate",
          value: String(format: "%.0f%%", completionRate * 100),
          icon: "percent",
          color: .green
        )
        if let avgDays = avgCompletionDays {
          MetricCard(
            title: "Avg Completion",
            value: avgDays < 1 ? String(format: "%.0fh", avgDays * 24) : String(format: "%.1fd", avgDays),
            icon: "clock",
            color: .orange
          )
        }
        MetricCard(
          title: "Active Owners",
          value: "\(ownerBreakdown.count)",
          icon: "person.2",
          color: .purple
        )
      }

      HStack(alignment: .top, spacing: 24) {
        // Status breakdown
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
              // Bar
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
        }
        .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(OTheme.cardBg)
        .clipShape(RoundedRectangle(cornerRadius: OTheme.cardRadius))
        .overlay(
          RoundedRectangle(cornerRadius: OTheme.cardRadius)
            .stroke(OTheme.border, lineWidth: 0.5)
        )

        // Tasks per project
        VStack(alignment: .leading, spacing: 10) {
          Text("Tasks per Project")
            .font(.callout)
            .fontWeight(.semibold)

          ForEach(tasksPerProject, id: \.0) { name, total, active, completed in
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

        // Most active + owner breakdown
        VStack(alignment: .leading, spacing: 16) {
          // Most active projects
          VStack(alignment: .leading, spacing: 8) {
            Text("Most Active (14d)")
              .font(.callout)
              .fontWeight(.semibold)

            if mostActiveProjects.isEmpty {
              Text("No recent activity")
                .font(.footnote)
                .foregroundStyle(.secondary)
            } else {
              ForEach(mostActiveProjects, id: \.0) { name, count in
                HStack {
                  Text(name)
                    .font(.callout)
                    .lineLimit(1)
                  Spacer()
                  Text("\(count) updates")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                }
              }
            }
          }

          Divider()

          // Owner breakdown
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

private struct WorkerStatusCard: View {
  let status: WorkerStatus

  private var isActive: Bool { status.active }

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
          .fill(isActive ? Color.green.opacity(0.15) : Color.gray.opacity(0.1))
          .frame(width: 40, height: 40)
        Image(systemName: isActive ? "bolt.fill" : "moon.zzz.fill")
          .font(.system(size: 18))
          .foregroundStyle(isActive ? .green : .secondary)
      }

      VStack(alignment: .leading, spacing: 4) {
        HStack(spacing: 6) {
          Text("Lobs Worker")
            .font(.callout)
            .fontWeight(.semibold)

          // Status pill
          Text(isActive ? "Active" : "Idle")
            .font(.system(size: 11, weight: .semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(isActive ? Color.green.opacity(0.15) : Color.gray.opacity(0.1))
            .foregroundStyle(isActive ? .green : .secondary)
            .clipShape(Capsule())
        }

        if isActive {
          HStack(spacing: 12) {
            if let task = status.currentTask {
              HStack(spacing: 4) {
                Image(systemName: "hammer.fill")
                  .font(.system(size: 10))
                  .foregroundStyle(.secondary)
                Text(task)
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
          }
        } else {
          if let heartbeat = status.lastHeartbeat {
            Text("Last seen \(relativeTime(heartbeat))")
              .font(.footnote)
              .foregroundStyle(.tertiary)
          }
        }
      }

      Spacer()
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
