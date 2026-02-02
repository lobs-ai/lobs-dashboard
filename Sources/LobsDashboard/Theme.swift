import SwiftUI

/// Shared design tokens used across all views.
enum Theme {
  static let bg = Color(nsColor: .windowBackgroundColor)
  static let boardBg = Color(nsColor: .underPageBackgroundColor)
  static let cardBg = Color(nsColor: .controlBackgroundColor)
  static let accent = Color.accentColor
  static let subtle = Color.primary.opacity(0.06)
  static let border = Color.primary.opacity(0.08)
  static let cardRadius: CGFloat = 14
  static let colRadius: CGFloat = 16
  static let columnMinWidth: CGFloat = 280
  static let columnIdealWidth: CGFloat = 320
}
