import SwiftUI

// MARK: - First-Run Onboarding Wizard
/// A 4-step guided setup shown on first launch.
/// Walks users through: Welcome → AI Provider → Email Setup → Ready.
struct OnboardingView: View {
    @EnvironmentObject var vm: AppViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var currentStep = 0
    @State private var aiKeyInput = ""
    @State private var smtpPasswordInput = ""
    @State private var testingConnection = false
    @State private var connectionResult: String?
    
    private let totalSteps = 4
    
    var body: some View {
        VStack(spacing: 0) {
            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(Color.gray.opacity(0.15))
                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: [Color(hex: "#8b5cf6"), Color(hex: "#3b82f6")],
                                startPoint: .leading, endPoint: .trailing
                            )
                        )
                        .frame(width: geo.size.width * CGFloat(currentStep + 1) / CGFloat(totalSteps))
                        .animation(.easeInOut(duration: 0.4), value: currentStep)
                }
            }
            .frame(height: 4)
            
            // Content
            TabView(selection: $currentStep) {
                welcomeStep.tag(0)
                aiProviderStep.tag(1)
                emailSetupStep.tag(2)
                readyStep.tag(3)
            }
            .tabViewStyle(.automatic)
            .animation(.easeInOut(duration: 0.3), value: currentStep)
            
            // Navigation buttons
            HStack {
                if currentStep > 0 {
                    Button {
                        withAnimation { currentStep -= 1 }
                    } label: {
                        Label("Back", systemImage: "chevron.left")
                    }
                    .buttonStyle(.bordered)
                }
                
                Spacer()
                
                Text("Step \(currentStep + 1) of \(totalSteps)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                if currentStep < totalSteps - 1 {
                    Button {
                        withAnimation { currentStep += 1 }
                    } label: {
                        Label("Next", systemImage: "chevron.right")
                            .labelStyle(.titleAndIcon)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color(hex: "#8b5cf6"))
                } else {
                    Button {
                        completeOnboarding()
                    } label: {
                        Label("Start Using JobBus", systemImage: "checkmark.circle.fill")
                            .font(.body.bold())
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color(hex: "#10b981"))
                }
            }
            .padding(20)
            .background(.bar)
        }
        .frame(width: 600, height: 520)
    }
    
    // MARK: - Step 1: Welcome
    private var welcomeStep: some View {
        VStack(spacing: 24) {
            Spacer()
            
            Image(systemName: "bus.fill")
                .font(.system(size: 56))
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color(hex: "#8b5cf6"), Color(hex: "#3b82f6")],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                )
            
            Text("Welcome to JobBus")
                .font(.largeTitle.bold())
            
            Text("AI-powered job outreach for macOS")
                .font(.title3)
                .foregroundColor(.secondary)
            
            VStack(alignment: .leading, spacing: 16) {
                featureRow(icon: "doc.text.magnifyingglass", color: "#8b5cf6",
                          title: "Smart Resume Parsing",
                          detail: "AI extracts your skills, achievements, and experience automatically")
                
                featureRow(icon: "person.2.fill", color: "#3b82f6",
                          title: "Contact Discovery",
                          detail: "Find recruiters and hiring managers matching your profile")
                
                featureRow(icon: "envelope.fill", color: "#10b981",
                          title: "Personalized Outreach",
                          detail: "AI writes unique emails for each contact — no templates, no spam")
            }
            .padding(.horizontal, 40)
            
            Spacer()
        }
        .padding(.top, 20)
    }
    
    // MARK: - Step 2: AI Provider
    private var aiProviderStep: some View {
        ScrollView {
            VStack(spacing: 20) {
                stepHeader(icon: "sparkles", color: "#8b5cf6",
                          title: "Choose Your AI Provider",
                          subtitle: "JobBus uses AI to parse resumes and write emails.")
                
                // Provider picker
                Picker("AI Provider", selection: $vm.settings.aiProvider) {
                    ForEach(AIProviderType.allCases) { provider in
                        Label(provider.rawValue, systemImage: provider.icon).tag(provider)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 40)
                
                // Provider description
                Text(vm.settings.aiProvider.description)
                    .font(.callout)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
                
                // API Key input (if needed)
                if vm.settings.aiProvider.requiresApiKey {
                    let keychainKey: KeychainService.KeychainKey = vm.settings.aiProvider == .gemini ? .geminiApiKey : .groqApiKey
                    let existingKey = KeychainService.shared.get(key: keychainKey)
                    
                    VStack(spacing: 12) {
                        if let key = existingKey, !key.isEmpty {
                            HStack(spacing: 8) {
                                Image(systemName: "checkmark.seal.fill")
                                    .foregroundColor(.green)
                                Text("API Key configured")
                                    .font(.callout.weight(.medium))
                                    .foregroundColor(.green)
                            }
                        } else {
                            HStack(spacing: 10) {
                                SecureField("Paste your API key...", text: $aiKeyInput)
                                    .textFieldStyle(.roundedBorder)
                                
                                Button {
                                    KeychainService.shared.save(key: keychainKey, value: aiKeyInput)
                                    aiKeyInput = ""
                                } label: {
                                    Label("Save", systemImage: "key.fill")
                                        .font(.caption.weight(.medium))
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(Color(hex: "#8b5cf6"))
                                .disabled(aiKeyInput.isEmpty)
                            }
                            
                            // Quick link
                            if vm.settings.aiProvider == .gemini {
                                Link("Get a free Gemini API key →", destination: URL(string: "https://aistudio.google.com/apikey")!)
                                    .font(.caption)
                            } else if vm.settings.aiProvider == .groq {
                                Link("Get a free Groq API key →", destination: URL(string: "https://console.groq.com/keys")!)
                                    .font(.caption)
                            }
                        }
                    }
                    .padding(16)
                    .background(.regularMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal, 40)
                } else {
                    // Ollama instructions
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Ollama runs locally — no API key needed!")
                            .font(.callout.weight(.medium))
                            .foregroundColor(.green)
                        
                        Text("Make sure Ollama is running:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Text("brew install ollama && ollama serve")
                            .font(.caption.monospaced())
                            .padding(8)
                            .background(Color.primary.opacity(0.06))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .padding(16)
                    .background(.regularMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal, 40)
                }
            }
            .padding(.vertical, 20)
        }
    }
    
    // MARK: - Step 3: Email Setup
    private var emailSetupStep: some View {
        ScrollView {
            VStack(spacing: 20) {
                stepHeader(icon: "envelope.fill", color: "#10b981",
                          title: "Email Setup",
                          subtitle: "Configure SMTP to send emails. You can skip this and set it up later.")
                
                // Provider picker
                Picker("Email Provider", selection: $vm.settings.emailProvider) {
                    ForEach(EmailProviderType.allCases) { provider in
                        Label(provider.rawValue, systemImage: provider.icon).tag(provider)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 40)
                
                // Quick setup instructions
                VStack(alignment: .leading, spacing: 12) {
                    if vm.settings.emailProvider == .gmail {
                        setupInstruction("1", "Enable 2-Factor Authentication on your Google account")
                        setupInstruction("2", "Go to myaccount.google.com → Security → App Passwords")
                        setupInstruction("3", "Generate a new App Password for 'Mail'")
                        setupInstruction("4", "Paste the 16-character password below")
                    } else if vm.settings.emailProvider == .outlook {
                        setupInstruction("1", "Sign in to your Microsoft account")
                        setupInstruction("2", "Go to Security → Advanced security options")
                        setupInstruction("3", "Create a new App Password")
                        setupInstruction("4", "Paste the generated password below")
                    } else {
                        setupInstruction("1", "Get your SMTP server hostname and port from your email provider")
                        setupInstruction("2", "Enter your email and password below")
                    }
                }
                .padding(16)
                .background(.regularMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal, 40)
                
                // Email + Password
                VStack(spacing: 12) {
                    LabeledContent("Your Email") {
                        TextField("you@gmail.com", text: $vm.settings.smtpEmail)
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 260)
                    }
                    
                    LabeledContent("App Password") {
                        SecureField("Paste app password...", text: $smtpPasswordInput)
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 260)
                    }
                    
                    if !smtpPasswordInput.isEmpty {
                        Button {
                            KeychainService.shared.save(key: .smtpPassword, value: smtpPasswordInput)
                            smtpPasswordInput = ""
                        } label: {
                            Label("Save Password", systemImage: "lock.shield.fill")
                                .font(.caption.weight(.medium))
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Color(hex: "#10b981"))
                    }
                    
                    let hasPassword = !(KeychainService.shared.get(key: .smtpPassword) ?? "").isEmpty
                    if hasPassword {
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.seal.fill")
                                .foregroundColor(.green)
                            Text("Password saved securely in Keychain")
                                .font(.caption)
                                .foregroundColor(.green)
                        }
                    }
                }
                .padding(.horizontal, 40)
                
                // Skip note
                HStack(spacing: 6) {
                    Image(systemName: "info.circle")
                        .foregroundColor(.blue)
                    Text("You can skip this step and configure email later in Settings.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 40)
            }
            .padding(.vertical, 20)
        }
    }
    
    // MARK: - Step 4: Ready
    private var readyStep: some View {
        VStack(spacing: 24) {
            Spacer()
            
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 56))
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color(hex: "#10b981"), Color(hex: "#3b82f6")],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                )
            
            Text("You're All Set!")
                .font(.largeTitle.bold())
            
            Text("Here's what happens next:")
                .font(.title3)
                .foregroundColor(.secondary)
            
            VStack(alignment: .leading, spacing: 14) {
                readyCheckmark(vm.settings.aiProvider.requiresApiKey
                    ? !(KeychainService.shared.get(key: vm.settings.aiProvider == .gemini ? .geminiApiKey : .groqApiKey) ?? "").isEmpty
                    : true,
                    "AI Provider configured (\(vm.settings.aiProvider.rawValue))")
                
                readyCheckmark(!vm.settings.smtpEmail.isEmpty,
                    "Email address set")
                
                readyCheckmark(!(KeychainService.shared.get(key: .smtpPassword) ?? "").isEmpty || vm.settings.sandboxMode,
                    "SMTP password saved (or using Sandbox)")
                
                readyCheckmark(true, "Sandbox mode is \(vm.settings.sandboxMode ? "ON" : "OFF")")
            }
            .padding(.horizontal, 40)
            
            // Sandbox explanation
            HStack(spacing: 8) {
                Image(systemName: "flask.fill")
                    .foregroundColor(.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Sandbox Mode is ON by default")
                        .font(.caption.bold())
                    Text("All emails go to a local test server. Turn it off in Settings when you're ready to go live.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(12)
            .background(Color.orange.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .padding(.horizontal, 40)
            
            Spacer()
        }
        .padding(.top, 20)
    }
    
    // MARK: - Components
    
    @ViewBuilder
    private func featureRow(icon: String, color: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(Color(hex: color))
                .frame(width: 32)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body.weight(.semibold))
                Text(detail)
                    .font(.callout)
                    .foregroundColor(.secondary)
            }
        }
    }
    
    @ViewBuilder
    private func stepHeader(icon: String, color: String, title: String, subtitle: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 36))
                .foregroundColor(Color(hex: color))
            
            Text(title)
                .font(.title2.bold())
            
            Text(subtitle)
                .font(.callout)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
    }
    
    @ViewBuilder
    private func setupInstruction(_ number: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(number)
                .font(.caption.bold())
                .foregroundColor(.white)
                .frame(width: 20, height: 20)
                .background(Color(hex: "#10b981"))
                .clipShape(Circle())
            
            Text(text)
                .font(.callout)
                .foregroundColor(.secondary)
        }
    }
    
    @ViewBuilder
    private func readyCheckmark(_ done: Bool, _ text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: done ? "checkmark.circle.fill" : "circle")
                .foregroundColor(done ? .green : .secondary)
            Text(text)
                .font(.callout)
                .foregroundColor(done ? .primary : .secondary)
        }
    }
    
    // MARK: - Actions
    
    private func completeOnboarding() {
        vm.settings.hasCompletedOnboarding = true
        vm.settings.save()
        dismiss()
    }
}
