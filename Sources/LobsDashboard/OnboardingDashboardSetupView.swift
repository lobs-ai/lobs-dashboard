import SwiftUI

/// Dashboard setup screen - checks minimal prerequisites for the dashboard app itself
struct OnboardingDashboardSetupView: View {
  @EnvironmentObject private var wizard: OnboardingWizardContext

  let onComplete: () -> Void

  var body: some View {
    VStack(spacing: 28) {
      Spacer()

      VStack(spacing: 10) {
        Image(systemName: "checkmark.circle.fill")
          .font(.system(size: 40))
          .foregroundColor(.green)
        Text("Dashboard Ready")
          .font(.system(size: 28, weight: .semibold))
        Text("The dashboard is now ready to connect to your lobs-server.")
          .font(.system(size: 14))
          .foregroundColor(.secondary)
          .multilineTextAlignment(.center)
          .frame(maxWidth: 560)
      }

      VStack(alignment: .leading, spacing: 16) {
        HStack(spacing: 8) {
          Image(systemName: "info.circle")
            .foregroundColor(.secondary)
            .font(.system(size: 13))
          Text("The dashboard is a pure REST API client. All it needs is the URL of your lobs-server.")
            .font(.system(size: 13))
            .foregroundColor(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        
        HStack(spacing: 8) {
          Image(systemName: "server.rack")
            .foregroundColor(.secondary)
            .font(.system(size: 13))
          Text("Server setup instructions are optional. You can configure your server URL in the next step.")
            .font(.system(size: 13))
            .foregroundColor(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
      .frame(width: 600)
      .padding(20)
      .background(Theme.cardBg)
      .cornerRadius(12)
      .overlay(
        RoundedRectangle(cornerRadius: 12).stroke(Theme.border, lineWidth: 1)
      )

      Spacer()
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Theme.bg)
    .onAppear {
      wizard.configureNext(title: "Next", enabled: true) {
        onComplete()
      }
      wizard.configureSkip(shown: false)
    }
  }
}

// // #Preview {
// OnboardingDashboardSetupView(onComplete: {})
// .environmentObject(OnboardingWizardContext())
// .frame(width: 900, height: 650)
// }
