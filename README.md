# 🚌 JobBus

**AI-powered job outreach for macOS** — Upload your resume, discover contacts, and send personalized cold emails at scale.

<p align="center">
  <img src="https://img.shields.io/badge/platform-macOS%2014%2B-blue" />
  <img src="https://img.shields.io/badge/swift-5.9%2B-orange" />
  <img src="https://img.shields.io/badge/license-MIT-green" />
  <img src="https://img.shields.io/badge/version-1.1.4-purple" />
</p>

---

## ✨ What is JobBus?

JobBus is a native macOS application that automates the hardest part of job hunting: **getting your foot in the door**. Instead of copy-pasting templates, JobBus uses AI to write unique, personalized outreach emails for every contact — tailored to their role, company, and your specific background.

### 🎯 Core Features

| Feature | Description |
|---|---|
| **🧠 AI Resume Parsing** | Upload your PDF/DOCX resume. AI extracts your skills, achievements, experience level, and career context automatically |
| **🔍 Smart Contact Discovery** | 2-step Apollo.io pipeline: discover contacts → enrich with verified emails. Also supports CSV import and manual entry |
| **✉️ Personalized Emails** | Every email is unique — AI adapts tone for recruiters vs. hiring managers, references specific companies, highlights your most relevant achievements |
| **📎 Resume Attachment** | Your PDF resume is automatically attached via SMTP (not a link — the actual file) |
| **🛡️ Quality & Safety** | 11-point quality scorer catches placeholders, spam words, and generic openers. Sandbox mode for safe testing |
| **📊 Campaign Intelligence** | Pre-send analysis with risk indicators, quality scores, and actionable suggestions |
| **🎨 Writing Style Matching** | Paste your own emails and the AI matches your voice, tone, and sentence patterns |

### 🆕 Latest Features (v1.0.1)

| Feature | Description |
|---|---|
| **✨ Premium Loading Overlay** | Animated pulse rings with phase-aware icons and gradients — replaces all basic spinners |
| **📈 Usage Stats Tracker** | Cumulative Apollo credits and Groq tokens displayed in sidebar — persisted across sessions |
| **🔄 Resume/Restart Dialog** | Cancel email generation mid-way? Come back and choose: resume remaining or restart all from scratch |
| **🔗 Apollo 2-Step Pipeline** | Discovery via search API → enrichment via match API with 1.5s throttling and 403 handling |
| **⚡ Groq Token Extraction** | Real-time token usage pulled from API response `usage.total_tokens` field |

---

## 🖥️ System Requirements

| Requirement | Minimum |
|---|---|
| **macOS** | 14.0 (Sonoma) or later |
| **Swift** | 5.9+ |
| **Xcode CLI Tools** | Required for building from source |
| **AI Provider** | Gemini (free), Groq (free), or Ollama (local) |
| **Contact Provider** | Apollo.io API key (free tier available) |

---

## 🚀 Quick Start

### Option A: Pre-built App

```bash
# Download, remove quarantine, install, and launch
unzip JobBus-v1.0.0-macOS.zip
xattr -cr JobBus.app          # ⚠️ REQUIRED — removes macOS quarantine (prevents "damaged" error)
mv JobBus.app /Applications/
open /Applications/JobBus.app
```

> **⚠️ Important**: The `xattr -cr` step is mandatory. Without it, macOS will show **"JobBus.app is damaged and can't be opened"** — the app is NOT damaged, it's just unsigned. See [INSTALL.md](INSTALL.md) for details.

### Option B: Build from Source

```bash
git clone https://github.com/neelmanim/JobBus.git
cd JobBus
./scripts/package.sh           # Build + bundle → dist/JobBus.app
```

### First Launch

On first launch, JobBus shows a guided setup wizard:

1. **AI Provider** — Choose Gemini, Groq, or Ollama and enter your API key
2. **Email Setup** — Configure SMTP (Gmail/Outlook/Custom) with an App Password
3. **Ready** — Sandbox mode is ON by default for safety

---

## 📋 The 5-Step Workflow

```
Upload Resume → Review AI Strategy → Discover Contacts → Compose Emails → Review & Send
```

### Step 1: Resume Upload
Upload your PDF or DOCX resume. AI parses it into structured profile data — skills, achievements, experience level, target role, and career context. The parsed profile drives all downstream personalization.

### Step 2: AI Strategy
AI recommends search filters (job titles, seniority levels, locations, industries) based on your resume. You refine and approve before searching.

### Step 3: Contact Discovery
- **Apollo.io Search** — 2-step pipeline: discover contacts via search API, then enrich each with verified email via match API
- **CSV Import** — Bulk import from any spreadsheet
- **Manual Entry** — Add individual contacts by hand
- **Resume/Restart** — If you cancel email generation and return, a dialog asks: resume remaining or restart all

### Step 4: Email Composition
AI generates a unique email for every selected contact. Each draft includes:
- Personalized subject line referencing the company
- Body tailored to the recipient's role and seniority
- Round-robin achievement rotation (different highlight per email)
- 11-point quality score with pass/fail indicator

You review, edit, and approve each draft before sending.

### Step 5: Campaign Launch
Launch the campaign with intelligent sending:
- **Rate limiting** — configurable delay between emails (default: 45s ± 20% jitter)
- **Business hours** — optional restriction to 9 AM–6 PM
- **Pause/Resume/Stop** — full campaign control during execution
- **Resume attachment** — automatically attached for recruiters and hiring managers

---

## 📈 Usage Stats & Monitoring

JobBus tracks cumulative API usage in a **sidebar footer** that appears automatically:

| Metric | Source | Tracking |
|---|---|---|
| **Apollo Credits** | Each successful contact enrichment | 1 credit per enriched contact |
| **Apollo Searches** | Each search batch initiated | 1 per search |
| **Groq Tokens** | AI response `usage.total_tokens` | Extracted from API response |
| **Groq Calls** | Each AI generation call | 1 per call |

- Stats are **persisted** to `~/Library/Application Support/JobBus/usage_stats.json`
- Survives app restarts and session changes
- **Reset button** with confirmation dialog to zero all counters
- Formatted display: `2.1K tokens`, `156 credits`

---

## ✨ Premium Loading Experience

Every loading state features an animated overlay with:

| Phase | Icon | Gradient | When |
|---|---|---|---|
| **Analyzing** | 🔍 doc.text.magnifyingglass | Amber → Red | Resume parsing |
| **Discovering** | 👥 person.3.fill | Purple → Indigo | Contact search |
| **Enriching** | 📧 envelope.badge.person | Blue → Cyan | Email enrichment |
| **Composing** | ✉️ envelope.open.fill | Purple → Pink | Draft generation |
| **Sending** | ✈️ paperplane.fill | Green → Blue | Campaign send |

- **3 animated pulse rings** with staggered timing
- **SF Symbols pulse effect** for native macOS feel
- **Progress bar** with spring animation during batch operations
- **Glassmorphism backdrop** with gradient border

---

## ⚙️ Configuration

### AI Provider Setup

| Provider | Cost | Speed | Setup |
|---|---|---|---|
| **Gemini Flash** | Free | Fast | [Get API key](https://aistudio.google.com/apikey) |
| **Groq** | Free tier | Ultra-fast | [Get API key](https://console.groq.com/keys) |
| **Ollama** | Free (local) | Depends on hardware | `brew install ollama && ollama serve` |

### SMTP Setup (Gmail)

1. Enable 2-Factor Authentication on your Google account
2. Go to [App Passwords](https://myaccount.google.com/apppasswords)
3. Generate a new password for "Mail"
4. Paste the 16-character password into JobBus Settings → Email → App Password

> **Tip**: Use **Sandbox Mode** (enabled by default) to test with [MailHog](https://github.com/mailhog/MailHog) before going live: `brew install mailhog && mailhog`

---

## 🏗️ Architecture

```
JobBusApp (Entry Point)
├── AppViewModel (Coordinator)
│   ├── ContactManager    — Apollo API, CSV import, manual entry
│   ├── DraftManager      — AI email generation, quality scoring
│   ├── SendEngine        — SMTP campaign execution, adaptive delays
│   └── UsageTracker      — Cumulative Apollo/Groq stats, persisted
├── Services
│   ├── AI/               — EmailWriter, ResumeParser (LLM integration)
│   ├── Safety/           — QualityScorer, CampaignIntelligence
│   └── UsageTracker      — Persistent cumulative usage stats
├── Providers
│   ├── AI/               — Groq, Gemini, Ollama (+ token reporting)
│   ├── Search/           — Apollo (2-step), Hunter, RocketReach
│   └── Email/            — SMTPEmailProvider (SwiftNIO)
└── Views
    ├── Components/       — LoadingOverlay, InlineLoadingIndicator
    ├── Steps/            — 5-step wizard (Resume → Send)
    ├── Settings/         — Provider config, SMTP, campaign rules
    └── Onboarding/       — First-run setup wizard
```

### Key Design Decisions

- **Coordinator Pattern**: `AppViewModel` orchestrates all domain managers. Views only talk to the ViewModel.
- **Notification-Based Tracking**: AI providers post usage notifications (decoupled) → AppViewModel subscribes via Combine.
- **Keychain for Secrets**: API keys and SMTP passwords stored in macOS Keychain, never in plaintext.
- **Sandbox-First**: Sandbox mode ON by default. Users must explicitly disable for production sends.
- **Quality Gate**: Every AI-generated email scored across 11 dimensions before approval.
- **Resume/Restart State**: Partial draft sets are detected and surfaced via dialog — no silent data loss.

---

## 🧪 Testing with Sandbox

JobBus ships with Sandbox Mode enabled. All emails go to a local SMTP server instead of real recipients.

```bash
# Install MailHog (one-time)
brew install mailhog

# Run MailHog
mailhog

# Open MailHog UI
open http://localhost:8025
```

Then launch JobBus and send a campaign — all emails appear in MailHog's web UI.

---

## 🔐 Data Locations

| Data | Path |
|---|---|
| Settings | `~/Library/Application Support/JobBus/settings.json` |
| Credentials | `~/Library/Application Support/JobBus/credentials.dat` |
| Logs | `~/Library/Application Support/JobBus/logs/` |
| Resume | `~/Library/Application Support/JobBus/resume_attachment.pdf` |
| Usage Stats | `~/Library/Application Support/JobBus/usage_stats.json` |

---

## 📄 License

MIT License — see [LICENSE](LICENSE) for details.

---

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

---

<p align="center">
  Built with ❤️ for job seekers everywhere.
</p>
