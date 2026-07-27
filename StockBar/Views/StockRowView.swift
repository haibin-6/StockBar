import SwiftUI

struct StockRowView: View {
    let stock: Stock
    var showColor: Bool = true
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            // 名称 + 代码
            VStack(alignment: .leading, spacing: 2) {
                Text(stock.name)
                    .font(.system(size: 13, weight: .medium))
                Text(stock.code)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // 当前价
            Text(formatPrice(stock.currentPrice))
                .font(.system(size: 13, design: .monospaced))
                .foregroundStyle(.primary)

            // 涨跌幅 — 灰色调，不醒目
            Text(formatChange(stock.changePercent))
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.secondary)

            // 删除按钮
            Button {
                onDelete()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    private func formatPrice(_ price: Double) -> String {
        String(format: "%.2f", price)
    }

    private func formatChange(_ change: Double) -> String {
        let sign = change > 0 ? "+" : ""
        return String(format: "%@%.2f%%", sign, change)
    }
}
