# Project Map - MeterBar

**Purpose:** Quick reference for project structure and responsibilities.
**Last Updated:** 2025-01-27

---

## Directory Overview

```
meterbarapp/
├── .agent/                      # AI documentation (you are here)
├── MeterBar/                  # Main app target
│   ├── App/
│   │   └── MeterBarApp.swift  # App entry point
│   ├── Models/                  # Data models
│   ├── Services/                # Business logic
│   └── Views/                   # UI components
├── MeterBarWidget/            # Widget extension target
│   ├── MeterBarWidgetBundle.swift
│   └── UsageWidget.swift
├── MeterBar.xcodeproj/        # Xcode project
├── Package.swift                 # Swift Package Manager
└── README.md
```

---

## Key Directories

### `/MeterBar/App/`
**Purpose:** App entry point and lifecycle
**Patterns:** SwiftUI App protocol, NSApplication
**Files:**
- `MeterBarApp.swift` - Main app, menu bar setup

### `/MeterBar/Models/`
**Purpose:** Data models and types
**Patterns:** Swift structs, enums, Codable
**Files:**
- `ServiceType.swift` - Enum for services
- `UsageLimit.swift` - Usage limit model
- `UsageMetrics.swift` - Unified usage data

### `/MeterBar/Services/`
**Purpose:** Business logic and API clients
**Patterns:** Singleton pattern, ObservableObject, async/await
**Files:**
- `KeychainManager.swift` - Secure storage
- `AuthenticationManager.swift` - Auth state
- `ClaudeService.swift` - Claude API client
- `OpenAIService.swift` - OpenAI API client
- `CursorService.swift` - Cursor API client
- `UsageDataManager.swift` - Data management
- `SharedDataStore.swift` - App Groups storage

### `/MeterBar/Views/`
**Purpose:** SwiftUI views
**Patterns:** SwiftUI views, @ObservedObject
**Files:**
- `SettingsView.swift` - Settings window
- `MenuBarView.swift` - Menu bar popover

### `/MeterBarWidget/`
**Purpose:** WidgetKit extension
**Patterns:** Widget protocol, TimelineProvider
**Files:**
- `MeterBarWidgetBundle.swift` - Widget bundle
- `UsageWidget.swift` - Widget views

---

## File Naming Conventions

| Type | Pattern | Example |
|------|---------|---------|
| App Entry | `*App.swift` | `MeterBarApp.swift` |
| Model | `*.swift` in Models/ | `UsageMetrics.swift` |
| Service | `*Service.swift` or `*Manager.swift` | `ClaudeService.swift`, `KeychainManager.swift` |
| View | `*View.swift` | `SettingsView.swift` |
| Widget | `*Widget.swift` or `*WidgetBundle.swift` | `UsageWidget.swift` |

---

## Entry Points

| File | Purpose | Called By |
|------|---------|-----------|
| `MeterBar/App/MeterBarApp.swift` | App entry point | macOS system |
| `MeterBarWidget/MeterBarWidgetBundle.swift` | Widget bundle | WidgetKit |

---

## Key Files and Responsibilities

### App Files

| File | Purpose | Key Classes/Structs |
|------|---------|---------------------|
| `MeterBarApp.swift` | App lifecycle, menu bar | `MeterBarApp` (App) |

### Model Files

| File | Purpose | Key Types |
|------|---------|-----------|
| `ServiceType.swift` | Service enum | `ServiceType` enum |
| `UsageLimit.swift` | Usage limit model | `UsageLimit` struct |
| `UsageMetrics.swift` | Usage data model | `UsageMetrics` struct |

### Service Files

| File | Purpose | Key Classes |
|------|---------|-------------|
| `KeychainManager.swift` | Keychain storage | `KeychainManager` (singleton) |
| `AuthenticationManager.swift` | Auth state | `AuthenticationManager` (singleton, ObservableObject) |
| `ClaudeService.swift` | Claude API | `ClaudeService` (singleton) |
| `OpenAIService.swift` | OpenAI API | `OpenAIService` (singleton) |
| `CursorService.swift` | Cursor API | `CursorService` (singleton) |
| `UsageDataManager.swift` | Data management | `UsageDataManager` (singleton, ObservableObject) |
| `SharedDataStore.swift` | App Groups storage | `SharedDataStore` (singleton) |

### View Files

| File | Purpose | Key Views |
|------|---------|-----------|
| `SettingsView.swift` | Settings window | `SettingsView` |
| `MenuBarView.swift` | Menu bar popover | `MenuBarView` |

### Widget Files

| File | Purpose | Key Types |
|------|---------|-----------|
| `MeterBarWidgetBundle.swift` | Widget bundle | `MeterBarWidgetBundle` |
| `UsageWidget.swift` | Widget views | `UsageWidget`, `SmallWidgetView`, `MediumWidgetView`, `LargeWidgetView` |

---

## Module Relationships

```
MeterBarApp
  ├──→ MenuBarView
  │     └──→ UsageDataManager (ObservableObject)
  │           ├──→ ClaudeService
  │           ├──→ OpenAIService
  │           └──→ AuthenticationManager
  │                 └──→ KeychainManager
  │
  ├──→ SettingsView
  │     └──→ AuthenticationManager
  │           └──→ KeychainManager
  │
  └──→ UsageDataManager
        └──→ SharedDataStore (App Groups)

MeterBarWidget
  └──→ UsageWidget
        └──→ SharedDataStore (App Groups)
```

---

## Configuration Files

| File | Purpose | Key Settings |
|------|---------|--------------|
| `Package.swift` | Swift Package Manager | Dependencies, targets |
| `MeterBar.xcodeproj/` | Xcode project | Targets, capabilities, signing |
| `Info.plist` | App metadata | Bundle ID, version |

---

## Capabilities Required

| Capability | Purpose | Targets |
|------------|---------|---------|
| App Groups | Data sharing | MeterBar, MeterBarWidget |
| Keychain Sharing | Credential access | MeterBar |
| UserNotifications | Alerts | MeterBar |

---

## Build Output

| Directory | Purpose | Generated By |
|-----------|---------|--------------|
| `build/` | Compiled binaries | Xcode build |
| `DerivedData/` | Xcode build artifacts | Xcode (in DerivedData location) |

---

## Related Documentation

- `../ARCHITECTURE.md` - System architecture
- `../RULES.md` - Coding standards
- `DECISIONS.md` - Architectural decisions
- `../../PROJECT_STRUCTURE.md` - Detailed project structure
- `../../IMPLEMENTATION_STATUS.md` - Implementation status
- `../../README.md` - User-facing documentation
