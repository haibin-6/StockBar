import SwiftUI

struct MenuBarView: View {
    @Bindable var viewModel: StockViewModel
    @State private var newStockCode = ""
    @State private var editingPositionStockId: String? = nil
    @State private var costPriceText = ""
    @State private var sharesText = ""
    @State private var stylePickerStockId: String? = nil
    @State private var showAddPopover = false
    @State private var hoveredStockId: String? = nil
    @State private var renamingStockId: String? = nil
    @State private var renameText = ""

    /// 根据布局动态计算内容宽度
    private var contentWidth: CGFloat {
        let maxRowSize = viewModel.layout.map { $0.count }.max() ?? 1
        if maxRowSize >= 3 { return 360 }
        return 280
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("系统监控")
                    .font(.headline)
                Spacer()
                Button {
                    viewModel.isEditing.toggle()
                } label: {
                    Text(viewModel.isEditing ? "完成" : "编辑")
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.blue)
                if viewModel.isLoading {
                    ProgressView()
                        .controlSize(.small)
                }
                Button {
                    viewModel.refresh()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.plain)
                Button {
                    viewModel.autoRefresh.toggle()
                } label: {
                    Image(systemName: viewModel.autoRefresh ? "antenna.radiowaves.left.and.right" : "antenna.radiowaves.left.and.right.slash")
                }
                .buttonStyle(.plain)
                .help(viewModel.autoRefresh ? "自动刷新中" : "自动刷新已关闭")
                // Privacy toggle
                Button {
                    viewModel.showColor.toggle()
                } label: {
                    Image(systemName: viewModel.showColor ? "eye" : "eye.slash")
                }
                .buttonStyle(.plain)
                .help(viewModel.showColor ? "显示颜色" : "隐私模式")
                // Menu bar info toggle
                Button {
                    viewModel.showMenuBarInfo.toggle()
                } label: {
                    Image(systemName: viewModel.showMenuBarInfo ? "text.badge.checkmark" : "text.badge.xmark")
                }
                .buttonStyle(.plain)
                .help(viewModel.showMenuBarInfo ? "菜单栏显示价格：开" : "菜单栏显示价格：关")
                // Add stock button
                Button {
                    showAddPopover.toggle()
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showAddPopover, arrowEdge: .bottom) {
                    HStack {
                        TextField("输入代码", text: $newStockCode)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 120)
                            .onSubmit {
                                addStock()
                                showAddPopover = false
                            }
                        Button("添加") {
                            addStock()
                            showAddPopover = false
                        }
                        .disabled(newStockCode.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    .padding(12)
                    .frame(minWidth: 220)
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 6)

            Divider()

            // Error
            if let error = viewModel.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                Divider()
            }

            // Stock list
            if viewModel.stocks.isEmpty {
                Text("暂无数据")
                    .foregroundStyle(.secondary)
                    .padding(12)
            } else {
                ForEach(viewModel.layout.indices, id: \.self) { rowIndex in
                    let rowIds = viewModel.layout[rowIndex]
                    HStack(spacing: 0) {
                        ForEach(rowIds, id: \.self) { stockId in
                            if let stock = viewModel.stockDict[stockId] {
                                stockCard(stock: stock, rowIds: rowIds)
                            }
                        }
                    }
                    .frame(width: contentWidth)
                    .zIndex(hoveredStockId != nil && rowIds.contains(hoveredStockId!) ? 1 : 0)
                }
            }

            Divider()

            // 持仓编辑区域（底部独立区域）
            if let editId = editingPositionStockId,
               let stock = viewModel.stockDict[editId] {
                HStack(spacing: 6) {
                    Text(viewModel.displayName(for: editId))
                        .font(.system(size: 11, weight: .medium))
                        .lineLimit(1)
                    TextField("成本价", text: $costPriceText)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 70)
                    TextField("股数", text: $sharesText)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 60)
                    Button("确认") {
                        if let cost = Double(costPriceText), let shares = Int(sharesText), shares > 0 {
                            viewModel.updatePosition(stockId: editId, costPrice: cost, shares: shares)
                            editingPositionStockId = nil
                        }
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.blue)
                    Button("取消") {
                        editingPositionStockId = nil
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
                .font(.system(size: 11))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                Divider()
            }

            // 重命名编辑区域
            if let renameId = renamingStockId {
                HStack(spacing: 6) {
                    Text("名称")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    TextField("自定义名称", text: $renameText)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 120)
                        .onSubmit {
                            viewModel.setCustomName(renameText, for: renameId)
                            renamingStockId = nil
                        }
                    Button("确认") {
                        viewModel.setCustomName(renameText, for: renameId)
                        renamingStockId = nil
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.blue)
                    Button("取消") {
                        renamingStockId = nil
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
                .font(.system(size: 11))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                Divider()
            }

            HStack {
                if let time = viewModel.lastUpdateTime {
                    Text(formatTime(time))
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if viewModel.showMenuBarInfo {
                    Text("轮播间隔")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                    TextField("秒", value: $viewModel.cycleInterval, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 36)
                    Text("秒")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
                Button("退出") {
                    NSApplication.shared.terminate(nil)
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
            .padding(.top, 4)
        }
        .frame(width: contentWidth)
    }

    // MARK: - Stock Card

    @ViewBuilder
    private func stockCard(stock: Stock, rowIds: [String]) -> some View {
        let style = viewModel.displayStyle(for: stock.id)
        let step = stock.id == "sh000001" ? 0.2 : 1.0  // 每格=涨跌幅1%，10格=10%上限
        let isSharedRow = rowIds.count > 1

        HStack(spacing: 4) {
            // 编辑模式下的排序按钮
            if viewModel.isEditing {
                let rowIdx = viewModel.layout.indices.first(where: { viewModel.layout[$0].contains(stock.id) })
                VStack(spacing: 2) {
                    Button {
                        viewModel.moveUp(stock.id)
                    } label: {
                        Image(systemName: "chevron.up")
                            .font(.system(size: 8, weight: .bold))
                            .frame(width: 16, height: 12)
                    }
                    .buttonStyle(.plain)
                    .disabled(rowIdx == nil || rowIdx == 0)

                    Button {
                        viewModel.moveDown(stock.id)
                    } label: {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 8, weight: .bold))
                            .frame(width: 16, height: 12)
                    }
                    .buttonStyle(.plain)
                    .disabled(rowIdx == nil || rowIdx == viewModel.layout.count - 1)
                }

                // 合并到上一行按钮（仅柱状图可用）
                if style == .barStack {
                    Button {
                        viewModel.mergeWithAbove(stock.id)
                    } label: {
                        Image(systemName: "arrow.left.to.line.compact")
                            .font(.system(size: 10))
                            .frame(width: 16, height: 24)
                    }
                    .buttonStyle(.plain)
                    .disabled(!viewModel.canMergeWithAbove(stock.id))
                    .help("合并到上一行")
                }
            }

            Group {
                switch style {
                case .gauge:
                    GaugeView(
                        value: stock.changePercent,
                        label: viewModel.displayName(for: stock.id),
                        detail: String(format: "%.2f", stock.currentPrice),
                        showColor: viewModel.showColor
                    )
                    .padding(.horizontal, isSharedRow ? 4 : 12)
                case .heatmap:
                    HeatmapView(value: stock.changePercent, label: viewModel.displayName(for: stock.id), price: stock.currentPrice, step: step, showColor: viewModel.showColor)
                case .barStack:
                    BarStackView(value: stock.changePercent, label: viewModel.displayName(for: stock.id), price: stock.currentPrice, step: step, showColor: viewModel.showColor)
                }
            }
            .frame(maxWidth: isSharedRow ? .infinity : nil)
        }
        .frame(maxWidth: isSharedRow ? .infinity : nil)
        .contentShape(Rectangle())
        .onHover { isHovered in
            hoveredStockId = isHovered && viewModel.hasPosition(stock.id) ? stock.id : nil
        }
        .overlay(alignment: .top) {
            if hoveredStockId == stock.id {
                VStack(alignment: .leading, spacing: 4) {
                    if let daily = viewModel.dailyProfit(for: stock.id) {
                        HStack(spacing: 4) {
                            Text("当日")
                                .foregroundStyle(.secondary)
                            Text(formatMoney(daily))
                                .fontWeight(.medium)
                                .monospacedDigit()
                                .foregroundStyle(viewModel.showColor ? (daily >= 0 ? .red : .green) : .primary)
                        }
                    }
                    if let total = viewModel.profit(for: stock.id) {
                        HStack(spacing: 4) {
                            Text("持仓")
                                .foregroundStyle(.secondary)
                            Text(formatMoney(total))
                                .fontWeight(.medium)
                                .monospacedDigit()
                                .foregroundStyle(viewModel.showColor ? (total >= 0 ? .red : .green) : .primary)
                        }
                    }
                }
                .font(.system(size: 11))
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(.regularMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
                .offset(y: -60)
                .transition(.opacity)
            }
        }
        .contextMenu {
            if stock.id != "sh000001" {
                Button("设置持仓") {
                    if let pos = viewModel.positions[stock.id] {
                        costPriceText = String(pos.costPrice)
                        sharesText = String(pos.shares)
                    } else {
                        costPriceText = ""
                        sharesText = ""
                    }
                    editingPositionStockId = stock.id
                }
            }

            Button("重命名") {
                renameText = viewModel.customName(for: stock.id) ?? stock.name
                renamingStockId = stock.id
            }

            Button(viewModel.isMenuBarVisible(stock.id) ? "✓ 菜单栏显示" : "菜单栏显示") {
                viewModel.toggleMenuBarVisible(stock.id)
            }

            Menu("显示样式") {
                Button(style == .gauge ? "✓ 音量条" : "音量条") {
                    viewModel.setDisplayStyle(.gauge, for: stock.id)
                }
                Button(style == .heatmap ? "✓ 热力图" : "热力图") {
                    viewModel.setDisplayStyle(.heatmap, for: stock.id)
                }
                Button(style == .barStack ? "✓ 柱状图" : "柱状图") {
                    viewModel.setDisplayStyle(.barStack, for: stock.id)
                }
            }

            if isSharedRow {
                Button("拆分行") {
                    viewModel.splitStock(stock.id)
                }
            }

            Button("移除") {
                viewModel.removeStock(stock.id)
            }
        }
    }

    // MARK: - Helpers

    private func formatMoney(_ value: Double) -> String {
        let absVal = abs(value)
        let sign = value >= 0 ? "+" : "-"
        if absVal >= 10000 {
            return String(format: "%@%.1f万", sign, absVal / 10000)
        }
        return String(format: "%@%.0f", sign, absVal)
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    private func formatTime(_ date: Date) -> String {
        "更新: " + Self.timeFormatter.string(from: date)
    }

    private func addStock() {
        let code = newStockCode.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !code.isEmpty else { return }
        viewModel.addStock(code)
        newStockCode = ""
    }

}
