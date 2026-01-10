# Task: Display Claude Usage in Widget and Menu Bar

**Priority:** P1 (High)  
**Status:** Not Started  
**Created:** 2026-01-10  
**Updated:** 2026-01-10
**Related PRD:** `../PRDs/prd-claude-usage-display.md`

## Description

Currently, Claude usage data is being fetched by `UsageDataManager` and saved to `SharedDataStore`, but nothing appears in the widget or menu bar UI. This task involves fixing the data flow to ensure usage metrics are properly displayed in both the macOS widget and the menu bar popover.

## Problem Analysis

After reviewing the code, I've identified the following issues:

1. **Storage Mechanism Mismatch:**
   - Main app's `SharedDataStore` (in `QuotaGuard/Services/SharedDataStore.swift`) writes to App Group container file: `containerURL.appendingPathComponent("cached_usage_metrics.json")`
   - Widget's `SharedDataStore` (in `UsageWidget.swift`) reads from UserDefaults suite: `UserDefaults(suiteName: suiteName)?.data(forKey: "shared_metrics")`
   - These are incompatible storage mechanisms

2. **Key Name Mismatch:**
   - Main app saves with key: `"cached_usage_metrics"`
   - Widget reads with key: `"shared_metrics"`
   - Different keys mean they won't find each other's data

3. **Service Type Mismatch:**
   - Main app uses `ServiceType.claudeCode` 
   - Widget's `ServiceType` enum doesn't include `.claudeCode` case
   - Widget only has `.claude`, `.openai`, `.cursor`

4. **Data Not Persisting to Widget:**
   - `UsageDataManager.refreshAll()` calls `sharedStore.saveMetrics(newMetrics)` after fetching
   - Widget's timeline provider calls `SharedDataStore.shared.loadMetrics()` but gets empty data
   - The storage implementations need to be unified

## Acceptance Criteria

- [ ] Widget displays Claude usage data (session, weekly limits) when authenticated
- [ ] Menu bar popover displays Claude usage data when authenticated
- [ ] Both widget and menu bar show "No data" or empty state when not authenticated
- [ ] Data refreshes automatically every 15 minutes and updates both UI surfaces
- [ ] Manual refresh button in menu bar updates both widget and menu bar
- [ ] Widget timeline provider correctly loads data from shared storage
- [ ] All `ServiceType` cases are consistent between main app and widget
- [ ] Shared storage uses consistent mechanism (App Group container file OR UserDefaults suite, not both)
- [ ] App Group identifier is properly configured in both main app and widget targets

## Technical Requirements

### 1. Unify SharedDataStore Implementation
- Create a single `SharedDataStore` implementation that both main app and widget can use
- Use App Group container file storage (more reliable for larger data)
- Ensure App Group identifier matches in both targets: `group.com.agenticindiedev.quotaguard`
- Both read and write operations must use the same file path and encoding

### 2. Fix ServiceType Enum
- Ensure widget's `ServiceType` enum includes all cases from main app:
  - `.claude`
  - `.claudeCode` 
  - `.openai`
  - `.cursor`
- Or move `ServiceType` to a shared location that both targets can access

### 3. Verify App Group Configuration
- Check Xcode project settings for App Groups capability
- Ensure both `QuotaGuard` (main app) and `QuotaGuardWidget` targets have App Groups enabled
- Verify the identifier is exactly: `group.com.agenticindiedev.quotaguard`

### 4. Fix Data Flow
- Ensure `UsageDataManager.saveMetrics()` is called after every successful fetch
- Ensure widget's timeline provider triggers when data changes (may need to use `WidgetCenter.shared.reloadTimelines()`)
- Test that data persists across app launches

### 5. Add Debugging
- Add logging to verify data is being saved and loaded
- Log file paths, data sizes, and any errors
- Verify App Group container URL is accessible

## Implementation Steps

1. **Audit Storage Implementation**
   - Remove duplicate `SharedDataStore` from `UsageWidget.swift`
   - Ensure both targets use the same `SharedDataStore` from `QuotaGuard/Services/SharedDataStore.swift`
   - Verify it uses App Group container file consistently

2. **Fix ServiceType**
   - Add `.claudeCode` case to widget's `ServiceType` enum (or extract to shared file)
   - Update widget views to handle all service types

3. **Test Data Persistence**
   - Add test data manually to verify storage mechanism works
   - Verify widget can read what main app writes
   - Check file permissions and App Group access

4. **Add Widget Refresh Trigger**
   - After saving metrics in `UsageDataManager`, call `WidgetCenter.shared.reloadTimelines(ofKind: "UsageWidget")`
   - This ensures widget updates immediately after data refresh

5. **Verify Menu Bar Display**
   - Check that `MenuBarView` is properly observing `UsageDataManager.shared.metrics`
   - Verify `ServiceRowView` displays Claude data when `metrics` is non-nil
   - Test that empty state shows when no data is available

## Testing Checklist

- [ ] Authenticate with Claude API key
- [ ] Wait for initial data fetch (or click refresh)
- [ ] Verify menu bar popover shows Claude usage metrics
- [ ] Verify widget (all sizes) shows Claude usage metrics
- [ ] Verify "No data" appears when not authenticated
- [ ] Verify data updates after 15 minutes auto-refresh
- [ ] Verify manual refresh updates both UI surfaces
- [ ] Verify data persists after app restart
- [ ] Test with multiple services (Claude + OpenAI + Claude Code)
- [ ] Verify widget updates when main app refreshes data

## Related PRD

This task implements the PRD: `../PRDs/prd-claude-usage-display.md`

See the PRD for detailed problem statement, solution design, and implementation plan.

## Notes

- The main app's `SharedDataStore` implementation in `QuotaGuard/Services/SharedDataStore.swift` looks correct (uses App Group container)
- The widget's inline `SharedDataStore` in `UsageWidget.swift` needs to be removed and replaced with import/reference to the main app's version
- May need to move `SharedDataStore` to a shared framework/target if direct import doesn't work
- WidgetKit requires App Groups to be properly configured in Xcode capabilities
- Consider adding debug logging to trace data flow

## Related Files

- `QuotaGuard/Services/SharedDataStore.swift` - Main app storage implementation (correct)
- `QuotaGuardWidget/UsageWidget.swift` - Widget implementation (has duplicate SharedDataStore)
- `QuotaGuard/Services/UsageDataManager.swift` - Manages data fetching and saving
- `QuotaGuard/Views/MenuBarView.swift` - Menu bar popover UI
- `QuotaGuard/Models/ServiceType.swift` - Service type definitions

## References

- [WidgetKit App Groups Documentation](https://developer.apple.com/documentation/widgetkit/creating-a-widget-extension)
- [App Groups User Guide](https://developer.apple.com/documentation/xcode/configuring-app-groups)
