import SwiftUI
import Foundation

/// Clone and validation screen of the onboarding wizard
struct OnboardingCloneView: View {
    @EnvironmentObject var vm: AppViewModel
    let repoUrl: String
    let isNewRepo: Bool
    let onBack: () -> Void
    let onComplete: () -> Void
    
    @State private var localPath: String = LobsPaths.defaultWorkspace + "/lobs-control"
    @State private var isCloning: Bool = false
    @State private var setupSteps: [SetupStep] = []
    @State private var errorMessage: String? = nil
    @State private var showPathInput: Bool = true
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
                Text(isCloning ? "Setting Up..." : "Repository Location")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundColor(.primary)
                
                // Subtitle
                if !isCloning {
                    Text("Choose where to clone the control repository")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 480)
                }
            }
            
            if showPathInput {
                // Path input section
                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Local Path")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.secondary)
                        
                        HStack(spacing: 8) {
                            TextField("~/lobs-control", text: $localPath)
                                .textFieldStyle(.plain)
                                .font(.system(size: 14, design: .monospaced))
                                .padding(10)
                                .background(Theme.cardBg)
                                .cornerRadius(8)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(Theme.border, lineWidth: 1)
                                )
                                .disabled(isCloning)
                            
                            Button(action: choosePath) {
                                Image(systemName: "folder")
                                    .font(.system(size: 14))
                                    .foregroundColor(.primary)
                                    .frame(width: 36, height: 36)
                            }
                            .buttonStyle(.plain)
                            .background(Theme.cardBg)
                            .cornerRadius(8)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Theme.border, lineWidth: 1)
                            )
                            .disabled(isCloning)
                        }
                        
                        Text("The repository will be cloned to this location")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                    .frame(width: 500)
                }
            } else {
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
                .disabled(isCloning && !canRetry)
                
                if canRetry {
                    Button(action: startSetup) {
                        Text("Try Again")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.white)
                            .frame(width: 120)
                            .padding(.vertical, 10)
                    }
                    .buttonStyle(.plain)
                    .background(Theme.accent)
                    .cornerRadius(8)
                } else if !isCloning && !setupSteps.contains(where: { 
                    if case .completed = $0.status { return true }
                    return false
                }) {
                    Button(action: startSetup) {
                        Text("Continue")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.white)
                            .frame(width: 120)
                            .padding(.vertical, 10)
                    }
                    .buttonStyle(.plain)
                    .background(Theme.accent)
                    .cornerRadius(8)
                    .disabled(localPath.trimmingCharacters(in: .whitespaces).isEmpty)
                    .opacity(localPath.trimmingCharacters(in: .whitespaces).isEmpty ? 0.5 : 1.0)
                }
            }
            .padding(.bottom, 60)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.bg)
    }
    
    /// Open file picker to choose destination path
    private func choosePath() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.message = "Choose where to clone the repository"
        panel.prompt = "Select"

        // Start near the current target path instead of home root to avoid broad folder probing.
        let expanded = expandPath(localPath).trimmingCharacters(in: .whitespacesAndNewlines)
        let fallback = (NSHomeDirectory() as NSString).appendingPathComponent("lobs")
        let baseDir = expanded.isEmpty
            ? fallback
            : URL(fileURLWithPath: expanded).deletingLastPathComponent().path
        panel.directoryURL = URL(fileURLWithPath: baseDir)
        
        if panel.runModal() == .OK, let url = panel.url {
            localPath = url.path + "/lobs-control"
        }
    }
    
    /// Start the setup process
    private func startSetup() {
        isCloning = true
        showPathInput = false
        canRetry = false
        errorMessage = nil
        setupSteps = []
        
        Task {
            await runSetup()
        }
    }
    
    /// Run the complete setup process
    private func runSetup() async {
        let expandedPath = expandPath(localPath)
        let fileManager = FileManager.default
        
        // Check if path already exists
        if fileManager.fileExists(atPath: expandedPath) {
            await updateStep(title: "Checking existing path...", status: .inProgress)
            
            // Check if it's a git repository
            let gitDir = expandedPath + "/.git"
            if fileManager.fileExists(atPath: gitDir) {
                // Existing repo - use it
                await updateStep(
                    title: "Repository exists at \(expandedPath)",
                    status: .warning("Using existing repository")
                )
            } else {
                // Path exists but not a repo
                await finishWithError("Path already exists but is not a git repository")
                return
            }
        } else {
            // Clone the repository
            await cloneRepository(from: repoUrl, to: expandedPath)
            if errorMessage != nil { return }
        }
        
        // Validate and create structure
        await validateStructure(at: expandedPath)
        if errorMessage != nil { return }
        
        // Save configuration
        await saveConfiguration(repoPath: expandedPath, repoUrl: repoUrl)
        if errorMessage != nil { return }
        
        // Setup complete
        await MainActor.run {
            try? Task.checkCancellation()
            
            // Show completion message briefly before continuing
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                onComplete()
            }
        }
    }
    
    /// Clone the git repository
    private func cloneRepository(from url: String, to path: String) async {
        await updateStep(title: "Cloning repository...", status: .inProgress)
        
        let result = await runGitCommand(["clone", url, path])
        
        if result.success {
            await updateStep(title: "Repository cloned", status: .completed)
        } else if let error = result.error {
            await finishWithError(error.errorDescription ?? "Failed to clone repository")
        } else {
            await finishWithError("Failed to clone repository")
        }
    }
    
    /// Validate repository structure and create missing files/folders
    private func validateStructure(at path: String) async {
        await updateStep(title: "Checking structure...", status: .inProgress)
        
        let fileManager = FileManager.default
        var createdItems: [String] = []
        
        // Required directories
        let requiredDirs = [
            "state",
            "state/tasks",
            "inbox",
            "artifacts"
        ]
        
        for dir in requiredDirs {
            let fullPath = path + "/" + dir
            if !fileManager.fileExists(atPath: fullPath) {
                do {
                    try fileManager.createDirectory(atPath: fullPath, withIntermediateDirectories: true)
                    createdItems.append(dir + "/")
                } catch {
                    await finishWithError("Failed to create directory \(dir): \(error.localizedDescription)")
                    return
                }
            }
        }
        
        // Required files
        let requiredFiles: [(path: String, content: String)] = [
            ("state/projects.json", """
            {
              "schemaVersion": 1,
              "projects": []
            }
            """),
            (".gitignore", """
            .DS_Store
            *~
            .*.swp
            """)
        ]
        
        for (filePath, defaultContent) in requiredFiles {
            let fullPath = path + "/" + filePath
            if !fileManager.fileExists(atPath: fullPath) {
                do {
                    try defaultContent.write(toFile: fullPath, atomically: true, encoding: .utf8)
                    createdItems.append(filePath)
                } catch {
                    await finishWithError("Failed to create file \(filePath): \(error.localizedDescription)")
                    return
                }
            }
        }
        
        // Update step with results
        if createdItems.isEmpty {
            await updateStep(title: "Structure verified", status: .completed)
        } else {
            await updateStep(
                title: "Structure validated",
                status: .warning("Created: " + createdItems.joined(separator: ", "))
            )
        }
        
        // Commit new files if any were created
        if !createdItems.isEmpty {
            await commitInitialStructure(at: path, createdItems: createdItems)
        }
    }
    
    /// Commit the initial structure
    private func commitInitialStructure(at path: String, createdItems: [String]) async {
        await updateStep(title: "Committing initial structure...", status: .inProgress)
        
        // Add all files
        let addResult = await runGitCommand(["add", "-A"], workingDirectory: path)
        guard addResult.success else {
            await updateStep(
                title: "Created structure",
                status: .warning("Could not commit changes")
            )
            return
        }
        
        // Commit
        let message = "Initialize repository structure\n\nCreated:\n" + 
                     createdItems.map { "- \($0)" }.joined(separator: "\n")
        let commitResult = await runGitCommand(["commit", "-m", message], workingDirectory: path)
        
        guard commitResult.success else {
            await updateStep(
                title: "Created structure",
                status: .warning("Could not commit changes")
            )
            return
        }
        
        await updateStep(title: "Initial structure committed", status: .completed)
    }
    
    /// Save configuration to AppConfig
    private func saveConfiguration(repoPath: String, repoUrl: String) async {
        await updateStep(title: "Saving configuration...", status: .inProgress)
        
        let saved = await MainActor.run { () -> Bool in
            // Ensure we always create/update config (fresh installs may have nil config).
            vm.setControlRepo(path: repoPath, repoUrl: repoUrl, onboardingComplete: nil)
        }

        if !saved {
            await finishWithError("Failed to save configuration. Please check permissions for ~/.lobs/config.json and try again.")
            return
        }

        await updateStep(title: "Configuration saved", status: .completed)
    }
    
    /// Run a git command with enhanced error handling
    private func runGitCommand(_ args: [String], workingDirectory: String? = nil) async -> GitOperationResult {
        let cwd: URL
        if let workDir = workingDirectory {
            cwd = URL(fileURLWithPath: workDir)
        } else {
            cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        }
        
        // Use retry for network-sensitive operations
        if args.first == "clone" || args.first == "fetch" || args.first == "pull" {
            return await Git.runWithRetry(args, cwd: cwd, maxRetries: 3)
        } else {
            return await Git.runAsyncWithErrorHandling(args, cwd: cwd)
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
            isCloning = false
            canRetry = true
        }
    }
    
    /// Expand ~ in path to home directory
    private func expandPath(_ path: String) -> String {
        if path.hasPrefix("~") {
            return NSHomeDirectory() + path.dropFirst()
        }
        return path
    }
}

#Preview {
    OnboardingCloneView(
        repoUrl: "git@github.com:user/lobs-control.git",
        isNewRepo: false,
        onBack: {},
        onComplete: {}
    )
    .environmentObject(AppViewModel())
    .frame(width: 800, height: 600)
}
