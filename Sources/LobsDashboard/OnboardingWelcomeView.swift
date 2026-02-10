import SwiftUI

/// First screen of the onboarding wizard - displays welcome message and app introduction.
///
/// Navigation buttons are provided by the wizard shell.
struct OnboardingWelcomeView: View {
  var body: some View {
    VStack(spacing: 32) {
      Spacer()

      if let iconUrl = Bundle.module.url(forResource: "AppIconRounded", withExtension: "png"),
         let nsImage = NSImage(contentsOf: iconUrl) {
        Image(nsImage: nsImage)
          .resizable()
          .aspectRatio(contentMode: .fit)
          .frame(width: 120, height: 120)
          .cornerRadius(24)
          .shadow(color: .black.opacity(0.1), radius: 20, x: 0, y: 10)
      }

      VStack(spacing: 12) {
        Text("Welcome to Lobs — your async AI assistant")
          .font(.system(size: 32, weight: .semibold))
          .foregroundColor(.primary)

        Text("Lobs helps you manage tasks, run background work, and keep everything synced in Git — without living in your terminal.")
          .font(.system(size: 16))
          .foregroundColor(.secondary)
          .multilineTextAlignment(.center)
          .frame(maxWidth: 420)
      }

      Spacer()

      Text("Use Next to continue")
        .font(.system(size: 13))
        .foregroundColor(.secondary)
        .padding(.bottom, 20)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Theme.bg)
  }
}

#Preview {
  OnboardingWelcomeView()
    .frame(width: 800, height: 600)
}
