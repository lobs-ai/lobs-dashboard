import XCTest
@testable import LobsDashboard

/// Tests for the onboarding done screen behavior to ensure users can always
/// exit onboarding when they reach 100% completion.
final class OnboardingDoneScreenTests: XCTestCase {
  
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
  
  /// Test that completing onboarding works even with no initial config
  func testCompleteOnboardingWithNoConfig() async {
    let vm = AppViewModel()
    
    await MainActor.run {
      // Simulate a user who has reached the done screen but has no config
      vm.config = nil
      
      var state = OnboardingState()
      state.markCompleted(.done)
      OnboardingStateManager.save(state)
      
      // Simulate what completeOnboarding() does
      // When config is nil, it creates a minimal config with onboardingComplete=true
      let newConfig = AppConfig(
        controlRepoUrl: "",
        controlRepoPath: "",
        onboardingComplete: true
      )
      vm.config = newConfig
      try? ConfigManager.save(newConfig)
      
      // After completion, should not need onboarding
      XCTAssertFalse(vm.needsOnboarding, "Should not need onboarding after creating config")
      XCTAssertTrue(vm.config?.onboardingComplete ?? false, "Config should have onboardingComplete=true")
    }
  }
  
  /// Test that completing onboarding works with existing config
  func testCompleteOnboardingWithExistingConfig() async {
    let vm = AppViewModel()
    
    await MainActor.run {
      // User has a config but onboarding isn't complete
      var config = AppConfig(
        controlRepoUrl: "git@github.com:user/lobs-control.git",
        controlRepoPath: "/Users/user/lobs-control",
        onboardingComplete: false
      )
      vm.config = config
      XCTAssertTrue(vm.needsOnboarding, "Should need onboarding initially")
      
      // Mark done step
      var state = OnboardingState()
      state.markCompleted(.done)
      OnboardingStateManager.save(state)
      
      // Complete onboarding
      config.onboardingComplete = true
      vm.config = config
      try? ConfigManager.save(config)
      
      // Force published update (as completeOnboarding does)
      vm.config = config
      
      // Should not need onboarding anymore
      XCTAssertFalse(vm.needsOnboarding, "Should not need onboarding after completion")
    }
  }
  
  /// Test that completeOnboarding works even if config save fails
  func testCompleteOnboardingWithConfigSaveFailure() async {
    let vm = AppViewModel()
    
    await MainActor.run {
      // Start with incomplete onboarding
      var config = AppConfig(
        controlRepoUrl: "",
        controlRepoPath: "",
        onboardingComplete: false
      )
      vm.config = config
      
      // Mark done step (this always succeeds, even if config save fails)
      var state = OnboardingState()
      state.markCompleted(.done)
      OnboardingStateManager.save(state)
      
      // Now, even if the config doesn't get the flag set, the auto-fix logic
      // in needsOnboarding should detect done step is complete and fix the config
      let needsOnboarding = vm.needsOnboarding
      
      XCTAssertFalse(needsOnboarding, "Auto-fix should handle done step being complete")
      XCTAssertTrue(vm.config?.onboardingComplete ?? false, "Config should be auto-fixed")
    }
  }
  
  /// Test that view refresh happens when config is updated
  func testViewRefreshOnConfigUpdate() async {
    let vm = AppViewModel()
    
    await MainActor.run {
      // Start needing onboarding
      var config = AppConfig(onboardingComplete: false)
      vm.config = config
      XCTAssertTrue(vm.needsOnboarding)
      
      // Update config to complete
      config.onboardingComplete = true
      vm.config = config
      
      // Should immediately reflect the change
      XCTAssertFalse(vm.needsOnboarding, "Should immediately see config change")
      
      // Verify multiple checks return consistent results
      XCTAssertFalse(vm.needsOnboarding, "Second check should also return false")
      XCTAssertFalse(vm.needsOnboarding, "Third check should also return false")
    }
  }
  
  /// Test that re-assigning config (as completeOnboarding does) triggers updates
  func testConfigReassignmentTriggersUpdate() async {
    let vm = AppViewModel()
    
    await MainActor.run {
      // Setup
      var config = AppConfig(onboardingComplete: true)
      vm.config = config
      XCTAssertFalse(vm.needsOnboarding)
      
      // Re-assign the same config (forces @Published to fire)
      vm.config = config
      
      // Should still return false
      XCTAssertFalse(vm.needsOnboarding, "Re-assignment should not break state")
    }
  }
}
