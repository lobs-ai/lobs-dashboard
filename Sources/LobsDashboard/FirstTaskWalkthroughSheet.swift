import SwiftUI

/// First-run interactive walkthrough that guides the user through creating a task,
/// seeing it picked up by the orchestrator, and viewing results.
struct FirstTaskWalkthroughSheet: View {
  @ObservedObject var vm: AppViewModel
  @Binding var autoPush: Bool

  /// Action that opens the standard "New Task" sheet.
  let openNewTaskSheet: () -> Void

  /// Optional action to open the inbox/results area.
  let openInbox: () -> Void

  @Environment(\.dismiss) private var dismiss

  @State private var step: Step = .intro
  @State private var baselineTaskIds: Set<String> = []
  @State private var trackedTaskId: String? = nil
  @State private var startedAt: Date = Date()

  enum Step: Int, CaseIterable {
    case intro
    case create
    case pickup
    case results
    case done
  }

  private var trackedTask: DashboardTask? {
    guard let id = trackedTaskId else { return nil }
    return vm.tasks.first(where: { $0.id == id })
  }

  private var trackedWorkRaw: String {
    trackedTask?.workState?.rawValue ?? "(none)"
  }

  private var trackedStatusRaw: String {
    trackedTask?.status.rawValue ?? "(none)"
  }

  private var isPickedUpByWorker: Bool {
    let raw = trackedTask?.workState?.rawValue ?? ""
    return raw == WorkState.inProgress.rawValue
  }

  private var isFinished: Bool {
    // The orchestrator may set status=completed/rejected, and/or workState=completed/failed.
    let status = trackedTask?.status
    if status == .completed || status == .rejected { return true }

    let raw = trackedTask?.workState?.rawValue ?? ""
    return raw == "completed" || raw == "failed"
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      header

      Divider()

      Group {
        switch step {
        case .intro:
          introStep
        case .create:
          createStep
        case .pickup:
          pickupStep
        case .results:
          resultsStep
        case .done:
          doneStep
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)

      Spacer()

      footer
    }
    .padding(24)
    .frame(minWidth: 640, idealWidth: 720, minHeight: 440)
    .onAppear {
      startedAt = Date()
      baselineTaskIds = Set(vm.tasks.map { $0.id })

      // If the user already has tasks, don't force a specific task — we still want
      // a first-run walkthrough, but focus it on the next task they create.
      if trackedTaskId == nil {
        trackedTaskId = nil
      }
    }
    .onChange(of: vm.tasks) { _ in
      advanceIfPossibleFromTaskUpdates()
    }
  }

  // MARK: - UI

  private var header: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack(spacing: 10) {
        Image(systemName: "sparkles")
          .font(.title2)
          .foregroundStyle(.linearGradient(colors: [.blue, .purple], startPoint: .topLeading, endPoint: .bottomTrailing))

        VStack(alignment: .leading, spacing: 2) {
          Text("First task walkthrough")
            .font(.title2)
            .fontWeight(.bold)

          Text("We’ll create one task, watch Lobs pick it up, then review the result.")
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }

        Spacer()

        Button("Skip") {
          vm.firstTaskWalkthroughComplete = true
          dismiss()
        }
        .keyboardShortcut(.cancelAction)
      }

      if let task = trackedTask {
        HStack(spacing: 12) {
          Text("Tracking:")
            .foregroundStyle(.secondary)
          Text(task.title)
            .fontWeight(.semibold)
          Text("•")
            .foregroundStyle(.tertiary)
          Text("status: \(trackedStatusRaw)")
            .font(.callout)
            .foregroundStyle(.secondary)
          Text("•")
            .foregroundStyle(.tertiary)
          Text("work: \(trackedWorkRaw)")
            .font(.callout)
            .foregroundStyle(.secondary)
          Spacer()
        }
        .font(.callout)
      } else {
        Text("No task selected yet — we’ll start tracking once you create one.")
          .font(.callout)
          .foregroundStyle(.secondary)
      }
    }
  }

  private var footer: some View {
    HStack {
      if step != .intro {
        Button("Back") {
          withAnimation(.easeInOut(duration: 0.2)) {
            step = Step(rawValue: max(step.rawValue - 1, 0)) ?? .intro
          }
        }
      }

      Spacer()

      Button(step == .done ? "Close" : "Next") {
        onNextTapped()
      }
      .keyboardShortcut(.defaultAction)
      .buttonStyle(.borderedProminent)
    }
  }

  private var introStep: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("How the system works")
        .font(.headline)

      Text("Lobs Dashboard is a UI on top of your git-backed control repo. When you create a task, the dashboard writes JSON into your `lobs-control` repo and (optionally) pushes it to GitHub. The orchestrator polls that repo, then spawns a worker to execute tasks.")
        .font(.body)

      VStack(alignment: .leading, spacing: 8) {
        Text("In this walkthrough you’ll:")
          .fontWeight(.medium)
        Text("1) Create a task (⌘N)")
        Text("2) Push it to the server (auto-push recommended)")
        Text("3) Watch it switch to in-progress")
        Text("4) Review the artifact / notes")
      }
      .font(.callout)
      .foregroundStyle(.secondary)

      Toggle("Auto-push new tasks", isOn: $autoPush)
        .toggleStyle(.switch)
        .help("When enabled, the dashboard will commit + push automatically after you create the task")

      Text("Tip: If you don’t see progress, open Settings and confirm auto-refresh is enabled (default: every 30s).")
        .font(.callout)
        .foregroundStyle(.secondary)
    }
  }

  private var createStep: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Step 1 — Create your first task")
        .font(.headline)

      Text("Click \"New Task\" (or press ⌘N). Give it a clear title and add a sentence of context in Notes. When you hit Create, we’ll start tracking that task here.")
        .font(.body)

      Button("Open New Task (⌘N)") {
        openNewTaskSheet()
      }

      GroupBox {
        VStack(alignment: .leading, spacing: 8) {
          Text("Suggested example")
            .fontWeight(.semibold)
          Text("Title: \"Hello Lobs — create a tiny demo artifact\"")
          Text("Notes: \"Please write a short summary of what you changed and where the artifact is saved.\"")
        }
        .font(.callout)
      }

      Text("Waiting for a new task…")
        .font(.callout)
        .foregroundStyle(.secondary)
    }
  }

  private var pickupStep: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Step 2 — Watch it get picked up")
        .font(.headline)

      Text("Behind the scenes:")
        .fontWeight(.medium)

      VStack(alignment: .leading, spacing: 6) {
        Text("• The dashboard writes `state/tasks/<id>.json` and commits it")
        Text("• If auto-push is on, it pushes to the remote")
        Text("• The orchestrator polls the repo, sees the new task, and assigns a worker")
        Text("• The worker updates `workState` to `in_progress` and starts executing")
      }
      .font(.callout)
      .foregroundStyle(.secondary)

      if trackedTask == nil {
        Text("No task is being tracked yet. Go back and create one.")
          .font(.callout)
          .foregroundStyle(.secondary)
      } else if isPickedUpByWorker {
        Text("✅ Picked up! The worker is now in progress.")
          .font(.callout)
      } else {
        Text("Waiting for the orchestrator… this can take a minute or two depending on the poll interval.")
          .font(.callout)
          .foregroundStyle(.secondary)
      }
    }
  }

  private var resultsStep: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Step 3 — Review results")
        .font(.headline)

      Text("When the worker finishes, you’ll typically see one or more of:")
        .font(.body)

      VStack(alignment: .leading, spacing: 6) {
        Text("• Task status changes (e.g. completed/failed)")
        Text("• Notes updated with what happened")
        Text("• An artifact saved in the control repo (often linked from the task)")
        Text("• Inbox items you can review and convert into new tasks")
      }
      .font(.callout)
      .foregroundStyle(.secondary)

      if isFinished {
        Text("✅ Done — looks like the task finished. Open it to read notes and view any artifact links.")
          .font(.callout)

        Button("Open Inbox") {
          openInbox()
        }
      } else {
        Text("Waiting for the worker to finish…")
          .font(.callout)
          .foregroundStyle(.secondary)
      }
    }
  }

  private var doneStep: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("You’re set")
        .font(.headline)

      Text("You now have the full loop: create a task → push → orchestrator picks it up → worker runs → results show up back here.")
        .font(.body)
      Text("Tip: If things look stuck, check that auto-refresh is enabled (Settings) and that your control repo is syncing.")
        .font(.callout)
        .foregroundStyle(.secondary)
    }
  }

  // MARK: - Behavior

  private func onNextTapped() {
    withAnimation(.easeInOut(duration: 0.2)) {
      switch step {
      case .intro:
        step = .create
      case .create:
        // Don’t advance until we have a task.
        if trackedTaskId != nil { step = .pickup }
      case .pickup:
        if isPickedUpByWorker { step = .results }
      case .results:
        if isFinished { step = .done }
      case .done:
        vm.firstTaskWalkthroughComplete = true
        dismiss()
      }
    }
  }

  private func advanceIfPossibleFromTaskUpdates() {
    // Step: create — detect first new task created after the walkthrough started.
    if step == .create {
      let currentIds = Set(vm.tasks.map { $0.id })
      let newIds = currentIds.subtracting(baselineTaskIds)
      if trackedTaskId == nil, let id = newIds.first {
        trackedTaskId = id
        // Keep baseline stable so we don't re-track if many tasks sync in.
        baselineTaskIds = currentIds
        withAnimation(.easeInOut(duration: 0.2)) {
          step = .pickup
        }
      }
    }

    if step == .pickup, isPickedUpByWorker {
      withAnimation(.easeInOut(duration: 0.2)) {
        step = .results
      }
    }

    if step == .results, isFinished {
      withAnimation(.easeInOut(duration: 0.2)) {
        step = .done
      }
    }
  }
}
