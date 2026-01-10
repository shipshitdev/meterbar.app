# Security Recommendations: Keychain Access & Network Monitoring

**Date:** 2026-01-10
**Status:** Complete
**Based on:** Security Assessment Report

## Overview

This document provides specific recommendations for addressing the security issues identified in the security assessment. All recommendations are prioritized by risk level and implementation complexity.

## Recommendation Summary

| Priority | Recommendation | Risk Addressed | Effort | Impact |
|----------|----------------|----------------|--------|--------|
| P0 | Remove cross-app keychain access | CRITICAL | Medium | High |
| P0 | Implement user credential input | CRITICAL | Medium | High |
| P1 | Remove network monitoring | MEDIUM | Low | Medium |
| P2 | Improve error handling | MEDIUM | Low | Low |

## Detailed Recommendations

### P0: Remove Cross-App Keychain Access (CRITICAL)

**Problem:**
- `CursorLocalService` and `ClaudeCodeLocalService` attempt to read credentials from other apps' keychains
- This will fail in App Sandbox (required for App Store)
- Violates App Store Review Guidelines

**Recommendation:**
**Remove all cross-app keychain access code immediately.**

**Affected Files:**
- `QuotaGuard/Services/CursorLocalService.swift`
- `QuotaGuard/Services/ClaudeCodeLocalService.swift`

**Specific Changes:**

1. **Remove keychain access methods:**
   - `getAccessToken()` in `CursorLocalService`
   - `getRefreshToken()` in `CursorLocalService`
   - `getOAuthToken()` in `ClaudeCodeLocalService`

2. **Remove keychain service identifiers:**
   - `keychainServiceAccess`, `keychainServiceRefresh`, `keychainAccount` in `CursorLocalService`
   - `keychainService` in `ClaudeCodeLocalService`

3. **Update authentication flow:**
   - Require users to manually provide credentials
   - Store credentials in our own KeychainManager (already implemented)

**Rationale:**
- Cross-app keychain access cannot work in App Sandbox
- App Store will reject the app
- No workaround exists that maintains App Store compliance
- User-provided credentials are the standard approach

**Alternative Considered:**
- Keychain Sharing entitlement: ❌ REJECTED - Requires Cursor/Claude Code to also use same entitlement (impossible)
- System entitlements: ❌ REJECTED - Not available for App Store apps
- Reading config files: ⚠️ INVESTIGATED - No documented public APIs

### P0: Implement User Credential Input (CRITICAL)

**Problem:**
- After removing cross-app keychain access, users need a way to provide credentials
- Current UI may not support manual credential input for Cursor/Claude Code

**Recommendation:**
**Add user credential input UI for Cursor and Claude Code services.**

**Implementation:**

1. **Update SettingsView.swift:**
   - Add input fields for Cursor API key (if they have a public API)
   - Add input fields for Claude Code OAuth token (user must obtain manually)
   - Add clear instructions on how to obtain credentials

2. **Update AuthenticationManager.swift:**
   - Add methods to store Cursor credentials via user input
   - Add methods to store Claude Code credentials via user input
   - Use existing KeychainManager (secure, App Sandbox compliant)

3. **Update Service Classes:**
   - Modify `CursorLocalService` to read from our keychain instead of Cursor's
   - Modify `ClaudeCodeLocalService` to read from our keychain instead of Claude Code's
   - Update `hasAccess` property to check our keychain

4. **Update Documentation:**
   - Update `SETUP.md` with instructions for obtaining Cursor/Claude Code credentials
   - Add troubleshooting section for credential issues

**User Experience:**

For **Cursor**:
- Option 1: If Cursor has a public API key, allow users to input it
- Option 2: If no public API, show message: "Cursor does not provide a public API. Please check Cursor documentation for usage tracking options."

For **Claude Code**:
- Instructions: "To get your Claude Code OAuth token, please refer to Claude Code documentation or contact support."
- Input field: Allow users to paste OAuth token
- Store securely in our keychain

**Rationale:**
- Standard approach for third-party integrations
- Gives users control over their credentials
- App Store compliant
- Secure (uses our KeychainManager)

### P1: Remove Network Monitoring (MEDIUM)

**Problem:**
- `NWPathMonitor` and `NWConnection` are used for pre-flight network checks
- This is unnecessary - URLSession already handles all network errors
- Adds complexity and performance overhead (2-7 second delays)

**Recommendation:**
**Remove network monitoring code and rely on URLSession error handling.**

**Affected Files:**
- `QuotaGuard/Services/CursorLocalService.swift` (lines 108-152)
- `QuotaGuard/Services/ClaudeCodeLocalService.swift` (lines 91-154)

**Specific Changes:**

1. **Remove methods:**
   - `checkNetworkConnectivity()` - both services
   - `resolveHostname()` - both services

2. **Update `fetchUsageMetrics()`:**
   - Remove pre-flight network checks
   - Remove calls to `checkNetworkConnectivity()` and `resolveHostname()`
   - Let URLSession handle network errors naturally
   - Improve URLSession error handling to provide user-friendly messages

3. **Improve error handling:**
   - Map URLSession errors to user-friendly messages
   - Use existing `URLError` codes for network diagnostics

**Code Example:**

**Before:**
```swift
let hasConnectivity = await checkNetworkConnectivity()
if !hasConnectivity {
    throw ServiceError.apiError("No network connectivity...")
}
let canResolve = await resolveHostname("api.cursor.com")
if !canResolve {
    throw ServiceError.apiError("Cannot resolve hostname...")
}
// Make request
```

**After:**
```swift
do {
    let (data, response) = try await urlSession.data(for: request)
    // Handle response
} catch let urlError as URLError {
    let errorMessage: String
    switch urlError.code {
    case .notConnectedToInternet:
        errorMessage = "No internet connection available"
    case .cannotFindHost, .dnsLookupFailed:
        errorMessage = "Cannot resolve hostname. Check your DNS settings."
    case .timedOut:
        errorMessage = "Request timed out"
    default:
        errorMessage = "Network error: \(urlError.localizedDescription)"
    }
    throw ServiceError.apiError(errorMessage)
}
```

**Rationale:**
- URLSession already provides comprehensive error handling
- Reduces code complexity (~60 lines per service)
- Improves performance (removes 2-7 second delays)
- Still provides good error messages to users
- No security benefit from pre-flight checks

**Impact:**
- **Performance**: Faster API requests (remove 2-7 second delays)
- **Code**: Simpler, easier to maintain
- **Errors**: Still user-friendly via URLSession error mapping

### P2: Improve Error Handling (MEDIUM)

**Problem:**
- Some error cases may not be handled gracefully
- Users may see generic error messages

**Recommendation:**
**Enhance error handling throughout authentication and API call flows.**

**Specific Changes:**

1. **Add comprehensive error handling:**
   - Keychain save/retrieve operations
   - API authentication failures
   - Network timeout scenarios
   - Invalid credential scenarios

2. **User-friendly error messages:**
   - Map technical errors to actionable messages
   - Provide troubleshooting hints where appropriate

3. **Error recovery:**
   - Graceful degradation when services fail
   - Retry logic for transient failures
   - Cached data fallback (already partially implemented)

**Rationale:**
- Better user experience
- Easier debugging
- More professional app behavior

## Implementation Priority

### Phase 1: Critical Fixes (Required for App Store)
1. Remove cross-app keychain access
2. Implement user credential input
3. Test with App Sandbox enabled

**Estimated Time:** 4-6 hours

### Phase 2: Improvements (Recommended)
1. Remove network monitoring
2. Improve error handling

**Estimated Time:** 2-3 hours

## Migration Path for Existing Users

**If app is already deployed:**
1. **Version 2.0 Release:**
   - Remove cross-app keychain access
   - Add credential input UI
   - Provide migration instructions in release notes

2. **User Communication:**
   - Release notes explaining change
   - Instructions for re-entering credentials
   - Why the change was necessary (App Store compliance)

3. **Backward Compatibility:**
   - Check for old keychain entries during migration
   - Prompt users to re-enter credentials if found
   - Clear old keychain entries after migration

**If app is not yet deployed:**
- No migration needed - implement recommendations before first release

## Testing Requirements

### Test with App Sandbox Enabled

1. **Enable App Sandbox in Xcode:**
   - Project Settings > Signing & Capabilities
   - Add "App Sandbox" capability
   - Configure required permissions:
     - Outgoing Connections (Client) ✅
     - User Selected File (Read/Write) - if needed

2. **Test Scenarios:**
   - [ ] Keychain access fails gracefully (expected)
   - [ ] User credential input works
   - [ ] Credentials stored securely in our keychain
   - [ ] API calls work with user-provided credentials
   - [ ] Network errors handled gracefully
   - [ ] No cross-app keychain access attempts

3. **Test Checklist:**
   - [ ] App launches with App Sandbox enabled
   - [ ] Settings UI allows credential input
   - [ ] Credentials save to our keychain
   - [ ] API requests work
   - [ ] Error messages are user-friendly
   - [ ] No console errors about keychain access

## Risk Mitigation

### If Recommendations Are Not Implemented

**Risk: App Store Rejection**
- **Probability:** 100%
- **Impact:** Cannot distribute via App Store
- **Mitigation:** Must implement P0 recommendations

**Risk: Functionality Failure**
- **Probability:** 100% (with App Sandbox)
- **Impact:** Cursor/Claude Code integration won't work
- **Mitigation:** Implement user credential input

**Risk: User Frustration**
- **Probability:** Medium
- **Impact:** Poor user experience, bad reviews
- **Mitigation:** Implement P1 recommendations (remove network monitoring)

## Success Criteria

- [ ] App passes App Store review
- [ ] App works with App Sandbox enabled
- [ ] Users can provide credentials manually
- [ ] Network errors handled gracefully
- [ ] No security vulnerabilities
- [ ] Code is simpler and more maintainable

## References

- Security Assessment Report: `SECURITY-ASSESSMENT.md`
- Implementation Plan: `SECURITY-IMPLEMENTATION-PLAN.md` (to be created)
