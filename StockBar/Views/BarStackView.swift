import SwiftUI

/// 纯竖向柱状图
struct BarStackView: View {
    let value: Double  // changePercent
    let label: String
    let price: Double  // currentPrice
    let step: Double
    var showColor: Bool = true

    private let totalBlocks = 10

    init(value: Double, label: String, price: Double, step: Double = 0.2, showColor: Bool = true) {
        self.value = value
        self.label = label
        self.price = price
        self.step = step
        self.showColor = showColor
    }

    var body: some View {
        HStack(spacing: 6) {
            // 竖向扁长方形柱块
            VStack(spacing: 1) {
                Spacer(minLength: 0)
                ForEach((0..<totalBlocks).reversed(), id: \.self) { i in
                    let threshold = Double(i) * step
                    let isLit = abs(value) >= threshold
                    RoundedRectangle(cornerRadius: 2)
                        .fill(blockColor(isLit: isLit))
                        .frame(height: 4)
                }
            }
            .frame(width: 24)

            // Label + value
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(formatPrice(price))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.primary)
                Text(formatValue(value))
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(showColor ? valueColor(value) : .primary)
            }

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
    }

    private func blockColor(isLit: Bool) -> Color {
        if isLit {
            return value >= 0 ? Color.red.opacity(0.6) : Color.green.opacity(0.6)
        }
        return Color.gray.opacity(0.12)
    }

    private func formatValue(_ v: Double) -> String {
        let sign = v > 0 ? "+" : ""
        return String(format: "%@%.2f%%", sign, v)
    }

    private func formatPrice(_ p: Double) -> String {
        String(format: "%.2f", p)
    }

    private func valueColor(_ v: Double) -> Color {
        return v >= 0 ? .red : .green
    }
}
