import SwiftUI

/// Container view for the full onboarding wizard flow.
struct OnboardingView: View {
  @EnvironmentObject var vm: AppViewModel

  @State private var currentStep: Step = .welcome

  @State private var onboardingState: OnboardingState = OnboardingStateManager.load()

  // Inputs gathered during onboarding
  @State private var workspacePath: String = NSHomeDirectory() + "/lobs"
  @State private var controlRepoUrl: String = ""
  @State private var isNewControlRepo: Bool = false

  @State private var agentName: String = "Lobs"
  @State private var userName: String = ""

  enum Step {
    case welcome
    case prereqs
    case workspace
    case repoSetup
    case cloneCoreRepos
    case installOpenClaw
    case configureOpenClaw
    case agentSetup
    case startOrchestrator
    case done
  }

  var body: some View {
    ZStack {
      Theme.bg.ignoresSafeArea()

      switch currentStep {
      case .welcome:
        OnboardingWelcomeView {
          markCompleted(.welcome)
          advance()
        }
        .transition(.opacity)

      case .prereqs:
        OnboardingPrereqsView(
          onBack: goBack,
          onContinue: {
            markCompleted(.prereqs)
            advance()
          }
        )
        .transition(.opacity)

      case .workspace:
        OnboardingWorkspaceView(
          initialWorkspace: workspacePath,
          onBack: goBack,
          onContinue: { path in
            workspacePath = path
            onboardingState.workspace = path
            markCompleted(.workspace)
            advance()
          }
        )
        .transition(.opacity)

      case .repoSetup:
        OnboardingRepoSetupView(
          onBack: goBack,
          onContinue: { url, isNew in
            controlRepoUrl = url
            isNewControlRepo = isNew
            advance()
          }
        )
        .transition(.opacity)

      case .cloneCoreRepos:
        OnboardingCloneCoreReposView(
          workspacePath: workspacePath,
          controlRepoUrl: controlRepoUrl,
          isNewControlRepo: isNewControlRepo,
          onBack: goBack,
          onComplete: { controlRepoPath in
            _ = vm.setControlRepo(path: controlRepoPath.path, repoUrl: controlRepoUrl, onboardingComplete: nil)
            markCompleted(.cloneCoreRepos)
            advance()
          }
        )
        .transition(.opacity)

      case .installOpenClaw:
        OnboardingOpenClawInstallView(
          onBack: goBack,
          onContinue: {
            markCompleted(.installOpenClaw)
            advance()
          }
        )
        .transition(.opacity)

      case .configureOpenClaw:
        OnboardingOpenClawConfigView(
          workspacePath: workspacePath,
          onBack: goBack,
          onContinue: {
            markCompleted(.configureOpenClaw)
            advance()
          }
        )
        .transition(.opacity)

      case .agentSetup:
        OnboardingAgentSetupView(
          workspacePath: workspacePath,
          initialAgentName: onboardingState.agentName ?? agentName,
          initialUserName: onboardingState.userName ?? userName,
          onBack: goBack,
          onContinue: { agent, user in
            agentName = agent
            userName = user
            onboardingState.agentName = agent
            onboardingState.userName = user
            markCompleted(.agentSetup)
            advance()
          }
        )
        .transition(.opacity)

      case .startOrchestrator:
        OnboardingOrchestratorView(
          workspacePath: workspacePath,
          onBack: goBack,
          onContinue: {
            markCompleted(.startOrchestrator)
            advance()
          }
        )
        .transition(.opacity)

      case .done:
        OnboardingDoneView {
          completeOnboarding()
        }
        .transition(.opacity)
      }
    }
    .animation(.easeInOut(duration: 0.25), value: currentStep)
    .onAppear {
      // Restore persisted onboarding state + pick first incomplete step.
      let s = OnboardingStateManager.load()
      onboardingState = s
      if let ws = s.workspace { workspacePath = ws }
      if let agent = s.agentName { agentName = agent }
      if let user = s.userName { userName = user }

      // If config already has a control repo URL (e.g., user partially set up), reuse it.
      if controlRepoUrl.isEmpty {
        let cfgUrl = vm.config?.controlRepoUrl.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !cfgUrl.isEmpty { controlRepoUrl = cfgUrl }
      }

      currentStep = firstIncompleteStep(state: s)
    }
  }

  private func firstIncompleteStep(state: OnboardingState) -> Step {
    if !state.isCompleted(.welcome) { return .welcome }
    if !state.isCompleted(.prereqs) { return .prereqs }
    if !state.isCompleted(.workspace) { return .workspace }
    // We intentionally don't persist repo setup separately.
    if controlRepoUrl.isEmpty { return .repoSetup }
    if !state.isCompleted(.cloneCoreRepos) { return .cloneCoreRepos }
    if !state.isCompleted(.installOpenClaw) { return .installOpenClaw }
    if !state.isCompleted(.configureOpenClaw) { return .configureOpenClaw }
    if !state.isCompleted(.agentSetup) { return .agentSetup }
    if !state.isCompleted(.startOrchestrator) { return .startOrchestrator }
    return .done
  }

  private func markCompleted(_ step: OnboardingStepID) {
    onboardingState.markCompleted(step)
    OnboardingStateManager.save(onboardingState)
  }

  private func advance() {
    currentStep = nextStep(after: currentStep)
    OnboardingStateManager.save(onboardingState)
  }

  private func goBack() {
    currentStep = previousStep(before: currentStep)
  }

  private func nextStep(after step: Step) -> Step {
    switch step {
    case .welcome: return .prereqs
    case .prereqs: return .workspace
    case .workspace: return .repoSetup
    case .repoSetup: return .cloneCoreRepos
    case .cloneCoreRepos: return .installOpenClaw
    case .installOpenClaw: return .configureOpenClaw
    case .configureOpenClaw: return .agentSetup
    case .agentSetup: return .startOrchestrator
    case .startOrchestrator: return .done
    case .done: return .done
    }
  }

  private func previousStep(before step: Step) -> Step {
    switch step {
    case .welcome: return .welcome
    case .prereqs: return .welcome
    case .workspace: return .prereqs
    case .repoSetup: return .workspace
    case .cloneCoreRepos: return .repoSetup
    case .installOpenClaw: return .cloneCoreRepos
    case .configureOpenClaw: return .installOpenClaw
    case .agentSetup: return .configureOpenClaw
    case .startOrchestrator: return .agentSetup
    case .done: return .startOrchestrator
    }
  }

  private func completeOnboarding() {
    // Persist onboarding completion.
    let path = vm.config?.controlRepoPath ?? ""
    let url = vm.config?.controlRepoUrl
    let ok = vm.setControlRepo(path: path, repoUrl: url, onboardingComplete: true)
    if !ok {
      print("⚠️ Failed to persist onboarding completion")
    }

    onboardingState.markCompleted(.done)
    OnboardingStateManager.save(onboardingState)
  }
}

#Preview {
  OnboardingView()
    .environmentObject(AppViewModel())
    .frame(width: 900, height: 650)
}
