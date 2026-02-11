import XCTest
@testable import LobsDashboard

/// Tests for onboarding completion logic to ensure the condition works correctly
/// when all steps are complete but the config flag isn't set.
final class OnboardingCompletionTests: XCTestCase {
  
  override func setUp() {
    super.setUp()
    // Clean up any existing test state
    cleanupTestState()
  }
  
  override func tearDown() {
    cleanupTestState()
    super.tearDown()
  }
  
  private func cleanupTestState() {
    // Reset onboarding state
    OnboardingStateManager.reset()
    
    // Clean up test config if it exists
    let testConfigPath = LobsPaths.appSupport.appendingPathComponent("test-config.json")
    try? FileManager.default.removeItem(at: testConfigPath)
  }
  
  /// Test that onboarding is needed when no config exists
  func testNeedsOnboardingWhenNoConfig() async {
    let vm = AppViewModel()
    await MainActor.run {
      vm.config = nil
      XCTAssertTrue(vm.needsOnboarding, "Should need onboarding when config is nil")
    }
  }
  
  /// Test that onboarding is not needed when config says it's complete
  func testDoesNotNeedOnboardingWhenConfigComplete() async {
    let vm = AppViewModel()
    await MainActor.run {
      var config = AppConfig(
        controlRepoUrl: "git@github.com:test/test.git",
        controlRepoPath: "/tmp/test",
        onboardingComplete: true
      )
      vm.config = config
      XCTAssertFalse(vm.needsOnboarding, "Should not need onboarding when config.onboardingComplete is true")
    }
  }
  
  /// Test that onboarding is needed when config exists but onboardingComplete is false
  func testNeedsOnboardingWhenConfigIncomplete() async {
    let vm = AppViewModel()
    await MainActor.run {
      var config = AppConfig(
        controlRepoUrl: "git@github.com:test/test.git",
        controlRepoPath: "/tmp/test",
        onboardingComplete: false
      )
      vm.config = config
      XCTAssertTrue(vm.needsOnboarding, "Should need onboarding when config.onboardingComplete is false")
    }
  }
  
  /// Test the bug fix: when all steps (including "done") are complete in OnboardingState
  /// but config.onboardingComplete is false, we should NOT show onboarding.
  func testAutoFixWhenDoneStepCompleteButConfigNotSet() async {
    // Setup: Mark the "done" step as complete in onboarding state
    var state = OnboardingState()
    state.markCompleted(.welcome)
    state.markCompleted(.workspace)
    state.markCompleted(.cloneCoreRepos)
    state.markCompleted(.serverGuide)
    state.markCompleted(.done)
    state.workspace = "/tmp/test"
    OnboardingStateManager.save(state)
    
    let vm = AppViewModel()
    await MainActor.run {
      // But config says onboarding is NOT complete
      var config = AppConfig(
        controlRepoUrl: "git@github.com:test/test.git",
        controlRepoPath: "/tmp/test",
        onboardingComplete: false
      )
      vm.config = config
      
      // The fix: needsOnboarding should return false and auto-fix the config
      XCTAssertFalse(vm.needsOnboarding, "Should not need onboarding when 'done' step is complete")
      
      // Verify the config was auto-fixed
      XCTAssertTrue(vm.config?.onboardingComplete ?? false, "Config should be auto-fixed to onboardingComplete=true")
    }
  }
  
  /// Test that onboarding is still needed when only some steps are complete
  func testNeedsOnboardingWhenOnlySomeStepsComplete() async {
    // Setup: Mark some steps as complete but not "done"
    var state = OnboardingState()
    state.markCompleted(.welcome)
    state.markCompleted(.workspace)
    state.workspace = "/tmp/test"
    OnboardingStateManager.save(state)
    
    let vm = AppViewModel()
    await MainActor.run {
      var config = AppConfig(
        controlRepoUrl: "git@github.com:test/test.git",
        controlRepoPath: "/tmp/test",
        onboardingComplete: false
      )
      vm.config = config
      
      // Should still need onboarding since "done" step is not complete
      XCTAssertTrue(vm.needsOnboarding, "Should need onboarding when 'done' step is not complete")
    }
  }
  
  /// Test that the fix works with empty workspace path
  func testAutoFixWithEmptyWorkspacePath() async {
    // Setup: Mark done step as complete
    var state = OnboardingState()
    state.markCompleted(.done)
    state.workspace = ""
    OnboardingStateManager.save(state)
    
    let vm = AppViewModel()
    await MainActor.run {
      var config = AppConfig(
        controlRepoUrl: "git@github.com:test/test.git",
        controlRepoPath: "",
        onboardingComplete: false
      )
      vm.config = config
      
      // Should still auto-fix even with empty workspace
      XCTAssertFalse(vm.needsOnboarding, "Should not need onboarding when 'done' step is complete, even with empty workspace")
      XCTAssertTrue(vm.config?.onboardingComplete ?? false, "Config should be auto-fixed")
    }
  }
}
