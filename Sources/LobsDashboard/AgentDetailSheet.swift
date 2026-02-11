import SwiftUI

struct AgentDetailSheet: View {
  let agentType: String
  @ObservedObject var vm: AppViewModel
  @Environment(\.dismiss) private var dismiss

  @State private var memory: String = ""
  @State private var evolvedTraits: String = ""
  @State private var personality: String = ""
  @State private var isEditingPersonality = false
  @State private var editedPersonality: String = ""
  @State private var isSaving = false

  private var status: AgentStatus? { vm.agentStatuses[agentType] }
  private var displayName: String { status?.displayName ?? agentType.capitalized }
  private var emoji: String { status?.emoji ?? "\u{1F916}" }

  var body: some View {
    VStack(spacing: 0) {
      headerView
      Divider()
      ScrollView {
        VStack(alignment: .leading, spacing: 20) {
          currentActivitySection
          personalitySection
          memorySection
          evolvedTraitsSection
        }
        .padding(20)
      }
    }
    .frame(minWidth: 520, minHeight: 500)
    .background(Theme.boardBg)
    .onAppear(perform: loadData)
  }

  // MARK: - Header

  private var headerView: some View {
    HStack(spacing: 12) {
      Text(emoji)
        .font(.largeTitle)
      VStack(alignment: .leading, spacing: 2) {
        Text(displayName)
          .font(.title2)
          .fontWeight(.bold)
        HStack(spacing: 6) {
          Circle()
            .fill(statusColor)
            .frame(width: 8, height: 8)
          Text(status?.status ?? "idle")
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
      }
      Spacer()

      if let stats = status?.stats {
        VStack(alignment: .trailing, spacing: 2) {
          if let completed = stats.tasksCompleted {
            Text("\(completed) completed")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
          if let failed = stats.tasksFailed, failed > 0 {
            Text("\(failed) failed")
              .font(.caption)
              .foregroundStyle(.red.opacity(0.8))
          }
        }
      }

      Button { dismiss() } label: {
        Image(systemName: "xmark.circle.fill")
          .font(.title2)
          .foregroundStyle(.secondary)
      }
      .buttonStyle(.plain)
    }
    .padding(20)
  }

  // MARK: - Current Activity

  @ViewBuilder
  private var currentActivitySection: some View {
    if status?.isActive == true {
      VStack(alignment: .leading, spacing: 8) {
        Label("Current Activity", systemImage: "bolt.fill")
          .font(.headline)
          .foregroundStyle(.green)

        if let activity = status?.activity {
          Text(activity)
            .font(.body)
        }
        if let project = status?.currentProjectId {
          HStack(spacing: 4) {
            Text("Project:")
              .foregroundStyle(.secondary)
            Text(project)
              .fontWeight(.medium)
          }
          .font(.callout)
        }
        if let thinking = status?.thinking, !thinking.isEmpty {
          VStack(alignment: .leading, spacing: 4) {
            Text("Thinking:")
              .font(.caption)
              .foregroundStyle(.secondary)
            Text(thinking)
              .font(.system(size: 12, design: .monospaced))
              .foregroundStyle(.primary)
              .padding(8)
              .frame(maxWidth: .infinity, alignment: .leading)
              .background(
                RoundedRectangle(cornerRadius: 6)
                  .fill(Color.primary.opacity(0.04))
              )
          }
        }
      }
      .padding(14)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(
        RoundedRectangle(cornerRadius: Theme.cardRadius)
          .fill(Color.green.opacity(0.06))
      )
      .overlay(
        RoundedRectangle(cornerRadius: Theme.cardRadius)
          .stroke(Color.green.opacity(0.2), lineWidth: 1)
      )
    }
  }

  // MARK: - Personality

  private var personalitySection: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Label("Personality (SOUL.md)", systemImage: "sparkles")
          .font(.headline)
        Spacer()
        if isEditingPersonality {
          Button("Cancel") {
            isEditingPersonality = false
            editedPersonality = personality
          }
          .buttonStyle(.plain)
          .foregroundStyle(.secondary)

          Button("Save") {
            savePersonality()
          }
          .buttonStyle(.borderedProminent)
          .controlSize(.small)
          .disabled(isSaving || editedPersonality == personality)
        } else {
          Button("Edit") {
            editedPersonality = personality
            isEditingPersonality = true
          }
          .buttonStyle(.plain)
          .foregroundStyle(.blue)
        }
      }

      if isEditingPersonality {
        TextEditor(text: $editedPersonality)
          .font(.system(size: 12, design: .monospaced))
          .frame(minHeight: 200)
          .padding(4)
          .background(
            RoundedRectangle(cornerRadius: 6)
              .fill(Theme.cardBg)
          )
          .overlay(
            RoundedRectangle(cornerRadius: 6)
              .stroke(Theme.border)
          )
      } else {
        Text(personality.isEmpty ? "(no personality set)" : personality)
          .font(.system(size: 12, design: .monospaced))
          .foregroundStyle(personality.isEmpty ? .tertiary : .primary)
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(10)
          .background(
            RoundedRectangle(cornerRadius: 6)
              .fill(Theme.cardBg)
          )
      }
    }
  }

  // MARK: - Memory

  private var memorySection: some View {
    VStack(alignment: .leading, spacing: 8) {
      Label("Memory", systemImage: "brain")
        .font(.headline)

      Text(memory.isEmpty ? "(no memories yet)" : memory)
        .font(.system(size: 12, design: .monospaced))
        .foregroundStyle(memory.isEmpty ? .tertiary : .primary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(
          RoundedRectangle(cornerRadius: 6)
            .fill(Theme.cardBg)
        )
    }
  }

  // MARK: - Evolved Traits

  private var evolvedTraitsSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      Label("Evolved Traits", systemImage: "chart.line.uptrend.xyaxis")
        .font(.headline)

      Text(evolvedTraits.isEmpty ? "(no evolved traits yet)" : evolvedTraits)
        .font(.system(size: 12, design: .monospaced))
        .foregroundStyle(evolvedTraits.isEmpty ? .tertiary : .primary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(
          RoundedRectangle(cornerRadius: 6)
            .fill(Theme.cardBg)
        )
    }
  }

  // MARK: - Helpers

  private var statusColor: Color {
    switch status?.status ?? "idle" {
    case "working": return .green
    case "thinking": return .yellow
    case "finalizing": return .blue
    default: return .gray
    }
  }

  private func loadData() {
    guard let repoURL = vm.repoURL else { return }
    Task.detached {
      let store = LobsControlStore(repoRoot: repoURL)
      let mem = store.loadAgentFile(agentType: agentType, filename: "MEMORY.md") ?? ""
      let traits = store.loadAgentFile(agentType: agentType, filename: "EVOLVED_TRAITS.md") ?? ""
      let soul = store.loadAgentFile(agentType: agentType, filename: "SOUL.md") ?? ""
      await MainActor.run {
        self.memory = mem
        self.evolvedTraits = traits
        self.personality = soul
        self.editedPersonality = soul
      }
    }
  }

  private func savePersonality() {
    guard let repoURL = vm.repoURL else { return }
    isSaving = true
    Task.detached {
      let store = LobsControlStore(repoRoot: repoURL)
      do {
        try store.saveAgentFile(agentType: agentType, filename: "SOUL.md", content: editedPersonality)
        // Best-effort git commit
        let cwd = repoURL
        _ = await Git.runAsyncWithErrorHandling(["add", "memory/\(agentType)/SOUL.md"], cwd: cwd)
        _ = await Git.runAsyncWithErrorHandling(
          ["commit", "-m", "agents: update \(agentType) personality"],
          cwd: cwd
        )
      } catch {
        // Silent failure — file saved even if git fails
      }
      await MainActor.run {
        self.personality = self.editedPersonality
        self.isEditingPersonality = false
        self.isSaving = false
      }
    }
  }
}
