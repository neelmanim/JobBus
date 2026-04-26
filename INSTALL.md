# JobBus — Installation Guide

## System Requirements

| Requirement | Minimum |
|---|---|
| **macOS** | 14.0 (Sonoma) or later |
| **Xcode** | 15.0+ (for building from source) |
| **Swift** | 5.9+ |
| **Disk Space** | ~50 MB |
| **RAM** | 4 GB recommended |

> **Note**: JobBus is a native macOS app built with SwiftUI. It does **not** run on Windows or Linux.

---

## Option 1: Install Pre-Built Binary (Easiest)

If someone has shared the compiled `.app` bundle with you:

### Steps

1. **Download** the `JobBus.app` file (or unzip `JobBus.zip`)

2. **Move** it to your `Applications` folder:
   ```bash
   mv ~/Downloads/JobBus.app /Applications/
   ```

3. **First launch** — macOS may block it because it's from an unidentified developer:
   - Right-click `JobBus.app` → **Open**
   - Click **"Open"** in the security dialog
   - Alternatively: `System Settings → Privacy & Security → Open Anyway`

4. **Done!** The onboarding wizard will guide you through AI and email setup.

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

2. **Build the app** (release mode recommended):
   ```bash
   swift build -c release
   ```
   This takes about 15-30 seconds on first build.

3. **Run the app**:
   ```bash
   .build/release/JobBus
   ```

4. **(Optional) Create a portable `.app` bundle**:
   ```bash
   # Create the app bundle structure
   mkdir -p JobBus.app/Contents/MacOS
   mkdir -p JobBus.app/Contents/Resources

   # Copy the binary
   cp .build/release/JobBus JobBus.app/Contents/MacOS/

   # Copy the app icon
   cp Sources/Resources/AppIcon.png JobBus.app/Contents/Resources/

   # Create the Info.plist
   cat > JobBus.app/Contents/Info.plist << 'EOF'
   <?xml version="1.0" encoding="UTF-8"?>
   <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
   <plist version="1.0">
   <dict>
       <key>CFBundleExecutable</key>
       <string>JobBus</string>
       <key>CFBundleIdentifier</key>
       <string>com.jobbus.app</string>
       <key>CFBundleName</key>
       <string>JobBus</string>
       <key>CFBundleDisplayName</key>
       <string>JobBus</string>
       <key>CFBundleVersion</key>
       <string>1.0</string>
       <key>CFBundleShortVersionString</key>
       <string>1.0</string>
       <key>CFBundleIconFile</key>
       <string>AppIcon</string>
       <key>CFBundlePackageType</key>
       <string>APPL</string>
       <key>LSMinimumSystemVersion</key>
       <string>14.0</string>
       <key>NSHighResolutionCapable</key>
       <true/>
   </dict>
   </plist>
   EOF

   # Move to Applications
   mv JobBus.app /Applications/
   echo "✅ JobBus.app installed to /Applications/"
   ```

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

## Data & Configuration Locations

| What | Path |
|---|---|
| **Settings** | `~/Library/Application Support/JobBus/settings.json` |
| **Credentials** | `~/Library/Application Support/JobBus/credentials.dat` (encrypted) |
| **Session Logs** | `~/Library/Application Support/JobBus/logs/` |
| **Resume Copy** | `~/Library/Application Support/JobBus/resume_attachment.pdf` |

---

## Troubleshooting

### "App is damaged and can't be opened"
```bash
xattr -cr /Applications/JobBus.app
```
Then try opening again.

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
# Clone & build
git clone https://github.com/neelmanim/JobBus.git && cd JobBus
swift build -c release

# Run
.build/release/JobBus

# Test emails (separate terminal)
brew install mailhog && mailhog
# Open http://localhost:8025
```
