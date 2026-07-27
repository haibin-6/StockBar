import SwiftUI

struct GaugeView: View {
    let value: Double
    let label: String
    let detail: String
    var profit: Double? = nil
    var showColor: Bool = true

    private let maxValue = 20.0

    var body: some View {
        VStack(spacing: 3) {
            // Bar
            GeometryReader { geo in
                let width = geo.size.width
                let height = geo.size.height
                let midX = width / 2
                let ratio = min(abs(value) / maxValue, 1.0)
                let barWidth = ratio * midX

                ZStack(alignment: .center) {
                    // Background track
                    Capsule()
                        .fill(Color.gray.opacity(0.15))

                    // Value bar
                    if value >= 0 {
                        Capsule()
                            .fill(Color.red.opacity(0.6))
                            .frame(width: max(barWidth, 2))
                            .offset(x: barWidth / 2)
                    } else {
                        Capsule()
                            .fill(Color.green.opacity(0.6))
                            .frame(width: max(barWidth, 2))
                            .offset(x: -barWidth / 2)
                    }

                    // Center line
                    Rectangle()
                        .fill(Color.primary.opacity(0.4))
                        .frame(width: 1)
                }
            }
            .frame(height: 8)

            // Label + value
            HStack {
                Text(label)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                Text(detail)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.primary)
                Text(formatChange(value))
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(showColor ? (value >= 0 ? .red : .green) : .primary)
            }

            // Profit row (only if position is set)
            if let profit {
                HStack {
                    Spacer()
                    Text(formatProfit(profit))
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(showColor ? (profit >= 0 ? .red : .green) : .primary)
                }
            }
        }
        .frame(width: 120, height: profit != nil ? 42 : 28)
    }

    private func formatChange(_ change: Double) -> String {
        let sign = change > 0 ? "+" : ""
        return String(format: "%@%.2f%%", sign, change)
    }

    private func formatProfit(_ value: Double) -> String {
        let sign = value > 0 ? "+" : ""
        return String(format: "%@%.2f", sign, value)
    }
}
