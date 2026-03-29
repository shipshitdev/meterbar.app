# PRD: Homebrew Cask Distribution

**Product:** Quota Guard
**Feature:** Install via Homebrew Cask (`brew install --cask quotaguard`)
**Priority:** P2 (Medium)
**Status:** Draft
**Created:** 2026-01-13
**Last Updated:** 2026-01-13
**Owner:** Engineering
**Related Tasks:** `../TASKS/homebrew-cask-distribution.md`

---

## Executive Summary

Enable users to install Quota Guard via Homebrew Cask, the standard way to install macOS GUI applications. This eliminates the friction of manual downloads, security warnings, and update management.

---

## Problem Statement

### Current State
- Users must manually download `.dmg` or `.zip` from GitHub Releases
- First-time launch requires right-click → Open to bypass Gatekeeper (app not notarized)
- No automatic update mechanism
- Users must manually check for new versions

### User Impact
- Extra friction during installation (multiple steps)
- Security warnings can be confusing ("Apple cannot verify this app")
- No streamlined update path
- Technical users expect `brew install` to work

### Business Impact
- Lower adoption rate due to installation friction
- Support requests about security warnings
- Perception as "less professional" without Homebrew presence

---

## Goals

### Primary Goals
1. **Create Homebrew Cask formula** - Enable `brew install --cask quotaguard`
2. **Automate release publishing** - Update formula automatically on new releases
3. **Improve discoverability** - Users can find app via `brew search`

### Success Metrics
- Users can install with single command: `brew install --cask quotaguard`
- Formula auto-updates when new GitHub release is published
- App launches correctly after Homebrew installation
- Uninstall via `brew uninstall quotaguard` works cleanly

---

## User Stories

### As a developer who uses Homebrew
**I want to** install Quota Guard via `brew install --cask quotaguard`
**So that** I can use my familiar workflow and get automatic updates

### As a user managing multiple apps
**I want to** update Quota Guard with `brew upgrade`
**So that** I don't have to manually check for updates

### As a user who wants clean uninstalls
**I want to** remove Quota Guard completely with `brew uninstall`
**So that** no orphaned files remain on my system

---

## Solution Design

### Option A: Homebrew Cask (Core) - Recommended
Submit formula to official `homebrew/homebrew-cask` repository.

**Pros:**
- Maximum discoverability (`brew search quotaguard` works)
- Trusted source, no tap needed
- Automatic formula maintenance by Homebrew community

**Cons:**
- Requires app notarization (code signing with Apple Developer ID)
- Strict review process
- Must meet Homebrew Cask guidelines

### Option B: Custom Homebrew Tap
Create `shipshitdev/homebrew-tap` repository with formula.

**Pros:**
- Full control over formula
- No notarization required
- Faster to publish

**Cons:**
- Users must add tap first: `brew tap shipshitdev/tap`
- Less discoverable
- We maintain the formula

### Recommendation
**Start with Option B (Custom Tap)** to ship quickly, then migrate to Option A after app notarization.

---

## Technical Requirements

### 1. Create Homebrew Tap Repository

Create new GitHub repo: `shipshitdev/homebrew-tap`

```
homebrew-tap/
├── Casks/
│   └── quotaguard.rb
└── README.md
```

### 2. Cask Formula Structure

```ruby
cask "quotaguard" do
  version "1.0.0"
  sha256 "abc123..." # SHA256 of the .zip file

  url "https://github.com/shipshitdev/quotaguardapp/releases/download/v#{version}/QuotaGuard-#{version}.zip"
  name "Quota Guard"
  desc "Track AI coding assistant usage limits from the menu bar"
  homepage "https://github.com/shipshitdev/quotaguardapp"

  livecheck do
    url :url
    strategy :github_latest
  end

  app "Quota Guard.app"

  zap trash: [
    "~/Library/Preferences/com.agenticindiedev.quotaguard.plist",
    "~/Library/Application Support/QuotaGuard",
    "~/Library/Caches/com.agenticindiedev.quotaguard",
  ]
end
```

### 3. Release Artifact Requirements

GitHub Release must include:
- `QuotaGuard-{version}.zip` containing `Quota Guard.app`
- Consistent naming convention across releases
- SHA256 checksum in release notes (or auto-computed)

### 4. CI/CD Integration

Update release workflow to:
1. Build and sign the app
2. Create `.zip` artifact with correct naming
3. Upload to GitHub Release
4. Compute SHA256
5. Auto-update Cask formula via PR or commit

### 5. Installation Flow

```bash
# First time only
brew tap shipshitdev/tap

# Install
brew install --cask quotaguard

# Update
brew upgrade quotaguard

# Uninstall
brew uninstall quotaguard
```

---

## Implementation Plan

### Phase 1: Setup (Day 1)
1. Create `shipshitdev/homebrew-tap` repository
2. Add initial Cask formula for current release
3. Test installation locally
4. Document installation in README

### Phase 2: Automation (Day 2)
1. Update release workflow to create proper `.zip` artifact
2. Add SHA256 computation to release process
3. Create GitHub Action to auto-update formula on release
4. Test end-to-end release flow

### Phase 3: Documentation (Day 3)
1. Update README with Homebrew installation instructions
2. Add badges for Homebrew formula version
3. Update website/landing page if applicable

### Future: Homebrew Core Migration
1. Apply for Apple Developer ID (if not already)
2. Notarize app builds
3. Submit Cask to `homebrew/homebrew-cask`
4. Redirect custom tap users to official formula

---

## Release Workflow Changes

Current workflow creates: Binary download from Releases page

New workflow should create:
```
QuotaGuard-v1.0.0.zip
├── Quota Guard.app/
│   ├── Contents/
│   │   ├── MacOS/
│   │   ├── Resources/
│   │   └── Info.plist
```

The `.zip` should:
- Contain only the `.app` bundle
- Have consistent naming: `QuotaGuard-v{version}.zip`
- Be created by `ditto -c -k --keepParent "Quota Guard.app" output.zip`

---

## Testing Checklist

- [ ] Formula syntax is valid (`brew audit --cask quotaguard`)
- [ ] Installation succeeds (`brew install --cask quotaguard`)
- [ ] App launches after installation
- [ ] App appears in `/Applications/`
- [ ] Uninstall removes app (`brew uninstall quotaguard`)
- [ ] Upgrade works when new version released
- [ ] `zap` removes all app data
- [ ] Formula auto-updates on new release

---

## Risks & Mitigations

| Risk | Impact | Mitigation |
|------|--------|------------|
| Users unfamiliar with custom taps | Medium | Clear docs, consider official Cask eventually |
| GitHub release artifact format changes | High | Pin workflow, test on release |
| Notarization required for official Cask | High | Start with custom tap, notarize later |

---

## References

- [Homebrew Cask Documentation](https://github.com/Homebrew/homebrew-cask/blob/master/CONTRIBUTING.md)
- [Creating a Tap](https://docs.brew.sh/How-to-Create-and-Maintain-a-Tap)
- [Cask Cookbook](https://docs.brew.sh/Cask-Cookbook)
- [App Notarization](https://developer.apple.com/documentation/security/notarizing_macos_software_before_distribution)
