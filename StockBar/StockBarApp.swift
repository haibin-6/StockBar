import SwiftUI

@main
struct StockBarApp: App {
    @State private var viewModel = StockViewModel()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(viewModel: viewModel)
        } label: {
            if viewModel.showMenuBarInfo, let stock = viewModel.currentMenuBarStock {
                Text(menuBarText(for: stock))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(stock.isUp ? .red : stock.isDown ? .green : .primary)
            } else {
                Image(systemName: viewModel.menuBarIcon)
                    .foregroundStyle(viewModel.menuBarIconColor)
            }
        }
        .menuBarExtraStyle(.window)
    }

    private func menuBarText(for stock: Stock) -> String {
        let price = String(format: "%.2f", stock.currentPrice)
        let sign = stock.changePercent > 0 ? "+" : ""
        let change = String(format: "%@%.2f%%", sign, stock.changePercent)
        return "\(price) \(change)"
    }
}
