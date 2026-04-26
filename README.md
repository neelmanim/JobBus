# 🚌 JobBus

**AI-powered job outreach for macOS** — Upload your resume, discover contacts, and send personalized cold emails at scale.

<p align="center">
  <img src="https://img.shields.io/badge/platform-macOS%2014%2B-blue" />
  <img src="https://img.shields.io/badge/swift-5.9%2B-orange" />
  <img src="https://img.shields.io/badge/license-MIT-green" />
</p>

---

## ✨ What is JobBus?

JobBus is a native macOS application that automates the hardest part of job hunting: **getting your foot in the door**. Instead of copy-pasting templates, JobBus uses AI to write unique, personalized outreach emails for every contact — tailored to their role, company, and your specific background.

### Key Features

- **🧠 AI Resume Parsing** — Upload your PDF resume. AI extracts your skills, achievements, experience level, and career context automatically.
- **🔍 Smart Contact Discovery** — Search Apollo.io for recruiters and hiring managers matching your profile. Import from CSV or add manually.
- **✉️ Personalized Email Generation** — Each email is unique. AI adapts tone for recruiters vs. hiring managers, references specific companies, and highlights your most relevant achievements.
- **📎 Resume Attachment** — Your PDF resume is automatically attached via SMTP (not a link, not a drive URL — the actual file).
- **🛡️ Quality & Safety Checks** — 11-point quality scorer catches placeholders, spam words, and generic openers. Sandbox mode lets you test without sending real emails.
- **📊 Campaign Intelligence** — Pre-send analysis with risk indicators, quality scores, and actionable suggestions.
- **🎨 Writing Style Matching** — Paste your own emails and the AI will match your voice, tone, and sentence patterns.

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

### 1. Build from Source

```bash
git clone https://github.com/your-username/JobBus.git
cd JobBus
swift build -c release
```

The binary is at `.build/release/JobBus`.

### 2. First Launch

On first launch, JobBus will show a guided setup wizard:

1. **AI Provider** — Choose Gemini, Groq, or Ollama and enter your API key
2. **Email Setup** — Configure SMTP (Gmail/Outlook/Custom) with an App Password
3. **Ready** — Sandbox mode is ON by default for safety

### 3. The Workflow

```
Upload Resume → Review AI Strategy → Discover Contacts → Compose Emails → Review & Send
```

| Step | What Happens |
|---|---|
| **1. Resume** | Upload your PDF. AI parses it into structured profile data. |
| **2. Strategy** | AI recommends search filters (titles, seniority, locations). You refine them. |
| **3. Contacts** | Search Apollo, import CSV, or add manually. Each contact gets a relevance score. |
| **4. Compose** | AI generates a unique email for each selected contact. You review, edit, approve. |
| **5. Send** | Launch the campaign. JobBus handles delays, business hours, and rate limiting. |

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
│   └── SendEngine        — SMTP campaign execution, adaptive delays
├── Services
│   ├── AI/               — EmailWriter, ResumeParser (LLM integration)
│   ├── Safety/           — QualityScorer, CampaignIntelligence
│   └── Persistence/      — KeychainService, AppSettings (JSON)
├── Providers
│   ├── Contact/          — ApolloProvider, CSVImporter
│   └── Email/            — SMTPEmailProvider, SMTPClient
└── Views
    ├── Steps/            — 5-step wizard (Resume → Strategy → Contacts → Compose → Send)
    ├── Settings/         — Provider config, SMTP, campaign rules, AI prompt
    └── Onboarding/       — First-run setup wizard
```

### Key Design Decisions

- **Coordinator Pattern**: `AppViewModel` orchestrates all domain managers. Views only talk to the ViewModel.
- **Keychain for Secrets**: API keys and SMTP passwords are stored in macOS Keychain, never in plaintext.
- **Sandbox-First**: Sandbox mode is ON by default. Users must explicitly disable it to send real emails.
- **Quality Gate**: Every AI-generated email is scored across 11 dimensions before it can be approved.

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
