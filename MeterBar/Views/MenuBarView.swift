import AppKit
import SwiftUI

private enum MenuTab: String, Hashable {
    case overview
    case codex
    case claude
    case cursor

    var title: String {
        switch self {
        case .overview:
            return "Overview"
        case .codex:
            return "Codex"
        case .claude:
            return "Claude"
        case .cursor:
            return "Cursor"
        }
    }
}

private struct ServiceSnapshot: Identifiable {
    let service: ServiceType
    let title: String
    let subtitle: String
    let accent: Color
    let summary: String?
    let metrics: UsageMetrics?
    let isConnected: Bool
    let actionLabel: String
    let dashboardURL: URL?
    let health: ProviderHealthSummary

    var id: ServiceType { service }
}

struct MenuBarView: View {
    @StateObject private var dataManager = UsageDataManager.shared
    @StateObject private var claudeCodeService = ClaudeCodeLocalService.shared
    @StateObject private var codexCliService = CodexCliLocalService.shared
    @StateObject private var cursorService = CursorLocalService.shared
    @StateObject private var costTracker = CostTracker.shared

    @AppStorage("showClaudeProvider") private var showClaudeProvider: Bool = true
    @AppStorage("showCodexProvider") private var showCodexProvider: Bool = true
    @AppStorage("showCursorProvider") private var showCursorProvider: Bool = true
    @AppStorage("showOverviewTab") private var showOverviewTab: Bool = true
    @AppStorage("selectedMenuTab") private var selectedTabRaw: String = MenuTab.overview.rawValue

    @State private var selectedTab: MenuTab = .overview

    private let panelBackground = Color(nsColor: NSColor(calibratedRed: 0.10, green: 0.11, blue: 0.14, alpha: 0.98))
    private let cardBackground = Color(nsColor: NSColor(calibratedRed: 0.15, green: 0.16, blue: 0.20, alpha: 1.0))
    private let dividerColor = Color.white.opacity(0.08)

    private var claudeSnapshot: ServiceSnapshot {
        let plan = claudeCodeService.subscriptionType?.capitalized ?? "CLI account"
        let metrics = dataManager.metrics[.claudeCode]
        return ServiceSnapshot(
            service: .claudeCode,
            title: "Claude",
            subtitle: plan,
            accent: .meterClaudeAccent,
            summary: claudeCodeService.rateLimitTier?.replacingOccurrences(of: "_", with: " ").capitalized,
            metrics: metrics,
            isConnected: claudeCodeService.hasAccess,
            actionLabel: "Run `claude login`",
            dashboardURL: URL(string: "https://claude.ai"),
            health: ProviderHealthSummary(
                service: .claudeCode,
                title: "Claude",
                metrics: metrics,
                isConnected: claudeCodeService.hasAccess,
                lastError: claudeCodeService.lastError
            )
        )
    }

    private var codexSnapshot: ServiceSnapshot {
        let plan = codexCliService.subscriptionType?.replacingOccurrences(of: "_", with: " ").capitalized ?? "CLI account"
        let metrics = dataManager.metrics[.codexCli]
        return ServiceSnapshot(
            service: .codexCli,
            title: "Codex",
            subtitle: plan,
            accent: .meterCodexAccent,
            summary: nil,
            metrics: metrics,
            isConnected: codexCliService.hasAccess,
            actionLabel: "Run `codex login`",
            dashboardURL: URL(string: "https://chatgpt.com"),
            health: ProviderHealthSummary(
                service: .codexCli,
                title: "Codex",
                metrics: metrics,
                isConnected: codexCliService.hasAccess,
                lastError: codexCliService.lastError
            )
        )
    }

    private var cursorSnapshot: ServiceSnapshot {
        let plan = cursorService.subscriptionType?.replacingOccurrences(of: "_", with: " ").capitalized ?? "Cursor account"
        let metrics = dataManager.metrics[.cursor]
        return ServiceSnapshot(
            service: .cursor,
            title: "Cursor",
            subtitle: plan,
            accent: .meterCursorAccent,
            summary: "Local database sync",
            metrics: metrics,
            isConnected: cursorService.hasAccess,
            actionLabel: "Open Cursor and sign in",
            dashboardURL: URL(string: "https://cursor.com/dashboard"),
            health: ProviderHealthSummary(
                service: .cursor,
                title: "Cursor",
                metrics: metrics,
                isConnected: cursorService.hasAccess,
                lastError: cursorService.lastError
            )
        )
    }

    private var availableTabs: [MenuTab] {
        var tabs: [MenuTab] = []
        if showOverviewTab || (!showCodexProvider && !showClaudeProvider && !showCursorProvider) {
            tabs.append(.overview)
        }
        if showCodexProvider {
            tabs.append(.codex)
        }
        if showClaudeProvider {
            tabs.append(.claude)
        }
        if showCursorProvider, (cursorSnapshot.isConnected || cursorSnapshot.metrics != nil) {
            tabs.append(.cursor)
        }
        return tabs
    }

    private var issueSummaries: [ProviderHealthSummary] {
        enabledSnapshots
            .map(\.health)
            .filter(\.shouldShowBanner)
            .sorted { $0.state > $1.state }
    }

    private var enabledSnapshots: [ServiceSnapshot] {
        var snapshots: [ServiceSnapshot] = []
        if showCodexProvider {
            snapshots.append(codexSnapshot)
        }
        if showClaudeProvider {
            snapshots.append(claudeSnapshot)
        }
        if showCursorProvider {
            snapshots.append(cursorSnapshot)
        }
        return snapshots
    }

    private var anyConnectedProvider: Bool {
        enabledSnapshots.contains(where: \.isConnected)
    }

    private var lastUpdatedText: String {
        let dates = [codexSnapshot.metrics?.lastUpdated, claudeSnapshot.metrics?.lastUpdated, cursorSnapshot.metrics?.lastUpdated].compactMap { $0 }
        guard let latest = dates.max() else {
            return "No data yet"
        }
        return relativeTimestamp(latest)
    }

    var body: some View {
        ZStack {
            panelBackground
                .ignoresSafeArea()

            VStack(spacing: 0) {
                header
                tabBar

                Divider()
                    .overlay(dividerColor)

                content

                Divider()
                    .overlay(dividerColor)

                footer
            }
        }
        .frame(width: 432, height: 560)
        .preferredColorScheme(.dark)
        .onAppear {
            selectedTab = MenuTab(rawValue: selectedTabRaw) ?? .overview
            normalizeSelectedTab()
            if dataManager.metrics.isEmpty {
                Task {
                    await dataManager.refreshAll()
                }
            }
        }
        .onChange(of: selectedTab) { newValue in
            selectedTabRaw = newValue.rawValue
        }
        .task(id: availableTabs.map(\.rawValue).joined(separator: ",")) {
            normalizeSelectedTab()
        }
        .task(id: selectedTab) {
            if selectedTab == .claude || selectedTab == .codex {
                guard costTracker.costSummary == nil, !costTracker.isScanning else {
                    return
                }
                await costTracker.scanCosts(days: 30)
            }
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("MeterBar")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(.white)
                Text(lastUpdatedText)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button(action: refreshAll) {
                Image(systemName: dataManager.isLoading ? "arrow.triangle.2.circlepath.circle.fill" : "arrow.clockwise")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.86))
            }
            .buttonStyle(.plain)
            .disabled(dataManager.isLoading)
            .help("Refresh usage")
        }
        .padding(.horizontal, 18)
        .padding(.top, 16)
        .padding(.bottom, 14)
    }

    private var tabBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(availableTabs, id: \.self) { tab in
                    Button(action: {
                        selectedTab = tab
                    }) {
                        VStack(spacing: 6) {
                            HStack(spacing: 6) {
                                Image(systemName: iconName(for: tab))
                                    .font(.system(size: 11, weight: .semibold))
                                Text(tab.title)
                                    .font(.system(size: 13, weight: .semibold))
                            }
                            .foregroundStyle(selectedTab == tab ? .white : Color.white.opacity(0.68))
                            .padding(.horizontal, 14)
                            .padding(.top, 9)

                            Capsule()
                                .fill(accentColor(for: tab))
                                .frame(height: 3)
                                .opacity(selectedTab == tab ? 1 : 0.65)
                                .padding(.horizontal, 12)
                        }
                        .padding(.bottom, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(selectedTab == tab ? Color.white.opacity(0.08) : Color.clear)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 10)
        }
    }

    @ViewBuilder
    private var content: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 14) {
                switch selectedTab {
                case .overview:
                    overviewTab
                case .codex:
                    ServiceDetailView(
                        snapshot: codexSnapshot,
                        primaryAction: refreshCodex,
                        secondaryAction: openDashboard(for: codexSnapshot),
                        supplemental: AnyView(codexCreditsCard)
                    )
                case .claude:
                    ServiceDetailView(
                        snapshot: claudeSnapshot,
                        primaryAction: refreshClaude,
                        secondaryAction: openDashboard(for: claudeSnapshot),
                        supplemental: AnyView(claudeCostCard)
                    )
                case .cursor:
                    ServiceDetailView(
                        snapshot: cursorSnapshot,
                        primaryAction: refreshCursor,
                        secondaryAction: openDashboard(for: cursorSnapshot)
                    )
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
        }
    }

    private var overviewTab: some View {
        VStack(spacing: 14) {
            if enabledSnapshots.isEmpty {
                InlineMessageCard(
                    title: "No providers enabled",
                    message: "Turn providers back on in Settings to show them in the menu bar."
                )
            } else if !anyConnectedProvider {
                onboardingCard
            }

            ForEach(issueSummaries) { summary in
                ProviderIssueCard(summary: summary)
            }

            if showCodexProvider {
                SummaryServiceCard(snapshot: codexSnapshot, action: refreshCodex)
            }

            if showClaudeProvider {
                SummaryServiceCard(snapshot: claudeSnapshot, action: refreshClaude)
            }

            if showCursorProvider, (cursorSnapshot.isConnected || cursorSnapshot.metrics != nil || !anyConnectedProvider) {
                SummaryServiceCard(snapshot: cursorSnapshot, action: refreshCursor)
            }

            if let error = dataManager.lastError {
                InlineMessageCard(
                    title: "Latest issue",
                    message: error.localizedDescription
                )
            }
        }
    }

    private var onboardingCard: some View {
        InlineMessageCard(
            title: "Connect your local tools",
            message: "Run `codex login`, run `claude`, and sign into Cursor. MeterBar reads those local credentials directly and avoids browser-cookie import."
        )
    }

    @ViewBuilder
    private var claudeCostCard: some View {
        if costTracker.isScanning {
            InlineMessageCard(title: "Scanning local sessions", message: "Estimating Claude Code cost from `~/.claude/projects`.")
        } else if let summary = costTracker.costSummary,
                  let claudeCost = summary.costs.first(where: { $0.provider == .claudeCode }) {
            CostSummaryCard(cost: claudeCost, total: summary)
        }
    }

    @ViewBuilder
    private var codexCreditsCard: some View {
        if costTracker.isScanning, costTracker.codexUsageSummary == nil {
            InlineMessageCard(title: "Scanning local sessions", message: "Reading recent Codex session files under `~/.codex`.")
        }

        if let credits = codexCliService.credits {
            CodexCreditsCard(credits: credits)
        }

        if let usageSummary = costTracker.codexUsageSummary {
            CodexLocalUsageCard(summary: usageSummary)
        }
    }

    private var footer: some View {
        HStack(spacing: 14) {
            FooterButton(title: "Settings…", action: openSettings)
            FooterButton(title: "About MeterBar", action: openAboutPanel)

            Spacer()

            Button("Quit", action: terminate)
                .buttonStyle(.plain)
                .foregroundStyle(Color.white.opacity(0.84))
        }
        .font(.system(size: 13, weight: .medium))
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }

    private func iconName(for tab: MenuTab) -> String {
        switch tab {
        case .overview:
            return "square.grid.2x2"
        case .codex:
            return "terminal"
        case .claude:
            return "sparkles"
        case .cursor:
            return "cursorarrow.click"
        }
    }

    private func accentColor(for tab: MenuTab) -> Color {
        switch tab {
        case .overview:
            return .meterOverviewAccent
        case .codex:
            return .meterCodexAccent
        case .claude:
            return .meterClaudeAccent
        case .cursor:
            return .meterCursorAccent
        }
    }

    private func refreshAll() {
        Task {
            await dataManager.refreshAll()
        }
    }

    private func refreshClaude() {
        claudeCodeService.checkAccess(forceRefresh: true)
        Task {
            await dataManager.refresh(service: .claudeCode)
            await costTracker.scanCosts(days: 30)
        }
    }

    private func refreshCodex() {
        codexCliService.checkAccess()
        Task {
            await dataManager.refresh(service: .codexCli)
            await costTracker.scanCosts(days: 30)
        }
    }

    private func refreshCursor() {
        cursorService.checkAccess(forceRescan: true)
        Task {
            await dataManager.refresh(service: .cursor)
        }
    }

    private func openDashboard(for snapshot: ServiceSnapshot) -> (() -> Void)? {
        guard let url = snapshot.dashboardURL else {
            return nil
        }
        return {
            NSWorkspace.shared.open(url)
        }
    }

    private func openSettings() {
        let selector = NSSelectorFromString("showSettingsWindow:")
        if NSApp.sendAction(selector, to: nil, from: nil) {
            return
        }
        NSApp.sendAction(NSSelectorFromString("showPreferencesWindow:"), to: nil, from: nil)
    }

    private func openAboutPanel() {
        NSApp.orderFrontStandardAboutPanel(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func terminate() {
        NSApplication.shared.terminate(nil)
    }

    private func relativeTimestamp(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return "Updated \(formatter.localizedString(for: date, relativeTo: Date()))"
    }

    private func normalizeSelectedTab() {
        guard !availableTabs.isEmpty else {
            selectedTab = .overview
            return
        }

        if !availableTabs.contains(selectedTab) {
            selectedTab = availableTabs.first ?? .overview
        }
    }
}

private struct SummaryServiceCard: View {
    let snapshot: ServiceSnapshot
    let action: () -> Void

    private let cardBackground = Color(nsColor: NSColor(calibratedRed: 0.15, green: 0.16, blue: 0.20, alpha: 1.0))

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            if snapshot.health.shouldShowBanner {
                HealthBanner(summary: snapshot.health)
            }

            if snapshot.isConnected, let metrics = snapshot.metrics {
                VStack(spacing: 12) {
                    ForEach(metricDescriptors(for: metrics)) { descriptor in
                        UsageMeterRow(
                            descriptor: descriptor,
                            accent: snapshot.accent
                        )
                    }
                }
            } else {
                disconnectedState
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        )
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(snapshot.title)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)

                    if snapshot.isConnected {
                        Text(snapshot.subtitle)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color.white.opacity(0.68))
                    }

                    StatusBadge(summary: snapshot.health)
                }

                if let metrics = snapshot.metrics {
                    Text("Updated \(relativeTimestamp(metrics.lastUpdated))")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                } else if let summary = snapshot.summary {
                    Text(summary)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Button(action: action) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.78))
                    .frame(width: 28, height: 28)
                    .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }

    private var disconnectedState: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(snapshot.actionLabel)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.78))

            Text(snapshot.health.message)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func metricDescriptors(for metrics: UsageMetrics) -> [MetricDescriptor] {
        var descriptors: [MetricDescriptor] = []

        if let session = metrics.sessionLimit {
            descriptors.append(MetricDescriptor(title: sessionTitle(for: metrics.service), limit: session))
        }

        if let weekly = metrics.weeklyLimit {
            descriptors.append(MetricDescriptor(title: weeklyTitle(for: metrics.service), limit: weekly))
        }

        if let codeReview = metrics.codeReviewLimit {
            descriptors.append(MetricDescriptor(title: codeReviewTitle(for: metrics.service), limit: codeReview))
        }

        return descriptors
    }

    private func sessionTitle(for service: ServiceType) -> String {
        switch service {
        case .claudeCode:
            return "Session"
        case .codexCli:
            return "Session"
        case .cursor:
            return "On-demand"
        case .claude, .openai:
            return "Current"
        }
    }

    private func weeklyTitle(for service: ServiceType) -> String {
        switch service {
        case .claudeCode, .codexCli:
            return "Weekly"
        case .cursor:
            return "Monthly"
        case .claude, .openai:
            return "Weekly"
        }
    }

    private func codeReviewTitle(for service: ServiceType) -> String {
        switch service {
        case .claudeCode:
            return "Sonnet"
        case .codexCli:
            return "Code Review"
        case .cursor, .claude, .openai:
            return "Extra"
        }
    }

    private func relativeTimestamp(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

private struct ServiceDetailView: View {
    let snapshot: ServiceSnapshot
    let primaryAction: () -> Void
    let secondaryAction: (() -> Void)?
    var supplemental: AnyView? = nil

    private let cardBackground = Color(nsColor: NSColor(calibratedRed: 0.15, green: 0.16, blue: 0.20, alpha: 1.0))

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            hero

            if snapshot.health.shouldShowBanner {
                HealthBanner(summary: snapshot.health)
            }

            if snapshot.isConnected, let metrics = snapshot.metrics {
                meterList(metrics: metrics)
            } else {
                InlineMessageCard(
                    title: "Not connected",
                    message: "\(snapshot.actionLabel). \(snapshot.health.message)"
                )
            }

            if let supplemental {
                supplemental
            }

            actions
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        )
    }

    private var hero: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(snapshot.title)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(.white)

                HStack(spacing: 8) {
                    Text(snapshot.subtitle)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.68))

                    if let summary = snapshot.summary, !summary.isEmpty {
                        Text(summary)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }

                if let metrics = snapshot.metrics {
                    Text("Updated \(relativeTimestamp(metrics.lastUpdated))")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            StatusBadge(summary: snapshot.health, prominent: true)
        }
    }

    private func meterList(metrics: UsageMetrics) -> some View {
        VStack(spacing: 14) {
            ForEach(metricDescriptors(for: metrics)) { descriptor in
                UsageMeterRow(
                    descriptor: descriptor,
                    accent: snapshot.accent,
                    emphasized: true
                )
            }
        }
    }

    private var actions: some View {
        HStack(spacing: 10) {
            ActionButton(title: "Refresh", icon: "arrow.clockwise", accent: snapshot.accent, action: primaryAction)

            if let secondaryAction {
                ActionButton(title: "Dashboard", icon: "globe", accent: Color.white.opacity(0.18), foreground: .white, action: secondaryAction)
            }
        }
    }

    private func metricDescriptors(for metrics: UsageMetrics) -> [MetricDescriptor] {
        var descriptors: [MetricDescriptor] = []

        if let session = metrics.sessionLimit {
            descriptors.append(MetricDescriptor(title: sessionTitle(for: snapshot.service), limit: session))
        }

        if let weekly = metrics.weeklyLimit {
            descriptors.append(MetricDescriptor(title: weeklyTitle(for: snapshot.service), limit: weekly))
        }

        if let codeReview = metrics.codeReviewLimit {
            descriptors.append(MetricDescriptor(title: codeReviewTitle(for: snapshot.service), limit: codeReview))
        }

        return descriptors
    }

    private func sessionTitle(for service: ServiceType) -> String {
        switch service {
        case .claudeCode, .codexCli:
            return "Session"
        case .cursor:
            return "On-demand"
        case .claude, .openai:
            return "Current"
        }
    }

    private func weeklyTitle(for service: ServiceType) -> String {
        switch service {
        case .claudeCode, .codexCli:
            return "Weekly"
        case .cursor:
            return "Monthly"
        case .claude, .openai:
            return "Weekly"
        }
    }

    private func codeReviewTitle(for service: ServiceType) -> String {
        switch service {
        case .claudeCode:
            return "Sonnet"
        case .codexCli:
            return "Code Review"
        case .cursor, .claude, .openai:
            return "Extra"
        }
    }

    private func relativeTimestamp(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

private struct MetricDescriptor: Identifiable {
    let id = UUID()
    let title: String
    let limit: UsageLimit
}

private struct UsageMeterRow: View {
    let descriptor: MetricDescriptor
    let accent: Color
    var emphasized: Bool = false

    private var remainingPercentage: Int {
        Int(round(max(0, 100 - descriptor.limit.percentage)))
    }

    private var remainingFraction: Double {
        max(0, min(1, descriptor.limit.remaining / max(descriptor.limit.total, 1)))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: emphasized ? 8 : 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(descriptor.title)
                    .font(.system(size: emphasized ? 17 : 15, weight: .semibold))
                    .foregroundStyle(.white)

                Spacer()

                Text("\(remainingPercentage)% left")
                    .font(.system(size: emphasized ? 15 : 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.86))
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.10))
                        .frame(height: emphasized ? 8 : 6)

                    Capsule()
                        .fill(accent)
                        .frame(width: max(18, proxy.size.width * remainingFraction), height: emphasized ? 8 : 6)
                }
            }
            .frame(height: emphasized ? 8 : 6)

            HStack(spacing: 8) {
                if descriptor.limit.percentage > 0 {
                    Text("\(Int(round(descriptor.limit.percentage)))% used")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if let resetTime = descriptor.limit.resetTime {
                    Text(countdownText(resetTime))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, emphasized ? 2 : 0)
    }

    private func countdownText(_ date: Date) -> String {
        guard date > Date() else {
            return "Resetting now"
        }

        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = date.timeIntervalSinceNow > 86_400 ? [.day, .hour] : [.hour, .minute]
        formatter.unitsStyle = .abbreviated
        formatter.maximumUnitCount = 2

        if let formatted = formatter.string(from: Date(), to: date) {
            return "Resets in \(formatted)"
        }

        return "Resets soon"
    }
}

private struct InlineMessageCard: View {
    let title: String
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
            Text(message)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.05))
        )
    }
}

private struct ProviderIssueCard: View {
    let summary: ProviderHealthSummary

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: summary.state.iconName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(summary.state.tintColor)
                .frame(width: 18, height: 18)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(summary.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                    StatusBadge(summary: summary)
                }

                Text(summary.message)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.05))
        )
    }
}

private struct HealthBanner: View {
    let summary: ProviderHealthSummary

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: summary.state.iconName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(summary.state.tintColor)
                .frame(width: 16, height: 16)

            Text(summary.message)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer()
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(summary.state.tintColor.opacity(0.12))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(summary.state.tintColor.opacity(0.20), lineWidth: 1)
        )
    }
}

private struct CostSummaryCard: View {
    let cost: TokenCost
    let total: CostSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Local Cost Estimate")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)

            HStack {
                summaryItem(title: "30 days", value: cost.formattedCost)
                Spacer()
                summaryItem(title: "Tokens", value: cost.formattedTokens)
                Spacer()
                summaryItem(title: "Avg/day", value: total.formattedDailyCost)
            }

            Text("Based on Claude Code session files already on disk. No extra network requests.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.05))
        )
    }

    private func summaryItem(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
        }
    }
}

private struct CodexCreditsCard: View {
    let credits: Credits

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Codex Credits")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)

            HStack {
                creditItem(title: "Credits", value: credits.unlimited ? "Unlimited" : (credits.hasCredits ? "Available" : "None"))
                Spacer()
                if let balance = credits.balance {
                    creditItem(title: "Balance", value: String(format: "%.0f", balance))
                }
                Spacer()
                if let approxCloud = credits.approxCloudMessages {
                    creditItem(title: "Cloud msgs", value: "\(approxCloud)")
                }
            }

            if let approxLocal = credits.approxLocalMessages {
                Text("Approx. local messages: \(approxLocal)")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.05))
        )
    }

    private func creditItem(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
        }
    }
}

private struct CodexLocalUsageCard: View {
    let summary: LocalUsageSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Local Session Usage")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)

            HStack {
                summaryItem(title: "30 days", value: summary.formattedTokens)
                Spacer()
                summaryItem(title: "Sessions", value: "\(summary.sessionCount)")
                Spacer()
                summaryItem(title: "Cached input", value: formatted(summary.cachedInputTokens))
            }

            Text("Derived from the last token-count event in each Codex session file under `~/.codex`.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.05))
        )
    }

    private func summaryItem(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
        }
    }

    private func formatted(_ value: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }
}

private struct ActionButton: View {
    let title: String
    let icon: String
    let accent: Color
    var foreground: Color = .black
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
            }
            .foregroundStyle(foreground)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(accent, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

private struct StatusBadge: View {
    let summary: ProviderHealthSummary
    var prominent: Bool = false

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: summary.state.iconName)
                .font(.system(size: prominent ? 11 : 10, weight: .semibold))
            Text(summary.state.label)
                .font(.system(size: prominent ? 11 : 10, weight: .semibold))
        }
        .foregroundStyle(prominent ? .white : summary.state.tintColor)
        .padding(.horizontal, prominent ? 10 : 8)
        .padding(.vertical, prominent ? 6 : 4)
        .background(
            Capsule(style: .continuous)
                .fill(prominent ? summary.state.tintColor.opacity(0.18) : summary.state.tintColor.opacity(0.12))
        )
        .overlay(
            Capsule(style: .continuous)
                .stroke(summary.state.tintColor.opacity(0.22), lineWidth: 1)
        )
    }
}

private struct FooterButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(title, action: action)
            .buttonStyle(.plain)
            .foregroundStyle(Color.white.opacity(0.84))
    }
}

private extension Color {
    static let meterOverviewAccent = Color(nsColor: NSColor(calibratedRed: 0.33, green: 0.58, blue: 1.00, alpha: 1.0))
    static let meterCodexAccent = Color(nsColor: NSColor(calibratedRed: 0.45, green: 0.82, blue: 0.85, alpha: 1.0))
    static let meterClaudeAccent = Color(nsColor: NSColor(calibratedRed: 0.92, green: 0.63, blue: 0.49, alpha: 1.0))
    static let meterCursorAccent = Color(nsColor: NSColor(calibratedRed: 0.54, green: 0.68, blue: 1.00, alpha: 1.0))
}

private extension ProviderHealthState {
    var tintColor: Color {
        switch self {
        case .disconnected:
            return Color.white.opacity(0.45)
        case .healthy:
            return Color.meterCodexAccent
        case .stale, .warning:
            return .orange
        case .critical, .error:
            return .red
        }
    }

    var iconName: String {
        switch self {
        case .disconnected:
            return "bolt.slash"
        case .healthy:
            return "checkmark.circle.fill"
        case .stale:
            return "clock.badge.exclamationmark"
        case .warning:
            return "exclamationmark.triangle.fill"
        case .critical:
            return "xmark.octagon.fill"
        case .error:
            return "exclamationmark.circle.fill"
        }
    }
}
