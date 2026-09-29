import SwiftUI

/// A compact color mark used only for 88VIP inside the popover.
struct VIPProviderIcon: View {
  let size: CGFloat

  var body: some View {
    ZStack {
      Circle()
        .fill(
          LinearGradient(
            colors: [Color(red: 0.0, green: 0.78, blue: 0.88), Color(red: 0.44, green: 0.18, blue: 0.94)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
          )
        )
      Text("88")
        .font(.system(size: size * 0.45, weight: .bold, design: .rounded))
        .foregroundStyle(.white)
        .minimumScaleFactor(0.7)
    }
    .frame(width: size, height: size)
    .accessibilityHidden(true)
  }
}
