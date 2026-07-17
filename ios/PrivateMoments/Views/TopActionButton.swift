import SwiftUI

struct TopActionButton: View {
    let title: String
    let systemImage: String
    let accessibilityIdentifier: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            topActionIcon(systemImage)
        }
        .accessibilityLabel(title)
        .accessibilityIdentifier(accessibilityIdentifier)
    }
}

struct TopActionMenuLabel: View {
    let systemImage: String

    var body: some View {
        topActionIcon(systemImage)
    }
}

@ViewBuilder
private func topActionIcon(_ systemImage: String) -> some View {
    Image(systemName: systemImage)
        .frame(width: 28, height: 36)
        .contentShape(Rectangle())
}
