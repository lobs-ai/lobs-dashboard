import SwiftUI

/// Container view for the full onboarding wizard flow.
///
/// Responsibilities:
/// - Track the current step (1-10)
/// - Persist/resume onboarding state
/// - Enforce navigation rules (Back always; Next only if validated; Skip only optional)
/// - Render wizard shell UI (sidebar, progress bar, bottom navigation)
struct OnboardingView: View {
  @EnvironmentObject var vm: AppViewModel

  @StateObject private var wizard = OnboardingWizardContext()

  @State private var currentStep: Step = .welcome
  @State private var onboardingState: OnboardingState = OnboardingStateManager.load(preferredWorkspacePath: LobsPaths.defaultWorkspace)

  // Inputs gathered during onboarding
  @State private var workspacePath: String = LobsPaths.defaultWorkspace
  @State private var controlRepoUrl: String = ""
  @State private var isNewControlRepo: Bool = false

  @State private var agentName: String = "Lobs"
  @State private var userName: String = ""

  enum Step: CaseIterable, Identifiable {
    case welcome
    case workspace
    case cloneRepos
    case serverGuide
    case done

    var id: String { title }

    var title: String {
      switch self {
      case .welcome: return "Welcome"
      case .workspace: return "Workspace"
      case .cloneRepos: return "Clone repos"
      case .serverGuide: return "Server setup"
      case .done: return "Done"
      }
    }

    var isOptional: Bool {
      switch self {
      case .cloneRepos, .serverGuide:
        return true
      default:
        return false
      }
    }

    var stepIndex1Based: Int {
      Step.allCases.firstIndex(of: self).map { $0 + 1 } ?? 1
    }

    var onboardingID: OnboardingStepID? {
      switch self {
      case .welcome: return .welcome
      case .workspace: return .workspace
      case .cloneRepos: return .cloneCoreRepos
      case .serverGuide: return .serverGuide
      case .done: return .done
      }
    }
  }

  private var totalSteps: Int { Step.allCases.count }

  var body: some View {
    HStack(spacing: 0) {
      sidebar

      Divider()

      VStack(spacing: 0) {
        progressBar

        Divider()

        ZStack {
          Theme.bg.ignoresSafeArea()

          stepBody
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .environmentObject(wizard)
            .id(currentStep)  // Force view recreation when step changes via sidebar
        }

        Divider()

        bottomNav
      }
    }
    .onAppear {
      restoreAndResume()
    }
    .onChange(of: currentStep) { newStep in
      configureWizardForStep(newStep)
    }
  }

  // MARK: - Shell UI

  private var sidebar: some View {
    VStack(alignment: .leading, spacing: 14) {
      Text("Setup")
        .font(.system(size: 16, weight: .semibold))
        .padding(.top, 18)

      VStack(alignment: .leading, spacing: 8) {
        ForEach(Step.allCases) { step in
          sidebarRow(step)
        }
      }

      Spacer()
    }
    .padding(.horizontal, 16)
    .frame(width: 220)
    .background(Theme.cardBg)
  }

  private func sidebarRow(_ step: Step) -> some View {
    let isCurrent = step == currentStep
    let completed = step.onboardingID.map { onboardingState.isCompleted($0) } ?? false

    return Button(action: { currentStep = step }) {
      HStack(spacing: 10) {
        Image(systemName: completed ? "checkmark.circle.fill" : "circle")
          .foregroundColor(completed ? .green : .secondary.opacity(0.6))
          .font(.system(size: 13))
          .frame(width: 16)

        VStack(alignment: .leading, spacing: 1) {
          Text(step.title)
            .font(.system(size: 13, weight: isCurrent ? .semibold : .regular))
            .foregroundColor(isCurrent ? .primary : .secondary)

          if step.isOptional {
            Text("Optional")
              .font(.system(size: 11))
              .foregroundColor(.secondary)
          }
        }

        Spacer(minLength: 0)
      }
      .padding(.vertical, 6)
      .padding(.horizontal, 10)
      .background(isCurrent ? Theme.bg.opacity(0.55) : Color.clear)
      .cornerRadius(8)
    }
    .buttonStyle(.plain)
  }

  private var progressBar: some View {
    VStack(spacing: 10) {
      HStack {
        Text("Step \(currentStep.stepIndex1Based) of \(totalSteps)")
          .font(.system(size: 13, weight: .medium))
          .foregroundColor(.secondary)
        Spacer()
      }

      ProgressView(value: Double(currentStep.stepIndex1Based), total: Double(totalSteps))
        .progressViewStyle(.linear)
    }
    .padding(.horizontal, 18)
    .padding(.vertical, 12)
    .background(Theme.bg)
  }

  private var bottomNav: some View {
    HStack(spacing: 12) {
      Button(action: goBack) {
        Text("Back")
          .font(.system(size: 14, weight: .medium))
          .foregroundColor(.primary)
          .frame(width: 120)
          .padding(.vertical, 10)
      }
      .buttonStyle(.plain)
      .background(Theme.cardBg)
      .cornerRadius(8)
      .disabled(currentStep == .welcome)
      .opacity(currentStep == .welcome ? 0.5 : 1.0)

      Spacer()

      if wizard.showsSkip {
        Button(action: { wizard.triggerSkip() }) {
          Text(wizard.skipTitle)
            .font(.system(size: 14, weight: .medium))
            .foregroundColor(.primary)
            .frame(width: 120)
            .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
        .background(Theme.cardBg)
        .cornerRadius(8)
        .disabled(!wizard.canSkip)
        .opacity(wizard.canSkip ? 1.0 : 0.5)
      }

      Button(action: { wizard.triggerNext() }) {
        Text(wizard.nextTitle)
          .font(.system(size: 14, weight: .medium))
          .foregroundColor(.white)
          .frame(width: 140)
          .padding(.vertical, 10)
      }
      .buttonStyle(.plain)
      .background(Theme.accent)
      .cornerRadius(8)
      .disabled(!wizard.canGoNext)
      .opacity(wizard.canGoNext ? 1.0 : 0.5)
    }
    .padding(.horizontal, 18)
    .padding(.vertical, 14)
    .background(Theme.bg)
  }

  // MARK: - Step content

  @ViewBuilder
  private var stepBody: some View {
    switch currentStep {
    case .welcome:
      OnboardingWelcomeView()

    case .workspace:
      OnboardingWorkspaceView(initialWorkspace: workspacePath) { path in
        workspacePath = path
        onboardingState.workspace = path
        markCompleted(.workspace)
        advance()
      }

    case .cloneRepos:
      Group {
        if controlRepoUrl.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
          OnboardingRepoSetupView(
            onComplete: { url, isNew in
              controlRepoUrl = url
              isNewControlRepo = isNew
              // Stay on this step; next view will be clone UI.
              wizard.configureNext(title: "Next", enabled: true) {
                // No-op; OnboardingRepoSetupView drives completion.
              }
            },
            onSkip: {
              // User chose to skip repo setup - mark complete and advance.
              markCompleted(.cloneCoreRepos)
              advance()
            }
          )
        } else {
          OnboardingCloneCoreReposView(
            workspacePath: workspacePath,
            controlRepoUrl: controlRepoUrl,
            isNewControlRepo: isNewControlRepo,
            onSkip: {
              markCompleted(.cloneCoreRepos)
              advance()
            }
          ) { controlRepoPath in
            _ = vm.setControlRepo(path: controlRepoPath.path, repoUrl: controlRepoUrl, onboardingComplete: nil)
            markCompleted(.cloneCoreRepos)
            advance()
          }
        }
      }

    case .serverGuide:
      OnboardingServerGuideView()
        .onAppear {
          wizard.configureNext(title: "Next", enabled: true) {
            markCompleted(.serverGuide)
            advance()
          }
          wizard.configureSkip(shown: true, title: "Skip for now", enabled: true) {
            markCompleted(.serverGuide)
            advance()
          }
        }

    case .done:
      OnboardingDoneView {
        completeOnboarding()
      }
    }
  }

  // MARK: - Persistence + resume

  private func restoreAndResume() {
    // Restore persisted onboarding state + pick first incomplete step.
    let s = OnboardingStateManager.load(preferredWorkspacePath: workspacePath)
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
    configureWizardForStep(currentStep)
  }
  
  private func configureWizardForStep(_ step: Step) {
    wizard.resetForStep()
    switch step {
    case .welcome:
      wizard.configureNext(title: "Let's go", enabled: true) {
        markCompleted(.welcome)
        advance()
      }
    case .done:
      wizard.configureNext(title: "Go to dashboard", enabled: true) {
        completeOnboarding()
      }
    default:
      // Other steps configure themselves via their views
      break
    }
  }

  private func firstIncompleteStep(state: OnboardingState) -> Step {
    if !state.isCompleted(.welcome) { return .welcome }
    if !state.isCompleted(.workspace) { return .workspace }
    if !state.isCompleted(.cloneCoreRepos) { return .cloneRepos }
    if !state.isCompleted(.serverGuide) { return .serverGuide }
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
    case .welcome: return .workspace
    case .workspace: return .cloneRepos
    case .cloneRepos: return .serverGuide
    case .serverGuide: return .done
    case .done: return .done
    }
  }

  private func previousStep(before step: Step) -> Step {
    switch step {
    case .welcome: return .welcome
    case .workspace: return .welcome
    case .cloneRepos: return .workspace
    case .serverGuide: return .cloneRepos
    case .done: return .serverGuide
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
    .frame(width: 1000, height: 700)
}
