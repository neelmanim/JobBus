import SwiftUI

// MARK: - SMTP Setup Guide
/// In-app modal with step-by-step SMTP configuration for Gmail, Outlook, and custom providers.
struct SMTPSetupGuideView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selectedProvider = 0  // 0=Gmail, 1=Outlook, 2=Custom
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "envelope.badge.shield.half.filled.fill")
                    .font(.title2)
                    .foregroundColor(Color(hex: "#10b981"))
                Text("SMTP Setup Guide")
                    .font(.title2.bold())
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(20)
            
            Divider()
            
            // Tab picker
            Picker("Provider", selection: $selectedProvider) {
                Text("Gmail").tag(0)
                Text("Outlook").tag(1)
                Text("Custom SMTP").tag(2)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 20)
            .padding(.top, 16)
            
            // Content
            ScrollView {
                switch selectedProvider {
                case 0: gmailGuide
                case 1: outlookGuide
                default: customGuide
                }
            }
            .padding(20)
        }
        .frame(width: 560, height: 520)
    }
    
    // MARK: - Gmail Guide
    private var gmailGuide: some View {
        VStack(alignment: .leading, spacing: 20) {
            configCard(host: "smtp.gmail.com", port: "587", encryption: "STARTTLS")
            
            Text("Setup Steps")
                .font(.headline)
            
            stepBlock(number: "1", title: "Enable 2-Factor Authentication", details: [
                "Go to myaccount.google.com",
                "Navigate to Security → 2-Step Verification",
                "Follow the prompts to enable 2FA",
                "⚠️ App Passwords require 2FA to be enabled"
            ])
            
            stepBlock(number: "2", title: "Generate App Password", details: [
                "Go to myaccount.google.com/apppasswords",
                "Or search \"App Passwords\" in Google Account settings",
                "Select app: \"Mail\"",
                "Select device: \"Mac\"",
                "Click \"Generate\""
            ])
            
            stepBlock(number: "3", title: "Copy the Password", details: [
                "Google will show a 16-character password (e.g., abcd efgh ijkl mnop)",
                "Copy it — you won't be able to see it again",
                "Paste it into Settings → Email → App Password in JobBus"
            ])
            
            importantNote("Gmail limits sending to ~500 emails/day for personal accounts and ~2000/day for Google Workspace. JobBus respects your daily limit setting.")
        }
    }
    
    // MARK: - Outlook Guide
    private var outlookGuide: some View {
        VStack(alignment: .leading, spacing: 20) {
            configCard(host: "smtp-mail.outlook.com", port: "587", encryption: "STARTTLS")
            
            Text("Setup Steps")
                .font(.headline)
            
            stepBlock(number: "1", title: "Sign in to Microsoft Account", details: [
                "Go to account.microsoft.com",
                "Sign in with your Outlook/Hotmail email"
            ])
            
            stepBlock(number: "2", title: "Enable Two-Step Verification", details: [
                "Go to Security → Advanced security options",
                "Turn on Two-step verification",
                "Follow the verification prompts"
            ])
            
            stepBlock(number: "3", title: "Create App Password", details: [
                "In Advanced security options, find \"App passwords\"",
                "Click \"Create a new app password\"",
                "Copy the generated password",
                "Paste it into Settings → Email → App Password in JobBus"
            ])
            
            importantNote("Outlook limits sending to ~300 emails/day for personal accounts. Use a reasonable daily limit in JobBus settings.")
        }
    }
    
    // MARK: - Custom Guide
    private var customGuide: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Custom SMTP Server")
                .font(.headline)
            
            Text("If you're using a custom email provider (Zoho, Fastmail, self-hosted, etc.), you'll need to get these details from your provider:")
                .font(.callout)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            
            VStack(alignment: .leading, spacing: 10) {
                configRow("SMTP Host", "e.g., smtp.zoho.com")
                configRow("SMTP Port", "Usually 587 (STARTTLS) or 465 (SSL)")
                configRow("Username", "Usually your full email address")
                configRow("Password", "Your email password or app-specific password")
            }
            .padding(16)
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            
            Text("Common Providers")
                .font(.headline)
            
            VStack(alignment: .leading, spacing: 8) {
                providerQuickRef("Zoho Mail", "smtp.zoho.com", "587")
                providerQuickRef("Fastmail", "smtp.fastmail.com", "587")
                providerQuickRef("Yahoo Mail", "smtp.mail.yahoo.com", "587")
                providerQuickRef("iCloud", "smtp.mail.me.com", "587")
                providerQuickRef("ProtonMail Bridge", "127.0.0.1", "1025")
            }
            .padding(16)
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            
            importantNote("Select \"Custom SMTP\" as your Email Provider in Settings, then enter your host and port in the fields that appear.")
        }
    }
    
    // MARK: - Components
    
    @ViewBuilder
    private func configCard(host: String, port: String, encryption: String) -> some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Host").font(.caption.weight(.semibold)).foregroundColor(.secondary)
                Text(host).font(.callout.monospaced().weight(.medium))
            }
            
            Divider().frame(height: 32)
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Port").font(.caption.weight(.semibold)).foregroundColor(.secondary)
                Text(port).font(.callout.monospaced().weight(.medium))
            }
            
            Divider().frame(height: 32)
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Encryption").font(.caption.weight(.semibold)).foregroundColor(.secondary)
                Text(encryption).font(.callout.monospaced().weight(.medium))
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(hex: "#10b981").opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
    
    @ViewBuilder
    private func stepBlock(number: String, title: String, details: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(number)
                    .font(.caption.bold())
                    .foregroundColor(.white)
                    .frame(width: 22, height: 22)
                    .background(Color(hex: "#10b981"))
                    .clipShape(Circle())
                
                Text(title)
                    .font(.callout.weight(.semibold))
            }
            
            VStack(alignment: .leading, spacing: 4) {
                ForEach(details, id: \.self) { detail in
                    HStack(alignment: .top, spacing: 6) {
                        Text("•")
                            .foregroundColor(.secondary)
                        Text(detail)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(.leading, 30)
        }
    }
    
    @ViewBuilder
    private func importantNote(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "info.circle.fill")
                .foregroundColor(.blue)
                .font(.caption)
            Text(text)
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .background(Color.blue.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
    
    @ViewBuilder
    private func configRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(.callout.weight(.medium))
                .frame(width: 120, alignment: .leading)
            Text(value)
                .font(.callout)
                .foregroundColor(.secondary)
        }
    }
    
    @ViewBuilder
    private func providerQuickRef(_ name: String, _ host: String, _ port: String) -> some View {
        HStack {
            Text(name)
                .font(.caption.weight(.medium))
                .frame(width: 140, alignment: .leading)
            Text(host)
                .font(.caption.monospaced())
                .foregroundColor(Color(hex: "#8b5cf6"))
                .frame(width: 180, alignment: .leading)
            Text(":\(port)")
                .font(.caption.monospaced())
                .foregroundColor(.secondary)
        }
    }
}
