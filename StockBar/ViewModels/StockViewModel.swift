import SwiftUI
import Combine

enum DisplayStyle: String, Codable, CaseIterable {
    case gauge    // 音量条
    case heatmap  // 热力图
    case barStack // 柱状图
}

@Observable
class StockViewModel {
    var stocks: [Stock] = []
    var isLoading = false
    var errorMessage: String?
    var autoRefresh = true
    var isEditing = false
    var showColor = true {
        didSet { UserDefaults.standard.set(showColor, forKey: Self.showColorKey) }
    }
    var showMenuBarInfo = false {
        didSet {
            UserDefaults.standard.set(showMenuBarInfo, forKey: Self.showMenuBarInfoKey)
            if showMenuBarInfo { startCycling() } else { stopCycling() }
        }
    }
    var cycleInterval: Double = 3.0 {
        didSet {
            UserDefaults.standard.set(cycleInterval, forKey: Self.cycleIntervalKey)
            if showMenuBarInfo { startCycling() }
        }
    }
    var menuBarStockIndex = 0
    private var menuBarVisibleStocks: Set<String> = [] {
        didSet { saveMenuBarVisibleStocks() }
    }
    var positions: [String: Position] = [:]
    private var displayStyles: [String: DisplayStyle] = [:]
    private var customNames: [String: String] = [:]
    var layout: [[String]] = []
    var lastUpdateTime: Date? = nil

    /// O(1) 股票查找字典，与 stocks 同步
    private(set) var stockDict: [String: Stock] = [:]

    /// 当前是否在交易时间（9:30~15:00 工作日）
    var isTradingHours: Bool {
        let now = Calendar.current.dateComponents([.hour, .minute, .weekday], from: Date())
        guard let hour = now.hour, let minute = now.minute, let weekday = now.weekday else {
            return false
        }
        // 周六(7)周日(1)不交易
        guard weekday != 1 && weekday != 7 else { return false }
        // 9:30 ~ 15:00
        let totalMinutes = hour * 60 + minute
        return totalMinutes >= (9 * 60 + 30) && totalMinutes <= (15 * 60)
    }

    /// 获取单只股票的盈亏（持仓涨跌额）
    func profit(for stockId: String) -> Double? {
        guard let pos = positions[stockId],
              let stock = stockDict[stockId] else { return nil }
        return (stock.currentPrice - pos.costPrice) * Double(pos.shares)
    }

    /// 获取单只股票的当日涨跌额
    func dailyProfit(for stockId: String) -> Double? {
        guard let pos = positions[stockId],
              let stock = stockDict[stockId] else { return nil }
        return stock.changeAmount * Double(pos.shares)
    }

    /// 是否有持仓设置
    func hasPosition(_ stockId: String) -> Bool {
        positions[stockId] != nil
    }

    /// 获取股票显示名称（优先自定义名称）
    func displayName(for stockId: String) -> String {
        if let custom = customNames[stockId] {
            return custom
        }
        return stockDict[stockId]?.name ?? stockId
    }

    /// 设置自定义名称
    func setCustomName(_ name: String, for stockId: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            customNames.removeValue(forKey: stockId)
        } else {
            customNames[stockId] = trimmed
        }
        saveCustomNames()
    }

    /// 获取当前自定义名称（用于编辑时回填）
    func customName(for stockId: String) -> String? {
        customNames[stockId]
    }

    /// 根据显示样式计算每行最大数量：音量条/热力图=1，柱状图=3
    func maxPerRow(for stockId: String) -> Int {
        switch displayStyle(for: stockId) {
        case .gauge, .heatmap: return 1
        case .barStack: return 3
        }
    }

    /// 当日持仓总盈亏
    var totalDailyProfit: Double? {
        guard !positions.isEmpty else { return nil }
        var total = 0.0
        var hasValue = false
        for stockId in positions.keys {
            if let daily = dailyProfit(for: stockId) {
                total += daily
                hasValue = true
            }
        }
        return hasValue ? total : nil
    }

    /// 今天是否已经开盘过（9:30 之后，含收盘后）
    private var hasMarketOpenedToday: Bool {
        let now = Calendar.current.dateComponents([.hour, .minute], from: Date())
        guard let hour = now.hour, let minute = now.minute else { return false }
        return (hour * 60 + minute) >= (9 * 60 + 30)
    }

    var menuBarIcon: String {
        guard let total = totalDailyProfit, hasMarketOpenedToday else {
            return "chart.line.uptrend.xyaxis"
        }
        if total > 0 { return "arrowtriangle.up.fill" }
        if total < 0 { return "arrowtriangle.down.fill" }
        return "minus"
    }

    var menuBarIconColor: Color {
        guard let total = totalDailyProfit, hasMarketOpenedToday else { return .primary }
        if total > 0 { return .red }
        if total < 0 { return .green }
        return .primary
    }

    private let service = StockService()
    private var cancellable: AnyCancellable?
    private var cycleTimer: AnyCancellable?
    private var watchedStockIds: [String]

    private static let watchedStocksKey = "watchedStockIds"
    private static let positionsKey = "stockbar.positions"
    private static let displayStylesKey = "stockbar.displayStyles"
    private static let layoutKey = "stockbar.layout"
    private static let showColorKey = "stockbar.showColor"
    private static let showMenuBarInfoKey = "stockbar.showMenuBarInfo"
    private static let cycleIntervalKey = "stockbar.cycleInterval"
    private static let menuBarVisibleStocksKey = "stockbar.menuBarVisibleStocks"
    private static let customNamesKey = "stockbar.customNames"

    init() {
        self.watchedStockIds = Self.loadWatchedStocks()
        self.positions = Self.loadPositions()
        self.displayStyles = Self.loadDisplayStyles()
        self.layout = Self.loadLayout()
        self.customNames = Self.loadCustomNames()
        self.showColor = UserDefaults.standard.object(forKey: Self.showColorKey) as? Bool ?? true
        self.showMenuBarInfo = UserDefaults.standard.object(forKey: Self.showMenuBarInfoKey) as? Bool ?? false
        self.cycleInterval = UserDefaults.standard.object(forKey: Self.cycleIntervalKey) as? Double ?? 3.0
        self.menuBarVisibleStocks = Self.loadMenuBarVisibleStocks()
        self.repairLayout()
        Task {
            await fetchStocks()
            startPolling()
        }
        if showMenuBarInfo { startCycling() }
    }

    /// 添加关注的股票
    /// 支持输入纯数字代码（自动加前缀）或带前缀的代码
    /// 6开头 → sh, 0/3开头 → sz
    func addStock(_ id: String) {
        let trimmed = id.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let code: String
        if trimmed.hasPrefix("sh") || trimmed.hasPrefix("sz") {
            code = trimmed
        } else if trimmed.first == "6" {
            code = "sh" + trimmed
        } else {
            code = "sz" + trimmed
        }

        guard !watchedStockIds.contains(code) else { return }
        watchedStockIds.append(code)
        layout.append([code])
        menuBarVisibleStocks.insert(code)  // 默认可见
        saveWatchedStocks()
        saveLayout()
        Task { await fetchStocks() }
    }

    /// 更新持仓
    func updatePosition(stockId: String, costPrice: Double, shares: Int) {
        positions[stockId] = Position(stockId: stockId, costPrice: costPrice, shares: shares)
        savePositions()
    }

    /// 删除关注的股票
    func removeStock(_ id: String) {
        watchedStockIds.removeAll { $0 == id }
        stocks.removeAll { $0.id == id }
        stockDict.removeValue(forKey: id)
        positions.removeValue(forKey: id)
        displayStyles.removeValue(forKey: id)
        customNames.removeValue(forKey: id)
        menuBarVisibleStocks.remove(id)
        // Remove from layout
        for i in layout.indices {
            layout[i].removeAll { $0 == id }
        }
        layout.removeAll { $0.isEmpty }
        saveWatchedStocks()
        savePositions()
        saveDisplayStyles()
        saveLayout()
    }

    /// 获取股票显示样式（上证指数默认热力图）
    func displayStyle(for stockId: String) -> DisplayStyle {
        if stockId == "sh000001" {
            return displayStyles[stockId] ?? .heatmap
        }
        return displayStyles[stockId] ?? .gauge
    }

    /// 设置股票显示样式
    func setDisplayStyle(_ style: DisplayStyle, for stockId: String) {
        displayStyles[stockId] = style
        saveDisplayStyles()
        // 切换到 gauge/heatmap 时，确保独占一行
        if style == .gauge || style == .heatmap {
            for i in layout.indices {
                if let idx = layout[i].firstIndex(of: stockId) {
                    if layout[i].count > 1 {
                        layout[i].remove(at: idx)
                        layout.append([stockId])
                        layout.removeAll { $0.isEmpty }
                        saveLayout()
                    }
                    break
                }
            }
        }
    }

    /// 立即刷新
    func refresh() {
        Task { await fetchStocks() }
    }

    /// 将 sourceId 移动到 targetId 所在的位置
    /// 音量条/热力图每行只能1个，柱状图最多3个
    func moveStock(_ sourceId: String, to targetId: String) {
        guard sourceId != targetId else { return }

        // 记录源和目标的原始位置
        guard let srcRowIdx = layout.indices.first(where: { layout[$0].contains(sourceId) }) else { return }
        guard let tgtRowIdx = layout.indices.first(where: { layout[$0].contains(targetId) }) else { return }

        // 从源行移除
        layout[srcRowIdx].removeAll { $0 == sourceId }
        let srcRowRemoved = layout[srcRowIdx].isEmpty
        if srcRowRemoved {
            layout.remove(at: srcRowIdx)
        }

        // 计算目标行的实际索引（移除源行后可能偏移）
        let adjustedTgtIdx: Int
        if srcRowRemoved && srcRowIdx < tgtRowIdx {
            adjustedTgtIdx = tgtRowIdx - 1
        } else {
            adjustedTgtIdx = tgtRowIdx
        }

        // 检查是否可以合并到目标行
        let canMerge: Bool
        if adjustedTgtIdx < layout.count && layout[adjustedTgtIdx].contains(targetId) {
            let sourceStyle = displayStyle(for: sourceId)
            if sourceStyle == .gauge || sourceStyle == .heatmap {
                canMerge = false
            } else {
                let hasNonBarStack = layout[adjustedTgtIdx].contains {
                    displayStyle(for: $0) != .barStack
                }
                canMerge = !hasNonBarStack && layout[adjustedTgtIdx].count < 3
            }
        } else {
            canMerge = false
        }

        if canMerge {
            layout[adjustedTgtIdx].append(sourceId)
        } else {
            // 插入到目标行之后，实现排序
            let insertIdx = min(adjustedTgtIdx + 1, layout.count)
            layout.insert([sourceId], at: insertIdx)
        }

        saveLayout()
    }

    /// 上移股票（与前一行交换）
    func moveUp(_ sourceId: String) {
        guard let rowIdx = layout.indices.first(where: { layout[$0].contains(sourceId) }),
              rowIdx > 0 else { return }
        layout.swapAt(rowIdx, rowIdx - 1)
        saveLayout()
    }

    /// 下移股票（与后一行交换）
    func moveDown(_ sourceId: String) {
        guard let rowIdx = layout.indices.first(where: { layout[$0].contains(sourceId) }),
              rowIdx < layout.count - 1 else { return }
        layout.swapAt(rowIdx, rowIdx + 1)
        saveLayout()
    }

    /// 将 sourceId 合并到上一行（仅限柱状图之间）
    func mergeWithAbove(_ sourceId: String) {
        guard let rowIdx = layout.indices.first(where: { layout[$0].contains(sourceId) }),
              rowIdx > 0 else { return }

        let aboveRow = layout[rowIdx - 1]
        let sourceStyle = displayStyle(for: sourceId)
        guard sourceStyle == .barStack else { return }
        // 上一行必须全部是柱状图且不超过3个
        let allBarStack = aboveRow.allSatisfy { displayStyle(for: $0) == .barStack }
        guard allBarStack && aboveRow.count < 3 else { return }

        layout[rowIdx].removeAll { $0 == sourceId }
        layout[rowIdx - 1].append(sourceId)
        if layout[rowIdx].isEmpty {
            layout.remove(at: rowIdx)
        }
        saveLayout()
    }

    /// 是否可以合并到上一行
    func canMergeWithAbove(_ sourceId: String) -> Bool {
        guard let rowIdx = layout.indices.first(where: { layout[$0].contains(sourceId) }),
              rowIdx > 0 else { return false }
        let aboveRow = layout[rowIdx - 1]
        guard displayStyle(for: sourceId) == .barStack else { return false }
        let allBarStack = aboveRow.allSatisfy { displayStyle(for: $0) == .barStack }
        return allBarStack && aboveRow.count < 3
    }

    /// 将 sourceId 从所在行拆出，独占一行
    func splitStock(_ sourceId: String) {
        for i in layout.indices {
            if let idx = layout[i].firstIndex(of: sourceId) {
                layout[i].remove(at: idx)
                layout.append([sourceId])
                layout.removeAll { $0.isEmpty }
                saveLayout()
                return
            }
        }
    }

    /// 确保 layout 与 watchedStockIds 一致
    private func repairLayout() {
        let allInLayout = Set(layout.flatMap { $0 })
        let watched = Set(watchedStockIds)

        // Add missing stocks as solo rows
        let missing = watched.subtracting(allInLayout)
        for id in missing {
            layout.append([id])
        }

        // Remove stocks not in watched list
        for i in layout.indices {
            layout[i] = layout[i].filter { watched.contains($0) }
        }
        layout.removeAll { $0.isEmpty }
    }

    // MARK: - Private

    /// 菜单栏轮播可见的股票列表
    var menuBarCycleStocks: [Stock] {
        stocks.filter { menuBarVisibleStocks.contains($0.id) }
    }

    /// 菜单栏当前轮播显示的股票
    var currentMenuBarStock: Stock? {
        guard !menuBarCycleStocks.isEmpty else { return nil }
        let idx = menuBarStockIndex % menuBarCycleStocks.count
        return menuBarCycleStocks[idx]
    }

    /// 某只股票是否在菜单栏可见
    func isMenuBarVisible(_ stockId: String) -> Bool {
        menuBarVisibleStocks.contains(stockId)
    }

    /// 切换菜单栏可见性
    func toggleMenuBarVisible(_ stockId: String) {
        if menuBarVisibleStocks.contains(stockId) {
            menuBarVisibleStocks.remove(stockId)
        } else {
            menuBarVisibleStocks.insert(stockId)
        }
    }

    private func startCycling() {
        cycleTimer?.cancel()
        let interval = max(1, cycleInterval)
        cycleTimer = Timer.publish(every: interval, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self, !self.menuBarCycleStocks.isEmpty else { return }
                self.menuBarStockIndex = (self.menuBarStockIndex + 1) % self.menuBarCycleStocks.count
            }
    }

    private func stopCycling() {
        cycleTimer?.cancel()
        cycleTimer = nil
    }

    private func fetchStocks() async {
        // 只保留有效格式（sh/sz + 数字）
        let validIds = watchedStockIds.filter { $0.hasPrefix("sh") || $0.hasPrefix("sz") }
        guard !validIds.isEmpty else { return }
        isLoading = true
        errorMessage = nil

        do {
            let results = try await service.fetchStocks(stockIds: validIds)
            await MainActor.run {
                self.stocks = results
                self.stockDict = Dictionary(uniqueKeysWithValues: results.map { ($0.id, $0) })
                self.lastUpdateTime = Date()
                self.isLoading = false
            }
        } catch {
            await MainActor.run {
                self.errorMessage = error.localizedDescription
                self.isLoading = false
            }
        }
    }

    private func startPolling() {
        cancellable = Timer.publish(every: 3, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self, self.autoRefresh, self.isTradingHours else { return }
                Task { await self.fetchStocks() }
            }
    }

    // MARK: - Persistence

    private static func loadWatchedStocks() -> [String] {
        if let saved = UserDefaults.standard.stringArray(forKey: watchedStocksKey) {
            return saved
        }
        // 默认预置：上证指数
        return ["sh000001"]
    }

    private func saveWatchedStocks() {
        UserDefaults.standard.set(watchedStockIds, forKey: Self.watchedStocksKey)
    }

    private static func loadPositions() -> [String: Position] {
        guard let data = UserDefaults.standard.data(forKey: positionsKey) else { return [:] }
        return (try? JSONDecoder().decode([String: Position].self, from: data)) ?? [:]
    }

    private func savePositions() {
        guard let data = try? JSONEncoder().encode(positions) else { return }
        UserDefaults.standard.set(data, forKey: Self.positionsKey)
    }

    private static func loadDisplayStyles() -> [String: DisplayStyle] {
        guard let data = UserDefaults.standard.data(forKey: displayStylesKey) else { return [:] }
        return (try? JSONDecoder().decode([String: DisplayStyle].self, from: data)) ?? [:]
    }

    private func saveDisplayStyles() {
        guard let data = try? JSONEncoder().encode(displayStyles) else { return }
        UserDefaults.standard.set(data, forKey: Self.displayStylesKey)
    }

    private static func loadLayout() -> [[String]] {
        guard let data = UserDefaults.standard.data(forKey: layoutKey) else { return [] }
        return (try? JSONDecoder().decode([[String]].self, from: data)) ?? []
    }

    private func saveLayout() {
        guard let data = try? JSONEncoder().encode(layout) else { return }
        UserDefaults.standard.set(data, forKey: Self.layoutKey)
    }

    private static func loadCustomNames() -> [String: String] {
        guard let data = UserDefaults.standard.data(forKey: customNamesKey) else { return [:] }
        return (try? JSONDecoder().decode([String: String].self, from: data)) ?? [:]
    }

    private func saveCustomNames() {
        guard let data = try? JSONEncoder().encode(customNames) else { return }
        UserDefaults.standard.set(data, forKey: Self.customNamesKey)
    }

    private static func loadMenuBarVisibleStocks() -> Set<String> {
        guard let data = UserDefaults.standard.data(forKey: menuBarVisibleStocksKey) else { return [] }
        return (try? JSONDecoder().decode(Set<String>.self, from: data)) ?? []
    }

    private func saveMenuBarVisibleStocks() {
        guard let data = try? JSONEncoder().encode(menuBarVisibleStocks) else { return }
        UserDefaults.standard.set(data, forKey: Self.menuBarVisibleStocksKey)
    }
}
