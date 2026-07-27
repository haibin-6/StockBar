import SwiftUI
import AppKit

@main
struct StockBarApp: App {
    @State private var viewModel = StockViewModel()
    @State private var persistentWindowController: NSWindowController?

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
        .onChange(of: viewModel.windowPersistent) { _, newValue in
            if newValue {
                showPersistentWindow()
            } else {
                closePersistentWindow()
            }
        }
    }

    private func showPersistentWindow() {
        guard persistentWindowController == nil else { return }
        let contentView = MenuBarView(viewModel: viewModel, isPersistent: true)
            .frame(width: 320)
        let hosting = NSHostingController(rootView: contentView)
        let window = NSWindow(contentViewController: hosting)
        window.title = "系统监控"
        window.styleMask = [.titled, .closable, .resizable, .miniaturizable]
        window.level = .floating
        window.hidesOnDeactivate = false
        window.collectionBehavior = [.canJoinAllSpaces, .stationary]
        window.setContentSize(NSSize(width: 320, height: 500))
        window.isReleasedWhenClosed = false
        window.delegate = WindowDelegate { [weak viewModel] in
            viewModel?.windowPersistent = false
        }
        let controller = NSWindowController(window: window)
        controller.showWindow(nil)
        persistentWindowController = controller
    }

    private func closePersistentWindow() {
        persistentWindowController?.close()
        persistentWindowController = nil
    }

    private func menuBarText(for stock: Stock) -> String {
        let price = String(format: "%.2f", stock.currentPrice)
        let sign = stock.changePercent > 0 ? "+" : ""
        let change = String(format: "%@%.2f%%", sign, stock.changePercent)
        return "\(price) \(change)"
    }
}

private class WindowDelegate: NSObject, NSWindowDelegate {
    let onClose: () -> Void
    init(onClose: @escaping () -> Void) { self.onClose = onClose }
    func windowWillClose(_ notification: Notification) { onClose() }
}
