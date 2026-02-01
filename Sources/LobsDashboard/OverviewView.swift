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

// MARK: - Overview View

struct OverviewView: View {
  @ObservedObject var vm: AppViewModel
  var onSelectProject: (String) -> Void

  private var allTasks: [DashboardTask] { vm.tasks }

  private var activeProjects: [Project] {
    vm.projects.filter { ($0.archived ?? false) == false }
  }

  // Stats
  private var activeTasks: Int {
    allTasks.filter { $0.status == .active }.count
  }

  private var completedThisWeek: Int {
    let weekAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
    return allTasks.filter { $0.status == .completed && $0.updatedAt >= weekAgo }.count
  }

  private var openResearchRequests: Int {
    var count = 0
    guard let repoURL = vm.repoURL else { return 0 }
    let store = LobsControlStore(repoRoot: repoURL)
    for project in activeProjects where project.resolvedType == .research {
      if let requests = try? store.loadRequests(projectId: project.id) {
        count += requests.filter { $0.status == .open || $0.status == .inProgress }.count
      }
    }
    return count
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
        StatsRow(
          activeTasks: activeTasks,
          completedThisWeek: completedThisWeek,
          openResearchRequests: openResearchRequests,
          blockedTasks: blockedTasks,
          inboxTasks: inboxTasks
        )

        // Project cards
        VStack(alignment: .leading, spacing: 12) {
          Text("Projects")
            .font(.headline)
            .fontWeight(.bold)

          LazyVGrid(columns: [
            GridItem(.adaptive(minimum: 280, maximum: 400), spacing: 16)
          ], spacing: 16) {
            ForEach(activeProjects) { project in
              ProjectCard(
                project: project,
                tasks: allTasks.filter { ($0.projectId ?? "default") == project.id },
                onTap: { onSelectProject(project.id) }
              )
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
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.vertical, 20)
                .frame(maxWidth: .infinity)
            } else {
              VStack(spacing: 0) {
                ForEach(Array(recentActivity.enumerated()), id: \.element.id) { idx, task in
                  ActivityRow(task: task, onTap: {
                    onSelectProject(task.projectId ?? "default")
                    vm.selectTask(task)
                  })
                  if idx < recentActivity.count - 1 {
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

          // Inbox items
          VStack(alignment: .leading, spacing: 12) {
            HStack {
              Text("Inbox")
                .font(.headline)
                .fontWeight(.bold)
              if vm.unreadInboxCount > 0 {
                Text("\(vm.unreadInboxCount)")
                  .font(.caption2)
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
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.vertical, 20)
                .frame(maxWidth: .infinity)
            } else {
              VStack(spacing: 0) {
                ForEach(Array(vm.inboxItems.prefix(8).enumerated()), id: \.element.id) { idx, item in
                  InboxRow(item: item)
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
          .font(.caption)
          .foregroundStyle(color)
        Text(label)
          .font(.caption)
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
          Image(systemName: project.resolvedType == .research ? "doc.text.magnifyingglass" : "rectangle.split.3x1")
            .font(.body)
            .foregroundStyle(project.resolvedType == .research ? .orange : .blue)

          Text(project.title)
            .font(.subheadline)
            .fontWeight(.bold)
            .lineLimit(1)

          Spacer()

          // Health indicator
          Image(systemName: health.icon)
            .font(.caption)
            .foregroundStyle(health.color)

          // Type badge
          Text(project.resolvedType.rawValue.capitalized)
            .font(.system(size: 9, weight: .medium))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(project.resolvedType == .research ? Color.orange.opacity(0.15) : Color.blue.opacity(0.15))
            .foregroundStyle(project.resolvedType == .research ? .orange : .blue)
            .clipShape(Capsule())
        }

        // Task counts
        HStack(spacing: 12) {
          CountBadge(label: "Active", count: activeCount, color: .orange)
          CountBadge(label: "Done", count: completedCount, color: .green)
          if inboxCount > 0 {
            CountBadge(label: "Inbox", count: inboxCount, color: .blue)
          }
          if blockedCount > 0 {
            CountBadge(label: "Blocked", count: blockedCount, color: .red)
          }
          Spacer()
          Text("\(totalCount) total")
            .font(.caption2)
            .foregroundStyle(.tertiary)
        }

        // Last activity
        if let last = lastActivity {
          HStack(spacing: 4) {
            Image(systemName: "clock")
              .font(.system(size: 9))
              .foregroundStyle(.tertiary)
            Text("Last activity: \(relativeTime(last))")
              .font(.caption2)
              .foregroundStyle(.tertiary)
          }
        }

        // Notes preview
        if let notes = project.notes, !notes.isEmpty {
          Text(notes)
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(2)
        }
      }
      .padding(16)
      .frame(maxWidth: .infinity, alignment: .leading)
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
        .font(.caption2)
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
          .font(.caption)
          .frame(width: 24)

        VStack(alignment: .leading, spacing: 2) {
          Text(task.title)
            .font(.caption)
            .fontWeight(.medium)
            .lineLimit(1)

          HStack(spacing: 6) {
            Text(task.owner.rawValue)
              .font(.system(size: 9, weight: .medium))
              .padding(.horizontal, 5)
              .padding(.vertical, 1)
              .background(Color.purple.opacity(0.1))
              .foregroundStyle(.purple)
              .clipShape(Capsule())

            Text(task.status.rawValue.replacingOccurrences(of: "_", with: " "))
              .font(.system(size: 9))
              .foregroundStyle(.tertiary)
          }
        }

        Spacer()

        Text(relativeTime(task.updatedAt))
          .font(.system(size: 9))
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

  var body: some View {
    HStack(spacing: 10) {
      Image(systemName: item.isRead ? "doc.text" : "doc.text.fill")
        .font(.caption)
        .foregroundStyle(item.isRead ? .secondary : .blue)
        .frame(width: 24)

      VStack(alignment: .leading, spacing: 2) {
        Text(item.title)
          .font(.caption)
          .fontWeight(item.isRead ? .regular : .semibold)
          .lineLimit(1)

        Text(item.summary)
          .font(.caption2)
          .foregroundStyle(.secondary)
          .lineLimit(1)
      }

      Spacer()

      Text(relativeTime(item.modifiedAt))
        .font(.system(size: 9))
        .foregroundStyle(.tertiary)
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 8)
  }
}

// MARK: - Relative Time Helper

private func relativeTime(_ date: Date) -> String {
  let now = Date()
  let seconds = now.timeIntervalSince(date)
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
