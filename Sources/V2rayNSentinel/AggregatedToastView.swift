import SwiftUI

struct AggregatedToastView: View {
    let title: String
    let count: Int

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                Text("连接错误")
                    .font(.caption2).foregroundStyle(.secondary)
                Text(count > 1 ? "\(title)  ×\(count)" : title)
                    .font(.callout).lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(width: 360, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}
