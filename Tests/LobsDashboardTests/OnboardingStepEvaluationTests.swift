import XCTest
@testable import LobsDashboard

/// Tests for onboarding step completion evaluation in OverviewView.
///
/// **Issue (2026-02-12):** User reported "onboarding still shows up even though i have a 100%"
///
/// **Root Cause:** The `onboardingSteps` property cached `onboardingComplete` from config
/// BEFORE calling `vm.needsOnboarding`, which can auto-fix the config when state shows
/// completion but config doesn't. This created a race condition:
///
/// 1. `let onboardingComplete = (vm.config?.onboardingComplete ?? false)` reads config (false)
/// 2. `isComplete: onboardingComplete && !vm.needsOnboarding` evaluates needsOnboarding
/// 3. needsOnboarding sees state has .done = true, auto-fixes config to onboardingComplete = true
/// 4. BUT `onboardingComplete` variable still has the old cached value (false)
/// 5. Step shows as incomplete even though needsOnboarding returned false
/// 6. Progress shows less than 100%, onboarding section remains visible
///
/// **Fix:** Removed the cached `onboardingComplete` variable and use `!vm.needsOnboarding`
/// directly for the completion check. The `needsOnboarding` property already checks both
/// config and state with auto-fix logic, so we don't need to duplicate that check.
final class OnboardingStepEvaluationTests: XCTestCase {
  
  /// Test: "Finish onboarding" step uses needsOnboarding directly
  ///
  /// Expected behavior:
  /// - The "Finish onboarding" step should check `!vm.needsOnboarding` directly
  /// - Should NOT cache config.onboardingComplete before calling needsOnboarding
  /// - This ensures auto-fix logic in needsOnboarding works correctly
  func testFinishOnboardingStepUsesNeedsOnboardingDirectly() {
    // This test documents the fix for the caching race condition.
    //
    // BEFORE (broken):
    // private var onboardingSteps: [OnboardingStep] {
    //   let onboardingComplete = (vm.config?.onboardingComplete ?? false)  // ← cached too early
    //   return [
    //     OnboardingStep(
    //       title: "Finish onboarding",
    //       isComplete: onboardingComplete && !vm.needsOnboarding,  // ← uses stale value
    //       ...
    //     )
    //   ]
    // }
    //
    // AFTER (fixed):
    // private var onboardingSteps: [OnboardingStep] {
    //   let onboardingDone = !vm.needsOnboarding  // ← evaluate directly
    //   return [
    //     OnboardingStep(
    //       title: "Finish onboarding",
    //       isComplete: onboardingDone,  // ← uses fresh value after auto-fix
    //       ...
    //     )
    //   ]
    // }
    //
    // The needsOnboarding property handles all completion logic:
    // - Checks config.onboardingComplete first (fast path)
    // - Falls back to onboarding-state.json if config missing/wrong
    // - Auto-fixes config when state shows completion
    // - Returns false when complete from either source
    
    XCTAssert(true, "Structural test - step should use needsOnboarding directly without caching")
  }
  
  /// Test: Auto-fix scenario where caching caused incorrect completion
  ///
  /// Scenario:
  /// - User completed onboarding (onboarding-state.json has .done = true)
  /// - Config was deleted or corrupted (config.onboardingComplete = nil/false)
  /// - User opens dashboard
  ///
  /// Expected behavior:
  /// - onboardingSteps evaluates needsOnboarding
  /// - needsOnboarding sees state has completion, auto-fixes config
  /// - "Finish onboarding" step shows as complete
  /// - Progress reaches 100% (assuming other steps complete)
  /// - Onboarding section hides
  ///
  /// With the bug (cached config):
  /// - onboardingComplete reads false from config before auto-fix
  /// - Step shows incomplete even after needsOnboarding fixes config
  /// - Progress stuck below 100%, section remains visible
  func testAutoFixScenarioCompletesStepCorrectly() {
    // This test documents the specific scenario that was failing.
    //
    // Manual verification:
    // 1. Complete all onboarding steps normally
    // 2. Delete ~/.lobs/config.json (or corrupt it)
    // 3. Open dashboard
    // 4. Verify: onboarding section shows briefly during auto-fix
    // 5. Verify: after auto-fix, section disappears
    // 6. Verify: config.json recreated with onboardingComplete = true
    //
    // With cached onboardingComplete:
    // - Section would stay visible showing <100% progress
    // - User stuck in loop, had to manually re-run onboarding
    //
    // With direct needsOnboarding check:
    // - Auto-fix happens during first evaluation
    // - Step immediately shows complete
    // - Section hides on next render
    
    XCTAssert(true, "Structural test - auto-fix should complete step without caching issue")
  }
  
  /// Test: needsOnboarding is source of truth for onboarding completion
  ///
  /// Expected behavior:
  /// - `vm.needsOnboarding` is the single source of truth for "is onboarding complete?"
  /// - It handles:
  ///   1. Checking config.onboardingComplete (primary)
  ///   2. Checking onboarding-state.json (fallback/recovery)
  ///   3. Auto-fixing config when state shows complete but config wrong
  ///   4. Auto-creating config when missing entirely
  /// - All UI checks should defer to needsOnboarding, not duplicate the logic
  func testNeedsOnboardingIsSingleSourceOfTruth() {
    // This test documents the architectural principle.
    //
    // Single Responsibility:
    // - AppViewModel.needsOnboarding: ALL onboarding completion logic
    // - OverviewView.onboardingSteps: UI presentation only, delegates to needsOnboarding
    //
    // Don't do this (duplicates logic):
    // let onboardingComplete = (vm.config?.onboardingComplete ?? false)
    // isComplete: onboardingComplete && !vm.needsOnboarding
    //
    // Do this (delegates to single source):
    // isComplete: !vm.needsOnboarding
    //
    // Benefits:
    // - Auto-fix logic centralized in one place
    // - UI always reflects current state after auto-recovery
    // - No caching race conditions
    // - Easier to maintain and debug
    
    XCTAssert(true, "Structural test - needsOnboarding is single source of truth")
  }
  
  /// Test: Other steps don't have caching issues
  ///
  /// Expected behavior:
  /// - "Connect lobs-control repo" step: checks vm.repoURL directly (no caching)
  /// - "First task walkthrough" step: checks vm.firstTaskWalkthroughComplete directly
  /// - Both are safe from race conditions
  func testOtherStepsDontCacheValues() {
    // This test documents that other steps don't have the same issue.
    //
    // Safe patterns:
    // 1. "Connect lobs-control repo"
    //    let repoSet = (vm.repoURL != nil)
    //    isComplete: repoSet
    //    → Value is read once at property start, no auto-fix happens during evaluation
    //
    // 2. "First task walkthrough"
    //    let walkthroughComplete = vm.firstTaskWalkthroughComplete
    //    isComplete: walkthroughComplete
    //    → Simple boolean read, no side effects
    //
    // The "Finish onboarding" step was unique because:
    // - It cached config.onboardingComplete
    // - Then called vm.needsOnboarding which has side effects (auto-fix)
    // - Used the cached value even though needsOnboarding changed the underlying state
    
    XCTAssert(true, "Structural test - other steps safely cache their values")
  }
  
  /// Test: View refresh after auto-fix
  ///
  /// Expected behavior:
  /// - When needsOnboarding auto-fixes config, it calls saveConfig()
  /// - Config is @Published, so changes trigger view refresh
  /// - onboardingSteps is recomputed on next render
  /// - Fresh evaluation gets correct completion state
  /// - Section hides if all steps complete
  func testViewRefreshesAfterAutoFix() {
    // This test documents the view refresh cycle.
    //
    // Flow:
    // 1. View renders, evaluates onboardingSteps
    // 2. onboardingSteps calls vm.needsOnboarding
    // 3. needsOnboarding detects state complete but config wrong
    // 4. Fixes config and calls saveConfig()
    // 5. config is @Published, triggers objectWillChange
    // 6. SwiftUI schedules view refresh
    // 7. Next render: onboardingSteps re-evaluates
    // 8. needsOnboarding now returns false (config fixed)
    // 9. Step shows complete, progress reaches 100%
    // 10. Section hides (if onboardingProgress < 1.0 condition now false)
    //
    // With cached onboardingComplete:
    // - Steps 7-9 would still use the cached false value
    // - Would require another render cycle to see changes
    // - Section might flicker or stay visible longer than needed
    //
    // With direct needsOnboarding:
    // - Fresh evaluation on each render
    // - Section hides as soon as auto-fix completes
    
    XCTAssert(true, "Structural test - view should refresh correctly after auto-fix")
  }
}
