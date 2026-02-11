import SwiftUI

struct OnboardingDoneView: View {
  @EnvironmentObject private var wizard: OnboardingWizardContext
  
  let onFinish: () -> Void

  var body: some View {
    VStack(spacing: 28) {
      Spacer()

      VStack(spacing: 12) {
        Image(systemName: "checkmark.seal.fill")
          .font(.system(size: 44))
          .foregroundColor(.green)
        Text("You're All Set!")
          .font(.system(size: 28, weight: .semibold))
        Text("Your assistant is ready. Create your first task to get started.")
          .font(.system(size: 14))
          .foregroundColor(.secondary)
          .multilineTextAlignment(.center)
          .frame(maxWidth: 560)
      }

      VStack(alignment: .leading, spacing: 10) {
        Text("Quick tips")
          .font(.system(size: 13, weight: .semibold))
        Text("• Use ⌘N for a new task\n• Add projects from the sidebar (+)\n• Settings: ⌘,\n• If sync looks stale, click Push Now")
          .font(.system(size: 12))
          .foregroundColor(.secondary)
      }
      .frame(width: 560, alignment: .leading)
      .padding(16)
      .background(Theme.cardBg)
      .cornerRadius(12)
      .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.border, lineWidth: 1))

      Spacer()

      Text("Click Next to go to the dashboard")
        .font(.system(size: 13))
        .foregroundColor(.secondary)
        .padding(.bottom, 20)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Theme.bg)
    .task {
      wizard.configureNext(title: "Go to dashboard", enabled: true) {
        onFinish()
      }
    }
  }
}

#Preview {
  OnboardingDoneView(onFinish: {})
    .frame(width: 800, height: 600)
}
