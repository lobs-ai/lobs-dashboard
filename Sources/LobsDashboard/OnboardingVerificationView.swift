import SwiftUI
import AppKit

/// API connection verification screen of the onboarding wizard
struct OnboardingVerificationView: View {
    @EnvironmentObject var vm: AppViewModel
    let repoUrl: String  // Now server URL
    let onBack: () -> Void
    let onComplete: () -> Void
    
    @State private var verificationState: VerificationState = .checking
    @State private var apiHealthStatus: CheckStatus = .pending
    @State private var orchestratorStatus: CheckStatus = .pending
    @State private var orchestratorInfo: String?
    @State private var errorMessage: String?
    
    enum VerificationState {
        case checking
        case success
        case failure
    }
    
    enum CheckStatus {
        case pending
        case running
        case success
        case failure
        
        var icon: String {
            switch self {
            case .pending: return "square"
            case .running: return "square"
            case .success: return "checkmark.square.fill"
            case .failure: return "xmark.square.fill"
            }
        }
        
        var color: Color {
            switch self {
            case .pending: return .secondary
            case .running: return Theme.accent
            case .success: return .green
            case .failure: return .red
            }
        }
    }
    
    var body: some View {
        VStack(spacing: 32) {
            Spacer()
            
            VStack(spacing: 12) {
                // Title
                Text(verificationState == .checking ? "Verifying Connection..." : 
                     verificationState == .success ? "Connection Verified!" : 
                     "Connection Failed")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundColor(.primary)
                
                // Subtitle
                if verificationState == .checking {
                    HStack(spacing: 8) {
                        ProgressView()
                            .scaleEffect(0.7)
                            .frame(width: 16, height: 16)
                        Text("Checking your server connection...")
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            // Status checks
            VStack(alignment: .leading, spacing: 16) {
                StatusCheckRow(
                    status: apiHealthStatus,
                    text: "Checking API health..."
                )
                
                StatusCheckRow(
                    status: orchestratorStatus,
                    text: "Checking orchestrator status..."
                )
            }
            .frame(width: 420)
            .padding(.vertical, 24)
            
            // Result content
            VStack(spacing: 20) {
                if verificationState == .success {
                    successContent
                } else if verificationState == .failure {
                    failureContent
                }
            }
            .frame(width: 520)
            
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
                .disabled(verificationState == .checking)
                .opacity(verificationState == .checking ? 0.5 : 1.0)
                
                if verificationState == .success {
                    Button(action: handleComplete) {
                        Text("Complete Setup")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.white)
                            .frame(width: 140)
                            .padding(.vertical, 10)
                    }
                    .buttonStyle(.plain)
                    .background(Theme.accent)
                    .cornerRadius(8)
                } else if verificationState == .failure {
                    HStack(spacing: 12) {
                        Button(action: retryVerification) {
                            Text("Retry")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.white)
                                .frame(width: 100)
                                .padding(.vertical, 10)
                        }
                        .buttonStyle(.plain)
                        .background(Theme.accent)
                        .cornerRadius(8)
                        
                        Button(action: handleComplete) {
                            Text("Skip for Now")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.primary)
                                .frame(width: 120)
                                .padding(.vertical, 10)
                        }
                        .buttonStyle(.plain)
                        .background(Theme.cardBg)
                        .cornerRadius(8)
                    }
                }
            }
            .padding(.bottom, 60)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.bg)
        .onAppear {
            runVerification()
        }
    }
    
    /// Success state content
    private var successContent: some View {
        VStack(spacing: 16) {
            // Success icon
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundColor(.green)
            
            // Success message
            Text("Connected! Your AI assistant is ready.")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.primary)
            
            // Orchestrator info
            if let info = orchestratorInfo {
                VStack(spacing: 4) {
                    Text("Orchestrator status:")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                    
                    Text(info)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.primary)
                }
                .padding(.top, 8)
            }
        }
    }
    
    /// Failure state content
    private var failureContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Error icon
            HStack {
                Spacer()
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 48))
                    .foregroundColor(.orange)
                Spacer()
            }
            
            // Error message
            if let error = errorMessage {
                Text(error)
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, 8)
            }
            
            // Troubleshooting tips
            VStack(alignment: .leading, spacing: 12) {
                Text("Troubleshooting Tips:")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.primary)
                
                TroubleshootingTip(
                    icon: "1.circle.fill",
                    text: "Make sure the Lobs server is running"
                )
                
                TroubleshootingTip(
                    icon: "2.circle.fill",
                    text: "Check that the server URL is correct"
                )
                
                TroubleshootingTip(
                    icon: "3.circle.fill",
                    text: "Verify that the orchestrator service is enabled"
                )
            }
            .padding(16)
            .background(Theme.cardBg)
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Theme.border, lineWidth: 1)
            )
        }
    }
    
    /// Run the verification checks
    private func runVerification() {
        Task {
            // Reset state
            await MainActor.run {
                verificationState = .checking
                apiHealthStatus = .pending
                orchestratorStatus = .pending
                errorMessage = nil
            }
            
            // Check 1: API health
            await MainActor.run {
                apiHealthStatus = .running
            }
            
            let healthSuccess = await checkAPIHealth()
            
            await MainActor.run {
                apiHealthStatus = healthSuccess ? .success : .failure
            }
            
            if !healthSuccess {
                await MainActor.run {
                    verificationState = .failure
                    errorMessage = "Failed to connect to the API server. Make sure it's running."
                }
                return
            }
            
            // Check 2: Orchestrator status
            await MainActor.run {
                orchestratorStatus = .running
            }
            
            let orchestratorResult = await checkOrchestratorStatus()
            
            await MainActor.run {
                orchestratorStatus = orchestratorResult.success ? .success : .failure
            }
            
            if !orchestratorResult.success {
                await MainActor.run {
                    verificationState = .failure
                    errorMessage = orchestratorResult.error ?? "Orchestrator is not running."
                }
                return
            }
            
            // All checks passed
            await MainActor.run {
                orchestratorInfo = orchestratorResult.info
                verificationState = .success
            }
        }
    }
    
    /// Check API health endpoint
    private func checkAPIHealth() async -> Bool {
        guard let url = URL(string: repoUrl)?.appendingPathComponent("/api/health") else {
            return false
        }
        
        do {
            let (_, response) = try await URLSession.shared.data(from: url)
            guard let httpResponse = response as? HTTPURLResponse else {
                return false
            }
            return httpResponse.statusCode == 200
        } catch {
            return false
        }
    }
    
    /// Check orchestrator status from API
    private func checkOrchestratorStatus() async -> (success: Bool, error: String?, info: String?) {
        guard let url = URL(string: repoUrl)?.appendingPathComponent("/api/orchestrator/status") else {
            return (false, "Invalid server URL", nil)
        }
        
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                return (false, "Invalid response from server", nil)
            }
            
            if httpResponse.statusCode == 200 {
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    let running = json["running"] as? Bool ?? false
                    let paused = json["paused"] as? Bool ?? false
                    
                    if running && !paused {
                        return (true, nil, "Running")
                    } else if paused {
                        return (true, nil, "Paused (click resume to start)")
                    } else {
                        return (false, "Orchestrator is not running", nil)
                    }
                } else {
                    return (false, "Invalid response format", nil)
                }
            } else {
                return (false, "Server returned status \(httpResponse.statusCode)", nil)
            }
        } catch {
            return (false, "Connection failed: \(error.localizedDescription)", nil)
        }
    }
    
    /// Retry verification
    private func retryVerification() {
        runVerification()
    }
    
    /// Handle completion - set onboardingComplete and save config
    private func handleComplete() {
        onComplete()
    }
}

/// Status check row with icon and text
struct StatusCheckRow: View {
    let status: OnboardingVerificationView.CheckStatus
    let text: String
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: status.icon)
                .font(.system(size: 18))
                .foregroundColor(status.color)
                .frame(width: 24)
            
            Text(text)
                .font(.system(size: 14))
                .foregroundColor(.primary)
            
            Spacer()
            
            if status == .running {
                ProgressView()
                    .scaleEffect(0.6)
                    .frame(width: 16, height: 16)
            }
        }
    }
}

/// Troubleshooting tip row
struct TroubleshootingTip: View {
    let icon: String
    let text: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundColor(Theme.accent)
                .frame(width: 20)
            
            Text(text)
                .font(.system(size: 13))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// // #Preview {
// OnboardingVerificationView(
// repoUrl: "http://localhost:8000",
// onBack: {},
// onComplete: {}
// )
// .environmentObject(AppViewModel())
// .frame(width: 800, height: 600)
// }
