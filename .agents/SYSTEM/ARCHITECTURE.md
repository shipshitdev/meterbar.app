# Architecture - MeterBar

**Purpose:** Document what IS implemented (not what WILL BE).
**Last Updated:** 2025-01-27

---

## Overview

MeterBar is a macOS menu bar application with WidgetKit widgets that tracks account-level usage limits from Claude, OpenAI, and Cursor dashboards. The app provides real-time usage monitoring, notifications when approaching limits, and secure credential storage using macOS Keychain.

The application consists of two main targets:
1. **MeterBar** - Main menu bar app with settings and popover
2. **MeterBarWidget** - WidgetKit extension for Notification Center widgets

---

## Tech Stack

- **Language:** Swift 5.9+
- **UI Framework:** SwiftUI
- **Widget Framework:** WidgetKit
- **Concurrency:** Swift async/await
- **Reactive:** Combine framework
- **Storage:** macOS Keychain (credentials), UserDefaults (cache), App Groups (shared data)
- **Notifications:** UserNotifications framework
- **Platform:** macOS 13.0+ (Ventura)
- **Build System:** Xcode, Swift Package Manager

---

## Project Structure

```
meterbarapp/
├── MeterBar/                  # Main app target
│   ├── App/
│   │   └── MeterBarApp.swift  # App entry point, menu bar setup
│   ├── Models/
│   │   ├── ServiceType.swift    # Enum: Claude, OpenAI, Cursor
│   │   ├── UsageLimit.swift     # Usage limit with percentage calculations
│   │   └── UsageMetrics.swift   # Unified usage data model
│   ├── Services/
│   │   ├── KeychainManager.swift        # Secure credential storage
│   │   ├── AuthenticationManager.swift  # Auth state management
│   │   ├── ClaudeService.swift          # Claude API client
│   │   ├── OpenAIService.swift          # OpenAI API client
│   │   ├── CursorService.swift          # Cursor API client (placeholder)
│   │   ├── UsageDataManager.swift       # Centralized data management
│   │   └── SharedDataStore.swift        # App Groups shared storage
│   └── Views/
│       ├── SettingsView.swift   # Settings window
│       └── MenuBarView.swift    # Menu bar popover
├── MeterBarWidget/            # Widget extension target
│   ├── MeterBarWidgetBundle.swift  # Widget bundle entry
│   └── UsageWidget.swift        # Widget views (Small/Medium/Large)
├── MeterBar.xcodeproj/        # Xcode project
├── Package.swift                # Swift Package Manager manifest
└── .agent/                      # AI documentation
```

---

## Key Components

### App Entry Point (`MeterBarApp.swift`)

**Purpose:** Initialize app, set up menu bar, configure notifications
**Location:** `MeterBar/App/MeterBarApp.swift`
**Dependencies:** SwiftUI App protocol, NSApplication

**Key Responsibilities:**
- App lifecycle management
- Menu bar icon and status
- Settings window management
- Notification permissions
- Background refresh scheduling

### Models

#### ServiceType (`Models/ServiceType.swift`)
**Purpose:** Enum for supported AI services
**Values:** `.claude`, `.openai`, `.cursor`
**Features:** Display names, icons, color coding

#### UsageLimit (`Models/UsageLimit.swift`)
**Purpose:** Model for usage limits with percentage calculations
**Properties:** `limit`, `used`, `remaining`, `percentage`
**Methods:** Percentage calculation, status indicators

#### UsageMetrics (`Models/UsageMetrics.swift`)
**Purpose:** Unified model for service usage data
**Properties:** Service type, current usage, limits, timestamps
**Features:** JSON encoding/decoding for caching

### Services

#### KeychainManager (`Services/KeychainManager.swift`)
**Purpose:** Secure credential storage using macOS Keychain
**Pattern:** Singleton (`KeychainManager.shared`)
**Methods:**
- `save(service:key:value:)` - Store credential
- `get(service:key:)` - Retrieve credential
- `delete(service:key:)` - Remove credential

**Security:**
- Uses macOS Keychain Services API
- Credentials encrypted by OS
- No plaintext storage

#### AuthenticationManager (`Services/AuthenticationManager.swift`)
**Purpose:** Manages authentication state for all services
**Pattern:** Singleton, ObservableObject
**Properties:**
- `@Published var isClaudeAuthenticated: Bool`
- `@Published var isOpenAIAuthenticated: Bool`
- `@Published var isCursorAuthenticated: Bool`

**Methods:**
- `authenticateClaude(sessionKey:)` - Store Claude session key
- `authenticateOpenAI(apiKey:)` - Store OpenAI API key
- `authenticateCursor(apiKey:)` - Store Cursor API key
- `logout(service:)` - Clear credentials

#### API Service Clients

**ClaudeService** (`Services/ClaudeService.swift`):
- Fetches usage data from Claude API
- Requires session key from Keychain
- Parses response to UsageMetrics

**OpenAIService** (`Services/OpenAIService.swift`):
- Fetches usage data from OpenAI API
- Requires API key from Keychain
- Parses response to UsageMetrics

**CursorService** (`Services/CursorService.swift`):
- Placeholder (Cursor doesn't provide usage API)
- Returns error when called

#### UsageDataManager (`Services/UsageDataManager.swift`)
**Purpose:** Centralized data management, caching, auto-refresh
**Pattern:** Singleton, ObservableObject, @MainActor
**Properties:**
- `@Published var metrics: [ServiceType: UsageMetrics]`
- `@Published var isLoading: Bool`
- `@Published var lastError: Error?`

**Methods:**
- `refreshAll()` - Fetch all authenticated services
- `refresh(service:)` - Fetch single service
- `setupAutoRefresh()` - Schedule 15-minute refresh timer

**Features:**
- Caching to UserDefaults
- Auto-refresh every 15 minutes
- Background refresh support
- Shared data store for widgets

#### SharedDataStore (`Services/SharedDataStore.swift`)
**Purpose:** App Groups shared storage for widget extension
**Pattern:** Singleton
**App Group:** `group.com.agenticindiedev.meterbar`

**Methods:**
- `saveMetrics(_:)` - Save metrics to shared UserDefaults
- `loadMetrics()` - Load metrics from shared UserDefaults

### Views

#### SettingsView (`Views/SettingsView.swift`)
**Purpose:** Settings window for authentication and preferences
**Features:**
- Service authentication (Claude, OpenAI, Cursor)
- Credential input fields
- Authentication status indicators
- Preferences configuration

#### MenuBarView (`Views/MenuBarView.swift`)
**Purpose:** Menu bar popover with usage metrics
**Features:**
- Service cards with usage percentages
- Color-coded status (green/yellow/red)
- Refresh button
- Settings link
- Real-time updates via @Published properties

### Widget Extension

#### UsageWidget (`MeterBarWidget/UsageWidget.swift`)
**Purpose:** WidgetKit widget implementation
**Sizes:** Small, Medium, Large
**Features:**
- Timeline provider with 15-minute refresh
- Displays usage metrics for authenticated services
- Color-coded status indicators
- Progress bars for usage percentages
- Background refresh support

**Widget Views:**
- `SmallWidgetView` - Single service, key metrics
- `MediumWidgetView` - All services, compact view
- `LargeWidgetView` - Detailed breakdown

---

## Data Flow

### Authentication Flow

```
1. User opens Settings
   ↓
2. Enters credentials (session key, API key)
   ↓
3. KeychainManager.save() stores in macOS Keychain
   ↓
4. AuthenticationManager updates @Published properties
   ↓
5. UI updates to show authenticated status
```

### Data Refresh Flow

```
1. UsageDataManager.refreshAll() called
   ↓
2. Check AuthenticationManager for authenticated services
   ↓
3. For each authenticated service:
   - ClaudeService.fetchUsageMetrics()
   - OpenAIService.fetchUsageMetrics()
   ↓
4. API calls return UsageMetrics
   ↓
5. Update @Published metrics dictionary
   ↓
6. Save to cache (UserDefaults)
   ↓
7. Save to SharedDataStore (App Groups)
   ↓
8. UI updates automatically (SwiftUI @Published)
   ↓
9. Widget timeline updates
```

### Widget Update Flow

```
1. WidgetKit requests timeline
   ↓
2. UsageWidget.TimelineProvider.getTimeline()
   ↓
3. Load metrics from SharedDataStore
   ↓
4. Create TimelineEntry with current metrics
   ↓
5. Schedule next refresh (15 minutes)
   ↓
6. Widget renders with latest data
```

### Notification Flow

```
1. UsageDataManager detects usage > 90%
   ↓
2. Check if notification already sent (cooldown)
   ↓
3. Create UserNotification
   ↓
4. Schedule notification
   ↓
5. User receives alert in Notification Center
```

---

## External Services

| Service | Purpose | Documentation | Authentication |
|---------|---------|---------------|----------------|
| Claude API | Usage data | (Research needed) | Session key from cookies |
| OpenAI API | Usage data | https://platform.openai.com/docs | API key |
| Cursor API | Usage data | (No API available) | N/A |

**API Endpoints (Placeholders - Need Research):**
- Claude: `https://claude.ai/api/usage` (placeholder)
- OpenAI: `https://api.openai.com/v1/usage` (placeholder)
- Cursor: No API available

**Credential Storage:**
- All credentials stored in macOS Keychain (encrypted by OS)
- No credentials in code or UserDefaults
- Keychain access controlled by app entitlements

---

## Configuration

### App Groups

**Identifier:** `group.com.agenticindiedev.meterbar`

**Purpose:** Share data between main app and widget extension

**Configuration:**
- Both targets must have App Groups capability enabled
- Same group identifier in both targets
- Shared UserDefaults container for data sharing

### Keychain Access

**Keychain Service Names:**
- `com.agenticindiedev.meterbar.claude`
- `com.agenticindiedev.meterbar.openai`
- `com.agenticindiedev.meterbar.cursor`

**Key Names:**
- `sessionKey` (Claude)
- `apiKey` (OpenAI, Cursor)

### UserDefaults Keys

| Key | Purpose |
|-----|---------|
| `cached_usage_metrics` | Cached usage data (main app) |
| `shared_usage_metrics` | Shared usage data (App Groups) |

### Refresh Intervals

- **Auto-refresh:** 15 minutes
- **Widget timeline:** 15 minutes
- **Background refresh:** System-managed (WidgetKit)

---

## Deployment

### Development

1. **Open Xcode:**
   ```bash
   open MeterBar.xcodeproj
   ```

2. **Select Scheme:**
   - `MeterBar` - Main app
   - `MeterBarWidget` - Widget extension

3. **Build and Run:**
   - Press `Cmd+R` to build and run
   - App appears in menu bar

### Distribution

1. **Archive:**
   - Product → Archive in Xcode
   - Creates `.xcarchive`

2. **Export:**
   - Distribute App
   - Choose distribution method (App Store, Developer ID, etc.)

3. **Notarization:**
   - Required for Developer ID distribution
   - Automated via Xcode

**Requirements:**
- macOS 13.0+ (Ventura)
- Xcode 15.0+
- Apple Developer account (for distribution)

---

## Security

See `quality/SECURITY-CHECKLIST.md` for security considerations.

**Key Security Features:**
- **Keychain Storage:** All credentials encrypted by macOS Keychain
- **No Plaintext:** No credentials in code, UserDefaults, or logs
- **App Groups:** Secure shared storage between app and widget
- **Keychain Access Control:** Controlled by app entitlements

**Security Considerations:**
- API keys stored securely in Keychain
- Session keys extracted from browser cookies (user responsibility)
- No network requests logged with credentials
- Widget extension has read-only access to shared data

---

## Related Documentation

- `RULES.md` - Coding standards
- `architecture/DECISIONS.md` - Architectural decisions
- `architecture/PROJECT-MAP.md` - Project map
- `PROJECT_STRUCTURE.md` - Detailed project structure
- `IMPLEMENTATION_STATUS.md` - Implementation status
- `README.md` - User-facing documentation
- `SETUP.md` - Setup instructions
- `XCODE_SETUP.md` - Xcode project setup
