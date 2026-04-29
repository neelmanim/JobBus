# Privacy Policy — JobBus

**Last Updated: April 29, 2026**

## Overview

JobBus ("the App") is a macOS application for AI-powered job outreach. This privacy policy explains how the App handles your data.

## Data Collection

**JobBus does NOT collect, transmit, or store any personal data on external servers.** All data remains on your local machine.

### What stays on your device:
- Your resume file and parsed profile data
- Contact lists (imported or discovered)
- Email drafts and campaign history
- SMTP credentials and API keys
- Usage statistics (Apollo credits, AI tokens)
- Application logs

### Data storage locations:
All app data is stored locally at:
- `~/Library/Application Support/JobBus/`
- macOS Keychain (for API keys and passwords)

## Third-Party Services

JobBus connects to the following third-party services **only when you explicitly configure and use them**:

| Service | Purpose | Data Sent |
|---|---|---|
| **Google Gemini** | AI email generation & resume parsing | Resume text, contact info for personalization |
| **Groq** | AI email generation & resume parsing | Resume text, contact info for personalization |
| **Ollama** (local) | AI email generation & resume parsing | Data stays on your machine |
| **Apollo.io** | Contact discovery & email enrichment | Job titles, company names, locations |
| **SMTP Server** | Email sending | Email content, recipient addresses |

Each of these services has its own privacy policy. JobBus does not control how these services handle data.

## API Keys & Credentials

- All API keys and SMTP passwords are stored in the **macOS Keychain**, Apple's secure credential storage.
- Credentials are never stored in plaintext files.
- Credentials are never transmitted to any server other than the service they belong to.

## Analytics & Tracking

JobBus does **NOT** include:
- Analytics SDKs
- Crash reporting services
- Advertising frameworks
- User tracking of any kind

## Sandbox Mode

JobBus includes a Sandbox Mode (enabled by default) that routes all emails to a local test SMTP server. No real emails are sent until you explicitly disable sandbox mode.

## Data Deletion

To delete all JobBus data:
1. Delete the app from `/Applications/`
2. Delete `~/Library/Application Support/JobBus/`
3. Remove stored credentials from Keychain Access (search for "JobBus")

## Children's Privacy

JobBus is not directed at children under 13 and does not knowingly collect data from children.

## Changes to This Policy

We may update this policy from time to time. Changes will be reflected in the "Last Updated" date above.

## Contact

For privacy questions, please open an issue at:
https://github.com/neelmanim/JobBus/issues

---

*This privacy policy applies to JobBus version 1.1.5 and later.*
