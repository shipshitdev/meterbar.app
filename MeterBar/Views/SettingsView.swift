import SwiftUI
import AppKit

struct SettingsView: View {
    @StateObject private var authManager = AuthenticationManager.shared
    @StateObject private var dataManager = UsageDataManager.shared
    @StateObject private var claudeCodeService = ClaudeCodeLocalService.shared
    @StateObject private var cursorService = CursorLocalService.shared
    @StateObject private var costTracker = CostTracker.shared

    @State private var claudeAdminKey: String = ""
    @State private var openaiAdminKey: String = ""

    @State private var showingClaudeHelp = false
    @State private var showingOpenAIHelp = false

    var body: some View {
        Form {
            Section("Claude (Anthropic)") {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(authManager.isClaudeAuthenticated ? .green : .gray)
                    Text(authManager.isClaudeAuthenticated ? "Connected" : "Not Connected")
                }

                SecureField("Admin API Key (sk-ant-admin...)", text: $claudeAdminKey)
                    .textFieldStyle(.roundedBorder)

                HStack {
                    Button("Save") {
                        _ = authManager.setClaudeAdminKey(claudeAdminKey)
                        claudeAdminKey = ""
                    }
                    .disabled(claudeAdminKey.isEmpty)

                    Button("Remove") {
                        authManager.removeClaudeAdminKey()
                    }
                    .foregroundColor(.red)
                    .disabled(!authManager.isClaudeAuthenticated)
                }

                Button("How to get Admin API Key") {
                    showingClaudeHelp = true
                }
                .buttonStyle(.link)
            }

            Section("Claude Code (Pro/Max)") {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(claudeCodeService.hasAccess ? .green : .gray)
                    Text(claudeCodeService.hasAccess ? "Connected" : "Not Connected")
                }

                if claudeCodeService.hasAccess {
                    if let subscriptionType = claudeCodeService.subscriptionType {
                        HStack {
                            Text("Plan:")
                                .foregroundColor(.secondary)
                            Text(subscriptionType.capitalized)
                                .bold()
                        }
                        .font(.caption)
                    }

                    if let rateLimitTier = claudeCodeService.rateLimitTier {
                        HStack {
                            Text("Tier:")
                                .foregroundColor(.secondary)
                            Text(rateLimitTier.replacingOccurrences(of: "_", with: " ").capitalized)
                        }
                        .font(.caption)
                    }

                    Button("Refresh Status") {
                        claudeCodeService.checkAccess()
                        Task {
                            await dataManager.refreshAll()
                        }
                    }
                } else {
                    Text("Automatically reads Claude Code CLI credentials from macOS Keychain.")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text("Log in to Claude Code CLI first: run 'claude' in terminal")
                        .font(.caption)
                        .foregroundColor(.orange)

                    Button("Check Again") {
                        claudeCodeService.checkAccess()
                        if claudeCodeService.hasAccess {
                            Task {
                                await dataManager.refreshAll()
                            }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
            }

            Section("OpenAI") {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(authManager.isOpenAIAuthenticated ? .green : .gray)
                    Text(authManager.isOpenAIAuthenticated ? "Connected" : "Not Connected")
                }

                SecureField("Admin API Key", text: $openaiAdminKey)
                    .textFieldStyle(.roundedBorder)

                HStack {
                    Button("Save") {
                        _ = authManager.setOpenAIAdminKey(openaiAdminKey)
                        openaiAdminKey = ""
                    }
                    .disabled(openaiAdminKey.isEmpty)

                    Button("Remove") {
                        authManager.removeOpenAIAdminKey()
                    }
                    .foregroundColor(.red)
                    .disabled(!authManager.isOpenAIAuthenticated)
                }

                Button("How to get Admin API Key") {
                    showingOpenAIHelp = true
                }
                .buttonStyle(.link)
            }

            Section("Cursor") {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(cursorService.hasAccess ? .green : .gray)
                    Text(cursorService.hasAccess ? "Connected" : "Not Connected")
                }

                if cursorService.hasAccess {
                    if let subscriptionType = cursorService.subscriptionType {
                        HStack {
                            Text("Plan:")
                                .foregroundColor(.secondary)
                            Text(subscriptionType.capitalized)
                                .bold()
                        }
                        .font(.caption)
                    }

                    Button("Refresh Status") {
                        cursorService.checkAccess()
                        Task {
                            await dataManager.refreshAll()
                        }
                    }
                } else {
                    Text("Automatically reads Cursor IDE credentials from macOS Keychain.")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text("Log in to Cursor IDE first: open Cursor and sign in to your account")
                        .font(.caption)
                        .foregroundColor(.orange)

                    Button("Check Again") {
                        // Force a rescan of all possible database paths
                        cursorService.checkAccess(forceRescan: true)
                        if cursorService.hasAccess {
                            Task {
                                await dataManager.refreshAll()
                            }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
            }

            Section("Cost Tracking (Last 30 Days)") {
                if costTracker.isScanning {
                    HStack {
                        ProgressView()
                            .scaleEffect(0.7)
                        Text("Scanning sessions...")
                            .foregroundColor(.secondary)
                    }
                } else if let summary = costTracker.costSummary {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Total Cost")
                            Spacer()
                            Text(summary.formattedTotalCost)
                                .bold()
                                .foregroundColor(.primary)
                        }

                        HStack {
                            Text("Daily Average")
                            Spacer()
                            Text(summary.formattedDailyCost)
                                .foregroundColor(.secondary)
                        }

                        Divider()

                        ForEach(summary.costs) { cost in
                            HStack {
                                Image(systemName: cost.provider.iconName)
                                    .foregroundColor(.secondary)
                                Text(cost.provider.displayName)
                                Spacer()
                                VStack(alignment: .trailing) {
                                    Text(cost.formattedCost)
                                        .font(.caption)
                                    Text("\(cost.formattedTokens) tokens")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }

                        if let lastScan = costTracker.lastScanDate {
                            Text("Last scanned: \(lastScan, style: .relative) ago")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                } else {
                    Text("No cost data available")
                        .foregroundColor(.secondary)
                }

                Button("Scan Local Sessions") {
                    Task {
                        await costTracker.scanCosts(days: 30)
                    }
                }
                .disabled(costTracker.isScanning)
            }

            Section("Refresh") {
                Picker("Auto-refresh interval", selection: Binding(
                    get: { dataManager.refreshInterval },
                    set: { dataManager.refreshInterval = $0 }
                )) {
                    ForEach(RefreshInterval.allCases) { interval in
                        Text(interval.displayName).tag(interval)
                    }
                }

                Button("Refresh Now") {
                    Task {
                        await dataManager.refreshAll()
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 450, minHeight: 500)
        .sheet(isPresented: $showingClaudeHelp) {
            ClaudeHelpView()
        }
        .sheet(isPresented: $showingOpenAIHelp) {
            OpenAIHelpView()
        }
    }
}

struct ClaudeHelpView: View {
    @Environment(\.dismiss) var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("How to get Claude Admin API Key")
                .font(.title2)
                .bold()

            Text("The Usage API requires an Admin API key, which is different from a regular API key.")
                .foregroundColor(.secondary)

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("1. Go to the Claude Console")
                Text("2. Navigate to Settings → Admin Keys")
                Text("3. Click 'Create Admin Key'")
                Text("4. Copy the key (starts with sk-ant-admin...)")
                Text("5. Paste it in the field above")
            }

            Divider()

            Text("Note: You must be an organization admin to create Admin API keys. Individual accounts cannot access the Usage API.")
                .font(.caption)
                .foregroundColor(.orange)

            HStack {
                Button("Open Claude Console") {
                    if let url = URL(string: "https://console.anthropic.com/settings/admin-keys") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .buttonStyle(.borderedProminent)

                Spacer()

                Button("Close") {
                    dismiss()
                }
            }
        }
        .padding()
        .frame(width: 500, height: 400)
    }
}

struct OpenAIHelpView: View {
    @Environment(\.dismiss) var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("How to get OpenAI Admin API Key")
                .font(.title2)
                .bold()

            Text("The Usage API requires an Admin key from your organization settings.")
                .foregroundColor(.secondary)

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("1. Go to OpenAI Platform")
                Text("2. Navigate to Settings → Organization → Admin Keys")
                Text("3. Click 'Create new admin key'")
                Text("4. Copy the key")
                Text("5. Paste it in the field above")
            }

            Divider()

            Text("Note: You must be an organization owner or admin to create Admin keys.")
                .font(.caption)
                .foregroundColor(.orange)

            HStack {
                Button("Open OpenAI Settings") {
                    if let url = URL(string: "https://platform.openai.com/settings/organization/admin-keys") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .buttonStyle(.borderedProminent)

                Spacer()

                Button("Close") {
                    dismiss()
                }
            }
        }
        .padding()
        .frame(width: 500, height: 400)
    }
}
