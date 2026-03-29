import Combine
import SwiftUI

@main
struct MeterBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            SettingsView()
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        guard let button = statusItem?.button else {
            return
        }

        let image = createMenuBarIcon()
        image.isTemplate = true
        button.image = image

        button.action = #selector(togglePopover)
        button.target = self
        button.toolTip = "MeterBar"

        popover = NSPopover()
        popover?.contentSize = NSSize(width: 432, height: 560)
        popover?.behavior = .transient
        popover?.contentViewController = NSHostingController(rootView: MenuBarView())

        configureObservers()
        updateStatusItemAppearance()

        Task { @MainActor in
            await UsageDataManager.shared.refreshAll()
        }
    }

    @objc func togglePopover() {
        guard let button = statusItem?.button,
              let popover = popover else { return }

        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    private func createMenuBarIcon() -> NSImage {
        let snapshots = enabledStatusSnapshots()
        let mode = UserDefaults.standard.string(forKey: "statusItemIconMode") ?? "usageBars"
        let indicator = statusIndicatorState()

        if mode == "providerDots" {
            return createProviderDotsIcon(snapshots: snapshots, indicator: indicator)
        }

        if mode == "template" || snapshots.isEmpty {
            return createTemplateMenuBarIcon(indicator: indicator)
        }

        return createUsageBarsIcon(snapshots: snapshots, indicator: indicator)
    }

    private func createTemplateMenuBarIcon(indicator: IconIndicatorState) -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { rect in
            let barHeight: CGFloat = 3
            let barSpacing: CGFloat = 2
            let cornerRadius: CGFloat = 1.5

            // Three bars with different widths (like progress indicators)
            let barWidths: [CGFloat] = [0.35, 0.55, 0.85] // 35%, 55%, 85%
            let totalBarsHeight = (barHeight * 3) + (barSpacing * 2)
            let startY = (rect.height - totalBarsHeight) / 2

            for (index, fillPercent) in barWidths.enumerated() {
                let y = startY + CGFloat(index) * (barHeight + barSpacing)
                let barWidth = rect.width * fillPercent

                let barRect = NSRect(x: 0, y: y, width: barWidth, height: barHeight)
                let path = NSBezierPath(roundedRect: barRect, xRadius: cornerRadius, yRadius: cornerRadius)
                NSColor.black.setFill()
                path.fill()
            }

            drawIndicator(indicator, in: rect)
            return true
        }
        image.isTemplate = true
        return image
    }

    private func createUsageBarsIcon(snapshots: [StatusIconSnapshot], indicator: IconIndicatorState) -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { rect in
            let rows = min(3, snapshots.count)
            let barHeight: CGFloat = 3
            let barSpacing: CGFloat = 2
            let cornerRadius: CGFloat = 1.5
            let totalBarsHeight = (barHeight * CGFloat(rows)) + (barSpacing * CGFloat(max(0, rows - 1)))
            let startY = (rect.height - totalBarsHeight) / 2

            for (index, snapshot) in snapshots.prefix(3).enumerated() {
                let y = startY + CGFloat(index) * (barHeight + barSpacing)
                let fillWidth = max(2, rect.width * snapshot.remainingFraction)
                let backgroundRect = NSRect(x: 0, y: y, width: rect.width - 2, height: barHeight)
                let fillRect = NSRect(x: 0, y: y, width: min(rect.width - 2, fillWidth), height: barHeight)

                NSColor.labelColor.withAlphaComponent(0.18).setFill()
                NSBezierPath(roundedRect: backgroundRect, xRadius: cornerRadius, yRadius: cornerRadius).fill()

                snapshot.color.setFill()
                NSBezierPath(roundedRect: fillRect, xRadius: cornerRadius, yRadius: cornerRadius).fill()
            }

            drawIndicator(indicator, in: rect)
            return true
        }
        image.isTemplate = false
        return image
    }

    private func createProviderDotsIcon(snapshots: [StatusIconSnapshot], indicator: IconIndicatorState) -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { rect in
            let dots = min(3, snapshots.count)
            let diameter: CGFloat = 4
            let spacing: CGFloat = 2
            let totalWidth = (diameter * CGFloat(dots)) + (spacing * CGFloat(max(0, dots - 1)))
            let startX = (rect.width - totalWidth) / 2
            let y = (rect.height - diameter) / 2

            for (index, snapshot) in snapshots.prefix(3).enumerated() {
                let x = startX + CGFloat(index) * (diameter + spacing)
                let dotRect = NSRect(x: x, y: y, width: diameter, height: diameter)
                snapshot.color.setFill()
                NSBezierPath(ovalIn: dotRect).fill()
            }

            drawIndicator(indicator, in: rect)
            return true
        }
        image.isTemplate = false
        return image
    }

    private func drawIndicator(_ indicator: IconIndicatorState, in rect: NSRect) {
        guard indicator != .none else {
            return
        }

        let badgeRect = NSRect(x: rect.maxX - 5.5, y: rect.maxY - 5.5, width: 4.5, height: 4.5)
        indicator.color.setFill()
        NSBezierPath(ovalIn: badgeRect).fill()
    }

    private func configureObservers() {
        let metricsPublisher = UsageDataManager.shared.$metrics.map { _ in () }.eraseToAnyPublisher()
        let errorPublisher = UsageDataManager.shared.$lastError.map { _ in () }.eraseToAnyPublisher()
        let claudePublisher = Publishers.Merge(
            ClaudeCodeLocalService.shared.$hasAccess.map { _ in () }.eraseToAnyPublisher(),
            ClaudeCodeLocalService.shared.$lastError.map { _ in () }.eraseToAnyPublisher()
        ).eraseToAnyPublisher()
        let codexPublisher = Publishers.Merge(
            CodexCliLocalService.shared.$hasAccess.map { _ in () }.eraseToAnyPublisher(),
            CodexCliLocalService.shared.$lastError.map { _ in () }.eraseToAnyPublisher()
        ).eraseToAnyPublisher()
        let cursorPublisher = Publishers.Merge(
            CursorLocalService.shared.$hasAccess.map { _ in () }.eraseToAnyPublisher(),
            CursorLocalService.shared.$lastError.map { _ in () }.eraseToAnyPublisher()
        ).eraseToAnyPublisher()
        let defaultsPublisher = NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification).map { _ in () }.eraseToAnyPublisher()

        Publishers.MergeMany([
            metricsPublisher,
            errorPublisher,
            claudePublisher,
            codexPublisher,
            cursorPublisher,
            defaultsPublisher,
        ])
        .receive(on: RunLoop.main)
        .sink { [weak self] in
            self?.updateStatusItemAppearance()
        }
        .store(in: &cancellables)
    }

    private func updateStatusItemAppearance() {
        guard let button = statusItem?.button else {
            return
        }

        let image = createMenuBarIcon()
        image.isTemplate = UserDefaults.standard.string(forKey: "statusItemIconMode") == "template"
        button.image = image
        button.toolTip = buildTooltip()
    }

    private func enabledStatusSnapshots() -> [StatusIconSnapshot] {
        var snapshots: [StatusIconSnapshot] = []
        let summaries = enabledHealthSummaries()

        if UserDefaults.standard.object(forKey: "showCodexProvider") as? Bool ?? true {
            let summary = summaries.first(where: { $0.service == .codexCli })
            snapshots.append(snapshot(for: summary, defaultColor: NSColor(calibratedRed: 0.45, green: 0.82, blue: 0.85, alpha: 1.0)))
        }

        if UserDefaults.standard.object(forKey: "showClaudeProvider") as? Bool ?? true {
            let summary = summaries.first(where: { $0.service == .claudeCode })
            snapshots.append(snapshot(for: summary, defaultColor: NSColor(calibratedRed: 0.92, green: 0.63, blue: 0.49, alpha: 1.0)))
        }

        if UserDefaults.standard.object(forKey: "showCursorProvider") as? Bool ?? true {
            let summary = summaries.first(where: { $0.service == .cursor })
            snapshots.append(snapshot(for: summary, defaultColor: NSColor(calibratedRed: 0.54, green: 0.68, blue: 1.00, alpha: 1.0)))
        }

        return snapshots
    }

    private func snapshot(for summary: ProviderHealthSummary?, defaultColor: NSColor) -> StatusIconSnapshot {
        let metrics = summary?.metrics
        let primaryLimit = metrics?.sessionLimit ?? metrics?.weeklyLimit ?? metrics?.codeReviewLimit
        let remainingFraction = primaryLimit.map { max(0.08, min(1, $0.remaining / max($0.total, 1))) } ?? ((summary?.isConnected ?? false) ? 0.18 : 0.06)
        let baseColor = (summary?.isConnected ?? false) ? defaultColor : NSColor.labelColor.withAlphaComponent(0.35)
        let statusColor = (summary?.state).map { $0.menuBarColor(defaultColor: baseColor) } ?? baseColor

        return StatusIconSnapshot(
            title: summary?.title ?? "Provider",
            remainingFraction: remainingFraction,
            color: statusColor
        )
    }

    private func statusIndicatorState() -> IconIndicatorState {
        let summaries = enabledHealthSummaries()
        if summaries.contains(where: { $0.state == .error || $0.state == .critical }) {
            return .error
        }

        if summaries.contains(where: { $0.state == .warning }) {
            return .warning
        }

        if summaries.contains(where: { $0.state == .stale }) {
            return .stale
        }

        return .none
    }

    private func buildTooltip() -> String {
        let summaries = enabledHealthSummaries()
        var parts: [String] = []

        for summary in summaries {
            if let remaining = summary.remainingText {
                parts.append("\(summary.title) \(remaining)")
            } else if !summary.isConnected && summary.metrics == nil {
                parts.append("\(summary.title) not connected")
            } else if summary.state.isIssue {
                parts.append("\(summary.title) \(summary.state.label.lowercased())")
            } else {
                parts.append("\(summary.title) ready")
            }
        }

        if parts.isEmpty {
            return "MeterBar"
        }

        return parts.joined(separator: " • ")
    }

    private func enabledHealthSummaries() -> [ProviderHealthSummary] {
        var summaries: [ProviderHealthSummary] = []

        if UserDefaults.standard.object(forKey: "showCodexProvider") as? Bool ?? true {
            summaries.append(
                ProviderHealthSummary(
                    service: .codexCli,
                    title: "Codex",
                    metrics: UsageDataManager.shared.metrics[.codexCli],
                    isConnected: CodexCliLocalService.shared.hasAccess,
                    lastError: CodexCliLocalService.shared.lastError
                )
            )
        }

        if UserDefaults.standard.object(forKey: "showClaudeProvider") as? Bool ?? true {
            summaries.append(
                ProviderHealthSummary(
                    service: .claudeCode,
                    title: "Claude",
                    metrics: UsageDataManager.shared.metrics[.claudeCode],
                    isConnected: ClaudeCodeLocalService.shared.hasAccess,
                    lastError: ClaudeCodeLocalService.shared.lastError
                )
            )
        }

        if UserDefaults.standard.object(forKey: "showCursorProvider") as? Bool ?? true {
            summaries.append(
                ProviderHealthSummary(
                    service: .cursor,
                    title: "Cursor",
                    metrics: UsageDataManager.shared.metrics[.cursor],
                    isConnected: CursorLocalService.shared.hasAccess,
                    lastError: CursorLocalService.shared.lastError
                )
            )
        }

        return summaries
    }
}

private struct StatusIconSnapshot {
    let title: String
    let remainingFraction: Double
    let color: NSColor
}

private enum IconIndicatorState {
    case none
    case stale
    case warning
    case error

    var color: NSColor {
        switch self {
        case .none:
            return .clear
        case .stale, .warning:
            return .systemOrange
        case .error:
            return .systemRed
        }
    }
}

private extension ProviderHealthState {
    func menuBarColor(defaultColor: NSColor) -> NSColor {
        switch self {
        case .disconnected:
            return NSColor.labelColor.withAlphaComponent(0.35)
        case .healthy:
            return defaultColor
        case .stale, .warning:
            return .systemOrange
        case .critical, .error:
            return .systemRed
        }
    }
}
