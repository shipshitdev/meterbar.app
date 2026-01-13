import SwiftUI
import UserNotifications

@main
struct MeterBarApp: App {
    @StateObject private var dataManager = UsageDataManager.shared
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    init() {
        print("═══════════════════════════════════════")
        print("🎯 MeterBar: App Initializing")
        print("═══════════════════════════════════════")
    }
    
    var body: some Scene {
        Settings {
            SettingsView()
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        print("🚀 MeterBar: Application did finish launching")
        
        // Create menu bar item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        guard let button = statusItem?.button else {
            print("❌ Failed to create status item button")
            return
        }
        
        // Set up the menu bar icon
        if let image = NSImage(systemSymbolName: "gauge.with.needle.fill", accessibilityDescription: "MeterBar") {
            image.isTemplate = true // Important for dark mode support
            button.image = image
            print("✅ Menu bar icon set successfully")
        } else {
            print("❌ Failed to create system symbol image")
            // Fallback to a simple text or emoji
            button.title = "📊"
        }
        
        button.action = #selector(togglePopover)
        button.target = self
        button.toolTip = "MeterBar"
        
        // Create popover
        popover = NSPopover()
        popover?.contentSize = NSSize(width: 320, height: 500)
        popover?.behavior = .transient
        popover?.contentViewController = NSHostingController(rootView: MenuBarView())

        // Setup notifications (also handles initial data refresh)
        setupNotifications()
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
    
    private func setupNotifications() {
        // Check current authorization status first
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            switch settings.authorizationStatus {
            case .notDetermined:
                // Request permission only if not yet determined
                UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
                    if let error = error {
                        print("Notification permission error: \(error)")
                    } else if !granted {
                        print("Notification permission denied by user")
                    }
                }
            case .denied:
                print("Notification permission was previously denied. User can enable in System Settings.")
            case .authorized, .provisional, .ephemeral:
                // Already authorized, no action needed
                break
            @unknown default:
                break
            }
        }
        
        // Monitor usage and send notifications
        Task {
            await monitorUsage()
        }
    }
    
    @MainActor
    private func monitorUsage() async {
        // Initial refresh on app launch
        await UsageDataManager.shared.refreshAll()

        // Check for approaching limits periodically
        // Note: UsageDataManager handles its own 15-minute auto-refresh
        // This loop just checks metrics for notification purposes
        while true {
            for (_, metrics) in UsageDataManager.shared.metrics {
                checkAndNotify(metrics: metrics)
            }

            // Wait 5 minutes before next notification check
            try? await Task.sleep(nanoseconds: 5 * 60 * 1_000_000_000)
        }
    }
    
    private func checkAndNotify(metrics: UsageMetrics) {
        let limits = [metrics.sessionLimit, metrics.weeklyLimit, metrics.codeReviewLimit].compactMap { $0 }
        
        for limit in limits {
            if limit.percentage >= 90 && limit.percentage < 100 {
                sendNotification(
                    title: "\(metrics.service.displayName) Usage Warning",
                    body: "You're at \(Int(limit.percentage))% of your limit"
                )
            } else if limit.percentage >= 100 {
                sendNotification(
                    title: "\(metrics.service.displayName) Limit Reached",
                    body: "You've reached your usage limit"
                )
            }
        }
    }
    
    private func sendNotification(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        
        UNUserNotificationCenter.current().add(request)
    }
}

