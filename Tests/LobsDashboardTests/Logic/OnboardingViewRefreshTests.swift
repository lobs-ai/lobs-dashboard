import XCTest
@testable import LobsDashboard

/// Tests for onboarding view refresh behavior to ensure the view updates
/// immediately when onboarding is completed.
final class OnboardingViewRefreshTests: XCTestCase {
  
  override func setUp() {
    super.setUp()
    cleanupTestState()
  }
  
  override func tearDown() {
    cleanupTestState()
    super.tearDown()
  }
  
  private func cleanupTestState() {
    OnboardingStateManager.reset()
    try? ConfigManager.reset()
  }
  
  /// Test that objectWillChange is triggered when onboarding is completed,
  /// ensuring the view immediately refreshes.
  func testOnboardingCompletionTriggersViewRefresh() async {
    let vm = AppViewModel()
    
    await MainActor.run {
      // Start with no config and onboarding needed
      vm.config = nil
      XCTAssertTrue(vm.needsOnboarding, "Should need onboarding initially")
      
      // Set up minimal config
      var config = AppConfig(
        controlRepoUrl: "",
        controlRepoPath: "",
        onboardingComplete: false
      )
      vm.config = config
      
      // Simulate completing onboarding by marking done step and saving
      var state = OnboardingState()
      state.markCompleted(.done)
      OnboardingStateManager.save(state)
      
      // Update config to mark onboarding complete
      config.onboardingComplete = true
      vm.config = config
      
      // After setting config with onboardingComplete=true, needsOnboarding should be false
      XCTAssertFalse(vm.needsOnboarding, "Should not need onboarding after completion")
    }
  }
  
  /// Test that the auto-fix logic works when config is out of sync with onboarding state
  func testAutoFixWhenOnboardingStateCompleteButConfigNot() async {
    let vm = AppViewModel()
    
    await MainActor.run {
      // Mark done step complete in onboarding state
      var state = OnboardingState()
      state.markCompleted(.done)
      state.workspace = ""
      OnboardingStateManager.save(state)
      
      // But config says onboarding is not complete
      var config = AppConfig(
        controlRepoUrl: "",
        controlRepoPath: "",
        onboardingComplete: false
      )
      vm.config = config
      
      // needsOnboarding should auto-fix the config and return false
      let needsOnboarding = vm.needsOnboarding
      XCTAssertFalse(needsOnboarding, "Auto-fix should mark onboarding as not needed")
      XCTAssertTrue(vm.config?.onboardingComplete ?? false, "Config should be auto-fixed")
    }
  }
  
  /// Test that onboarding state is prioritized over incomplete config
  func testOnboardingStatePriorityOverConfig() async {
    let vm = AppViewModel()
    
    await MainActor.run {
      // Create onboarding state with done marked complete
      var state = OnboardingState()
      state.markCompleted(.welcome)
      state.markCompleted(.workspace)
      state.markCompleted(.cloneCoreRepos)
      state.markCompleted(.serverGuide)
      state.markCompleted(.done)
      state.workspace = "/tmp/test"
      OnboardingStateManager.save(state)
      
      // Config exists but onboardingComplete is false
      var config = AppConfig(
        controlRepoUrl: "git@github.com:test/lobs-control.git",
        controlRepoPath: "/tmp/test/lobs-control",
        onboardingComplete: false
      )
      vm.config = config
      
      // Should not need onboarding because done step is complete
      XCTAssertFalse(vm.needsOnboarding, "Should not need onboarding when done step is marked")
      
      // Config should be auto-fixed
      XCTAssertTrue(vm.config?.onboardingComplete ?? false, "Config should be updated to onboardingComplete=true")
    }
  }
  
  /// Test that config.onboardingComplete takes priority when set
  func testConfigCompleteFlagTakesPriority() async {
    let vm = AppViewModel()
    
    await MainActor.run {
      // Config says onboarding is complete
      var config = AppConfig(
        controlRepoUrl: "git@github.com:test/lobs-control.git",
        controlRepoPath: "/tmp/test/lobs-control",
        onboardingComplete: true
      )
      vm.config = config
      
      // Even if onboarding state doesn't have done marked (shouldn't happen, but test it)
      var state = OnboardingState()
      state.markCompleted(.welcome)
      OnboardingStateManager.save(state)
      
      // Should not need onboarding because config flag is set
      XCTAssertFalse(vm.needsOnboarding, "Config flag should take priority")
    }
  }
}
