import SwiftUI

struct OrchestratorStatusIndicator: View {
  @EnvironmentObject var orch: OrchestratorManager
  @EnvironmentObject var vm: AppViewModel

  @State private var showDetails: Bool = false

  var body: some View {
    Button {
      if case .stopped = orch.status {
        Task { await orch.start() }
      } else {
        showDetails.toggle()
      }
    } label: {
      HStack(spacing: 6) {
        Circle()
          .fill(orch.status.indicatorColor)
          .frame(width: 8, height: 8)
        Text("Orchestrator")
          .font(.system(size: 11, weight: .medium))
          .foregroundStyle(.secondary)
      }
      .padding(.horizontal, 8)
      .padding(.vertical, 6)
      .background(Theme.subtle)
      .clipShape(RoundedRectangle(cornerRadius: 8))
    }
    .buttonStyle(.plain)
    .help("\(orch.status.label) — click for details")
    .popover(isPresented: $showDetails, arrowEdge: .bottom) {
      OrchestratorControlPanel(compact: true)
        .environmentObject(orch)
        .environmentObject(vm)
        .frame(width: 440, height: 420)
        .padding(12)
    }
  }
}

struct OrchestratorControlPanel: View {
  @EnvironmentObject var orch: OrchestratorManager
  @EnvironmentObject var vm: AppViewModel

  var compact: Bool = false

  @State private var isWorking: Bool = false

  private var currentTaskLabel: String {
    if let t = vm.workerStatus?.currentTask, !t.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      return t
    }
    return "Idle"
  }

  private var tasksCompletedToday: Int {
    guard let hist = vm.workerHistory else { return 0 }
    let cal = Calendar.current
    let today = Date()

    var count = 0
    for run in hist.runs {
      if let log = run.taskLog {
        for entry in log {
          if let d = entry.completedAt, cal.isDate(d, inSameDayAs: today) {
            count += 1
          }
        }
      } else if let ended = run.endedAt, cal.isDate(ended, inSameDayAs: today) {
        count += run.tasksCompleted ?? 0
      }
    }
    return count
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack {
        Text(compact ? "Orchestrator" : "Orchestrator Control")
          .font(.system(size: compact ? 14 : 16, weight: .semibold))
        Spacer()
        HStack(spacing: 8) {
          Circle().fill(orch.status.indicatorColor).frame(width: 8, height: 8)
          Text(orch.status.label)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.secondary)
        }
      }

      VStack(alignment: .leading, spacing: 8) {
        infoRow(label: "Status", value: orch.status.label)
        infoRow(label: "Uptime", value: orch.uptimeText)
        infoRow(label: "Current task", value: currentTaskLabel)
        infoRow(label: "Tasks completed today", value: "\(tasksCompletedToday)")
      }
      .padding(10)
      .background(Theme.cardBg)
      .cornerRadius(10)
      .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.border, lineWidth: 1))

      HStack(spacing: 10) {
        Button("Start") {
          Task { await runAction { await orch.start() } }
        }
        .disabled(isWorking || orch.status.isRunning)

        Button("Stop") {
          Task { await runAction { await orch.stop() } }
        }
        .disabled(isWorking || !orch.status.isRunning)

        Button("Restart") {
          Task { await runAction { await orch.restart() } }
        }
        .disabled(isWorking || !orch.status.isRunning)

        Spacer()

        Button("Refresh") {
          Task { await orch.refreshStatusAndLogs() }
        }
        .disabled(isWorking)
      }
      .controlSize(.small)

      Toggle("Run on login", isOn: Binding(
        get: { orch.runOnLogin },
        set: { val in
          Task { await orch.setRunOnLogin(val) }
        }
      ))
      .toggleStyle(.switch)
      .disabled(isWorking)

      VStack(alignment: .leading, spacing: 6) {
        Text("Logs (last 50 lines)")
          .font(.system(size: 12, weight: .semibold))
          .foregroundStyle(.secondary)

        ScrollView {
          Text(orch.lastLogText.isEmpty ? "(no logs found)" : orch.lastLogText)
            .font(.system(size: 11, design: .monospaced))
            .foregroundStyle(.secondary)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxHeight: .infinity)
        .padding(10)
        .background(Theme.cardBg)
        .cornerRadius(10)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.border, lineWidth: 1))
      }
    }
    .task {
      orch.startMonitoring()
      await orch.refreshStatusAndLogs()
    }
  }

  private func infoRow(label: String, value: String) -> some View {
    HStack(alignment: .top) {
      Text(label + ":")
        .font(.system(size: 12, weight: .semibold))
        .frame(width: 150, alignment: .leading)
        .foregroundStyle(.secondary)
      Text(value)
        .font(.system(size: 12))
        .foregroundStyle(.primary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .lineLimit(3)
    }
  }

  private func runAction(_ action: @escaping () async -> Void) async {
    isWorking = true
    await action()
    isWorking = false
  }
}
