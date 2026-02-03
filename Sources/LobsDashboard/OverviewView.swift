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

  @State private var detailTask: DashboardTask? = nil
  @State private var showDetailedStats: Bool = false
  @State private var draggingProjectId: String? = nil
  @State private var showCreateProject: Bool = false

  private var allTasks: [DashboardTask] { vm.tasks }

  private var activeProjects: [Project] {
    vm.sortedActiveProjects
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
    return allTasks.filter { $0.status == .completed && $0.updatedAt >= weekStart && $0.updatedAt < weekEnd }.count
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

  /// Inbox items needing attention (unread docs or unread follow-ups).
  private var inboxNeedsAttentionCount: Int {
    vm.unreadInboxCount
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
            inboxTasks: inboxTasks,
            inboxNeedsAttentionCount: inboxNeedsAttentionCount,
            workerHistory: vm.workerHistory
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
          DetailedStatsView(tasks: allTasks, projects: activeProjects, researchRequestCountsByProject: researchRequestCountsByProject)
            .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .top)))
            .clipped()
        }

        // Worker status
        if let ws = vm.workerStatus {
          WorkerStatusCard(
            status: ws,
            history: vm.workerHistory,
            canRequestWorker: !ws.active && !vm.workerRequestPending,
            workerRequested: vm.workerRequestPending,
            onRequestWorker: { vm.requestWorker() }
          )
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

            // New Project button card
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
              .frame(maxWidth: .infinity, minHeight: 100)
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
                  .background(Color.red)
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
                // Sort: items needing attention first, then by modified date
                let sortedItems = vm.inboxItems.sorted { a, b in
                  let aNeeds = !a.isRead || vm.unreadFollowupCount(docId: a.id) > 0
                  let bNeeds = !b.isRead || vm.unreadFollowupCount(docId: b.id) > 0
                  if aNeeds != bNeeds { return aNeeds }
                  return a.modifiedAt > b.modifiedAt
                }
                ForEach(Array(sortedItems.prefix(8).enumerated()), id: \.element.id) { idx, item in
                  InboxRow(item: item, unreadFollowups: vm.unreadFollowupCount(docId: item.id), onTap: {
                    vm.markInboxItemRead(item)
                    if let onOpenInbox {
                      onOpenInbox(item.id)
                    }
                  })
                  if idx < min(sortedItems.count, 8) - 1 {
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
  }
}

// MARK: - Stats Row

private struct StatsRow: View {
  let activeTasks: Int
  let completedThisWeek: Int
  let openResearchRequests: Int
  let blockedTasks: Int
  let inboxTasks: Int
  let inboxNeedsAttentionCount: Int
  var workerHistory: WorkerHistory? = nil

  private var weeklySpend: Double {
    guard let history = workerHistory else { return 0 }
    let calendar = Calendar.current
    let startOfWeek = calendar.dateInterval(of: .weekOfYear, for: Date())?.start ?? Date()
    return history.runs
      .filter { run in
        guard let ended = run.endedAt else { return false }
        return ended >= startOfWeek
      }
      .reduce(0.0) { $0 + ($1.estimatedCostUSD ?? 0) }
  }

  var body: some View {
    HStack(spacing: 16) {
      StatCard(label: "Active Tasks", value: "\(activeTasks)", icon: "flame.fill", color: .orange)
      StatCard(label: "Completed This Week", value: "\(completedThisWeek)", icon: "checkmark.circle.fill", color: .green)
      StatCard(label: "Research Requests", value: "\(openResearchRequests)", icon: "magnifyingglass", color: .purple)
      if blockedTasks > 0 {
        StatCard(label: "Blocked", value: "\(blockedTasks)", icon: "exclamationmark.octagon.fill", color: .red)
      }
      if inboxTasks > 0 {
        StatCard(label: "Inbox Tasks", value: "\(inboxTasks)", icon: "tray.full.fill", color: .blue)
      }
      if inboxNeedsAttentionCount > 0 {
        StatCard(label: "Inbox", value: "\(inboxNeedsAttentionCount)", icon: "envelope.badge", color: .red)
      }
      if weeklySpend > 0 {
        StatCard(label: "Worker Spend (Week)", value: "~$\(String(format: "%.2f", weeklySpend))", icon: "dollarsign.circle.fill", color: .mint)
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

        // Counts
        HStack(spacing: 12) {
          // Research projects don't use task status columns, so avoid showing Active/Done.
          if project.resolvedType != .research {
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
          }
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
    tasks.filter { $0.status == .completed && $0.updatedAt >= weekStart && $0.updatedAt < weekEnd }
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

private struct WorkerStatusCard: View {
  let status: WorkerStatus
  var history: WorkerHistory? = nil
  var canRequestWorker: Bool = false
  var workerRequested: Bool = false
  var onRequestWorker: (() -> Void)? = nil
  @State private var showHistory = false

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
              let isResearch = task.lowercased().hasPrefix("research:")
              HStack(spacing: 4) {
                Image(systemName: isResearch ? "magnifyingglass" : "hammer.fill")
                  .font(.system(size: 10))
                  .foregroundStyle(isResearch ? .purple : .secondary)
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

    // Recent runs history
    if let history = history, !history.runs.isEmpty {
      VStack(alignment: .leading, spacing: 0) {
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
            let totalRuns = history.runs.count
            let shownRuns = min(totalRuns, 10)
            Text(totalRuns > shownRuns ? "(last \\(shownRuns) of \\(totalRuns))" : "(\\(totalRuns))")
              .font(.footnote)
              .foregroundStyle(.tertiary)

            Spacer()

            // Cumulative cost summary
            let totalCost = history.runs.reduce(0.0) { $0 + ($1.estimatedCostUSD ?? 0) }
            let todayRuns = history.runs.filter { run in
              guard let ended = run.endedAt else { return false }
              return Calendar.current.isDateInToday(ended)
            }
            let todayCost = todayRuns.reduce(0.0) { $0 + ($1.estimatedCostUSD ?? 0) }
            if totalCost > 0 {
              HStack(spacing: 8) {
                if todayCost > 0 {
                  Text("Today: ~$\(todayCost, specifier: "%.2f")")
                    .font(.system(size: 11, weight: .medium).monospacedDigit())
                    .foregroundStyle(.orange)
                }
                Text("Total: ~$\(totalCost, specifier: "%.2f")")
                  .font(.system(size: 11, weight: .medium).monospacedDigit())
                  .foregroundStyle(.secondary)
              }
            }
          }
          .padding(.horizontal, 14)
          .padding(.vertical, 8)
        }
        .buttonStyle(.plain)

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
    }
  }
}

private struct WorkerHistoryRow: View {
  let run: WorkerHistoryRun

  var body: some View {
    HStack(spacing: 10) {
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

      // Cost
      if let cost = run.estimatedCostUSD, cost > 0 {
        HStack(spacing: 2) {
          Text("~$\(cost, specifier: "%.2f")")
            .font(.footnote.monospacedDigit())
            .foregroundStyle(.secondary)
        }
        .frame(width: 55, alignment: .leading)
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
