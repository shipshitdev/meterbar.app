# Quota Guard

![Project Type](https://img.shields.io/badge/Project-App-blue)
![License](https://img.shields.io/badge/license-MIT-green)

An open-source macOS widget (WidgetKit + menu bar) that tracks account-level usage limits from Claude, OpenAI, and Cursor dashboards.

## Features

- **WidgetKit Widgets**: Display usage metrics in Notification Center
- **Menu Bar App**: Quick access to usage data with dropdown
- **Multi-Service Support**: Track Claude, Codex, and Cursor usage
- **Secure Authentication**: Session keys stored in macOS Keychain
- **Real-time Updates**: Background refresh with smart scheduling
- **Notifications**: Alerts when approaching limits

## Installation

### Prerequisites

- macOS 13.0 or later
- Xcode 15.0 or later
- Swift 5.9 or later

### Build from Source

1. Clone the repository:
   ```bash
   git clone <repo-url>
   cd apps/ai-usage-tracker
   ```

2. Open in Xcode:
   ```bash
   open QuotaGuard.xcodeproj
   ```

3. Build and run:
   - Select the `QuotaGuard` scheme
   - Press Cmd+R to build and run

## Setup

### Claude Authentication

1. Open Safari and navigate to `claude.ai`
2. Log in to your account
3. Open Developer Tools (Cmd+Option+I)
4. Go to Storage > Cookies > claude.ai
5. Find the session key cookie
6. Copy the value and paste it in the app settings

### Codex Authentication

1. Open Safari and navigate to Codex dashboard
2. Log in to your account
3. The app will extract cookies automatically (requires Safari)

### Cursor Authentication

1. Get your API key from Cursor settings
2. Enter it in the app settings
3. The app will store it securely in Keychain

## Usage

### Widget Setup

1. Add the widget to Notification Center:
   - Click the date/time in the menu bar
   - Click "Edit Widgets"
   - Search for "Quota Guard"
   - Select your preferred size (small, medium, or large)

2. Configure the widget:
   - Right-click the widget
   - Select "Edit Widget"
   - Choose which services to display

### Menu Bar

- Click the menu bar icon to see usage metrics
- Color-coded status:
  - Green: Plenty of usage remaining
  - Yellow: Approaching limit
  - Red: Near or at limit

## Architecture

- **SwiftUI**: Modern declarative UI framework
- **WidgetKit**: Native macOS widgets
- **Combine**: Reactive data flow
- **Keychain**: Secure credential storage

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

## License

MIT License - see [LICENSE](LICENSE) for details.

## Privacy

- All credentials stored locally in macOS Keychain
- No data sent to external servers
- All processing happens on-device
- Open source for transparency

