import SwiftUI

// MARK: - Settings View
struct SettingsView: View {
    @EnvironmentObject var vm: AppViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var selectedTab = 0
    @State private var apiKeyInput = ""
    @State private var smtpPasswordInput = ""
    @State private var aiKeyInput = ""
    @State private var saveConfirmation = ""
    
    private let accentGradient = LinearGradient(
        colors: [Color(hex: "#8b5cf6"), Color(hex: "#6366f1")],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )
    
    var body: some View {
        VStack(spacing: 0) {
            // MARK: - Header Bar
            HStack {
                Text("Settings")
                    .font(.title2.bold())
                
                Spacer()
                
                if !saveConfirmation.isEmpty {
                    Label(saveConfirmation, systemImage: "checkmark.circle.fill")
                        .font(.caption.weight(.medium))
                        .foregroundColor(.green)
                        .transition(.opacity.combined(with: .scale))
                }
                
                Button {
                    vm.settings.save()
                    dismiss()
                } label: {
                    Text("Done")
                        .font(.body.weight(.semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 7)
                        .background(accentGradient)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 28)
            .padding(.top, 24)
            .padding(.bottom, 16)
            
            // MARK: - Tab Picker
            Picker("", selection: $selectedTab) {
                Label("Providers", systemImage: "puzzlepiece.fill").tag(0)
                Label("Email", systemImage: "envelope.fill").tag(1)
                Label("Campaign", systemImage: "paperplane.fill").tag(2)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 28)
            .padding(.bottom, 20)
            
            Divider()
            
            // MARK: - Tab Content
            ScrollView {
                VStack(spacing: 0) {
                    switch selectedTab {
                    case 0: providersTab
                            .transition(.opacity)
                    case 1: emailTab
                            .transition(.opacity)
                    case 2: campaignTab
                            .transition(.opacity)
                    default: EmptyView()
                    }
                }
                .animation(.easeInOut(duration: 0.2), value: selectedTab)
                .padding(28)
            }
            .onDisappear {
                // Auto-save on dismiss to prevent data loss if user closes without clicking Done
                vm.settings.save()
            }
        }
        .frame(width: 640, height: 560)
        .background(Color(nsColor: .windowBackgroundColor))
    }
    
    // MARK: - Providers Tab
    private var providersTab: some View {
        VStack(spacing: 24) {
            // Contact Provider
            SettingsCard(title: "Contact Search Provider", icon: "magnifyingglass.circle.fill", color: "#3b82f6") {
                VStack(alignment: .leading, spacing: 14) {
                    Picker("Provider", selection: $vm.settings.searchProvider) {
                        ForEach(SearchProviderType.allCases) { provider in
                            Label(provider.rawValue, systemImage: provider.icon).tag(provider)
                        }
                    }
                    .pickerStyle(.menu)
                    
                    Text(vm.settings.searchProvider.description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    
                    HStack(spacing: 10) {
                        TextField("Enter API key...", text: $apiKeyInput)
                            .textFieldStyle(.roundedBorder)
                        
                        Button {
                            saveSearchKey()
                        } label: {
                            Label("Save", systemImage: "key.fill")
                                .font(.caption.weight(.medium))
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Color(hex: "#3b82f6"))
                        .disabled(apiKeyInput.isEmpty)
                    }
                }
            }
            
            // AI Provider
            SettingsCard(title: "AI Provider", icon: "brain.head.profile.fill", color: "#8b5cf6") {
                VStack(alignment: .leading, spacing: 14) {
                    Picker("Provider", selection: $vm.settings.aiProvider) {
                        ForEach(AIProviderType.allCases) { provider in
                            Label(provider.rawValue, systemImage: provider.icon).tag(provider)
                        }
                    }
                    .pickerStyle(.menu)
                    
                    Text(vm.settings.aiProvider.description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    
                    if vm.settings.aiProvider == .ollama {
                        LabeledContent("Server URL") {
                            TextField("", text: $vm.settings.ollamaBaseURL)
                                .textFieldStyle(.roundedBorder)
                                .frame(maxWidth: 280)
                        }
                        
                        LabeledContent("Model") {
                            TextField("", text: $vm.settings.ollamaModel)
                                .textFieldStyle(.roundedBorder)
                                .frame(maxWidth: 280)
                        }
                    }
                    
                    if vm.settings.aiProvider.requiresApiKey {
                        HStack(spacing: 10) {
                            TextField("Enter API key...", text: $aiKeyInput)
                                .textFieldStyle(.roundedBorder)
                            
                            Button {
                                saveAIKey()
                            } label: {
                                Label("Save", systemImage: "key.fill")
                                    .font(.caption.weight(.medium))
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(Color(hex: "#8b5cf6"))
                            .disabled(aiKeyInput.isEmpty)
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - Email Tab
    private var emailTab: some View {
        VStack(spacing: 24) {
            // SMTP Configuration
            SettingsCard(title: "SMTP Configuration", icon: "server.rack", color: "#10b981") {
                VStack(alignment: .leading, spacing: 14) {
                    Picker("Email Provider", selection: $vm.settings.emailProvider) {
                        ForEach(EmailProviderType.allCases) { provider in
                            Label(provider.rawValue, systemImage: provider.icon).tag(provider)
                        }
                    }
                    .pickerStyle(.menu)
                    
                    Text(vm.settings.emailProvider.description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    
                    Divider().padding(.vertical, 4)
                    
                    LabeledContent("Your Email") {
                        TextField("you@gmail.com", text: $vm.settings.smtpEmail)
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 300)
                    }
                    
                    LabeledContent("Display Name") {
                        TextField("John Doe", text: $vm.settings.smtpDisplayName)
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 300)
                    }
                    
                    HStack(spacing: 10) {
                        Text("App Password")
                            .frame(width: 110, alignment: .trailing)
                        TextField("Generated app password...", text: $smtpPasswordInput)
                            .textFieldStyle(.roundedBorder)
                        Button {
                            KeychainService.shared.save(key: .smtpPassword, value: smtpPasswordInput)
                            showSaveConfirmation("Password saved securely")
                        } label: {
                            Label("Save", systemImage: "lock.shield.fill")
                                .font(.caption.weight(.medium))
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Color(hex: "#10b981"))
                        .disabled(smtpPasswordInput.isEmpty)
                    }
                    
                    if vm.settings.emailProvider == .custom {
                        Divider().padding(.vertical, 4)
                        
                        LabeledContent("SMTP Host") {
                            TextField("smtp.example.com", text: $vm.settings.customSmtpHost)
                                .textFieldStyle(.roundedBorder)
                                .frame(maxWidth: 300)
                        }
                        
                        LabeledContent("Port") {
                            TextField("", value: $vm.settings.customSmtpPort, format: .number)
                                .textFieldStyle(.roundedBorder)
                                .frame(maxWidth: 100)
                        }
                    }
                }
            }
            
            // Email Signature
            SettingsCard(title: "Email Signature", icon: "signature", color: "#f59e0b") {
                VStack(spacing: 12) {
                    LabeledContent("Name") {
                        TextField("Your full name", text: $vm.settings.signatureName)
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 300)
                    }
                    
                    LabeledContent("Title") {
                        TextField("Software Engineer", text: $vm.settings.signatureTitle)
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 300)
                    }
                    
                    LabeledContent("LinkedIn") {
                        TextField("https://linkedin.com/in/...", text: $vm.settings.signatureLinkedin)
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 300)
                    }
                    
                    LabeledContent("Phone") {
                        TextField("+1 (555) 123-4567", text: $vm.settings.signaturePhone)
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 300)
                    }
                }
            }
        }
    }
    
    // MARK: - Campaign Tab
    private var campaignTab: some View {
        VStack(spacing: 24) {
            // Sending Rules
            SettingsCard(title: "Sending Rules", icon: "clock.arrow.circlepath", color: "#6366f1") {
                VStack(alignment: .leading, spacing: 16) {
                    LabeledContent("Delay between emails") {
                        HStack(spacing: 8) {
                            TextField("", value: $vm.settings.delaySeconds, format: .number)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 70)
                            Text("seconds")
                                .foregroundColor(.secondary)
                                .font(.callout)
                        }
                    }
                    
                    LabeledContent("Daily send limit") {
                        TextField("", value: $vm.settings.maxPerDay, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 70)
                    }
                    
                    Divider().padding(.vertical, 2)
                    
                    Toggle("Business hours only", isOn: $vm.settings.businessHoursOnly)
                        .toggleStyle(.switch)
                    
                    if vm.settings.businessHoursOnly {
                        HStack(spacing: 12) {
                            Text("Active hours")
                                .foregroundColor(.secondary)
                            Spacer()
                            Stepper("\(vm.settings.businessHoursStart):00", value: $vm.settings.businessHoursStart, in: 0...23)
                                .frame(width: 120)
                            Text("to")
                                .foregroundColor(.secondary)
                            Stepper("\(vm.settings.businessHoursEnd):00", value: $vm.settings.businessHoursEnd, in: 0...23)
                                .frame(width: 120)
                        }
                    }
                    
                    Toggle("Warm-up mode (gradual daily increase)", isOn: $vm.settings.warmUpEnabled)
                        .toggleStyle(.switch)
                }
            }
            
            // Safety
            SettingsCard(title: "Safety", icon: "shield.checkered", color: "#ef4444") {
                VStack(alignment: .leading, spacing: 14) {
                    Toggle(isOn: $vm.settings.sandboxMode) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Sandbox Mode")
                                .font(.body.weight(.medium))
                            Text("Emails go to local Mailhog instead of real recipients")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .toggleStyle(.switch)
                    
                    if vm.settings.sandboxMode {
                        Divider().padding(.vertical, 2)
                        
                        LabeledContent("Sandbox Host") {
                            TextField("localhost", text: $vm.settings.sandboxHost)
                                .textFieldStyle(.roundedBorder)
                                .frame(maxWidth: 200)
                        }
                        
                        LabeledContent("Sandbox Port") {
                            TextField("", value: $vm.settings.sandboxPort, format: .number)
                                .textFieldStyle(.roundedBorder)
                                .frame(maxWidth: 100)
                        }
                        
                        HStack(spacing: 6) {
                            Image(systemName: "info.circle.fill")
                                .foregroundColor(.blue)
                            Text("Install Mailhog: ")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text("brew install mailhog && mailhog")
                                .font(.caption.monospaced())
                                .foregroundColor(.primary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Color.primary.opacity(0.08))
                                .cornerRadius(4)
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - Actions
    
    private func saveSearchKey() {
        let key: KeychainService.KeychainKey
        switch vm.settings.searchProvider {
        case .apollo: key = .apolloApiKey
        case .hunter: key = .hunterApiKey
        case .rocketReach: key = .rocketReachApiKey
        }
        KeychainService.shared.save(key: key, value: apiKeyInput)
        showSaveConfirmation("\(vm.settings.searchProvider.rawValue) key saved")
    }
    
    private func saveAIKey() {
        let key: KeychainService.KeychainKey = vm.settings.aiProvider == .gemini ? .geminiApiKey : .groqApiKey
        KeychainService.shared.save(key: key, value: aiKeyInput)
        showSaveConfirmation("\(vm.settings.aiProvider.rawValue) key saved")
    }
    
    private func showSaveConfirmation(_ message: String) {
        withAnimation(.easeInOut(duration: 0.3)) { saveConfirmation = message }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation(.easeInOut(duration: 0.3)) { saveConfirmation = "" }
        }
    }
}

// MARK: - Settings Card Component
struct SettingsCard<Content: View>: View {
    let title: String
    let icon: String
    let color: String
    @ViewBuilder let content: Content
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Card Header
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.body.weight(.semibold))
                    .foregroundColor(Color(hex: color))
                    .frame(width: 28, height: 28)
                    .background(Color(hex: color).opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                
                Text(title)
                    .font(.headline)
            }
            
            content
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }
}
