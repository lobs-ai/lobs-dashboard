import SwiftUI
import AppKit

/// Server configuration screen of the onboarding wizard
struct OnboardingRepoSetupView: View {
    @EnvironmentObject var vm: AppViewModel
    @EnvironmentObject private var wizard: OnboardingWizardContext

    let onComplete: (String, Bool) -> Void
    let onSkip: (() -> Void)?
    
    @State private var serverURL: String = "http://localhost:8000"
    @State private var validationError: String? = nil

    var body: some View {
        VStack(spacing: 32) {
            Spacer()
            
            VStack(spacing: 12) {
                // Title
                Text("Server Configuration")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundColor(.primary)
                
                // Subtitle
                Text("Connect to your Lobs API server. This is where tasks, projects, and state are managed.")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 520)
                
                // Skip hint
                if onSkip != nil {
                    Text("You can skip this for now and configure the server later from Settings.")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary.opacity(0.8))
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 520)
                }
            }
            
            VStack(spacing: 24) {
                // Server URL input field
                VStack(alignment: .leading, spacing: 6) {
                    Text("Server URL")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                    
                    TextField("http://localhost:8000", text: $serverURL)
                        .textFieldStyle(.plain)
                        .font(.system(size: 14, design: .monospaced))
                        .padding(10)
                        .background(Theme.cardBg)
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(validationError != nil ? Color.red : Theme.border, lineWidth: 1)
                        )
                        .onChange(of: serverURL) { _ in
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
                        Text("Enter the URL of your Lobs API server (e.g., http://localhost:8000)")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                }
                .frame(width: 450)
                
                // Info box about the server
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        Image(systemName: "info.circle")
                            .foregroundColor(.secondary)
                        Text("The Lobs server manages tasks, orchestration, and state. Make sure it's running before connecting.")
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
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
            enabled: !serverURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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
        .onChange(of: serverURL) { _ in
          wizard.updateNextEnabled(!serverURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }
    
    /// Validate server URL and proceed if valid
    private func handleContinue() {
        let trimmedUrl = serverURL.trimmingCharacters(in: .whitespaces)
        
        // Validate URL format
        if !isValidURL(trimmedUrl) {
            validationError = "Invalid URL format. Must be a valid HTTP or HTTPS URL."
            return
        }
        
        // Pass data to parent (second param is now unused but kept for compatibility)
        onComplete(trimmedUrl, false)
    }
    
    /// Validate that the URL is a proper HTTP/HTTPS URL
    private func isValidURL(_ urlString: String) -> Bool {
        guard let url = URL(string: urlString) else {
            return false
        }
        
        return url.scheme == "http" || url.scheme == "https"
    }
}

#Preview {
    OnboardingRepoSetupView(
        onComplete: { url, _ in
            print("Continue with server URL: \(url)")
        },
        onSkip: {
            print("Skip server setup")
        }
    )
    .environmentObject(AppViewModel())
    .environmentObject(OnboardingWizardContext())
    .frame(width: 800, height: 600)
}
