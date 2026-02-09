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
        // Add more steps as needed (e.g., .gitSetup, .completion)
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
            // When repo setup is complete, mark onboarding as done
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
        }
    }
    
    /// Handle repository setup completion
    private func handleRepoSetup(url: String, isNew: Bool) {
        repoUrl = url
        isNewRepo = isNew
        
        // Save the repository URL to config
        if var config = vm.config {
            config.controlRepoUrl = url
            // Note: controlRepoPath will be set when the repo is actually cloned
            // For now, we just save the URL
            do {
                try ConfigManager.save(config)
                vm.config = config
            } catch {
                print("⚠️ Failed to save repo URL: \(error)")
            }
        }
        
        // Advance to next step (or complete onboarding if this is the last step)
        advanceToNextStep()
    }
    
    /// Mark onboarding as complete and save configuration
    private func completeOnboarding() {
        // This will be called when all onboarding steps are finished
        if var config = vm.config {
            config.onboardingComplete = true
            do {
                try ConfigManager.save(config)
                vm.config = config
            } catch {
                print("⚠️ Failed to save onboarding completion: \(error)")
            }
        }
    }
}

#Preview {
    OnboardingView()
        .environmentObject(AppViewModel())
        .frame(width: 800, height: 600)
}
