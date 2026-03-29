# PRD: Claude Usage Display in Widget and Menu Bar

**Product:** Quota Guard  
**Feature:** Display Claude API usage metrics in macOS widget and menu bar popover  
**Priority:** P1 (High)  
**Status:** Draft  
**Created:** 2026-01-10  
**Last Updated:** 2026-01-10
**Owner:** Engineering
**Related Tasks:** `../TASKS/display-claude-usage-widget-menu-bar.md`

---

## Executive Summary

Users currently authenticate with Claude API and the app successfully fetches usage metrics, but the data does not appear in the widget or menu bar UI. This PRD addresses fixing the data flow and storage mechanism to ensure Claude usage is properly displayed in both UI surfaces.

---

## Problem Statement

### Current State
- ✅ Claude API authentication works
- ✅ Usage metrics are successfully fetched from Anthropic API
- ✅ Data is saved to `SharedDataStore` after fetching
- ❌ Widget shows "No data" even when metrics are available
- ❌ Menu bar popover may not be displaying data correctly

### User Impact
- Users cannot see their Claude API usage at a glance
- Widget functionality is non-functional despite authentication
- Users must manually check Anthropic console to see usage
- Primary value proposition of the app (usage visibility) is broken

### Business Impact
- Core feature is non-functional
- Reduces user confidence and trust
- Prevents users from monitoring usage effectively
- Blocks widget functionality, a key differentiator

---

## Goals

### Primary Goals
1. **Fix data storage mechanism** - Ensure widget and main app use the same storage system
2. **Display Claude usage in widget** - Show session, weekly, and code review limits
3. **Display Claude usage in menu bar** - Show detailed metrics in popover
4. **Enable real-time updates** - Refresh widget when data changes

### Success Metrics
- ✅ Widget displays Claude usage within 15 seconds of authentication
- ✅ Menu bar popover shows Claude metrics when authenticated
- ✅ Widget updates automatically every 15 minutes
- ✅ Manual refresh updates both widget and menu bar immediately
- ✅ Data persists across app restarts

---

## User Stories

### As a user who has authenticated with Claude API
**I want to** see my Claude API usage in the macOS widget  
**So that** I can monitor my usage at a glance without opening the app

### As a user monitoring my API usage
**I want to** see detailed Claude usage metrics in the menu bar popover  
**So that** I can see session, weekly, and code review limits all in one place

### As a power user
**I want** the widget to update automatically when usage data refreshes  
**So that** I always have current usage information without manual intervention

---

## Technical Analysis

### Root Causes Identified

1. **Storage Mechanism Mismatch**
   ```
   Main App:  App Group container file → `containerURL/cached_usage_metrics.json`
   Widget:    UserDefaults suite → `UserDefaults(suiteName).data(forKey: "shared_metrics")`
   ```
   - These are incompatible storage mechanisms
   - Widget cannot read what main app writes

2. **Key Name Mismatch**
   - Main app saves with key: `"cached_usage_metrics"`
   - Widget reads with key: `"shared_metrics"`
   - Different keys = no data found

3. **Service Type Enum Mismatch**
   - Main app defines: `.claude`, `.claudeCode`, `.openai`, `.cursor`
   - Widget defines: `.claude`, `.openai`, `.cursor` (missing `.claudeCode`)
   - Missing case causes decoding failures

4. **No Widget Refresh Trigger**
   - Main app saves data but doesn't notify widget
   - Widget only updates on timeline schedule (every 15 min)
   - Manual refresh doesn't trigger widget update

### Architecture Diagram

```
┌─────────────────┐
│ UsageDataManager│
│  (Main App)     │
└────────┬────────┘
         │
         │ fetchUsageMetrics()
         ▼
┌─────────────────┐
│  ClaudeService  │
│  (Main App)     │
└────────┬────────┘
         │
         │ UsageMetrics
         ▼
┌─────────────────┐      ┌──────────────────┐
│ SharedDataStore │─────▶│ App Group        │
│  (Main App)     │      │ Container File   │
└─────────────────┘      └────────┬─────────┘
                                  │
                    ┌─────────────┴─────────────┐
                    │                           │
         ┌──────────▼──────────┐   ┌───────────▼──────────┐
         │ SharedDataStore     │   │ MenuBarView          │
         │ (Widget - BROKEN)   │   │ (Main App - BROKEN?) │
         └──────────┬──────────┘   └──────────────────────┘
                    │
                    │ loadMetrics()
                    ▼
         ┌──────────────────┐
         │ UsageWidget      │
         │ (Widget)         │
         └──────────────────┘
```

**Current Flow (Broken):**
1. Main app saves to file storage ✓
2. Widget reads from UserDefaults ✗
3. Menu bar reads from in-memory state ✓ (but data may not be persisted correctly)

---

## Solution Design

### 1. Unify SharedDataStore Implementation

**Problem:** Two different `SharedDataStore` implementations with incompatible storage.

**Solution:**
- Remove duplicate `SharedDataStore` class from `UsageWidget.swift`
- Use single `SharedDataStore` from `QuotaGuard/Services/SharedDataStore.swift`
- Both main app and widget import from shared location
- If direct import fails, create shared framework target

**Implementation:**
```swift
// Single source of truth: QuotaGuard/Services/SharedDataStore.swift
class SharedDataStore {
    static let shared = SharedDataStore()
    private let appGroupIdentifier = "group.com.agenticindiedev.quotaguard"
    private let metricsKey = "cached_usage_metrics"
    
    // Uses App Group container file consistently
    func saveMetrics(_ metrics: [ServiceType: UsageMetrics]) { ... }
    func loadMetrics() -> [ServiceType: UsageMetrics] { ... }
}
```

### 2. Fix ServiceType Enum Consistency

**Problem:** Widget's `ServiceType` is missing `.claudeCode` case.

**Solution:**
- Option A: Move `ServiceType` to shared file that both targets import
- Option B: Ensure widget's enum includes all cases from main app
- Prefer Option A for maintainability

**Implementation:**
```swift
// Shared: QuotaGuard/Models/ServiceType.swift
enum ServiceType: String, Codable, CaseIterable, Identifiable {
    case claude = "Claude"
    case claudeCode = "Claude Code"
    case openai = "OpenAI"
    case cursor = "Cursor"
    // ... rest of implementation
}
```

### 3. Add Widget Refresh Trigger

**Problem:** Widget only updates on timeline schedule, not when data changes.

**Solution:**
- After saving metrics in `UsageDataManager`, call `WidgetCenter.shared.reloadTimelines()`
- This ensures widget updates immediately after data refresh
- Manual refresh should also trigger widget reload

**Implementation:**
```swift
// In UsageDataManager.saveCachedData()
private func saveCachedData() {
    // ... existing save logic ...
    sharedStore.saveMetrics(metrics)
    
    // Trigger widget reload
    WidgetCenter.shared.reloadTimelines(ofKind: "UsageWidget")
}
```

### 4. Verify App Group Configuration

**Problem:** App Groups may not be properly configured in Xcode.

**Solution:**
- Verify both `QuotaGuard` (main app) and `QuotaGuardWidget` targets have:
  - App Groups capability enabled
  - Same identifier: `group.com.agenticindiedev.quotaguard`
- Check entitlements files are correct
- Test container URL access

### 5. Fix Data Flow

**Current Flow (Incomplete):**
```
UsageDataManager.refreshAll()
  → ClaudeService.fetchUsageMetrics()
  → UsageDataManager.metrics[.claude] = metrics
  → UsageDataManager.saveCachedData()
  → SharedDataStore.saveMetrics() ✓
  → Widget never notified ✗
```

**Fixed Flow:**
```
UsageDataManager.refreshAll()
  → ClaudeService.fetchUsageMetrics()
  → UsageDataManager.metrics[.claude] = metrics
  → UsageDataManager.saveCachedData()
  → SharedDataStore.saveMetrics() ✓
  → WidgetCenter.reloadTimelines() ✓
  → Widget timeline provider loads data ✓
  → Widget displays data ✓
```

---

## Implementation Plan

### Phase 1: Fix Storage Mechanism (2-3 hours)
- [ ] Audit `SharedDataStore` implementations
- [ ] Remove duplicate from `UsageWidget.swift`
- [ ] Ensure single implementation uses App Group container
- [ ] Test file read/write in both targets
- [ ] Verify App Group configuration in Xcode

### Phase 2: Fix ServiceType Enum (1 hour)
- [ ] Move `ServiceType` to shared location or add missing case
- [ ] Update widget views to handle all service types
- [ ] Test encoding/decoding with all service types

### Phase 3: Add Widget Refresh Trigger (1 hour)
- [ ] Add `WidgetCenter.reloadTimelines()` call after saving metrics
- [ ] Add to both `refreshAll()` and `refresh(service:)` methods
- [ ] Test immediate widget update after manual refresh

### Phase 4: Verify Menu Bar Display (1 hour)
- [ ] Check `MenuBarView` observes `UsageDataManager.shared.metrics`
- [ ] Verify `ServiceRowView` displays Claude data correctly
- [ ] Test empty state when no data available
- [ ] Test authenticated state with data

### Phase 5: Testing & Debugging (2-3 hours)
- [ ] Test full flow: authenticate → fetch → display
- [ ] Test widget updates (all sizes: small, medium, large)
- [ ] Test menu bar popover display
- [ ] Test data persistence across app restarts
- [ ] Test with multiple services (Claude + OpenAI)
- [ ] Add debug logging for data flow
- [ ] Test error handling (API failures, network issues)

**Total Estimated Time:** 7-10 hours

---

## Testing Strategy

### Unit Tests
- [ ] Test `SharedDataStore.saveMetrics()` writes to correct file
- [ ] Test `SharedDataStore.loadMetrics()` reads from correct file
- [ ] Test `ServiceType` encoding/decoding with all cases
- [ ] Test `UsageMetrics` serialization/deserialization

### Integration Tests
- [ ] Test main app saves data, widget reads data
- [ ] Test widget refresh trigger fires correctly
- [ ] Test data persists across app launches
- [ ] Test multiple services save/load correctly

### Manual Testing
- [ ] Authenticate with Claude API key
- [ ] Verify menu bar shows Claude metrics
- [ ] Verify widget (all sizes) shows Claude metrics
- [ ] Test manual refresh updates both UI surfaces
- [ ] Wait 15 minutes and verify auto-refresh works
- [ ] Restart app and verify data persists
- [ ] Test with no authentication (empty state)
- [ ] Test with API errors (graceful degradation)

---

## Edge Cases & Error Handling

### Edge Cases
1. **No App Group Access:** Widget cannot read container file
   - Handle: Show "No data" with helpful error message
   - Log error to console for debugging

2. **Corrupted Data:** JSON decode fails
   - Handle: Log error, show "No data", attempt to delete corrupted file

3. **Missing Service Type:** Enum case not found during decode
   - Handle: Skip unknown service types, log warning
   - Continue loading other services

4. **Widget Not Installed:** User hasn't added widget to Notification Center
   - Handle: `WidgetCenter.reloadTimelines()` is safe to call, no-op if widget not installed

5. **Data Stale:** Metrics are older than 24 hours
   - Handle: Show "Last updated: X hours ago" indicator
   - Still display data but indicate staleness

### Error Handling
- All file operations should be wrapped in try/catch
- Log all errors with context (file path, error type, service)
- Don't crash on storage errors, show user-friendly message
- Preserve cached data on fetch failure (already implemented)

---

## Rollout Plan

### Phase 1: Internal Testing
- Fix implementation locally
- Test on development machine
- Verify all test cases pass

### Phase 2: Beta Testing
- Deploy to TestFlight (if available)
- Or test with signed build locally
- Gather feedback on widget and menu bar display

### Phase 3: Production Release
- Merge fixes to main branch
- Tag release with fix notes
- Monitor for any issues

---

## Success Criteria

### Must Have (P0)
- ✅ Widget displays Claude usage when authenticated
- ✅ Menu bar displays Claude usage when authenticated
- ✅ Data persists across app restarts
- ✅ No crashes or data loss

### Should Have (P1)
- ✅ Widget updates automatically every 15 minutes
- ✅ Manual refresh updates widget immediately
- ✅ Multiple services display correctly
- ✅ Empty states show correctly when not authenticated

### Nice to Have (P2)
- Widget shows "Last updated" timestamp
- Widget shows percentage as visual indicator
- Menu bar shows detailed breakdown (session, weekly, code review)
- Smooth animations when data updates

---

## Dependencies

### Technical Dependencies
- Xcode project configuration (App Groups capability)
- WidgetKit framework (already included)
- App Groups entitlement configuration
- Shared data models (`ServiceType`, `UsageMetrics`, `UsageLimit`)

### External Dependencies
- None - all fixes are internal to the app

---

## Risks & Mitigation

### Risk 1: App Groups Not Properly Configured
**Impact:** High - Widget won't be able to read data  
**Probability:** Medium  
**Mitigation:** 
- Add verification step to check App Group access on app launch
- Show user-friendly error if App Groups not accessible
- Provide setup instructions in documentation

### Risk 2: SharedDataStore Import Issues
**Impact:** High - Code won't compile  
**Probability:** Low  
**Mitigation:**
- Test import paths early
- Create shared framework target if direct import fails
- Keep implementation simple (single file)

### Risk 3: Widget Not Updating in Real-Time
**Impact:** Medium - User experience degraded  
**Probability:** Low  
**Mitigation:**
- Test `WidgetCenter.reloadTimelines()` thoroughly
- Add fallback to timeline schedule if immediate reload fails
- Document expected behavior in release notes

---

## Open Questions

1. **Should we use UserDefaults suite or App Group container file?**
   - **Decision:** App Group container file (already implemented, more reliable for larger data)
   - **Rationale:** Current main app implementation uses file storage, easier to keep consistent

2. **Should ServiceType be in shared framework or duplicated?**
   - **Decision:** Shared location (extract to shared file both targets import)
   - **Rationale:** Single source of truth prevents drift and bugs

3. **How often should widget update?**
   - **Decision:** Keep 15-minute timeline schedule + immediate reload on data change
   - **Rationale:** Balance between freshness and battery life

---

## References

- [WidgetKit Documentation](https://developer.apple.com/documentation/widgetkit)
- [App Groups User Guide](https://developer.apple.com/documentation/xcode/configuring-app-groups)
- [SharedDataStore Implementation](../QuotaGuard/Services/SharedDataStore.swift)
- [UsageWidget Implementation](../QuotaGuardWidget/UsageWidget.swift)
- [UsageDataManager Implementation](../QuotaGuard/Services/UsageDataManager.swift)

---

## Appendix

### File Changes Required

1. **QuotaGuardWidget/UsageWidget.swift**
   - Remove duplicate `SharedDataStore` class (lines 112-139)
   - Import main app's `SharedDataStore` instead
   - Update `loadMetrics()` to use shared implementation
   - Ensure `ServiceType` enum matches main app

2. **QuotaGuard/Services/UsageDataManager.swift**
   - Add `import WidgetKit`
   - Call `WidgetCenter.shared.reloadTimelines(ofKind: "UsageWidget")` after saving metrics
   - Update both `refreshAll()` and `refresh(service:)` methods

3. **Xcode Project Settings**
   - Verify App Groups capability enabled for both targets
   - Verify App Group identifier matches: `group.com.agenticindiedev.quotaguard`
   - Check entitlements files are correct

4. **Testing**
   - Add debug logging to trace data flow
   - Verify file paths and App Group container URL
   - Test data encoding/decoding with all service types

---

**Document Version:** 1.0  
**Last Updated:** 2026-01-10  
**Next Review:** After implementation complete
