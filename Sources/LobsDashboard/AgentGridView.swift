import SwiftUI

private typealias OTheme = Theme

// MARK: - Agent Grid

struct AgentGridView: View {
  @ObservedObject var vm: AppViewModel

  private let columns = [
    GridItem(.flexible(), spacing: 12),
    GridItem(.flexible(), spacing: 12),
    GridItem(.flexible(), spacing: 12),
  ]

  private let allAgentTypes = ["programmer", "architect", "researcher", "reviewer", "writer"]

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        Image(systemName: "person.3.fill")
          .foregroundStyle(.purple)
        Text("Agents")
          .font(.headline)
          .fontWeight(.bold)
        Spacer()

        let activeCount = vm.agentStatuses.values.filter(\.isActive).count
        if activeCount > 0 {
          Text("\(activeCount) active")
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
              Capsule()
                .fill(Color.green.opacity(0.2))
            )
        }
      }

      LazyVGrid(columns: columns, spacing: 12) {
        ForEach(allAgentTypes, id: \.self) { agentType in
          let status = vm.agentStatuses[agentType]
          AgentCard(agentType: agentType, status: status)
            .onTapGesture {
              vm.selectedAgentType = agentType
            }
        }
      }
    }
  }
}

// MARK: - Agent Card

private struct AgentCard: View {
  let agentType: String
  let status: AgentStatus?

  private var isActive: Bool { status?.isActive ?? false }
  private var displayName: String { status?.displayName ?? agentType.capitalized }
  private var emoji: String { status?.emoji ?? "\u{1F916}" }

  private var statusColor: Color {
    switch status?.status ?? "idle" {
    case "working": return .green
    case "thinking": return .yellow
    case "finalizing": return .blue
    default: return .gray
    }
  }

  private var statusLabel: String {
    switch status?.status ?? "idle" {
    case "working": return "Working"
    case "thinking": return "Thinking"
    case "finalizing": return "Finalizing"
    default: return "Idle"
    }
  }

  private var lastActiveText: String? {
    guard let date = status?.lastActiveAt else { return nil }
    let interval = Date().timeIntervalSince(date)
    if interval < 60 { return "just now" }
    if interval < 3600 { return "\(Int(interval / 60))m ago" }
    if interval < 86400 { return "\(Int(interval / 3600))h ago" }
    return "\(Int(interval / 86400))d ago"
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      // Header: emoji + name + status dot
      HStack(spacing: 8) {
        Text(emoji)
          .font(.title2)
        Text(displayName)
          .font(.subheadline)
          .fontWeight(.semibold)
        Spacer()
        Circle()
          .fill(statusColor)
          .frame(width: 8, height: 8)
          .shadow(color: isActive ? statusColor.opacity(0.6) : .clear, radius: 4)
      }

      // Status label
      Text(statusLabel)
        .font(.caption)
        .foregroundStyle(isActive ? statusColor : .secondary)

      // Activity (when working)
      if let activity = status?.activity, !activity.isEmpty {
        Text(activity)
          .font(.caption2)
          .foregroundStyle(.primary)
          .lineLimit(2)
      }

      // Thinking snippet
      if let thinking = status?.thinking, !thinking.isEmpty {
        Text(thinking)
          .font(.system(size: 10, design: .monospaced))
          .foregroundStyle(.secondary)
          .lineLimit(2)
          .padding(6)
          .frame(maxWidth: .infinity, alignment: .leading)
          .background(
            RoundedRectangle(cornerRadius: 4)
              .fill(Color.primary.opacity(0.03))
          )
      }

      Spacer(minLength: 0)

      // Footer: stats
      HStack {
        if let completed = status?.stats?.tasksCompleted, completed > 0 {
          Label("\(completed)", systemImage: "checkmark.circle")
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        Spacer()
        if let text = lastActiveText {
          Text(text)
            .font(.caption2)
            .foregroundStyle(.tertiary)
        }
      }
    }
    .padding(12)
    .frame(minHeight: 120)
    .background(
      RoundedRectangle(cornerRadius: OTheme.cardRadius)
        .fill(OTheme.cardBg)
    )
    .overlay(
      RoundedRectangle(cornerRadius: OTheme.cardRadius)
        .stroke(isActive ? statusColor.opacity(0.4) : OTheme.border, lineWidth: isActive ? 1.5 : 1)
    )
    .contentShape(Rectangle())
  }
}
