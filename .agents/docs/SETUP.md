# Setup Guide

This guide will help you set up MeterBar on your Mac.

## Prerequisites

- macOS 13.0 (Ventura) or later
- Xcode 15.0 or later
- Swift 5.9 or later

### Development Tools (Recommended)

Install SwiftLint and SwiftFormat for code quality:

```bash
brew install swiftlint swiftformat
```

These tools help maintain consistent code style across the project.

## Building from Source

### 1. Clone the Repository

```bash
git clone <repository-url>
cd apps/ai-usage-tracker
```

### 2. Open in Xcode

```bash
open MeterBar.xcodeproj
```

If you don't have an Xcode project yet, you can create one:

```bash
# Create Xcode project from Package.swift
swift package generate-xcodeproj
```

### 3. Configure the Project

1. Select the `MeterBar` target
2. Go to Signing & Capabilities
3. Add your development team
4. Enable App Sandbox if needed

### 4. Build and Run

- Press `Cmd+R` to build and run
- Or use Product > Run from the menu

## Authentication Setup

### Claude

1. Open Safari and navigate to `https://claude.ai`
2. Log in to your account
3. Open Developer Tools (`Cmd+Option+I`)
4. Go to Storage > Cookies > `claude.ai`
5. Find the session key cookie (usually named `sessionKey` or similar)
6. Copy the cookie value
7. Open MeterBar Settings
8. Paste the session key in the Claude section
9. Click "Save"

### Codex

1. Open Safari and navigate to the Codex dashboard
2. Log in to your account
3. Open Developer Tools (`Cmd+Option+I`)
4. Go to Storage > Cookies
5. Copy relevant cookies (you may need to copy multiple cookies)
6. Open MeterBar Settings
7. Paste the cookies in the Codex section
8. Click "Save"

### Cursor

1. Open Cursor IDE
2. Go to Settings > Account
3. Find your API key
4. Copy the API key
5. Open MeterBar Settings
6. Paste the API key in the Cursor section
7. Click "Save"

## Widget Setup

### Adding the Widget

1. Click the date/time in the menu bar
2. Click "Edit Widgets"
3. Search for "MeterBar"
4. Select your preferred size:
   - **Small**: Shows one service with key metrics
   - **Medium**: Shows all connected services
   - **Large**: Shows detailed breakdown with all limits

### Configuring the Widget

1. Right-click the widget
2. Select "Edit Widget"
3. Choose which services to display (if multiple are connected)

## Menu Bar

The menu bar icon shows your overall usage status:
- **Green**: All services have plenty of usage remaining
- **Yellow**: One or more services are approaching limits
- **Red**: One or more services are at or near their limits

Click the icon to see detailed usage metrics for all connected services.

## Troubleshooting

### Widget Not Updating

1. Check that you're authenticated for at least one service
2. Try manually refreshing from the menu bar
3. Check your internet connection
4. Restart the app

### Authentication Not Working

1. Verify your credentials are correct
2. Check that you're logged in to the service in Safari
3. Try removing and re-adding your credentials
4. Check the console for error messages

### Notifications Not Appearing

1. Check System Settings > Notifications
2. Ensure MeterBar has notification permissions
3. Check that notification thresholds are configured

## Security Notes

- All credentials are stored securely in macOS Keychain
- No data is sent to external servers
- All processing happens on your device
- The app is open source for transparency

## Development

### Linting and Formatting

This project uses SwiftLint and SwiftFormat for code quality.

**Run SwiftLint:**
```bash
swiftlint
```

**Run SwiftFormat:**
```bash
swiftformat .
```

**Xcode Integration:**

To run linting on every build, add a "Run Script Phase" to your target:

1. Select your target in Xcode
2. Go to Build Phases
3. Click "+" and add "New Run Script Phase"
4. Add this script:
   ```bash
   if which swiftlint > /dev/null; then
     swiftlint
   else
     echo "warning: SwiftLint not installed, download from https://github.com/realm/SwiftLint"
   fi
   ```

## Getting Help

- Check the [README](README.md) for general information
- Open an issue on GitHub for bugs or feature requests
- See [CONTRIBUTING.md](CONTRIBUTING.md) for contribution guidelines

