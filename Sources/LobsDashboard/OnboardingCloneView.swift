import SwiftUI
import Foundation

/// Server connection verification screen of the onboarding wizard
struct OnboardingCloneView: View {
    @EnvironmentObject var vm: AppViewModel
    let repoUrl: String  // Now contains server URL
    let isNewRepo: Bool  // Unused, kept for compatibility
    let onBack: () -> Void
    let onComplete: () -> Void
    
    @State private var isConnecting: Bool = false
    @State private var setupSteps: [SetupStep] = []
    @State private var errorMessage: String? = nil
    @State private var canRetry: Bool = false
    
    /// Represents a single step in the setup process
    struct SetupStep: Identifiable {
        let id = UUID()
        var title: String
        var status: StepStatus
        
        enum StepStatus {
            case pending
            case inProgress
            case completed
            case warning(String)
            case error(String)
            
            var icon: String {
                switch self {
                case .pending: return "circle"
                case .inProgress: return "circle.dotted"
                case .completed: return "checkmark.circle.fill"
                case .warning: return "exclamationmark.triangle.fill"
                case .error: return "xmark.circle.fill"
                }
            }
            
            var color: Color {
                switch self {
                case .pending: return .secondary.opacity(0.5)
                case .inProgress: return .blue
                case .completed: return .green
                case .warning: return .orange
                case .error: return .red
                }
            }
        }
    }
    
    var body: some View {
        VStack(spacing: 32) {
            Spacer()
            
            VStack(spacing: 12) {
                // Title
                Text(isConnecting ? "Connecting..." : "Server Connection")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundColor(.primary)
                
                // Subtitle
                if !isConnecting {
                    Text("We'll test the connection to your Lobs server")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 480)
                }
            }
            
            if !setupSteps.isEmpty {
                // Progress section
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(setupSteps) { step in
                        HStack(spacing: 12) {
                            Image(systemName: step.status.icon)
                                .font(.system(size: 14))
                                .foregroundColor(step.status.color)
                                .frame(width: 20)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text(step.title)
                                    .font(.system(size: 14))
                                    .foregroundColor(.primary)
                                
                                if case .warning(let message) = step.status {
                                    Text(message)
                                        .font(.system(size: 12))
                                        .foregroundColor(.orange)
                                } else if case .error(let message) = step.status {
                                    Text(message)
                                        .font(.system(size: 12))
                                        .foregroundColor(.red)
                                }
                            }
                            
                            Spacer()
                            
                            // Show spinner for in-progress steps
                            if case .inProgress = step.status {
                                ProgressView()
                                    .scaleEffect(0.7)
                                    .frame(width: 16, height: 16)
                            }
                        }
                    }
                }
                .frame(width: 500)
                .padding(20)
                .background(Theme.cardBg)
                .cornerRadius(12)
            }
            
            // Error message
            if let error = errorMessage {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.red)
                    Text(error)
                        .font(.system(size: 13))
                        .foregroundColor(.red)
                }
                .frame(maxWidth: 500)
            }
            
            Spacer()
            
            // Navigation buttons
            HStack(spacing: 12) {
                Button(action: onBack) {
                    Text("Back")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.primary)
                        .frame(width: 120)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.plain)
                .background(Theme.cardBg)
                .cornerRadius(8)
                .disabled(isConnecting && !canRetry)
                
                if canRetry {
                    Button(action: startConnection) {
                        Text("Try Again")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.white)
                            .frame(width: 120)
                            .padding(.vertical, 10)
                    }
                    .buttonStyle(.plain)
                    .background(Theme.accent)
                    .cornerRadius(8)
                } else if !isConnecting {
                    Button(action: startConnection) {
                        Text("Connect")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.white)
                            .frame(width: 120)
                            .padding(.vertical, 10)
                    }
                    .buttonStyle(.plain)
                    .background(Theme.accent)
                    .cornerRadius(8)
                }
            }
            .padding(.bottom, 60)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.bg)
        .onAppear {
            // Auto-start connection test
            startConnection()
        }
    }
    
    /// Start the connection test
    private func startConnection() {
        isConnecting = true
        canRetry = false
        errorMessage = nil
        setupSteps = []
        
        Task {
            await runConnectionTest()
        }
    }
    
    /// Run the connection test
    private func runConnectionTest() async {
        // Test server health endpoint
        await updateStep(title: "Connecting to server...", status: .inProgress)
        
        guard let url = URL(string: repoUrl)?.appendingPathComponent("/api/health") else {
            await finishWithError("Invalid server URL")
            return
        }
        
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                await finishWithError("Invalid response from server")
                return
            }
            
            if httpResponse.statusCode == 200 {
                await updateStep(title: "Server is reachable", status: .completed)
                
                // Parse health response
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let status = json["status"] as? String {
                    await updateStep(title: "Health check: \(status)", status: .completed)
                } else {
                    await updateStep(title: "Health check passed", status: .completed)
                }
                
                // Save configuration
                await saveConfiguration()
            } else {
                await finishWithError("Server returned status \(httpResponse.statusCode)")
            }
        } catch {
            await finishWithError("Connection failed: \(error.localizedDescription)")
        }
    }
    
    /// Save server URL to configuration
    private func saveConfiguration() async {
        await updateStep(title: "Saving configuration...", status: .inProgress)
        
        let saved = await MainActor.run { () -> Bool in
            guard var config = vm.config else {
                // Create new config
                let newConfig = AppConfig(
                    onboardingComplete: false,
                    serverURL: repoUrl
                )
                vm.config = newConfig
                do {
                    try ConfigManager.save(newConfig)
                    return true
                } catch {
                    return false
                }
            }
            
            // Update existing config
            config.serverURL = repoUrl
            vm.config = config
            do {
                try ConfigManager.save(config)
                return true
            } catch {
                return false
            }
        }
        
        if !saved {
            await finishWithError("Failed to save configuration")
            return
        }
        
        await updateStep(title: "Configuration saved", status: .completed)
        
        // Complete setup
        await MainActor.run {
            try? Task.checkCancellation()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                onComplete()
            }
        }
    }
    
    /// Update or add a setup step
    private func updateStep(title: String, status: SetupStep.StepStatus) async {
        await MainActor.run {
            if let index = setupSteps.firstIndex(where: { $0.title == title }) {
                setupSteps[index].status = status
            } else {
                setupSteps.append(SetupStep(title: title, status: status))
            }
        }
    }
    
    /// Finish with an error
    private func finishWithError(_ message: String) async {
        await MainActor.run {
            errorMessage = message
            isConnecting = false
            canRetry = true
        }
    }
}

// // #Preview {
// OnboardingCloneView(
// repoUrl: "http://localhost:8000",
// isNewRepo: false,
// onBack: {},
// onComplete: {}
// )
// .environmentObject(AppViewModel())
// .frame(width: 800, height: 600)
// }
