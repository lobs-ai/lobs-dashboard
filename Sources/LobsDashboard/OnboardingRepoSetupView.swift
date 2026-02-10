import SwiftUI
import AppKit

/// Repository setup screen of the onboarding wizard
struct OnboardingRepoSetupView: View {
    @EnvironmentObject var vm: AppViewModel
    @EnvironmentObject private var wizard: OnboardingWizardContext

    let onComplete: (String, Bool) -> Void
    let onSkip: (() -> Void)?
    
    @State private var repoChoice: RepoChoice = .existing
    @State private var sshUrl: String = ""
    @State private var validationError: String? = nil
    
    /// Whether the user has an existing repo or needs to create one
    enum RepoChoice {
        case existing
        case new
    }
    
    private let templateRepoWebURL = URL(string: "https://github.com/RafeSymonds/lobs-control")

    var body: some View {
        VStack(spacing: 32) {
            Spacer()
            
            VStack(spacing: 12) {
                // Title
                Text("Control Repository")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundColor(.primary)
                
                // Subtitle
                Text("Set up your \"lobs-control\" repository. This is where tasks, projects, and state live.")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 520)
                
                // Skip hint
                if onSkip != nil {
                    Text("You can skip this for now and add repositories later from Settings.")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary.opacity(0.8))
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 520)
                }
            }
            
            VStack(spacing: 24) {
                // Radio button selection
                VStack(spacing: 12) {
                    RadioOption(
                        title: "I have an existing control repo",
                        isSelected: repoChoice == .existing,
                        action: {
                            repoChoice = .existing
                            validationError = nil
                        }
                    )
                    
                    RadioOption(
                        title: "I want to fork a new control repo (recommended)",
                        isSelected: repoChoice == .new,
                        action: {
                            repoChoice = .new
                            validationError = nil
                        }
                    )
                }
                .padding(.top, 8)
                
                // Instructions for new repo
                if repoChoice == .new {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 8) {
                            Image(systemName: "info.circle")
                                .foregroundColor(.secondary)
                            Text("Recommended: fork the template repo on GitHub, then paste your fork's SSH URL below.")
                                .font(.system(size: 13))
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text("How to fork")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.primary)

                            Text("1) Open the template repo\n2) Click Fork\n3) Copy your fork's SSH URL (Code → SSH)")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                        }

                        if let url = templateRepoWebURL {
                            Button {
                                NSWorkspace.shared.open(url)
                            } label: {
                                Label("Open template on GitHub", systemImage: "arrow.up.right.square")
                            }
                            .buttonStyle(.plain)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(Theme.accent)
                        }
                    }
                    .frame(maxWidth: 450, alignment: .leading)
                    .padding(12)
                    .background(Theme.cardBg)
                    .cornerRadius(10)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Theme.border, lineWidth: 1)
                    )
                }
                
                // SSH URL input field
                VStack(alignment: .leading, spacing: 6) {
                    Text("SSH URL")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                    
                    TextField("git@github.com:user/lobs-control.git", text: $sshUrl)
                        .textFieldStyle(.plain)
                        .font(.system(size: 14, design: .monospaced))
                        .padding(10)
                        .background(Theme.cardBg)
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(validationError != nil ? Color.red : Theme.border, lineWidth: 1)
                        )
                        .onChange(of: sshUrl) { _ in
                            validationError = nil
                        }
                    
                    // Helper or error text
                    if let error = validationError {
                        HStack(spacing: 4) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 11))
                            Text(error)
                                .font(.system(size: 12))
                        }
                        .foregroundColor(.red)
                    } else {
                        Text(helperText)
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                }
                .frame(width: 450)
            }
            
            Spacer()
            
            Text("Use Next to continue")
              .font(.system(size: 13))
              .foregroundColor(.secondary)
              .padding(.bottom, 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.bg)
        .onAppear {
          wizard.configureNext(
            title: "Next",
            enabled: !sshUrl.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
          ) {
            handleContinue()
          }
          wizard.configureSkip(
            shown: onSkip != nil,
            title: "Skip for now",
            enabled: true
          ) {
            onSkip?()
          }
        }
        .onChange(of: sshUrl) { _ in
          wizard.updateNextEnabled(!sshUrl.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }
    
    /// Helper text that changes based on repo choice
    private var helperText: String {
        switch repoChoice {
        case .existing:
            return "Enter the SSH URL of your existing control repository"
        case .new:
            return "We'll clone your fork and verify the required structure"
        }
    }
    
    /// Validate SSH URL and proceed if valid
    private func handleContinue() {
        let trimmedUrl = sshUrl.trimmingCharacters(in: .whitespaces)
        
        // Validate SSH URL format
        if !isValidSSHUrl(trimmedUrl) {
            validationError = "Invalid SSH URL format. Must start with 'git@' or use SSH format."
            return
        }
        
        // Pass data to parent
        let isNewRepo = repoChoice == .new
        onComplete(trimmedUrl, isNewRepo)
    }
    
    /// Validate that the URL is a proper SSH Git URL
    private func isValidSSHUrl(_ url: String) -> Bool {
        // Check if it starts with git@
        if url.hasPrefix("git@") {
            // Basic check: should contain : and end with .git
            return url.contains(":") && url.hasSuffix(".git")
        }
        
        // Check for ssh:// format
        if url.hasPrefix("ssh://") {
            return url.hasSuffix(".git")
        }
        
        return false
    }
}

/// Reusable radio button option component
struct RadioOption: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                // Radio circle
                ZStack {
                    Circle()
                        .stroke(isSelected ? Theme.accent : Color.secondary.opacity(0.3), lineWidth: 2)
                        .frame(width: 20, height: 20)
                    
                    if isSelected {
                        Circle()
                            .fill(Theme.accent)
                            .frame(width: 10, height: 10)
                    }
                }
                
                Text(title)
                    .font(.system(size: 14))
                    .foregroundColor(.primary)
                
                Spacer()
            }
            .padding(12)
            .frame(maxWidth: 450)
            .background(isSelected ? Theme.accent.opacity(0.08) : Theme.cardBg)
            .cornerRadius(10)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isSelected ? Theme.accent.opacity(0.3) : Theme.border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    OnboardingRepoSetupView(
        onComplete: { url, isNew in
            print("Continue with URL: \(url), isNew: \(isNew)")
        },
        onSkip: {
            print("Skip repo setup")
        }
    )
    .environmentObject(AppViewModel())
    .environmentObject(OnboardingWizardContext())
    .frame(width: 800, height: 600)
}
