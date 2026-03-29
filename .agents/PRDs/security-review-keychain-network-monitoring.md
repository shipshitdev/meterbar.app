# PRD: Security Review - Keychain Access & Network Monitoring

**Status:** In Progress
**Priority:** P0 (Critical)
**Created:** 2026-01-10
**Last Updated:** 2026-01-10
**Related Tasks:** `../TASKS/security-review-keychain-network-monitoring.md`

## Problem Statement

QuotaGuard app currently implements two security-sensitive features that may:
1. Violate macOS App Sandbox requirements (required for App Store distribution)
2. Violate App Store Review Guidelines
3. Raise privacy concerns with users
4. Fail silently or require special entitlements that may not be granted

## Current Implementation

### 1. Cross-App Keychain Access

**CursorLocalService** (`QuotaGuard/Services/CursorLocalService.swift`):
- Accesses Cursor app's keychain using hardcoded service identifiers:
  - `keychainServiceAccess = "cursor-access-token"`
  - `keychainServiceRefresh = "cursor-refresh-token"`
  - `keychainAccount = "cursor-user"`
- Reads access and refresh tokens directly from Cursor's keychain storage
- Lines 47-93: Direct SecItemCopyMatching calls with Cursor's keychain identifiers

**ClaudeCodeLocalService** (`QuotaGuard/Services/ClaudeCodeLocalService.swift`):
- Accesses Claude Code's keychain using:
  - `keychainService = "Claude Code-credentials"`
- Reads OAuth tokens from Claude Code's keychain storage
- Lines 44-75: Direct SecItemCopyMatching calls with Claude Code's keychain identifiers

### 2. Network Monitoring

**Both Services** use network monitoring:
- `NWPathMonitor` for connectivity checks (lines 108-125 in CursorLocalService, 91-118 in ClaudeCodeLocalService)
- `NWConnection` for DNS resolution (lines 128-152 in CursorLocalService, 121-154 in ClaudeCodeLocalService)
- Pre-flight network diagnostics before API requests

## Security Concerns

### Keychain Access Risks

1. **App Sandbox Violation**: Cross-app keychain access may be blocked when App Sandbox is enabled (required for App Store)
2. **Fragile Implementation**: Relies on another app's internal keychain structure that could change at any time
3. **No User Consent**: Accesses other apps' credentials without explicit user permission
4. **Entitlements Required**: May need special entitlements that App Store won't approve
5. **Silent Failures**: May fail without clear error messages if access is denied
6. **Privacy Concerns**: Users may be uncomfortable with one app accessing another app's credentials

### Network Monitoring Risks

1. **Permission Requirements**: May require special entitlements or trigger security prompts
2. **Unnecessary Complexity**: URLSession already handles network connectivity and DNS resolution errors
3. **Privacy Concerns**: Network monitoring capabilities may trigger privacy warnings
4. **App Sandbox**: Network monitoring tools may be restricted in sandboxed apps

## Questions to Answer

### Keychain Access
- [ ] Does cross-app keychain access work with App Sandbox enabled?
- [ ] What entitlements are required? Will App Store approve them?
- [ ] Is there a public API or documented method for accessing these tokens?
- [ ] Should we require users to manually provide credentials instead?
- [ ] Can we access configuration files instead of keychain?
- [ ] What happens if Cursor/Claude Code changes their keychain structure?

### Network Monitoring
- [ ] Is network monitoring necessary, or does URLSession error handling suffice?
- [ ] What permissions/entitlements does NWPathMonitor require?
- [ ] Does NWPathMonitor work in App Sandbox?
- [ ] Can we simplify to just handle URLSession errors?
- [ ] Are there privacy implications that would concern users?

## Success Criteria

1. **Security Assessment Report** with:
   - Current security posture
   - Identified vulnerabilities
   - Risk levels (Critical/High/Medium/Low)
   - App Store compliance status

2. **Recommendations** for each issue:
   - Keep as-is (if secure and necessary)
   - Modify implementation (specific changes)
   - Remove feature (if unnecessary)
   - Alternative approach (better solution)

3. **Implementation Plan** (if changes needed):
   - Specific code changes required
   - Entitlements/permissions to add/remove
   - Testing requirements
   - Migration path for existing users

## Deliverables

1. Security Assessment Report (`SECURITY-ASSESSMENT.md`)
2. Implementation Recommendations (`SECURITY-RECOMMENDATIONS.md`)
3. Implementation Plan (if needed) (`SECURITY-IMPLEMENTATION-PLAN.md`)

## Timeline

- Investigation: 1-2 days
- Report writing: 1 day
- Review and approval: 1 day
- Implementation (if needed): TBD based on recommendations
