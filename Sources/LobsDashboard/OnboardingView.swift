import SwiftUI

/// Container view for the onboarding wizard flow
struct OnboardingView: View {
    @EnvironmentObject var vm: AppViewModel
    @State private var currentStep: OnboardingStep = .welcome
    @State private var repoUrl: String = ""
    @State private var isNewRepo: Bool = false
    
    /// Onboarding wizard steps
    enum OnboardingStep {
        case welcome
        case repoSetup
        case cloneAndValidate
        case personality
        case serverSetup
        case verification
    }
    
    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            
            switch currentStep {
            case .welcome:
                OnboardingWelcomeView {
                    advanceToNextStep()
                }
                .transition(.opacity)
            
            case .repoSetup:
                OnboardingRepoSetupView(
                    onBack: goBackToPreviousStep,
                    onContinue: { url, isNew in
                        handleRepoSetup(url: url, isNew: isNew)
                    }
                )
                .transition(.opacity)
            
            case .cloneAndValidate:
                OnboardingCloneView(
                    repoUrl: repoUrl,
                    isNewRepo: isNewRepo,
                    onBack: goBackToPreviousStep,
                    onComplete: advanceToNextStep
                )
                .transition(.opacity)
            
            case .personality:
                OnboardingPersonalityView(
                    onBack: goBackToPreviousStep,
                    onContinue: advanceToNextStep
                )
                .transition(.opacity)

            case .serverSetup:
                OnboardingServerSetupView(
                    repoUrl: repoUrl,
                    onBack: goBackToPreviousStep,
                    onContinue: advanceToNextStep
                )
                .transition(.opacity)
            
            case .verification:
                OnboardingVerificationView(
                    repoUrl: repoUrl,
                    onBack: goBackToPreviousStep,
                    onComplete: completeOnboarding
                )
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: currentStep)
    }
    
    /// Advance to the next step in the onboarding flow
    private func advanceToNextStep() {
        switch currentStep {
        case .welcome:
            currentStep = .repoSetup
        case .repoSetup:
            currentStep = .cloneAndValidate
        case .cloneAndValidate:
            currentStep = .personality
        case .personality:
            currentStep = .serverSetup
        case .serverSetup:
            currentStep = .verification
        case .verification:
            completeOnboarding()
        }
    }
    
    /// Go back to the previous step in the onboarding flow
    private func goBackToPreviousStep() {
        switch currentStep {
        case .welcome:
            // Already at first step, do nothing
            break
        case .repoSetup:
            currentStep = .welcome
        case .cloneAndValidate:
            currentStep = .repoSetup
        case .personality:
            currentStep = .cloneAndValidate
        case .serverSetup:
            currentStep = .personality
        case .verification:
            currentStep = .serverSetup
        }
    }
    
    /// Handle repository setup completion
    private func handleRepoSetup(url: String, isNew: Bool) {
        repoUrl = url
        isNewRepo = isNew
        
        // Don't save config yet - the clone screen will handle that
        // Just advance to the next step
        advanceToNextStep()
    }
    
    /// Mark onboarding as complete and save configuration
    private func completeOnboarding() {
        // This will be called when all onboarding steps are finished
        let path = vm.config?.controlRepoPath ?? ""
        let url = vm.config?.controlRepoUrl
        // Persist onboardingComplete, even on fresh installs where config started as nil.
        let ok = vm.setControlRepo(path: path, repoUrl: url, onboardingComplete: true)
        if !ok {
            print("⚠️ Failed to persist onboarding completion")
        }
    }
}

#Preview {
    OnboardingView()
        .environmentObject(AppViewModel())
        .frame(width: 800, height: 600)
}
