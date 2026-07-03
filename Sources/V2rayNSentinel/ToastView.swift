import SwiftUI
import SentinelCore

struct ToastView: View {
    let entry: HistoryEntry
    let isImportant: Bool
    let onClose: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                Text(entry.timestamp)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(entry.message)
                    .font(.callout)
                    .lineLimit(isImportant ? 6 : 2)
                    .foregroundStyle(isImportant ? Color.red : Color.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            if isImportant {
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .frame(width: isImportant ? 420 : 360, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isImportant ? Color.red : Color.clear, lineWidth: 2)
        )
    }
}
