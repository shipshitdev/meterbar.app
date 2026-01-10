# Implementation Plan: Security Fixes

**Date:** 2026-01-10
**Status:** Ready for Implementation
**Estimated Time:** 6-9 hours

## Overview

This plan provides step-by-step instructions for implementing the security recommendations. All changes are required for App Store compliance.

## Phase 1: Remove Cross-App Keychain Access (CRITICAL)

### Step 1.1: Update CursorLocalService.swift

**File:** `QuotaGuard/Services/CursorLocalService.swift`

**Changes:**

1. **Remove keychain service identifiers** (lines ~19-22):
   ```swift
   // REMOVE these lines:
   private let keychainServiceAccess = "cursor-access-token"
   private let keychainServiceRefresh = "cursor-refresh-token"
   private let keychainAccount = "cursor-user"
   ```

2. **Remove keychain access methods** (lines 47-93):
   ```swift
   // REMOVE these methods entirely:
   // - getAccessToken()
   // - getRefreshToken()
   // - checkAccess()
   ```

3. **Add reference to AuthenticationManager:**
   ```swift
   private let authManager = AuthenticationManager.shared
   ```

4. **Update `hasAccess` property:**
   ```swift
   // Change from checking Cursor's keychain to checking our keychain
   var hasAccess: Bool {
       return authManager.cursorAccessToken != nil
   }
   ```

5. **Update `fetchUsageMetrics()` method:**
   ```swift
   func fetchUsageMetrics() async throws -> UsageMetrics {
       guard let token = authManager.cursorAccessToken else {
           let error = ServiceError.notAuthenticated
           await MainActor.run {
               self.lastError = error
               self.hasAccess = false
           }
           throw error
       }
       
       // Rest of method unchanged (but remove network monitoring in Phase 2)
   }
   ```

6. **Update `init()` method:**
   ```swift
   private init() {
       // Remove keychain check, rely on AuthenticationManager
       checkAccessStatus()
   }
   
   private func checkAccessStatus() {
       hasAccess = authManager.cursorAccessToken != nil
   }
   ```

### Step 1.2: Update ClaudeCodeLocalService.swift

**File:** `QuotaGuard/Services/ClaudeCodeLocalService.swift`

**Changes:**

1. **Remove keychain service identifier** (line ~18):
   ```swift
   // REMOVE this line:
   private let keychainService = "Claude Code-credentials"
   ```

2. **Remove keychain access methods** (lines 44-86):
   ```swift
   // REMOVE these methods entirely:
   // - getOAuthToken()
   // - checkAccess()
   ```

3. **Add reference to AuthenticationManager:**
   ```swift
   private let authManager = AuthenticationManager.shared
   ```

4. **Update `hasAccess` property:**
   ```swift
   var hasAccess: Bool {
       return authManager.claudeCodeOAuthToken != nil
   }
   ```

5. **Update `fetchUsageMetrics()` method:**
   ```swift
   func fetchUsageMetrics() async throws -> UsageMetrics {
       guard let token = authManager.claudeCodeOAuthToken else {
           let error = ServiceError.notAuthenticated
           await MainActor.run {
               self.lastError = error
               self.hasAccess = false
           }
           throw error
       }
       
       // Rest of method unchanged (but remove network monitoring in Phase 2)
   }
   ```

6. **Update `init()` method:**
   ```swift
   private init() {
       checkAccessStatus()
   }
   
   private func checkAccessStatus() {
       hasAccess = authManager.claudeCodeOAuthToken != nil
   }
   ```

### Step 1.3: Update AuthenticationManager.swift

**File:** `QuotaGuard/Services/AuthenticationManager.swift`

**Changes:**

1. **Add new published properties:**
   ```swift
   @Published var cursorAccessToken: String?
   @Published var claudeCodeOAuthToken: String?
   ```

2. **Update `loadCredentials()` method:**
   ```swift
   private func loadCredentials() {
       claudeAdminKey = keychain.get(key: "claude_admin_key")
       openaiAdminKey = keychain.get(key: "openai_admin_key")
       cursorAccessToken = keychain.get(key: "cursor_access_token")
       claudeCodeOAuthToken = keychain.get(key: "claude_code_oauth_token")
   }
   ```

3. **Add methods for Cursor:**
   ```swift
   func setCursorAccessToken(_ token: String) -> Bool {
       let success = keychain.save(key: "cursor_access_token", value: token)
       if success {
           cursorAccessToken = token
       }
       return success
   }
   
   func removeCursorAccessToken() {
       _ = keychain.delete(key: "cursor_access_token")
       cursorAccessToken = nil
   }
   
   var isCursorAuthenticated: Bool {
       return cursorAccessToken != nil
   }
   ```

4. **Add methods for Claude Code:**
   ```swift
   func setClaudeCodeOAuthToken(_ token: String) -> Bool {
       let success = keychain.save(key: "claude_code_oauth_token", value: token)
       if success {
           claudeCodeOAuthToken = token
       }
       return success
   }
   
   func removeClaudeCodeOAuthToken() {
       _ = keychain.delete(key: "claude_code_oauth_token")
       claudeCodeOAuthToken = nil
   }
   
   var isClaudeCodeAuthenticated: Bool {
       return claudeCodeOAuthToken != nil
   }
   ```

5. **Remove/update old Cursor authentication method:**
   ```swift
   // REMOVE this old method (lines 57-59):
   // var isCursorAuthenticated: Bool {
   //     return false
   // }
   ```

### Step 1.4: Update SettingsView.swift

**File:** `QuotaGuard/Views/SettingsView.swift`

**Note:** Need to read this file first to see current implementation.

**Expected Changes:**

1. **Add input fields for Cursor:**
   - Text field for Cursor API key/access token
   - Save/Remove buttons
   - Connection status indicator

2. **Add input fields for Claude Code:**
   - Text field for Claude Code OAuth token
   - Instructions on how to obtain token
   - Save/Remove buttons
   - Connection status indicator

3. **Update UI to show authentication status:**
   - Use `authManager.isCursorAuthenticated`
   - Use `authManager.isClaudeCodeAuthenticated`

**Implementation Notes:**
- Follow same pattern as existing Claude/OpenAI authentication UI
- Add helpful instructions/links for obtaining credentials
- Show clear error messages if credentials are invalid

## Phase 2: Remove Network Monitoring (RECOMMENDED)

### Step 2.1: Update CursorLocalService.swift

**File:** `QuotaGuard/Services/CursorLocalService.swift`

**Changes:**

1. **Remove network monitoring methods** (lines 108-152):
   ```swift
   // REMOVE these methods entirely:
   // - checkNetworkConnectivity()
   // - resolveHostname()
   ```

2. **Update `fetchUsageMetrics()` method:**
   ```swift
   func fetchUsageMetrics() async throws -> UsageMetrics {
       guard let token = authManager.cursorAccessToken else {
           // ... existing auth check ...
       }
       
       // REMOVE these pre-flight checks:
       // let hasConnectivity = await checkNetworkConnectivity()
       // let canResolve = await resolveHostname("api.cursor.com")
       
       // Keep the endpoint loop, but improve error handling:
       for endpoint in endpointPatterns {
           guard let url = URL(string: endpoint) else { continue }
           
           var request = URLRequest(url: url)
           request.httpMethod = "GET"
           request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
           request.setValue("application/json", forHTTPHeaderField: "Accept")
           request.setValue("application/json", forHTTPHeaderField: "Content-Type")
           request.timeoutInterval = 30.0
           
           do {
               let (data, response) = try await urlSession.data(for: request)
               
               // Handle response (existing code)...
               
           } catch let urlError as URLError {
               // IMPROVE error handling with user-friendly messages:
               let errorMessage: String
               switch urlError.code {
               case .notConnectedToInternet:
                   errorMessage = "No internet connection available. Please check your network connection."
               case .cannotFindHost, .dnsLookupFailed:
                   errorMessage = "Cannot resolve hostname. Please check your DNS settings or network configuration."
               case .timedOut:
                   errorMessage = "Request timed out. The server may be slow or unreachable."
               case .networkConnectionLost:
                   errorMessage = "Network connection lost during request. Please try again."
               case .cannotConnectToHost:
                   errorMessage = "Cannot connect to server. Please check your internet connection."
               default:
                   errorMessage = "Network error: \(urlError.localizedDescription)"
               }
               
               lastError = ServiceError.apiError(errorMessage)
               print("[CursorLocalService] Network error: \(errorMessage)")
               continue // Try next endpoint
           } catch {
               lastError = ServiceError.apiError("Unexpected error: \(error.localizedDescription)")
               continue
           }
       }
       
       // Handle all endpoints failed case...
   }
   ```

3. **Remove Network import if not used elsewhere:**
   ```swift
   // Check if Network framework is still needed
   // If only used for monitoring, remove: import Network
   ```

### Step 2.2: Update ClaudeCodeLocalService.swift

**File:** `QuotaGuard/Services/ClaudeCodeLocalService.swift`

**Changes:**

**Same as CursorLocalService:**
1. Remove `checkNetworkConnectivity()` method (lines 91-118)
2. Remove `resolveHostname()` method (lines 121-154)
3. Remove pre-flight network checks from `fetchUsageMetrics()`
4. Improve URLSession error handling with user-friendly messages
5. Update hostname references: change `"api.cursor.com"` to `"api.anthropic.com"`

## Phase 3: Enable App Sandbox (REQUIRED FOR TESTING)

### Step 3.1: Configure App Sandbox in Xcode

1. **Open Xcode Project:**
   - Open `QuotaGuard.xcodeproj`

2. **Select Main App Target:**
   - Select `QuotaGuard` target in project navigator

3. **Add App Sandbox Capability:**
   - Go to "Signing & Capabilities" tab
   - Click "+ Capability"
   - Add "App Sandbox"

4. **Configure Sandbox Permissions:**
   - ✅ **Outgoing Connections (Client)** - Required for API calls
   - ❌ User Selected File - Not needed unless file access required
   - ❌ Incoming Connections - Not needed
   - ❌ All other permissions - Leave disabled

5. **Verify Entitlements:**
   - Check that entitlements file is created
   - Verify no Keychain Access Groups are configured (we don't need cross-app access)

### Step 3.2: Test with App Sandbox Enabled

1. **Build and Run:**
   - Clean build folder (Cmd+Shift+K)
   - Build project (Cmd+B)
   - Run app (Cmd+R)

2. **Test Scenarios:**
   - [ ] App launches successfully
   - [ ] Settings UI displays correctly
   - [ ] Can save credentials to our keychain
   - [ ] Can retrieve credentials from our keychain
   - [ ] API calls work with user-provided credentials
   - [ ] No keychain access errors in console
   - [ ] Network errors handled gracefully

3. **Check Console for Errors:**
   - Open Console app or Xcode console
   - Look for any `errSec` errors (should be none)
   - Verify no cross-app keychain access attempts

## Phase 4: Update Documentation

### Step 4.1: Update SETUP.md

**File:** `SETUP.md`

**Changes:**

1. **Update Cursor Authentication Section:**
   ```markdown
   ### Cursor Authentication
   
   **Note:** Cursor does not provide a public API. You have two options:
   
   **Option 1:** If Cursor provides an API key in settings:
   1. Open Cursor IDE
   2. Go to Settings > Account > API Keys
   3. Copy your API key
   4. Open Quota Guard Settings
   5. Paste the API key in the Cursor section
   6. Click "Save"
   
   **Option 2:** If no public API is available:
   - Cursor usage tracking may not be available
   - Check Cursor documentation for usage tracking options
   ```

2. **Update Claude Code Authentication Section:**
   ```markdown
   ### Claude Code Authentication
   
   1. Obtain your Claude Code OAuth token:
      - Check Claude Code documentation for OAuth token access
      - Or contact Claude Code support for API access
   2. Open Quota Guard Settings
   3. Paste the OAuth token in the Claude Code section
   4. Click "Save"
   
   **Note:** The OAuth token must be obtained from Claude Code's official documentation or support.
   ```

3. **Add Security Note:**
   ```markdown
   ## Security
   
   - All credentials are stored securely in macOS Keychain
   - Credentials are stored in QuotaGuard's own keychain (not shared with other apps)
   - No data is sent to external servers except the official API endpoints
   - All processing happens on your device
   ```

### Step 4.2: Update README.md

**File:** `README.md`

**Changes:**

1. **Update Cursor Authentication section** (lines 59-63):
   - Remove reference to automatic keychain access
   - Add manual credential input instructions

2. **Add App Store Compliance Note:**
   ```markdown
   ## Security & Privacy
   
   QuotaGuard is designed with security and privacy in mind:
   - All credentials stored securely in macOS Keychain
   - App Sandbox compliant (required for App Store)
   - No cross-app data access
   - Open source for transparency
   ```

### Step 4.3: Update XCODE_SETUP.md

**File:** `XCODE_SETUP.md`

**Changes:**

1. **Add App Sandbox Configuration:**
   ```markdown
   ### 7. Enable App Sandbox (Required for App Store)
   
   1. Select the `QuotaGuard` target
   2. Go to "Signing & Capabilities"
   3. Click "+ Capability"
   4. Add "App Sandbox"
   5. Enable "Outgoing Connections (Client)"
   6. Leave other permissions disabled
   ```

2. **Update Required Capabilities section:**
   ```markdown
   ## Required Capabilities
   
   ### Main App
   - App Groups (for widget data sharing)
   - App Sandbox (REQUIRED for App Store)
     - Outgoing Connections (Client)
   - Keychain (for storing credentials - uses default keychain, no special entitlement needed)
   
   ### Widget Extension
   - App Groups (same group as main app)
   ```

## Phase 5: Testing Checklist

### Pre-Implementation Testing
- [ ] Current implementation reviewed
- [ ] All files identified for changes
- [ ] Backup created (git commit)

### Implementation Testing
- [ ] Phase 1: Cross-app keychain access removed
- [ ] Phase 1: User credential input added
- [ ] Phase 1: AuthenticationManager updated
- [ ] Phase 2: Network monitoring removed (optional)
- [ ] Phase 3: App Sandbox enabled
- [ ] Phase 3: App works with App Sandbox

### Functional Testing
- [ ] Can save Cursor credentials
- [ ] Can save Claude Code credentials
- [ ] Can retrieve saved credentials
- [ ] Can delete credentials
- [ ] API calls work with saved credentials
- [ ] Error handling works correctly
- [ ] UI shows authentication status correctly

### Security Testing
- [ ] No cross-app keychain access attempts
- [ ] Credentials stored in our keychain only
- [ ] App Sandbox restrictions respected
- [ ] No security warnings in console
- [ ] Network errors handled securely

### App Store Readiness
- [ ] App Sandbox enabled
- [ ] No violations of App Store guidelines
- [ ] Documentation updated
- [ ] Error messages user-friendly
- [ ] Privacy policy considerations (if needed)

## Rollback Plan

If issues are discovered:

1. **Git Revert:**
   ```bash
   git revert <commit-hash>
   ```

2. **Restore Previous Version:**
   - Checkout previous working version
   - Test thoroughly before re-implementing

3. **Partial Rollback:**
   - Keep Phase 1 changes (required for App Store)
   - Revert Phase 2 if issues found (network monitoring)

## Estimated Time Breakdown

- **Phase 1 (Critical):** 3-4 hours
  - CursorLocalService updates: 1 hour
  - ClaudeCodeLocalService updates: 1 hour
  - AuthenticationManager updates: 30 minutes
  - SettingsView updates: 1-1.5 hours
  - Testing: 30 minutes

- **Phase 2 (Recommended):** 1-2 hours
  - Remove network monitoring: 1 hour
  - Improve error handling: 30 minutes
  - Testing: 30 minutes

- **Phase 3 (Testing):** 1 hour
  - Configure App Sandbox: 15 minutes
  - Testing: 45 minutes

- **Phase 4 (Documentation):** 1-2 hours
  - Update all documentation files

**Total:** 6-9 hours

## Success Criteria

- [ ] All cross-app keychain access removed
- [ ] User credential input implemented
- [ ] App works with App Sandbox enabled
- [ ] No security vulnerabilities
- [ ] All tests pass
- [ ] Documentation updated
- [ ] Ready for App Store submission

## Next Steps After Implementation

1. **Code Review:**
   - Review all changes with team
   - Verify security fixes
   - Check code quality

2. **User Testing:**
   - Test with real credentials
   - Verify user experience
   - Check error messages

3. **App Store Submission:**
   - Prepare App Store listing
   - Submit for review
   - Monitor for any issues

## References

- Security Assessment: `SECURITY-ASSESSMENT.md`
- Security Recommendations: `SECURITY-RECOMMENDATIONS.md`
- Task: `security-review-keychain-network-monitoring.md`
- PRD: `../PRDs/prd-security-review-keychain-network-monitoring.md`
