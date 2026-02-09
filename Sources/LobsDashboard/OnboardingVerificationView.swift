import SwiftUI
import AppKit

/// Server connection verification screen of the onboarding wizard
struct OnboardingVerificationView: View {
    @EnvironmentObject var vm: AppViewModel
    let repoUrl: String
    let onBack: () -> Void
    let onComplete: () -> Void
    
    @State private var verificationState: VerificationState = .checking
    @State private var gitPullStatus: CheckStatus = .pending
    @State private var workerStatusCheckStatus: CheckStatus = .pending
    @State private var lastHeartbeat: Date?
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
                    status: gitPullStatus,
                    text: "Pulling latest changes..."
                )
                
                StatusCheckRow(
                    status: workerStatusCheckStatus,
                    text: "Checking worker status..."
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
            Text("Connected! Your AI assistant is running.")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.primary)
            
            // Last heartbeat info
            if let heartbeat = lastHeartbeat {
                VStack(spacing: 4) {
                    Text("Last heartbeat:")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                    
                    Text(formatHeartbeatTime(heartbeat))
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
                    text: "Make sure the orchestrator is running on your server"
                )
                
                TroubleshootingTip(
                    icon: "2.circle.fill",
                    text: "Check that your server can push to the control repo"
                )
                
                TroubleshootingTip(
                    icon: "3.circle.fill",
                    text: "Verify that the worker has sent at least one heartbeat"
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
                gitPullStatus = .pending
                workerStatusCheckStatus = .pending
                errorMessage = nil
            }
            
            // Check 1: Git pull
            await MainActor.run {
                gitPullStatus = .running
            }
            
            let gitPullSuccess = await performGitPull()
            
            await MainActor.run {
                gitPullStatus = gitPullSuccess ? .success : .failure
            }
            
            if !gitPullSuccess {
                await MainActor.run {
                    verificationState = .failure
                    errorMessage = "Failed to pull latest changes from the control repository."
                }
                return
            }
            
            // Check 2: Worker status
            await MainActor.run {
                workerStatusCheckStatus = .running
            }
            
            let workerStatusResult = await checkWorkerStatus()
            
            await MainActor.run {
                workerStatusCheckStatus = workerStatusResult.success ? .success : .failure
            }
            
            if !workerStatusResult.success {
                await MainActor.run {
                    verificationState = .failure
                    errorMessage = workerStatusResult.error ?? "Worker status check failed."
                }
                return
            }
            
            // All checks passed
            await MainActor.run {
                lastHeartbeat = workerStatusResult.heartbeat
                verificationState = .success
            }
        }
    }
    
    /// Perform git pull in the control repo
    private func performGitPull() async -> Bool {
        guard let config = vm.config else { return false }
        let repoPath = URL(fileURLWithPath: config.controlRepoPath)
        
        do {
            let result = try await Git.runAsync(["pull"], cwd: repoPath)
            return result.ok
        } catch {
            print("Git pull error: \(error)")
            return false
        }
    }
    
    /// Check worker status from state/worker-status.json
    private func checkWorkerStatus() async -> (success: Bool, error: String?, heartbeat: Date?) {
        guard let config = vm.config else {
            return (false, "No configuration found.", nil)
        }
        
        let statusPath = (config.controlRepoPath as NSString)
            .appendingPathComponent("state/worker-status.json")
        
        // Check if file exists
        guard FileManager.default.fileExists(atPath: statusPath) else {
            return (false, "Worker status file not found. Make sure the orchestrator has run at least once.", nil)
        }
        
        // Read and parse JSON
        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: statusPath))
            let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any]
            
            guard let json = json else {
                return (false, "Invalid worker status file format.", nil)
            }
            
            // Check for lastHeartbeat
            guard let heartbeatString = json["lastHeartbeat"] as? String else {
                return (false, "No heartbeat found. The worker hasn't sent any status updates yet.", nil)
            }
            
            // Parse ISO8601 date
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            
            guard let heartbeatDate = formatter.date(from: heartbeatString) else {
                return (false, "Invalid heartbeat timestamp format.", nil)
            }
            
            // Check if heartbeat is within last 5 minutes
            let fiveMinutesAgo = Date().addingTimeInterval(-5 * 60)
            
            if heartbeatDate < fiveMinutesAgo {
                let minutesAgo = Int(-heartbeatDate.timeIntervalSinceNow / 60)
                return (false, "Last heartbeat was \(minutesAgo) minutes ago. The worker may not be running.", heartbeatDate)
            }
            
            return (true, nil, heartbeatDate)
            
        } catch {
            return (false, "Failed to read worker status: \(error.localizedDescription)", nil)
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
    
    /// Format heartbeat time for display
    private func formatHeartbeatTime(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: Date())
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

#Preview {
    OnboardingVerificationView(
        repoUrl: "git@github.com:user/lobs-control.git",
        onBack: {},
        onComplete: {}
    )
    .environmentObject(AppViewModel())
    .frame(width: 800, height: 600)
}
