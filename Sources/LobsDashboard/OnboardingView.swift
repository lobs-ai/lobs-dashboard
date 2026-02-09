import SwiftUI

/// Container view for the onboarding wizard flow
struct OnboardingView: View {
    @EnvironmentObject var vm: AppViewModel
    @State private var currentStep: OnboardingStep = .welcome
    
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
                // Placeholder for repo setup screen
                // TODO: Create OnboardingRepoSetupView.swift
                Text("Repo Setup Screen")
                    .font(.largeTitle)
                    .foregroundColor(.secondary)
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
    
    /// Mark onboarding as complete and save configuration
    private func completeOnboarding() {
        // This will be called when all onboarding steps are finished
        // The actual config will be populated during the repo setup step
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
