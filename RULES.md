# Job Bus — Project Rules & Reference

> **Native macOS application for personalized, AI-powered job outreach.**
> Built with SwiftUI · Swift Package Manager · macOS 14+

---

## 📌 Repository

| Item | Value |
|---|---|
| **Repo** | `git@github.com:neelmanim/JobBus.git` |
| **HTTPS** | `https://github.com/neelmanim/JobBus` |
| **Local Path** | `/Users/neelmani-mishra/Documents/TryingSomethingInteresting/JobBus/` |
| **Auth** | SSH key (`~/.ssh/id_ed25519`) |
| **Package Manager** | Swift Package Manager (`Package.swift`) |
| **Min Target** | macOS 14.0 (Sonoma) |
| **Dependencies** | `ZIPFoundation` (DOCX parsing) |

---

## 🌿 Branch Strategy

| Branch | Purpose | Rules |
|---|---|---|
| `main` | Production-ready, stable | Never commit directly — merge from `develop` via PR |
| `develop` | Active development | All new features and fixes go here first |

### Workflow

```
feature-branch → develop → main
```

1. Create feature branches off `develop` for significant work
2. Small fixes can go directly to `develop`
3. Merge `develop` → `main` only when tested and stable
4. Tag releases on `main` (e.g., `v1.0`, `v1.1`)

---

## 🏗️ Architecture

### Design Principles

1. **Protocol-based modularity** — Every external service (search, AI, email) is behind a Swift protocol. Swap providers in Settings without code changes.
2. **No third-party UI frameworks** — Pure SwiftUI. No Electron, no web views.
3. **No third-party networking** — Raw `URLSession` for APIs, raw socket `InputStream`/`OutputStream` for SMTP. Full control over every byte.
4. **Keychain for secrets** — API keys and passwords stored in macOS Keychain, never in files or UserDefaults.
5. **Sandbox-first** — Sandbox mode is ON by default. Must be explicitly disabled before real emails can be sent.

### Source Structure

```
Sources/
├── JobBusApp.swift                          # @main entry point
│
├── Models/
│   ├── AppSettings.swift                    # Settings + Keychain + persistence
│   ├── Contact.swift                        # Contact, ContactSource, RecipientType
│   ├── EmailDraft.swift                     # Draft, QualityScore, SendRecord
│   └── ResumeProfile.swift                  # ResumeProfile, SearchStrategy
│
├── Protocols/
│   └── Protocols.swift                      # ContactSearchProvider, AIProvider,
│                                            # EmailSenderProvider, EmailEnrichmentProvider
│
├── Providers/                               # Concrete implementations of protocols
│   ├── AI/AIProviders.swift                 # OllamaProvider, GeminiFlashProvider
│   ├── Email/SMTPEmailProvider.swift        # SMTPEmailProvider, SMTPClient, EmailTemplateBuilder
│   └── Search/ApolloSearchProvider.swift    # ApolloSearchProvider (search + enrich)
│
├── Services/
│   ├── AI/
│   │   ├── EmailWriter.swift               # AI prompt engineering + email composition
│   │   └── ResumeAnalyzer.swift             # Resume → profile + strategy extraction
│   ├── DocumentParser/
│   │   ├── DOCXParserService.swift          # DOCX via ZIP extraction of word/document.xml
│   │   └── PDFParserService.swift           # PDF via Apple PDFKit
│   ├── Import/CSVImporter.swift             # CSV with auto-detect delimiter/columns/encoding
│   └── Safety/QualityScorer.swift           # 8-point scorer + duplicate detector
│
├── ViewModels/
│   └── AppViewModel.swift                   # Central pipeline orchestrator
│
├── Views/
│   ├── MainView.swift                       # NavigationSplitView + sidebar steps
│   ├── Settings/SettingsView.swift          # Tabbed settings (providers, email, campaign)
│   └── Steps/
│       ├── Step1_ResumeView.swift           # Drop zone + AI analysis display
│       ├── Step2_StrategyView.swift         # Filter builder + contact count slider
│       ├── Step3_ContactsView.swift         # Multi-source table + CSV import + manual entry
│       ├── Step4_DraftsView.swift           # Draft review + quality badges + edit/regenerate
│       └── Step5_SendView.swift             # Campaign progress ring + controls
│
└── Resources/
    └── AppIcon.png
```

---

## 🔌 Provider System (Modular)

All providers conform to protocols in `Protocols.swift`. To add a new provider:

1. Create a new class conforming to the relevant protocol
2. Add the provider type to the corresponding enum in `AppSettings.swift`
3. Add the factory case in `AppViewModel.swift`

### Search Providers

| Provider | Protocol | Status |
|---|---|---|
| Apollo.io | `ContactSearchProvider` + `EmailEnrichmentProvider` | ✅ Implemented |
| Hunter.io | `ContactSearchProvider` | 🔲 Placeholder |
| RocketReach | `ContactSearchProvider` | 🔲 Placeholder |

### AI Providers

| Provider | Protocol | Status |
|---|---|---|
| Ollama (Local) | `AIProvider` | ✅ Implemented |
| Gemini Flash | `AIProvider` | ✅ Implemented |
| Groq | `AIProvider` | 🔲 Placeholder |

### Email Providers

| Provider | Protocol | Status |
|---|---|---|
| Gmail SMTP | `EmailSenderProvider` | ✅ Implemented |
| Outlook SMTP | `EmailSenderProvider` | ✅ Implemented |
| Custom SMTP | `EmailSenderProvider` | ✅ Implemented |

---

## 🚦 App Pipeline (5 Steps)

```
Step 1: Resume Upload → Parse PDF/DOCX → AI extracts profile
            ↓
Step 2: AI Strategy → Review/edit search filters → Set contact count
            ↓
Step 3: Contacts → Apollo search + enrich → CSV import → Manual add
            ↓
Step 4: AI Compose → Draft per contact → Quality score → Review/edit
            ↓
Step 5: Campaign → Type-to-confirm → Throttled send → Live progress
```

---

## 🛡️ Safety Guardrails

### Layer 1: Automated Validation (Pre-Send)

| Check | What It Does | Blocks If |
|---|---|---|
| Name Match | Verifies recipient's first name appears in body | Name missing |
| Company Match | Verifies company name in body or subject | Company missing |
| Length Check | Body must be 30–250 words | Outside range |
| Subject Length | Subject must be 5–100 characters | Outside range |
| Placeholder Scan | Detects `{{`, `[NAME]`, `XXX`, `INSERT`, etc. | Any found |
| Spam Word Scan | 17 spam triggers: "act now", "guaranteed", "click here", etc. | Any found |
| CTA Detection | Must have a soft call-to-action | No CTA detected |
| Tone Check | Blocks 7 weak/generic phrases like "I hope this finds you well" | Any found |

### Layer 2: Human-in-the-Loop Gates

| Gate | When | What Happens |
|---|---|---|
| **Min 10 Reviews** | Before "Approve All" unlocks | Must manually review at least 10 drafts |
| **Type-to-Confirm** | Before campaign launch | Must type exactly `SEND {count}` to proceed |
| **First-3 Hold** | After first 3 emails sent | Auto-pauses — user must check Gmail Sent folder |

### Layer 3: Runtime Protection

| Mechanism | Default | Description |
|---|---|---|
| Sandbox Mode | **ON** | Emails go to Mailhog (localhost:1025), not real recipients |
| Rate Limiting | 45 sec delay | Configurable delay between each email |
| Daily Max | 450/day | Hard cap on emails per day |
| Business Hours | 9:00–18:00 | Sends only during configured hours |
| Anomaly Detection | 20% threshold | Auto-pauses if failure rate exceeds 20% |
| Warm-up Mode | Enabled | Gradual daily increase for new accounts |

### Layer 4: Quality Scoring

Each draft gets a score from 0–8:

| Grade | Score | Action |
|---|---|---|
| Excellent | 7–8 | Auto-ready for approval |
| Good | 5–6 | Ready for approval |
| Fair | 3–4 | Flagged for review |
| Poor | 0–2 | **Blocked** — must edit or regenerate |

---

## ✉️ Email Rules

### Formatting

- **HTML emails use table-based layout** — renders correctly in Gmail, Outlook, Apple Mail, and all mobile clients
- **MIME multipart/alternative** — both plain text and HTML versions in every email
- **Inline CSS only** — no `<style>` blocks, no external CSS
- **Max width 600px** — standard email container width
- **Signature auto-appended** — from Settings, never in AI-generated body

### Content Rules (Enforced via AI Prompt)

1. Under 150 words (body only)
2. Use recipient's FIRST NAME only (not "Dear", not full name)
3. Reference their company by name at least once
4. Include one quantifiable achievement
5. End with a soft, low-commitment CTA
6. **NO** buzzwords: "passionate", "motivated", "synergy", "leverage"
7. **NO** filler: "I hope this finds you well", "I am writing to"
8. **NO** exclamation marks
9. **NO** salary/compensation mentions
10. **NO** signature block in AI output (added separately)

### Recipient-Specific Tone

| Type | Tone | Max Words | CTA Style |
|---|---|---|---|
| Recruiter | Warm, professional | 120 | "Would you be open to a quick chat?" |
| Hiring Manager | Value-focused, peer | 150 | "Would it make sense to connect?" |
| Engineering Leader | Technical, confident | 150 | "I'd welcome a conversation about..." |
| C-Suite | Executive, strategic | 80 | "Would a brief intro be worthwhile?" |
| HR | Polite, structured | 120 | "Could you point me to the right person?" |

---

## 🔑 Credentials Storage

| Secret | Keychain Key | Where Set |
|---|---|---|
| Apollo API Key | `apollo_api_key` | Settings → Providers tab |
| Hunter API Key | `hunter_api_key` | Settings → Providers tab |
| RocketReach Key | `rocketreach_api_key` | Settings → Providers tab |
| Gemini API Key | `gemini_api_key` | Settings → Providers tab |
| Groq API Key | `groq_api_key` | Settings → Providers tab |
| SMTP Password | `smtp_password` | Settings → Email tab |

**NEVER** store credentials in:
- Source code
- UserDefaults
- Property lists
- Environment variables committed to git

---

## 🧪 Testing Strategy

### Sandbox Mode (Default)

1. Install Mailhog: `brew install mailhog`
2. Start: `mailhog`
3. Dashboard: `http://localhost:8025`
4. All emails route to Mailhog instead of real recipients
5. Verify formatting, subject lines, personalization

### Going Live Checklist

- [ ] Reviewed at least 10 drafts manually
- [ ] Tested full pipeline in sandbox mode
- [ ] Checked 3+ emails in Mailhog for formatting
- [ ] Turned OFF sandbox mode in Settings
- [ ] Configured real SMTP email + app password
- [ ] Set appropriate daily limit and delay
- [ ] Confirmed business hours settings

---

## 🖥️ Build & Run

```bash
# Build
cd /Users/neelmani-mishra/Documents/TryingSomethingInteresting/JobBus
swift build

# Run
swift run

# Open in Xcode (optional)
open Package.swift
```

### Distribution (DMG)

```bash
# Build release
swift build -c release

# The binary is at:
# .build/release/JobBus

# Create DMG (future — requires Apple Developer ID for notarization)
```

---

## 📋 API Reference

### Apollo.io

- **Search endpoint**: `POST /api/v1/mixed_people/search` (free, no credits)
- **Enrichment endpoint**: `POST /api/v1/people/match` (consumes credits)
- **Auth header**: `x-api-key: {key}`
- **Rate limit**: Handle 429 with `Retry-After` header
- **Docs**: https://docs.apollo.io/

### Ollama (Local LLM)

- **Generate**: `POST http://localhost:11434/api/generate`
- **List models**: `GET http://localhost:11434/api/tags`
- **Default model**: `llama3.1:8b`
- **Start**: `ollama serve`

### Gemini Flash

- **Endpoint**: `POST https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent?key={key}`
- **Free tier**: Yes
- **Docs**: https://ai.google.dev/

---

## 🚨 Edge Cases to Remember

1. **Scanned PDFs** — PDFKit extracts no text → show clear error, suggest DOCX
2. **Password-protected PDFs** — Detected and rejected with message
3. **CSV encoding** — Try UTF-8 first, fallback to ISO-8859-1
4. **CSV delimiter** — Auto-detect comma vs tab vs semicolon
5. **Name formats** — Handle "Last, First" and "First Last" in CSV
6. **Duplicate emails** — Deduped by lowercase email across all sources
7. **Empty emails from Apollo** — Contacts with no email marked as `noEmail`, skipped for drafts
8. **AI returning markdown** — JSON parser strips ```json fences before parsing
9. **SMTP auth failure** — Clear error message, don't retry with wrong password
10. **Rate limiting** — Exponential backoff on 429 responses
11. **Credits exhausted** — Stop enrichment, return what we have so far
12. **AI hallucination** — Quality scorer catches name/company mismatches
13. **Gmail sending limits** — 500/day for regular accounts, configurable in Settings

---

## 📝 Conventions

- **Naming**: Swift standard — PascalCase for types, camelCase for properties
- **File naming**: Match the primary type name (e.g., `Contact.swift` for `struct Contact`)
- **Comments**: MARK comments for section headers (`// MARK: - Section`)
- **Error handling**: All providers throw `ProviderError` enum cases
- **Async**: All network/AI calls are `async throws`
- **UI updates**: All `@Published` properties on `@MainActor`
- **Color hex**: Use `Color(hex: "#8b5cf6")` extension throughout

---

*Last updated: 2026-04-25*
*Commit: `7fb157f` — Job Bus v1.0*
