import SwiftUI

struct SuggestionView: View {
    let text: String
    let onUse: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "lightbulb.fill")
                    .foregroundStyle(.yellow)
                Text("Suggested answer")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }

            Text(text)
                .font(.system(size: 13))
                .lineLimit(4)

            Button("Use this answer") {
                onUse()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .padding(12)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
