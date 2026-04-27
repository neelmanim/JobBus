# JobBus — Installation Guide

## System Requirements

| Requirement | Minimum |
|---|---|
| **macOS** | 14.0 (Sonoma) or later |
| **Xcode** | 15.0+ (for building from source only) |
| **Swift** | 5.9+ |
| **Disk Space** | ~50 MB |
| **RAM** | 4 GB recommended |

> **Note**: JobBus is a native macOS app built with SwiftUI. It does **not** run on Windows or Linux.

---

## Option 1: Install Pre-Built Binary (Easiest)

If someone has shared the compiled `.app` bundle or `.zip` archive with you:

### Steps

1. **Unzip** the archive (if you received a `.zip`):
   ```bash
   unzip JobBus-v1.0.0-macOS.zip
   ```

2. **⚠️ Remove macOS quarantine** (REQUIRED for unsigned apps):

   macOS marks files downloaded from the internet or received via AirDrop/WhatsApp/email as "quarantined". Without this step, you'll get **"JobBus.app is damaged and can't be opened"** — the app is NOT actually damaged.

   ```bash
   xattr -cr JobBus.app
   ```

   > **What this does**: Removes the `com.apple.quarantine` extended attribute that macOS applies to files from unidentified developers. This is safe — the app is open source and you can verify the code yourself.

3. **Move** to Applications:
   ```bash
   mv JobBus.app /Applications/
   ```

4. **First launch** — if macOS still shows a Gatekeeper warning:
   - **Method A** (recommended): Right-click `JobBus.app` → **Open** → Click **"Open"** in the dialog
   - **Method B**: Go to `System Settings → Privacy & Security` → scroll down → click **"Open Anyway"** next to the JobBus warning
   - **Method C** (terminal):
     ```bash
     open /Applications/JobBus.app
     ```

5. **Done!** The onboarding wizard will guide you through AI and email setup.

### One-Liner Install

```bash
unzip JobBus-v1.0.0-macOS.zip && xattr -cr JobBus.app && mv JobBus.app /Applications/ && open /Applications/JobBus.app
```

---

## Option 2: Build from Source

### Prerequisites

1. **Install Xcode Command Line Tools** (if not already installed):
   ```bash
   xcode-select --install
   ```

2. **Verify Swift is available**:
   ```bash
   swift --version
   # Should show Swift 5.9 or later
   ```

### Build Steps

1. **Clone the repository**:
   ```bash
   git clone https://github.com/neelmanim/JobBus.git
   cd JobBus
   ```

2. **Build and package** (recommended — creates a portable `.app` bundle):
   ```bash
   ./scripts/package.sh
   ```
   Output: `dist/JobBus.app` and `dist/JobBus-v1.0.0-macOS.zip`

3. **Install**:
   ```bash
   cp -r dist/JobBus.app /Applications/
   open /Applications/JobBus.app
   ```

### Alternative: Run Without Packaging

If you just want to run it quickly without creating an `.app` bundle:

```bash
swift build -c release
.build/release/JobBus
```

> **Note**: Running the raw binary works but won't show a Dock icon or appear in Spotlight. Use `./scripts/package.sh` for a proper app experience.

---

## First-Time Setup

When you launch JobBus for the first time, the **Onboarding Wizard** will walk you through:

### Step 1: AI Provider

Choose your AI provider for email generation:

| Provider | Setup | Cost |
|---|---|---|
| **Groq** (Recommended) | Get API key from [console.groq.com](https://console.groq.com) | Free tier available |
| **OpenAI** | Get API key from [platform.openai.com](https://platform.openai.com) | Pay-per-use |
| **Ollama** (Local) | Install from [ollama.ai](https://ollama.ai), run `ollama pull llama3.1:8b` | Free, runs locally |

### Step 2: Email (SMTP) Configuration

You need an **App Password** (NOT your regular password) for your email provider:

#### Gmail
1. Go to [myaccount.google.com/security](https://myaccount.google.com/security)
2. Enable **2-Factor Authentication** (required)
3. Go to [myaccount.google.com/apppasswords](https://myaccount.google.com/apppasswords)
4. Create an app password for "Mail" → Copy the 16-character code
5. In JobBus Settings → Email:
   - **Email**: your.email@gmail.com
   - **App Password**: paste the 16-character code
   - **Provider**: Gmail (auto-configures SMTP server)

#### Outlook / Hotmail
1. Go to [account.live.com/proofs/manage](https://account.live.com/proofs/manage)
2. Enable **2-Factor Authentication**
3. Create an App Password under Security → Advanced
4. In JobBus Settings → Email:
   - **Email**: your.email@outlook.com
   - **App Password**: paste the generated password
   - **Provider**: Outlook

### Step 3: Test with Sandbox Mode (Recommended!)

JobBus starts in **Sandbox Mode** by default — emails go to a local test server instead of real inboxes. This lets you verify everything works before sending real emails.

1. **Install MailHog** (one-time):
   ```bash
   brew install mailhog
   ```

2. **Start MailHog**:
   ```bash
   mailhog
   ```

3. **Open the MailHog inbox**: [http://localhost:8025](http://localhost:8025)

4. **Run a campaign** in JobBus — emails will appear in MailHog, not real inboxes

5. **When ready for production**: Go to Settings → Campaign → Turn off "Sandbox Mode"

---

## Sharing JobBus with Others

When distributing the app to someone else, include these instructions:

### For the Sender (You)

```bash
# Build and package
./scripts/package.sh

# Share this file via AirDrop, email, or any file sharing service:
# dist/JobBus-v1.0.0-macOS.zip
```

### Instructions to Include for the Recipient

Copy-paste this to whoever you're sharing with:

```
To install JobBus:

1. Unzip the file:     unzip JobBus-v1.0.0-macOS.zip
2. Remove quarantine:  xattr -cr JobBus.app
3. Move to Apps:       mv JobBus.app /Applications/
4. Launch:             open /Applications/JobBus.app

Or as one command:
unzip JobBus-v1.0.0-macOS.zip && xattr -cr JobBus.app && mv JobBus.app /Applications/ && open /Applications/JobBus.app
```

---

## Data & Configuration Locations

| What | Path |
|---|---|
| **Settings** | `~/Library/Application Support/JobBus/settings.json` |
| **Credentials** | `~/Library/Application Support/JobBus/credentials.dat` (encrypted) |
| **Session Logs** | `~/Library/Application Support/JobBus/logs/` |
| **Resume Copy** | `~/Library/Application Support/JobBus/resume_attachment.pdf` |
| **Usage Stats** | `~/Library/Application Support/JobBus/usage_stats.json` |

---

## Troubleshooting

### "App is damaged and can't be opened"

This is macOS Gatekeeper blocking unsigned apps. The app is NOT damaged.

**Fix:**
```bash
# Remove the quarantine attribute
xattr -cr /Applications/JobBus.app

# If that doesn't work, also try:
sudo xattr -rd com.apple.quarantine /Applications/JobBus.app

# Then open:
open /Applications/JobBus.app
```

**Why this happens:** macOS adds a `com.apple.quarantine` extended attribute to any file downloaded from the internet or received via AirDrop/USB/email from an unidentified developer. Since JobBus is not code-signed with an Apple Developer certificate, Gatekeeper blocks it. The `xattr -cr` command removes this attribute.

### "Cannot be opened because the developer cannot be verified"

Same root cause as above. Fix:
1. Run `xattr -cr /Applications/JobBus.app`
2. **OR** go to `System Settings → Privacy & Security` → click **"Open Anyway"**

### App opens but immediately closes

Check that you're running macOS 14.0 (Sonoma) or later:
```bash
sw_vers -productVersion
```

### Build fails with "module not found"

Make sure Xcode CLI tools are installed:
```bash
xcode-select --install
sudo xcodebuild -license accept
```

### MailHog port already in use

```bash
lsof -ti :1025 | xargs kill -9
lsof -ti :8025 | xargs kill -9
mailhog
```

### Emails not sending (production mode)

1. Check Settings → Email → verify email and app password are set
2. Ensure you're using an **App Password**, not your regular password
3. Check the in-app SMTP Setup Guide (Settings → Email → "Setup Guide")
4. Check logs at `~/Library/Application Support/JobBus/logs/`

### AI not generating emails

1. Verify your API key is saved (Settings → Providers → green checkmark)
2. If using Ollama: ensure it's running (`ollama serve`) and the model is pulled
3. Check logs for rate-limiting warnings (Groq free tier: ~30 req/min)

---

## Uninstall

To completely remove JobBus:

```bash
# Remove the app
rm -rf /Applications/JobBus.app

# Remove all data (settings, logs, credentials)
rm -rf ~/Library/Application\ Support/JobBus/
```

---

## Quick Reference

```bash
# === Pre-built install (one-liner) ===
unzip JobBus-v1.0.0-macOS.zip && xattr -cr JobBus.app && mv JobBus.app /Applications/ && open /Applications/JobBus.app

# === Build from source ===
git clone https://github.com/neelmanim/JobBus.git && cd JobBus
./scripts/package.sh
cp -r dist/JobBus.app /Applications/
open /Applications/JobBus.app

# === Test emails (separate terminal) ===
brew install mailhog && mailhog
# Open http://localhost:8025
```
