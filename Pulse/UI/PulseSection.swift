import SwiftUI

struct PulseSection<Content: View>: View {
  let title: String
  let symbol: String
  @ViewBuilder let content: Content

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      Label(title, systemImage: symbol)
        .font(.headline)
      content
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    .padding(12)
    .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 10))
  }
}
