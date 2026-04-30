# JobBus — Development Context & Rules

> **Last Updated**: 2026-04-30 (Disabled Button Fix — isLoading flag, Developer ID + Notarization packaging)
> **Version**: 1.1.5
> **Status**: App Store build uploaded ✅ — Direct distribution DMG signed + notarized ✅

---

## 🔁 Session Protocol (READ THIS FIRST)

### Starting a session
```
"I'm working on JobBus. Read @RULES.md for context."
```

### Ending a session
```
"Update RULES.md and push."
```
The AI will update the "Last Updated" date, "Bugs Fixed" table, "What's Next" list,
and any architectural changes — then commit and push to git.

**This ensures zero context loss between sessions, across any AI assistant.**

---

## 🏗️ What Is JobBus?

A **native macOS desktop application** (SwiftUI + Swift 5.9) that automates personalized job outreach:

1. **Parse** a resume (PDF/DOCX) → extract skills, experience, profile
2. **Discover** contacts via Apollo.io / Hunter.io / RocketReach APIs
3. **Generate** AI-powered personalized emails (Gemini / Groq / OpenAI / Ollama)
4. **Send** campaigns via SMTP with resume attachment, rate limiting, and safety checks

---

## 📁 Project Structure

```
JobBus/
├── Package.swift                    # SPM manifest (SwiftNIO, ZIPFoundation)
├── VERSION                          # Single source of truth for app version
├── Sources/
│   ├── JobBusApp.swift              # @main entry, AppDelegate (activation, quit, icon)
│   ├── Models/
│   │   ├── AppSettings.swift        # All settings — Codable, @Published, JSON persistence
│   │   ├── Contact.swift            # Contact model + RecipientType enum
│   │   ├── EmailDraft.swift         # Draft model (subject, body, quality, approval)
│   │   └── ResumeProfile.swift      # Parsed resume data
│   ├── Protocols/
│   │   └── Protocols.swift          # SearchProvider, EmailProvider, AIProvider protocols
│   ├── Providers/
│   │   ├── AI/AIProviders.swift     # Gemini, Groq, OpenAI, Ollama + dynamic model discovery + fallback
│   │   ├── Email/SMTPEmailProvider.swift  # Raw SMTP via SwiftNIO + MIME builder
│   │   └── Search/                  # Apollo, Hunter, RocketReach search providers
│   ├── Services/
│   │   ├── AI/
│   │   │   ├── EmailWriter.swift    # Prompt engineering + style matching from samples
│   │   │   └── ResumeAnalyzer.swift # AI-powered resume parsing
│   │   ├── AppLogger.swift          # File + console logging — dynamic version in headers
│   │   ├── DocumentParser/          # PDF (PDFKit) and DOCX (ZIP) text extraction
│   │   ├── Import/CSVImporter.swift # CSV contact import
│   │   ├── UsageTracker.swift       # Cumulative Apollo credits + Groq tokens, persisted
│   │   └── Safety/
│   │       ├── QualityScorer.swift  # 11-point email quality + duplicate detection
│   │       └── CampaignIntelligence.swift  # Pre-send analysis and stats
│   ├── ViewModels/
│   │   ├── AppViewModel.swift       # Central coordinator (settings, resume, navigation)
│   │   ├── ContactManager.swift     # Contact CRUD, search, import orchestration
│   │   ├── DraftManager.swift       # Draft generation, approval, batch operations
│   │   └── SendEngine.swift         # Campaign execution (send loop, pause/resume/stop)
│   └── Views/
│       ├── Components/
│       │   └── LoadingOverlay.swift  # Premium animated loading (pulse rings, phases, progress)
│       ├── MainView.swift           # Sidebar + content layout + usage stats footer
│       ├── Onboarding/OnboardingView.swift  # 4-step first-run wizard
│       ├── Settings/
│       │   ├── SettingsView.swift    # 5 tabs: Providers, Email, Campaign, AI Prompt, About
│       │   └── SMTPSetupGuideView.swift  # Gmail/Outlook/Custom SMTP instructions
│       └── Steps/
│           ├── Step1_ResumeView.swift    # Resume upload + parsing
│           ├── Step2_StrategyView.swift  # AI strategy review + filters
│           ├── Step3_ContactsView.swift  # Contact table + search + resume/restart dialog
│           ├── Step4_DraftsView.swift    # Email drafts + quality scores + approval
│           └── Step5_SendView.swift      # Campaign dashboard + launch
├── Tests/                           # 58 unit tests
├── scripts/
│   ├── package.sh                   # Build → sign → .app + .zip + .dmg packaging
│   └── Install JobBus.command       # Double-click installer for end users
├── dist/                            # Generated .app, .zip, .dmg, .pkg (gitignored)
│   ├── appstore/                    # App Store .pkg builds
│   ├── screenshots/                 # App Store screenshots (2560x1600)
│   └── screenshots_clean/           # sRGB JPEG screenshots for upload
├── README.md                        # User-facing docs
├── INSTALL.md                       # Installation guide for other systems
├── PRIVACY.md                       # Privacy policy (required for App Store)
├── LICENSE                          # MIT
└── RULES.md                         # THIS FILE — development context
```

---

## 🔧 Key Architecture Decisions

### State Management
- **AppViewModel** (`@StateObject`) is the single source of truth, passed via `.environmentObject()`
- **AppSettings** is `ObservableObject` with `@Published` properties, persisted to `~/Library/Application Support/JobBus/settings.json`
- **Credentials** (API keys, SMTP passwords) stored in `KeychainService` (encrypted), NOT in settings JSON

### SMTP & Email
- **SMTPEmailProvider** uses raw SwiftNIO sockets (no third-party SMTP library)
- MIME messages built manually: `multipart/mixed` → `multipart/alternative` (plaintext + HTML) + optional PDF attachment
- **Sandbox Mode** (default ON): routes all emails to `localhost:1025` (MailHog) for safe testing
- Resume attachment is controlled per-contact via `Contact.shouldAttachResume` (true for recruiter/hiringManager types)

### AI Integration
- **Dynamic Model Discovery**: Gemini and Groq fetch available models at runtime via ListModels APIs
  - Gemini: `GET /v1beta/models?pageSize=100`, filtered for `generateContent` capability
  - Groq: `GET /openai/v1/models`, filtered for `active: true` and `chat` context
  - Hardcoded fallback lists if API calls fail (network error, DNS, timeout)
- **503/429 Handling**: Overloaded or rate-limited responses trigger automatic fallback to next-best model in the preference list
- **EmailWriter** constructs prompts with: resume profile + contact context + custom instructions + writing style samples
- **Writing Style Samples**: Users paste 1-3 of their own emails → `buildStyleBlock()` injects them into the AI prompt for tone matching

### Campaign Engine (SendEngine)
- `campaignState` is a **class-level stored property** (NOT task-local) — critical for pause/resume to work
- Campaign loop checks state on every iteration: `.running` → send, `.paused` → sleep loop, `.stopped` → break
- Delay between emails is randomized: `baseDelay ± 20%`
- Business hours enforcement with DST-safe date math

### Quality & Safety
- **QualityScorer**: 11-point scoring (subject length, body length, personalization, spam words, etc.)
- Contacts with empty emails are routed to duplicates list (EC7 fix)
- **CampaignIntelligence**: Pre-send analysis showing stats, estimated completion time, and risk warnings

### Usage Tracking (UsageTracker)
- **Cumulative stats**: Apollo credits used, search count, Groq tokens consumed, AI call count
- **Persisted** to `~/Library/Application Support/JobBus/usage_stats.json` — survives app restarts
- **Notification-based**: `AIProviders.swift` posts `.aiTokensUsed` with `usage.total_tokens`; `ApolloSearchProvider.swift` posts `.apolloCreditUsed` on successful enrichment
- **AppViewModel** subscribes via Combine and forwards changes to SwiftUI
- **Sidebar footer** in `MainView` shows live stats with reset button + confirmation dialog

### Loading Overlay (LoadingOverlay.swift)
- **Phase-aware**: Different icon + gradient per operation phase (parsing, searching, enriching, composing, sending)
- **Animated pulse rings**: 3 concentric circles with staggered animation + SF Symbols `.symbolEffect(.pulse)`
- **Progress bar**: Spring-animated fill bar for batch operations (e.g., enrichment 3/8)
- **Glassmorphism**: `.ultraThinMaterial` backdrop with gradient border stroke
- Replaces all `ProgressView()` spinners across Step1, Step2, Step3

### Draft Resume/Restart
- When user cancels draft generation mid-way and returns to compose, a dialog offers **Resume** (generate remaining) vs **Restart All** (clear + regenerate)
- `generateDraftsFromScratch()` clears all existing drafts before re-invoking `generateDrafts()`

### Logging (AppLogger.swift)
- **Thread-safe**: Uses `DispatchQueue(label: "com.jobbus.logger", qos: .utility)` for serial writes
- **Dual output**: Console (print) + rotating log files in `~/Library/Application Support/JobBus/logs/`
- **Session files**: Each launch creates `jobbus_YYYY-MM-DD_HH-mm-ss.log` with version + OS header
- **Dynamic version**: Log header reads `CFBundleShortVersionString` + `CFBundleVersion` from Info.plist
- **Auto-cleanup**: Keeps last 20 log files, deletes older ones
- **Settings UI**: About tab shows log file stats, "Open Logs Folder" + "View Current Log" buttons, "Clear Old Logs" action

---

## 🔐 Data Locations

| Data | Path | Format |
|---|---|---|
| Settings | `~/Library/Application Support/JobBus/settings.json` | JSON (Codable) |
| Credentials | `~/Library/Application Support/JobBus/credentials.dat` | Encrypted blob |
| Logs | `~/Library/Application Support/JobBus/logs/` | Timestamped text files |
| Resume | `~/Library/Application Support/JobBus/resume_attachment.pdf` | PDF/DOCX copy |
| Usage Stats | `~/Library/Application Support/JobBus/usage_stats.json` | JSON (cumulative) |

---

## ⚙️ Settings Schema (AppSettings.swift)

```swift
// Providers
searchProvider: SearchProviderType    // .apollo, .hunter, .rocketReach
aiProvider: AIProviderType            // .gemini, .groq, .openAI, .ollama
emailProvider: EmailProviderType      // .gmail, .outlook, .custom

// Email
smtpEmail: String                     // Sender email address
smtpDisplayName: String               // "From" display name
customSmtpHost: String                // Custom SMTP server
customSmtpPort: Int                   // Custom SMTP port

// Campaign
delaySeconds: Double                  // Base delay between emails (default: 45)
maxPerDay: Int                        // Daily send limit (default: 450)
businessHoursOnly: Bool               // Restrict to business hours
businessHoursStart/End: Int           // 9-18 default
warmUpEnabled: Bool                   // Gradual ramp-up

// Sandbox
sandboxMode: Bool                     // DEFAULT TRUE — routes to MailHog
sandboxHost: String                   // localhost
sandboxPort: Int                      // 1025

// AI
ollamaModel: String                   // llama3.1:8b
ollamaBaseURL: String                 // http://localhost:11434
customPromptInstructions: String      // Free-form AI prompt additions
sampleEmails: [String]                // User's own email samples for style matching

// Signature
signatureName, signatureTitle, signatureLinkedin, signaturePhone: String

// State
hasCompletedOnboarding: Bool          // First-run wizard flag
contactCount: Int                     // Number of contacts to search for
```

---

## 🐛 Bugs Fixed (This Session — 2026-04-30)

| ID | Bug | Fix | File |
|---|---|---|---|
| — | "Find Contacts" button permanently disabled on Step 2 | Removed `vm.isLoading` from disabled condition — `isLoading` gates resume parsing, not search | `Step2_StrategyView.swift` |
| — | "Apollo Search" button disabled on Step 3 (same root cause) | Removed `vm.isLoading` from disabled condition | `Step3_ContactsView.swift` |
| — | `isLoading` flag could get stuck `true` on edge-case error paths | Added `defer { isLoading = false }` to `parseResume()` — guarantees reset on all exit paths | `AppViewModel.swift` |

### Previous Session (2026-04-29)

| ID | Bug | Fix | File |
|---|---|---|---|
| 90886 | Missing application identifier in bundle signature | Added `com.apple.application-identifier` and `com.apple.developer.team-identifier` to entitlements | `AppStore.entitlements` |
| 91109 | `com.apple.quarantine` xattr in .pkg rejected by App Store | `xattr -cr` + `ditto --norsrc` to strip all extended attributes before packaging | Packaging pipeline |
| — | Build version collision in App Store Connect | Bumped version to 1.1.5 (Build 1) for distinct identification | `VERSION` |
| — | Screenshots rejected by App Store Connect | Converted to sRGB JPEG at exact 2560×1600 dimensions | `dist/screenshots_clean/` |

### Previous Session (2026-04-27)

| ID | Bug | Fix | File |
|---|---|---|---|
| — | Hardcoded model lists → 404 crashes | Dynamic ListModels API (Gemini + Groq) with fallback | `AIProviders.swift` |
| — | 503 overloaded kills generation | Auto-fallback to next model in preference list | `AIProviders.swift` |
| — | 429 rate limit kills generation | Catch + retry with next model | `AIProviders.swift` |
| — | Groq inactive/non-chat models cause errors | Filter by `active: true` + `chat` context | `AIProviders.swift` |
| — | Gemini model list truncated | `pageSize=100` for full list | `AIProviders.swift` |
| — | No versioning → confusion on builds | `VERSION` file + `package.sh --bump` auto-increment | `VERSION`, `package.sh` |
| — | Log header shows hardcoded "1.0" | Dynamic version from `CFBundleShortVersionString` | `AppLogger.swift` |
| — | No build metadata in releases | `BUILD_INFO.txt` manifest (version, git hash, date, arch) | `package.sh` |
| — | Logs inaccessible to users | "About" tab with Open Logs / View Current / Clear Old | `SettingsView.swift` |
| — | No version info in app | About tab shows version + build number from Info.plist | `SettingsView.swift` |
| — | App shows "damaged" on other Macs | Ad-hoc code signing (`codesign --sign -`) | `package.sh` |
| — | "Unsealed contents" breaks codesign | Resource bundle → `Contents/Resources/` (not app root) | `package.sh`, `JobBusApp.swift` |
| — | No user-friendly installer | DMG with drag-to-install + `Install JobBus.command` | `package.sh`, `Install JobBus.command` |
| — | `Bundle.module` crash in .app | Icon loaded via `Bundle.main.resourceURL` (no `Bundle.module`) | `JobBusApp.swift` |
| — | "Gemini Flash" provider rename crash | Custom `Decodable` init migrates old settings | `AppSettings.swift` |

---

## ✅ E2E Test Results (2026-04-26)

| Phase | Result | Details |
|---|---|---|
| App Launch | ✅ | Groq AI, Apollo search, Sandbox ON |
| Resume Parse | ✅ | PDF → 5651 chars, profile in <1s |
| Contact Discovery | ✅ | 8/8 contacts discovered + enriched with emails |
| Draft Generation | ✅ | 8/8 drafts, all "excellent" quality |
| Campaign Send | ✅ | 2/8 sent, pause/resume/stop verified |
| MIME Structure | ✅ | 3 parts: plaintext + HTML + boundary |
| Usage Tracking | ✅ | Credits + tokens accumulate across sessions |
| Loading UI | ✅ | Animated overlays with phase-aware icons |
| Resume/Restart | ✅ | Dialog appears on partial drafts, both paths work |
| Logs | ✅ | Clean — only expected Groq rate-limit warnings |

---

## 📦 Packaging & Distribution

### Versioning
- `VERSION` file is single source of truth
- `package.sh --bump` auto-increments patch version
- Build number: `{git_commit_count}.{short_hash}` (e.g., `26.da9610c`)
- Both stamped into `Info.plist` (`CFBundleShortVersionString` + `CFBundleVersion`)

### Distribution Channels

#### 1. App Store (Primary — v1.1.5+)
- **Status**: Build v1.1.5 (1) uploaded & processed ✅ on App Store Connect
- **TestFlight**: Build is Complete, ready for internal testing groups
- **Signing**: `3rd Party Mac Developer Application: Viren Baid (TS6UH83Q2Q)`
- **Installer Signing**: `3rd Party Mac Developer Installer: Viren Baid (TS6UH83Q2Q)`
- **Bundle ID**: `com.neelmani.jobbus`
- **Team ID**: `TS6UH83Q2Q`
- **Provisioning Profile**: Embedded at `Contents/embedded.provisionprofile`
- **Entitlements**: `Sources/Resources/AppStore.entitlements`
- **Upload Tool**: Transporter (GUI) — proven stable for `.pkg` delivery

#### App Store Build Pipeline
```
swift build -c release
→ ditto --norsrc (strip xattrs) → clean .app bundle
→ codesign inner binary with entitlements (3rd Party Mac Developer Application)
→ codesign outer .app bundle with entitlements
→ embed provisioning profile
→ xattr -cr (strip ALL quarantine/provenance attributes)
→ productbuild --sign (3rd Party Mac Developer Installer) → .pkg
→ Upload via Transporter
```

#### AppStore.entitlements (Sources/Resources/AppStore.entitlements)
```xml
<key>com.apple.security.app-sandbox</key> <true/>
<key>com.apple.security.network.client</key> <true/>
<key>com.apple.security.files.user-selected.read-only</key> <true/>
<key>com.apple.application-identifier</key> <string>TS6UH83Q2Q.com.neelmani.jobbus</string>
<key>com.apple.developer.team-identifier</key> <string>TS6UH83Q2Q</string>
```

#### 2. Direct Distribution (Ad-hoc)
```bash
./scripts/package.sh              # Same version
./scripts/package.sh --bump       # Increment patch version

# Output (dist/):
# dist/JobBus.app                     ← App bundle (ad-hoc signed)
# dist/JobBus-v1.1.5-macOS.zip       ← For techies (includes Install.command)
# dist/JobBus-v1.1.5-macOS.dmg       ← For everyone (drag to Applications)
# dist/BUILD_INFO.txt                ← Build metadata manifest
```

### Installation (direct distribution)
**DMG (recommended):** Open DMG → drag JobBus to Applications → right-click → Open

**If "damaged" error appears:**
```bash
xattr -cr /Applications/JobBus.app && open /Applications/JobBus.app
```

**Or:** System Settings → Privacy & Security → "Open Anyway"

### App Store Submission Collaterals
- **Screenshots**: 5 promotional images at 2560×1600 (sRGB JPEG) in `dist/screenshots_clean/`
- **Privacy Policy**: `PRIVACY.md` in repo root (URL: `https://github.com/neelmanim/JobBus/blob/main/PRIVACY.md`)
- **Support URL**: `https://github.com/neelmanim/JobBus`
- **Category**: Productivity / Business
- **Price**: Free
- **App Review Notes**: Explains API key requirements, sandbox mode, no demo credentials needed

---

## 🚀 What's Next (Potential Improvements)

### Immediate (App Store)
- [ ] **Complete App Store submission** — fill metadata, upload screenshots, submit for review
- [ ] **TestFlight internal testing** — create test group, add testers, validate on real devices
- [ ] **App Store Review prep** — ensure sandbox mode and API key flow pass review guidelines

### High Priority
- [x] ~~**Apple Developer certificate** — proper code signing + notarization~~ ✅ Done (signed with 3rd Party Mac Developer certs)
- [ ] **Unit test expansion** — 58 tests exist but need coverage for new features (onboarding, SMTP validation)

### Medium Priority
- [ ] **Email tracking** — open/click tracking via pixel or link wrapping
- [ ] **Follow-up sequences** — auto-send follow-ups after N days if no reply
- [ ] **Template library** — pre-built email templates for common job types
- [ ] **Campaign history** — persist sent campaigns for analytics
- [ ] **Usage stats detail view** — expandable panel showing per-session breakdown, cost estimates

### Low Priority
- [ ] **Dark mode polish** — verify all views look good in dark mode
- [ ] **Auto-update** — Sparkle framework for in-app updates (not needed if on App Store)
- [ ] **Export** — export sent emails / contacts to CSV
- [ ] **Multi-resume** — support different resumes for different job types

### Backlog
- [ ] **iOS / iPadOS port** — ~3-4 weeks effort, ~60% code reuse. Recommend iPad-first (skip iPhone). Key blockers: background execution (iOS kills after 30s), App Store rejection risk (use TestFlight). Views (3,800 lines) need full rewrite for iOS nav patterns. Full analysis: `ios_feasibility_analysis.md` in conversation artifacts.

---

## 🧰 Development Commands

```bash
# Build
swift build                    # Debug build
swift build -c release         # Release build

# Run
.build/release/JobBus          # Run from terminal

# Test
swift test                     # Run 58 unit tests

# Package
./scripts/package.sh           # Build + sign + bundle + zip + dmg
./scripts/package.sh --bump    # Same + increment patch version

# Test emails (separate terminal)
brew install mailhog && mailhog  # Start MailHog
# Open http://localhost:8025

# Dependencies
# Package.swift → SwiftNIO (SMTP), ZIPFoundation (DOCX parsing)
```

---

## ⚠️ Known Gotchas

1. **SPM + SwiftUI**: App must call `NSApplication.shared.setActivationPolicy(.regular)` in AppDelegate or text fields won't receive keyboard focus
2. **Icon loading**: SPM apps can't use Assets.xcassets — icon loaded from `Bundle.main.resourceURL` at runtime (NOT `Bundle.module` which crashes if resource bundle isn't at app root)
3. **Keychain**: API keys and SMTP passwords use `KeychainService` — never store in `settings.json`
4. **Groq rate limits**: Free tier hits 429 frequently — the retry logic handles it (3 attempts with backoff)
5. **Resume attachment**: Only attached for contacts with `recipientType` of `.recruiter` or `.hiringManager`
6. **Sandbox default**: `sandboxMode` defaults to `true` — users must explicitly turn it off for production sends
7. **Apollo 2-step flow**: Discovery via `/mixed_people/api_search` returns only IDs + obfuscated names; enrichment via `/people/match` with Apollo ID is mandatory to get emails
8. **Apollo rate limiting**: 1.5s inter-request delay prevents 403 blocks; enrichment retry waits 60s on 429
9. **Usage tracker persistence**: `Task.detached` for file I/O — must capture `Self.fileURL` before the detached context to avoid `@MainActor` isolation errors
10. **Notification-based tracking**: AI providers post token/credit notifications (decoupled from AppViewModel) — subscribed via Combine in `init()`
11. **Code signing**: Ad-hoc signing (`codesign --sign -`) requires all content inside `Contents/`. SPM resource bundles MUST go in `Contents/Resources/`, NOT the app root — otherwise `codesign` fails with "unsealed contents"
12. **Dynamic model discovery**: Gemini/Groq model lists fetched at runtime; if API is down, hardcoded fallback models are used. Never assume a model name is permanent.
13. **Provider rename migration**: Changing `AIProviderType` raw values requires a custom `init(from: Decoder)` to migrate existing user settings — otherwise `Decodable` crashes
14. **App Store entitlements**: `AppStore.entitlements` MUST include `com.apple.application-identifier` (format: `TEAMID.BUNDLEID`) and `com.apple.developer.team-identifier` — without these, TestFlight rejects with error 90886
15. **Quarantine xattrs in .pkg**: macOS adds `com.apple.quarantine` and `com.apple.provenance` to downloaded/created files. These MUST be stripped via `xattr -cr` or `ditto --norsrc` before packaging — App Store rejects with error 91109
16. **macOS Sequoia provenance**: `com.apple.provenance` xattr is re-added automatically by the OS on every file operation. Use `ditto --norsrc` for copy operations to avoid re-introduction
17. **App Store screenshots**: Must be exact 2560×1600 (or 1280×800, 1440×900, 2880×1800), sRGB color space, JPEG or PNG. Generated images may have wrong color profile — always convert with `sips -m /System/Library/ColorSync/Profiles/sRGB\ Profile.icc`
18. **Transporter for uploads**: CLI tools (`altool`, `xcrun notarytool`) can be flaky — Transporter.app (GUI) is the proven reliable method for uploading `.pkg` to App Store Connect
19. **Privacy Policy required**: App Store submission requires a public privacy policy URL — `PRIVACY.md` in repo serves this purpose (must be on a public URL)
20. **`isLoading` flag scope**: `isLoading` is for resume parsing (Step 1) only. Do NOT use it to gate buttons on Step 2/3 — if it gets stuck, it permanently disables search/import. Each operation has its own guard (`isSearching`, `isGenerating`). Use `defer { flag = false }` for safety.
21. **App Store .pkg ≠ local install**: `.pkg` files signed with "3rd Party Mac Developer Installer" are for App Store Connect upload via Transporter ONLY. They cannot be installed locally — macOS Installer refuses them. Use Developer ID-signed DMG for local distribution.
