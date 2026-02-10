import Foundation

/// Shared controller object used by onboarding step views to configure the wizard shell
/// (Next button enabled state, Next/Skip actions, etc.).
@MainActor
final class OnboardingWizardContext: ObservableObject {
  @Published var nextTitle: String = "Next"
  @Published var canGoNext: Bool = false

  @Published var showsSkip: Bool = false
  @Published var skipTitle: String = "Skip"
  @Published var canSkip: Bool = true

  private var nextAction: (() -> Void)?
  private var skipAction: (() -> Void)?

  func configureNext(title: String = "Next", enabled: Bool, action: @escaping () -> Void) {
    nextTitle = title
    canGoNext = enabled
    nextAction = action
  }

  func updateNextEnabled(_ enabled: Bool) {
    canGoNext = enabled
  }

  func configureSkip(shown: Bool, title: String = "Skip", enabled: Bool = true, action: (() -> Void)? = nil) {
    showsSkip = shown
    skipTitle = title
    canSkip = enabled
    skipAction = action
  }

  func triggerNext() {
    guard canGoNext else { return }
    nextAction?()
  }

  func triggerSkip() {
    guard showsSkip, canSkip else { return }
    skipAction?()
  }

  func resetForStep() {
    nextTitle = "Next"
    canGoNext = false
    nextAction = nil
    configureSkip(shown: false)
  }
}
