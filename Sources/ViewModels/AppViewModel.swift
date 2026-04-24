import SwiftUI

// MARK: - App View Model
@MainActor
class AppViewModel: ObservableObject {
    @Published var currentStep: AppStep = .resume
    @Published var settings: AppSettings
    @Published var resumeProfile: ResumeProfile?
    @Published var searchStrategy: SearchStrategy?
    @Published var contacts: [Contact] = []
    @Published var drafts: [EmailDraft] = []
    @Published var sendRecords: [SendRecord] = []
    @Published var campaignStatus: CampaignStatus = .idle
    
    // Progress tracking
    @Published var isLoading = false
    @Published var loadingMessage = ""
    @Published var errorMessage: String?
    @Published var showError = false
    
    // Sending progress
    @Published var sentCount = 0
    @Published var failedCount = 0
    @Published var isPaused = false
    
    // Services
    let pdfParser = PDFParserService()
    let docxParser = DOCXParserService()
    let csvImporter = CSVImporter()
    let resumeAnalyzer = ResumeAnalyzer()
    let emailWriter = EmailWriter()
    
    private var sendTask: Task<Void, Never>?
    
    init() {
        self.settings = AppSettings.load()
    }
    
    // MARK: - Provider Factory
    
    var searchProvider: ContactSearchProvider {
        switch settings.searchProvider {
        case .apollo: return ApolloSearchProvider()
        case .hunter: return HunterSearchProvider()
        case .rocketReach: return RocketReachSearchProvider()
        }
    }
    
    var enrichmentProvider: EmailEnrichmentProvider {
        switch settings.searchProvider {
        case .apollo: return ApolloSearchProvider()
        case .hunter: return HunterSearchProvider()
        case .rocketReach: return RocketReachSearchProvider()
        }
    }
    
    var aiProvider: AIProvider {
        switch settings.aiProvider {
        case .ollama:
            return OllamaProvider(model: settings.ollamaModel, baseURL: settings.ollamaBaseURL)
        case .gemini:
            return GeminiFlashProvider()
        case .groq:
            return GroqProvider()
        }
    }
    
    var emailSender: SMTPEmailProvider {
        return SMTPEmailProvider(
            providerType: settings.emailProvider,
            customHost: settings.customSmtpHost,
            customPort: settings.customSmtpPort
        )
    }
    
    // MARK: - Resume Parsing
    
    func parseResume(from url: URL) async {
        isLoading = true
        loadingMessage = "Reading resume..."
        
        do {
            // Offload heavy file I/O to a background thread so the UI stays responsive.
            // PDFKit text extraction and DOCX XML parsing are CPU-heavy and must not
            // run on @MainActor — this was the primary cause of the app freeze/crash.
            let pdfParser = self.pdfParser
            let docxParser = self.docxParser
            let fileExtension = url.pathExtension.lowercased()
            
            let text: String = try await Task.detached(priority: .userInitiated) {
                if fileExtension == "pdf" {
                    return try pdfParser.extractText(from: url)
                } else {
                    return try docxParser.extractText(from: url)
                }
            }.value
            
            loadingMessage = "AI analyzing your resume..."
            let profile = try await resumeAnalyzer.analyze(resumeText: text, ai: aiProvider)
            self.resumeProfile = profile
            
            loadingMessage = "Generating search strategy..."
            let strategy = try await resumeAnalyzer.generateStrategy(from: profile, ai: aiProvider)
            self.searchStrategy = strategy
            
            // Auto-fill signature from resume
            if settings.signatureName.isEmpty {
                settings.signatureName = profile.name
                settings.signatureTitle = profile.currentRole
                settings.signatureLinkedin = profile.linkedinUrl
                settings.signaturePhone = profile.phone
            }
            
            isLoading = false
            currentStep = .strategy
        } catch is CancellationError {
            isLoading = false
            showError("Resume parsing was cancelled.")
        } catch let providerError as ProviderError {
            isLoading = false
            switch providerError {
            case .notConfigured(let msg):
                showError(msg)
            case .invalidApiKey:
                showError("Invalid API key for \(settings.aiProvider.rawValue).\n\nGo to Settings → Providers to check your API key.")
            case .rateLimited(let msg):
                showError("Rate limit reached for \(settings.aiProvider.rawValue).\n\n\(msg)\n\nPlease wait a minute or switch to a different provider.")
            case .serviceUnavailable(let msg):
                if settings.aiProvider == .ollama {
                    showError("Ollama is not running.\n\n1. Install: brew install ollama\n2. Start: ollama serve\n3. Pull model: ollama pull llama3.1:8b\n\nOr switch to Gemini/Groq in Settings → Providers.")
                } else {
                    showError("Service unavailable: \(msg)")
                }
            default:
                showError(providerError.localizedDescription)
            }
        } catch {
            isLoading = false
            let msg = error.localizedDescription
            if msg.contains("Could not connect") || msg.contains("Connection refused") {
                showError("Could not connect to \(settings.aiProvider.rawValue). Check your internet connection and try again.")
            } else {
                showError(msg)
            }
        }
    }
    
    // MARK: - Contact Search
    
    func searchContacts() async {
        guard let strategy = searchStrategy else { return }
        isLoading = true
        loadingMessage = "Searching for contacts..."
        
        do {
            let found = try await searchProvider.search(strategy: strategy, count: settings.contactCount)
            
            loadingMessage = "Enriching contacts to get emails..."
            let enriched = try await enrichmentProvider.enrichBatch(contacts: found) { done, total in
                Task { @MainActor in
                    self.loadingMessage = "Enriching contacts: \(done)/\(total)..."
                }
            }
            
            // Add to contacts pool (dedup with existing)
            let allContacts = contacts + enriched
            let (unique, _) = DuplicateDetector.removeDuplicates(from: allContacts)
            contacts = unique
            
            isLoading = false
            currentStep = .contacts
        } catch let providerError as ProviderError {
            isLoading = false
            switch providerError {
            case .notConfigured(let msg):
                showError(msg)
            case .invalidApiKey:
                showError("Invalid Apollo API key.\n\nGo to Settings → Providers to check your Apollo key.")
            case .rateLimited(let msg):
                showError("Apollo rate limit reached.\n\n\(msg)")
            case .creditsExhausted:
                showError("Apollo credits exhausted.\n\nUpgrade your Apollo plan or use CSV import / Manual entry instead.")
            default:
                showError(providerError.localizedDescription)
            }
        } catch {
            isLoading = false
            showError(error.localizedDescription)
        }
    }
    
    // MARK: - CSV Import
    
    func importCSV(from url: URL) {
        do {
            let result = try csvImporter.parseCSV(from: url)
            let allContacts = contacts + result.contacts
            let (unique, _) = DuplicateDetector.removeDuplicates(from: allContacts)
            contacts = unique
        } catch {
            showError(error.localizedDescription)
        }
    }
    
    // MARK: - Manual Add
    
    func addManualContact(_ contact: Contact) {
        let allContacts = contacts + [contact]
        let (unique, _) = DuplicateDetector.removeDuplicates(from: allContacts)
        contacts = unique
    }
    
    // MARK: - Generate Drafts
    
    func generateDrafts() async {
        guard let profile = resumeProfile else { return }
        let selectedContacts = contacts.filter { $0.isSelected && !$0.email.isEmpty }
        
        isLoading = true
        drafts = []
        
        for (index, contact) in selectedContacts.enumerated() {
            loadingMessage = "Composing email \(index + 1)/\(selectedContacts.count)..."
            
            do {
                let draft = try await emailWriter.compose(contact: contact, resume: profile, ai: aiProvider)
                drafts.append(draft)
            } catch {
                // Create a failed draft entry
                var failedDraft = EmailDraft(contactId: contact.id)
                failedDraft.status = .failed
                failedDraft.recipientName = contact.fullName
                failedDraft.recipientEmail = contact.email
                failedDraft.recipientCompany = contact.company
                drafts.append(failedDraft)
            }
            
            // Small delay between AI calls
            try? await Task.sleep(for: .milliseconds(200))
        }
        
        isLoading = false
        currentStep = .drafts
    }
    
    // MARK: - Campaign Sending
    
    func startCampaign() {
        campaignStatus = .running
        sentCount = 0
        failedCount = 0
        isPaused = false
        
        let approvedDrafts = drafts.filter { $0.status == .approved }
        
        sendTask = Task {
            for (index, draft) in approvedDrafts.enumerated() {
                // Check pause/stop
                while isPaused { try? await Task.sleep(for: .seconds(1)) }
                if campaignStatus == .stopped { break }
                
                // Business hours check
                if settings.businessHoursOnly {
                    await waitForBusinessHours()
                }
                
                // Daily limit check
                if sentCount >= settings.maxPerDay {
                    campaignStatus = .paused
                    loadingMessage = "Daily limit reached. Will resume tomorrow."
                    break
                }
                
                // First-3 hold
                if index == 3 && sentCount == 3 {
                    isPaused = true
                    loadingMessage = "Sent 3 emails. Check your Gmail Sent folder — do they look right?"
                    while isPaused { try? await Task.sleep(for: .seconds(1)) }
                }
                
                // Send
                let result = try? await emailSender.send(
                    to: draft.recipientEmail,
                    toName: draft.recipientName,
                    from: settings.smtpEmail,
                    fromName: settings.smtpDisplayName,
                    subject: draft.subject,
                    textBody: draft.body,
                    htmlBody: draft.htmlBody
                )
                
                if result?.success == true {
                    sentCount += 1
                    sendRecords.append(SendRecord(
                        draftId: draft.id,
                        recipientEmail: draft.recipientEmail,
                        recipientName: draft.recipientName,
                        subject: draft.subject,
                        sentAt: Date(),
                        status: .sent,
                        smtpResponse: result?.smtpResponse
                    ))
                } else {
                    failedCount += 1
                    sendRecords.append(SendRecord(
                        draftId: draft.id,
                        recipientEmail: draft.recipientEmail,
                        recipientName: draft.recipientName,
                        subject: draft.subject,
                        sentAt: Date(),
                        status: .failed,
                        errorMessage: result?.errorMessage
                    ))
                    
                    // Anomaly detection: >20% failure → auto-pause
                    let total = sentCount + failedCount
                    if total >= 5 && Double(failedCount) / Double(total) > 0.2 {
                        isPaused = true
                        loadingMessage = "High failure rate detected (\(failedCount)/\(total)). Paused for review."
                    }
                }
                
                // Delay between emails
                try? await Task.sleep(for: .seconds(settings.delaySeconds))
            }
            
            if campaignStatus != .stopped {
                campaignStatus = .complete
            }
        }
    }
    
    func pauseCampaign() { isPaused = true }
    func resumeCampaign() { isPaused = false }
    func stopCampaign() { campaignStatus = .stopped; sendTask?.cancel() }
    
    // MARK: - Helpers
    
    private func waitForBusinessHours() async {
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: Date())
        if hour < settings.businessHoursStart || hour >= settings.businessHoursEnd {
            let nextStart = calendar.nextDate(
                after: Date(),
                matching: DateComponents(hour: settings.businessHoursStart),
                matchingPolicy: .nextTime
            )!
            let waitTime = nextStart.timeIntervalSince(Date())
            loadingMessage = "Waiting for business hours (\(settings.businessHoursStart):00)..."
            try? await Task.sleep(for: .seconds(max(1, waitTime)))
        }
    }
    
    func showError(_ message: String) {
        errorMessage = message
        showError = true
    }
}

// MARK: - App Steps
enum AppStep: Int, CaseIterable, Identifiable {
    case resume = 0
    case strategy = 1
    case contacts = 2
    case drafts = 3
    case send = 4
    
    var id: Int { rawValue }
    
    var title: String {
        switch self {
        case .resume: return "Resume"
        case .strategy: return "Strategy"
        case .contacts: return "Contacts"
        case .drafts: return "Compose"
        case .send: return "Send"
        }
    }
    
    var icon: String {
        switch self {
        case .resume: return "doc.text.fill"
        case .strategy: return "target"
        case .contacts: return "person.3.fill"
        case .drafts: return "envelope.fill"
        case .send: return "paperplane.fill"
        }
    }
}
