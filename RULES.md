# JobBus — Development Context & Rules

> **Last Updated**: 2026-04-26 (v1.0.0 Launch Release)
> **Status**: Production-ready, E2E tested, packaged for distribution

---

## 🏗️ What Is JobBus?

A **native macOS desktop application** (SwiftUI + Swift 5.9) that automates personalized job outreach:

1. **Parse** a resume (PDF/DOCX) → extract skills, experience, profile
2. **Discover** contacts via Apollo.io / Hunter.io / RocketReach APIs
3. **Generate** AI-powered personalized emails (Groq / OpenAI / Ollama)
4. **Send** campaigns via SMTP with resume attachment, rate limiting, and safety checks

---

## 📁 Project Structure

```
JobBus/
├── Package.swift                    # SPM manifest (SwiftNIO, ZIPFoundation)
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
│   │   ├── AI/AIProviders.swift     # Groq, OpenAI, Ollama HTTP clients + retry logic
│   │   ├── Email/SMTPEmailProvider.swift  # Raw SMTP via SwiftNIO + MIME builder
│   │   └── Search/                  # Apollo, Hunter, RocketReach search providers
│   ├── Services/
│   │   ├── AI/
│   │   │   ├── EmailWriter.swift    # Prompt engineering + style matching from samples
│   │   │   └── ResumeAnalyzer.swift # AI-powered resume parsing
│   │   ├── AppLogger.swift          # File + console logging (INFO/WARN/DEBUG)
│   │   ├── DocumentParser/          # PDF (PDFKit) and DOCX (ZIP) text extraction
│   │   ├── Import/CSVImporter.swift # CSV contact import
│   │   └── Safety/
│   │       ├── QualityScorer.swift  # 11-point email quality + duplicate detection
│   │       └── CampaignIntelligence.swift  # Pre-send analysis and stats
│   ├── ViewModels/
│   │   ├── AppViewModel.swift       # Central coordinator (settings, resume, navigation)
│   │   ├── ContactManager.swift     # Contact CRUD, search, import orchestration
│   │   ├── DraftManager.swift       # Draft generation, approval, batch operations
│   │   └── SendEngine.swift         # Campaign execution (send loop, pause/resume/stop)
│   └── Views/
│       ├── MainView.swift           # Sidebar + content layout
│       ├── Onboarding/OnboardingView.swift  # 4-step first-run wizard
│       ├── Settings/
│       │   ├── SettingsView.swift    # Tabbed settings (Providers, Email, Campaign, AI Prompt)
│       │   └── SMTPSetupGuideView.swift  # Gmail/Outlook/Custom SMTP instructions
│       └── Steps/
│           ├── Step1_ResumeView.swift    # Resume upload + parsing
│           ├── Step2_StrategyView.swift  # AI strategy review + filters
│           ├── Step3_ContactsView.swift  # Contact table + search + import
│           ├── Step4_DraftsView.swift    # Email drafts + quality scores + approval
│           └── Step5_SendView.swift      # Campaign dashboard + launch
├── Tests/                           # 58 unit tests
├── scripts/package.sh               # Build → .app bundle → .zip packaging
├── dist/                            # Generated .app and .zip (gitignored)
├── README.md                        # User-facing docs
├── INSTALL.md                       # Installation guide for other systems
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
- **EmailWriter** constructs prompts with: resume profile + contact context + custom instructions + writing style samples
- **Writing Style Samples**: Users paste 1-3 of their own emails → `buildStyleBlock()` injects them into the AI prompt for tone matching
- **Rate limiting**: Built-in retry with exponential backoff (3 attempts) for Groq/OpenAI

### Campaign Engine (SendEngine)
- `campaignState` is a **class-level stored property** (NOT task-local) — critical for pause/resume to work
- Campaign loop checks state on every iteration: `.running` → send, `.paused` → sleep loop, `.stopped` → break
- Delay between emails is randomized: `baseDelay ± 20%`
- Business hours enforcement with DST-safe date math

### Quality & Safety
- **QualityScorer**: 11-point scoring (subject length, body length, personalization, spam words, etc.)
- Contacts with empty emails are routed to duplicates list (EC7 fix)
- **CampaignIntelligence**: Pre-send analysis showing stats, estimated completion time, and risk warnings

---

## 🔐 Data Locations

| Data | Path | Format |
|---|---|---|
| Settings | `~/Library/Application Support/JobBus/settings.json` | JSON (Codable) |
| Credentials | `~/Library/Application Support/JobBus/credentials.dat` | Encrypted blob |
| Logs | `~/Library/Application Support/JobBus/logs/` | Timestamped text files |
| Resume | `~/Library/Application Support/JobBus/resume_attachment.pdf` | PDF/DOCX copy |

---

## ⚙️ Settings Schema (AppSettings.swift)

```swift
// Providers
searchProvider: SearchProviderType    // .apollo, .hunter, .rocketReach
aiProvider: AIProviderType            // .groq, .openAI, .ollama
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

## 🐛 Bugs Fixed (This Session)

| ID | Bug | Fix | File |
|---|---|---|---|
| EC1-3 | Pause/Resume broken | `campaignState` → class property | `SendEngine.swift` |
| EC5 | SMTP password visible | `SecureField` | `SettingsView.swift` |
| EC6 | No SMTP pre-flight check | `smtpReady` computed property + warning | `Step5_SendView.swift` |
| EC7 | Empty-email contacts leak | Route to duplicates | `QualityScorer.swift` |
| EC9 | DST calendar crash | Safe unwrap + fallback | `SendEngine.swift` |
| — | Dock "Quit" not working | Added `applicationShouldTerminate` delegate | `JobBusApp.swift` |
| — | App icon white background | Converted JPEG → PNG with alpha | `AppIcon.png` |

---

## ✅ E2E Test Results (2026-04-26)

| Phase | Result | Details |
|---|---|---|
| App Launch | ✅ | Groq AI, Apollo search, Sandbox ON |
| Resume Parse | ✅ | PDF → 5651 chars, profile in <1s |
| Draft Generation | ✅ | 7/7 drafts, all "excellent" quality |
| Campaign Send | ✅ | 3/3 sent, 0 failed via MailHog |
| MIME Structure | ✅ | 3 parts: plaintext + HTML + boundary |
| Logs | ✅ | Clean — only expected Groq rate-limit warnings |

---

## 📦 Packaging & Distribution

```bash
# Build + package in one command:
./scripts/package.sh

# Output:
# dist/JobBus.app           ← Double-click to run
# dist/JobBus-v1.0.0-macOS.zip  ← 3.6 MB, share via AirDrop/WhatsApp

# Recipient installation:
unzip JobBus-v1.0.0-macOS.zip
xattr -cr JobBus.app          # Remove quarantine (required for unsigned apps)
mv JobBus.app /Applications/
open /Applications/JobBus.app
```

---

## 🚀 What's Next (Potential Improvements)

### High Priority
- [ ] **Code signing & notarization** — eliminate the `xattr -cr` requirement
- [ ] **Unit test expansion** — 58 tests exist but need coverage for new features (onboarding, SMTP validation)
- [ ] **Pause/Resume E2E test** — needs a campaign with 5+ contacts to verify

### Medium Priority
- [ ] **Email tracking** — open/click tracking via pixel or link wrapping
- [ ] **Follow-up sequences** — auto-send follow-ups after N days if no reply
- [ ] **Contact enrichment** — LinkedIn profile scraping for better personalization
- [ ] **Template library** — pre-built email templates for common job types
- [ ] **Campaign history** — persist sent campaigns for analytics

### Low Priority
- [ ] **Dark mode polish** — verify all views look good in dark mode
- [ ] **Keyboard shortcuts** — ⌘N (new campaign), ⌘S (save), ⌘Enter (send)
- [ ] **Auto-update** — Sparkle framework for in-app updates
- [ ] **Export** — export sent emails / contacts to CSV
- [ ] **Multi-resume** — support different resumes for different job types

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
./scripts/package.sh           # Build + bundle + zip

# Test emails (separate terminal)
brew install mailhog && mailhog  # Start MailHog
# Open http://localhost:8025

# Dependencies
# Package.swift → SwiftNIO (SMTP), ZIPFoundation (DOCX parsing)
```

---

## ⚠️ Known Gotchas

1. **SPM + SwiftUI**: App must call `NSApplication.shared.setActivationPolicy(.regular)` in AppDelegate or text fields won't receive keyboard focus
2. **Icon**: SPM apps can't use Assets.xcassets — icon is loaded from `Bundle.module` at runtime via `AppDelegate`
3. **Keychain**: API keys and SMTP passwords use `KeychainService` — never store in `settings.json`
4. **Groq rate limits**: Free tier hits 429 frequently — the retry logic handles it (3 attempts with backoff)
5. **Resume attachment**: Only attached for contacts with `recipientType` of `.recruiter` or `.hiringManager`
6. **Sandbox default**: `sandboxMode` defaults to `true` — users must explicitly turn it off for production sends
