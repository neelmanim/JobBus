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
    @State private var isEditingSearchKey = false
    @State private var isEditingAIKey = false
    
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
                Label("AI Prompt", systemImage: "wand.and.stars").tag(3)
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
                    case 3: aiPromptTab
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
        .frame(width: 680, height: 620)
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
                    
                    apiKeySection(
                        keychainKey: searchKeychainKey,
                        inputBinding: $apiKeyInput,
                        isEditing: $isEditingSearchKey,
                        providerName: vm.settings.searchProvider.rawValue,
                        accentColor: "#3b82f6",
                        onSave: { saveSearchKey() }
                    )
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
                        apiKeySection(
                            keychainKey: aiKeychainKey,
                            inputBinding: $aiKeyInput,
                            isEditing: $isEditingAIKey,
                            providerName: vm.settings.aiProvider.rawValue,
                            accentColor: "#8b5cf6",
                            onSave: { saveAIKey() }
                        )
                    }
                }
            }
        }
    }
    
    // MARK: - Reusable API Key Section
    @ViewBuilder
    private func apiKeySection(
        keychainKey: KeychainService.KeychainKey,
        inputBinding: Binding<String>,
        isEditing: Binding<Bool>,
        providerName: String,
        accentColor: String,
        onSave: @escaping () -> Void
    ) -> some View {
        let storedKey = KeychainService.shared.get(key: keychainKey)
        let hasKey = storedKey != nil && !(storedKey ?? "").isEmpty
        
        if hasKey && !isEditing.wrappedValue {
            // ✅ Key is configured — show masked preview with Edit/Delete
            HStack(spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundColor(.green)
                        .font(.body)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("API Key Configured")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.green)
                        Text(maskedKey(storedKey ?? ""))
                            .font(.caption.monospaced())
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                Button {
                    inputBinding.wrappedValue = ""
                    isEditing.wrappedValue = true
                } label: {
                    Label("Change", systemImage: "pencil")
                        .font(.caption.weight(.medium))
                }
                .buttonStyle(.bordered)
                
                Button {
                    KeychainService.shared.delete(key: keychainKey)
                    showSaveConfirmation("\(providerName) key removed")
                } label: {
                    Image(systemName: "trash")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .tint(.red)
            }
            .padding(10)
            .background(Color.green.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        } else {
            // Key not configured or user is editing — show input field
            VStack(alignment: .leading, spacing: 6) {
                if !hasKey {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                            .font(.caption)
                        Text("API key not configured")
                            .font(.caption.weight(.medium))
                            .foregroundColor(.orange)
                    }
                }
                
                HStack(spacing: 10) {
                    TextField("Enter API key...", text: inputBinding)
                        .textFieldStyle(.roundedBorder)
                    
                    Button {
                        onSave()
                        isEditing.wrappedValue = false
                    } label: {
                        Label("Save", systemImage: "key.fill")
                            .font(.caption.weight(.medium))
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color(hex: accentColor))
                    .disabled(inputBinding.wrappedValue.isEmpty)
                    
                    if hasKey {
                        Button("Cancel") {
                            isEditing.wrappedValue = false
                        }
                        .buttonStyle(.bordered)
                        .font(.caption)
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
    
    // MARK: - AI Prompt Tab
    private var aiPromptTab: some View {
        VStack(spacing: 24) {
            // How It Works — Pipeline Explainer
            SettingsCard(title: "How Email Generation Works", icon: "arrow.triangle.branch", color: "#06b6d4") {
                VStack(alignment: .leading, spacing: 16) {
                    pipelineStep(number: "1", icon: "doc.text.fill", color: "#8b5cf6",
                                 title: "Resume Parsed",
                                 detail: "Your resume is analyzed by AI to extract: name, role, skills, achievements, and experience level.")
                    
                    pipelineArrow()
                    
                    pipelineStep(number: "2", icon: "person.2.fill", color: "#3b82f6",
                                 title: "Contacts Matched",
                                 detail: "Each contact's name, title, company, and type (recruiter/hiring manager) is paired with your profile.")
                    
                    pipelineArrow()
                    
                    pipelineStep(number: "3", icon: "wand.and.stars", color: "#f59e0b",
                                 title: "AI Generates Email",
                                 detail: "The AI receives your profile + each contact's info and writes a personalized email. Your custom instructions (below) are injected here.")
                    
                    pipelineArrow()
                    
                    pipelineStep(number: "4", icon: "checkmark.shield.fill", color: "#10b981",
                                 title: "Quality Check & Send",
                                 detail: "Each draft is scored for quality (placeholder detection, length, personalization). Your resume PDF is attached automatically via SMTP.")
                    
                    Divider().padding(.vertical, 4)
                    
                    // Data mapping table
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Data Mapping")
                            .font(.caption.weight(.bold))
                            .foregroundColor(.secondary)
                        
                        HStack(spacing: 0) {
                            VStack(alignment: .leading, spacing: 6) {
                                mappingRow(source: "Resume → Name", target: "Sender name & signature")
                                mappingRow(source: "Resume → Skills", target: "Email body highlights")
                                mappingRow(source: "Resume → Achievements", target: "Quantifiable proof points")
                                mappingRow(source: "Contact → First Name", target: "Email greeting")
                                mappingRow(source: "Contact → Company", target: "Company reference in body")
                                mappingRow(source: "Contact → Type", target: "Tone & approach style")
                                mappingRow(source: "Resume PDF", target: "SMTP attachment")
                            }
                        }
                    }
                }
            }
            
            // Custom Instructions
            SettingsCard(title: "Custom Prompt Instructions", icon: "text.bubble.fill", color: "#f59e0b") {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Add your own instructions that will be included in every email generation prompt. Use this to customize the tone, focus areas, or add specific requirements.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    
                    TextEditor(text: $vm.settings.customPromptInstructions)
                        .font(.callout.monospaced())
                        .frame(minHeight: 100, maxHeight: 160)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(Color.primary.opacity(0.15), lineWidth: 1)
                        )
                    
                    if vm.settings.customPromptInstructions.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Examples:")
                                .font(.caption.weight(.semibold))
                                .foregroundColor(.secondary)
                            
                            Group {
                                Text("• \"Mention that I'm open to relocating to the Bay Area\"")
                                Text("• \"Focus on my Salesforce CPQ expertise\"")
                                Text("• \"Keep the tone very casual and conversational\"")
                                Text("• \"Always mention my 12 years of enterprise SaaS experience\"")
                            }
                            .font(.caption)
                            .foregroundColor(.secondary.opacity(0.8))
                        }
                        .padding(10)
                        .background(Color.primary.opacity(0.03))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
            
            // Writing Style Samples
            SettingsCard(title: "Writing Style Samples", icon: "text.quote", color: "#ec4899") {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Paste 1-3 emails you've written before. The AI will analyze your writing style — sentence length, tone, formality, greeting patterns — and generate emails that sound like you.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    
                    let validSamples = vm.settings.sampleEmails.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                    
                    if !validSamples.isEmpty {
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                                .font(.caption)
                            Text("\(validSamples.count) sample\(validSamples.count == 1 ? "" : "s") loaded — AI will match your writing style")
                                .font(.caption.weight(.medium))
                                .foregroundColor(.green)
                        }
                    }
                    
                    ForEach(vm.settings.sampleEmails.indices, id: \.self) { index in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("Sample \(index + 1)")
                                    .font(.caption.bold())
                                    .foregroundColor(.secondary)
                                Spacer()
                                let charCount = vm.settings.sampleEmails[index].count
                                Text("\(charCount) chars")
                                    .font(.caption2)
                                    .foregroundColor(charCount > 50 ? .secondary : .orange)
                                Button {
                                    vm.settings.sampleEmails.remove(at: index)
                                    vm.settings.save()
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(.secondary)
                                        .font(.caption)
                                }
                                .buttonStyle(.plain)
                            }
                            TextEditor(text: Binding(
                                get: { vm.settings.sampleEmails[index] },
                                set: { vm.settings.sampleEmails[index] = $0 }
                            ))
                            .font(.callout)
                            .frame(minHeight: 80, maxHeight: 120)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .strokeBorder(Color.primary.opacity(0.15), lineWidth: 1)
                            )
                        }
                    }
                    
                    HStack {
                        if vm.settings.sampleEmails.count < 3 {
                            Button {
                                vm.settings.sampleEmails.append("")
                            } label: {
                                Label("Add Sample Email", systemImage: "plus.circle")
                                    .font(.caption)
                            }
                            .buttonStyle(.bordered)
                        }
                        
                        Spacer()
                        
                        if !vm.settings.sampleEmails.isEmpty {
                            Button {
                                vm.settings.sampleEmails.removeAll()
                                vm.settings.save()
                            } label: {
                                Label("Clear All", systemImage: "trash")
                                    .font(.caption)
                            }
                            .buttonStyle(.bordered)
                            .tint(.red)
                        }
                    }
                    
                    if vm.settings.sampleEmails.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("What makes a good sample?")
                                .font(.caption.weight(.semibold))
                                .foregroundColor(.secondary)
                            
                            Group {
                                Text("• A cold outreach email you sent that got a response")
                                Text("• A networking email to someone you didn't know")
                                Text("• A professional intro email you're proud of")
                                Text("• Even a LinkedIn message works — paste the text")
                            }
                            .font(.caption)
                            .foregroundColor(.secondary.opacity(0.8))
                        }
                        .padding(10)
                        .background(Color.primary.opacity(0.03))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
            
            // Built-in Prompt Preview (read-only)
            SettingsCard(title: "Built-in Prompt Template", icon: "doc.plaintext.fill", color: "#6366f1") {
                VStack(alignment: .leading, spacing: 10) {
                    Text("This is the base prompt sent to the AI for each contact. Your custom instructions above are injected into it.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    
                    ScrollView {
                        Text(builtInPromptPreview)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.secondary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 200)
                    .padding(10)
                    .background(Color.primary.opacity(0.04))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    
                    HStack(spacing: 6) {
                        Image(systemName: "info.circle.fill")
                            .foregroundColor(.blue)
                        Text("This template is read-only. Use the Custom Instructions above to add your own rules.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
    }
    
    // MARK: - Pipeline Step Components
    @ViewBuilder
    private func pipelineStep(number: String, icon: String, color: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color(hex: color).opacity(0.15))
                    .frame(width: 32, height: 32)
                Image(systemName: icon)
                    .font(.caption.weight(.bold))
                    .foregroundColor(Color(hex: color))
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.callout.weight(.semibold))
                Text(detail)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
    
    @ViewBuilder
    private func pipelineArrow() -> some View {
        HStack {
            Spacer().frame(width: 14)
            Image(systemName: "arrow.down")
                .font(.caption2)
                .foregroundColor(.secondary.opacity(0.5))
            Spacer()
        }
    }
    
    @ViewBuilder
    private func mappingRow(source: String, target: String) -> some View {
        HStack(spacing: 8) {
            Text(source)
                .font(.caption.monospaced())
                .foregroundColor(Color(hex: "#8b5cf6"))
                .frame(width: 200, alignment: .leading)
            Image(systemName: "arrow.right")
                .font(.caption2)
                .foregroundColor(.secondary.opacity(0.5))
            Text(target)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
    
    // MARK: - Built-in Prompt Preview
    private var builtInPromptPreview: String {
        """
        Write a personalized cold outreach email from a job seeker to a professional.
        
        SENDER PROFILE:
        Name: {Your Name}
        Current Role: {Your Current Role}
        Experience: {Years} years
        Key Skills: {skill1, skill2, skill3, ...}
        Top Achievements: {achievement1; achievement2; ...}
        Context: {AI-generated career summary}
        
        RECIPIENT:
        Name: {Contact First Name} {Contact Last Name}
        Title: {Contact Title}
        Company: {Contact Company}
        Type: {Recruiter / Hiring Manager / ...}
        Location: {Contact Location}
        
        INSTRUCTIONS FOR {RECIPIENT TYPE}:
        {Type-specific writing guidance}
        
        \(vm.settings.customPromptInstructions.isEmpty ? "[Your custom instructions would appear here]" : "ADDITIONAL INSTRUCTIONS FROM USER:\n\(vm.settings.customPromptInstructions)")
        
        ABSOLUTE RULES:
        1. Email must be under 150 words
        2. Use recipient's FIRST NAME only
        3. Sound human, not template-like
        4. Reference company by name
        5. Include quantifiable achievement
        6. Soft, low-commitment CTA
        7-12. No buzzwords, no filler, no exclamation marks...
        
        FORMAT: SUBJECT: ... BODY: ...
        """
    }
    
    // MARK: - Helpers
    
    private var searchKeychainKey: KeychainService.KeychainKey {
        switch vm.settings.searchProvider {
        case .apollo: return .apolloApiKey
        case .hunter: return .hunterApiKey
        case .rocketReach: return .rocketReachApiKey
        }
    }
    
    private var aiKeychainKey: KeychainService.KeychainKey {
        return vm.settings.aiProvider == .gemini ? .geminiApiKey : .groqApiKey
    }
    
    private func maskedKey(_ key: String) -> String {
        guard key.count > 8 else { return "••••••••" }
        let prefix = String(key.prefix(4))
        let suffix = String(key.suffix(4))
        return "\(prefix)••••••••\(suffix)"
    }
    
    // MARK: - Actions
    
    private func saveSearchKey() {
        KeychainService.shared.save(key: searchKeychainKey, value: apiKeyInput)
        showSaveConfirmation("\(vm.settings.searchProvider.rawValue) key saved")
    }
    
    private func saveAIKey() {
        KeychainService.shared.save(key: aiKeychainKey, value: aiKeyInput)
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
