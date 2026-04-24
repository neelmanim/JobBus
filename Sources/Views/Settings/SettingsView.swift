import SwiftUI

// MARK: - Settings View
struct SettingsView: View {
    @EnvironmentObject var vm: AppViewModel
    @State private var apiKeyInput = ""
    @State private var smtpPasswordInput = ""
    @State private var aiKeyInput = ""
    @State private var validationMessage = ""
    @State private var isValidating = false
    
    var body: some View {
        TabView {
            // MARK: - Providers Tab
            Form {
                Section("Contact Provider") {
                    Picker("Provider", selection: $vm.settings.searchProvider) {
                        ForEach(SearchProviderType.allCases) { provider in
                            HStack {
                                Image(systemName: provider.icon)
                                Text(provider.rawValue)
                            }
                            .tag(provider)
                        }
                    }
                    
                    Text(vm.settings.searchProvider.description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    HStack {
                        SecureField("API Key", text: $apiKeyInput)
                        Button(isValidating ? "Validating..." : "Save Key") {
                            let key: KeychainService.KeychainKey
                            switch vm.settings.searchProvider {
                            case .apollo: key = .apolloApiKey
                            case .hunter: key = .hunterApiKey
                            case .rocketReach: key = .rocketReachApiKey
                            }
                            KeychainService.shared.save(key: key, value: apiKeyInput)
                            validationMessage = "API key saved"
                        }
                        .buttonStyle(.bordered)
                        .disabled(apiKeyInput.isEmpty || isValidating)
                    }
                }
                
                Section("AI Provider") {
                    Picker("Provider", selection: $vm.settings.aiProvider) {
                        ForEach(AIProviderType.allCases) { provider in
                            HStack {
                                Image(systemName: provider.icon)
                                Text(provider.rawValue)
                            }
                            .tag(provider)
                        }
                    }
                    
                    Text(vm.settings.aiProvider.description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    if vm.settings.aiProvider == .ollama {
                        TextField("Ollama URL", text: $vm.settings.ollamaBaseURL)
                        TextField("Model", text: $vm.settings.ollamaModel)
                    }
                    
                    if vm.settings.aiProvider.requiresApiKey {
                        HStack {
                            SecureField("API Key", text: $aiKeyInput)
                            Button("Save") {
                                let key: KeychainService.KeychainKey = vm.settings.aiProvider == .gemini ? .geminiApiKey : .groqApiKey
                                KeychainService.shared.save(key: key, value: aiKeyInput)
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
            }
            .tabItem { Label("Providers", systemImage: "puzzlepiece.fill") }
            .padding()
            
            // MARK: - Email Tab
            Form {
                Section("SMTP Configuration") {
                    Picker("Email Provider", selection: $vm.settings.emailProvider) {
                        ForEach(EmailProviderType.allCases) { provider in
                            Text(provider.rawValue).tag(provider)
                        }
                    }
                    
                    TextField("Your Email", text: $vm.settings.smtpEmail)
                    TextField("Display Name", text: $vm.settings.smtpDisplayName)
                    
                    HStack {
                        SecureField("App Password", text: $smtpPasswordInput)
                        Button("Save") {
                            KeychainService.shared.save(key: .smtpPassword, value: smtpPasswordInput)
                        }
                        .buttonStyle(.bordered)
                    }
                    
                    if vm.settings.emailProvider == .custom {
                        TextField("SMTP Host", text: $vm.settings.customSmtpHost)
                        TextField("Port", value: $vm.settings.customSmtpPort, format: .number)
                    }
                }
                
                Section("Email Signature") {
                    TextField("Name", text: $vm.settings.signatureName)
                    TextField("Title", text: $vm.settings.signatureTitle)
                    TextField("LinkedIn URL", text: $vm.settings.signatureLinkedin)
                    TextField("Phone", text: $vm.settings.signaturePhone)
                }
            }
            .tabItem { Label("Email", systemImage: "envelope.fill") }
            .padding()
            
            // MARK: - Campaign Tab
            Form {
                Section("Sending Rules") {
                    HStack {
                        Text("Delay between emails")
                        Spacer()
                        TextField("", value: $vm.settings.delaySeconds, format: .number)
                            .frame(width: 60)
                        Text("seconds")
                    }
                    
                    HStack {
                        Text("Daily send limit")
                        Spacer()
                        TextField("", value: $vm.settings.maxPerDay, format: .number)
                            .frame(width: 60)
                    }
                    
                    Toggle("Business hours only", isOn: $vm.settings.businessHoursOnly)
                    
                    if vm.settings.businessHoursOnly {
                        HStack {
                            Text("Hours:")
                            Stepper("\(vm.settings.businessHoursStart):00", value: $vm.settings.businessHoursStart, in: 0...23)
                            Text("to")
                            Stepper("\(vm.settings.businessHoursEnd):00", value: $vm.settings.businessHoursEnd, in: 0...23)
                        }
                    }
                    
                    Toggle("Warm-up mode (gradual increase)", isOn: $vm.settings.warmUpEnabled)
                }
                
                Section("Safety") {
                    Toggle("Sandbox Mode (no real emails sent)", isOn: $vm.settings.sandboxMode)
                    
                    if vm.settings.sandboxMode {
                        TextField("Sandbox Host", text: $vm.settings.sandboxHost)
                        TextField("Sandbox Port", value: $vm.settings.sandboxPort, format: .number)
                        Text("Install Mailhog: brew install mailhog && mailhog")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .tabItem { Label("Campaign", systemImage: "paperplane.fill") }
            .padding()
        }
        .frame(width: 550, height: 450)
        .onDisappear {
            vm.settings.save()
        }
    }
}
