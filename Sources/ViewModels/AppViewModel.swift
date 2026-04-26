import SwiftUI
import UserNotifications
import Combine

// MARK: - App View Model
/// Thin coordinator that owns all @Published UI state and delegates
/// business logic to focused managers (ContactManager, DraftManager, SendEngine).
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
    
    // Resume file for email attachment
    @Published var resumeFileURL: URL?
    
    // Granular operation state (prevents double-clicks and enables cancel)
    @Published var isLoading = false
    @Published var isGenerating = false
    @Published var isSearching = false
    @Published var loadingMessage = ""
    @Published var errorMessage: String?
    @Published var showError = false
    
    // Retry support
    @Published var canRetry = false
    var retryAction: (() async -> Void)?
    
    // Sending progress
    @Published var sentCount = 0
    @Published var failedCount = 0
    @Published var campaignTotal = 0
    
    // Completion banner
    @Published var showCompletionBanner = false
    @Published var completionMessage = ""
    
    // Services
    let pdfParser = PDFParserService()
    let docxParser = DOCXParserService()
    let csvImporter = CSVImporter()
    let resumeAnalyzer = ResumeAnalyzer()
    let emailWriter = EmailWriter()
    
    // Managers (extracted business logic)
    let contactManager = ContactManager()
    let draftManager = DraftManager()
    let sendEngine = SendEngine()
    let usageTracker = UsageTracker()
    
    // Task handles for cancellation
    private var searchTask: Task<Void, Never>?
    
    // Forward nested ObservableObject changes so SwiftUI sees them
    private var settingsSink: AnyCancellable?
    private var tokenSink: AnyCancellable?
    private var creditSink: AnyCancellable?
    private var usageSink: AnyCancellable?
    
    init() {
        self.settings = AppSettings.load()
        
        // Forward settings changes to our objectWillChange so SwiftUI picks them up
        settingsSink = settings.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
        
        // Forward usage tracker changes so the sidebar stats update
        usageSink = usageTracker.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
        
        // Load cached contacts from previous session
        contacts = contactManager.loadCached()
        
        // Restore resume attachment URL if a cached copy exists
        restoreCachedResumeURL()
        
        requestNotificationPermission()
        
        // Subscribe to AI token usage notifications
        tokenSink = NotificationCenter.default.publisher(for: .aiTokensUsed)
            .receive(on: RunLoop.main)
            .sink { [weak self] notification in
                if let tokens = notification.userInfo?["tokens"] as? Int {
                    self?.usageTracker.addGroqTokens(tokens)
                }
            }
        
        // Subscribe to Apollo credit usage notifications
        creditSink = NotificationCenter.default.publisher(for: .apolloCreditUsed)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.usageTracker.addApolloCredits(1)
            }
        
        log.section("APP LAUNCH")
        log.info("AI Provider: \(settings.aiProvider.rawValue)")
        log.info("Search Provider: \(settings.searchProvider.rawValue)")
        log.info("Sandbox Mode: \(settings.sandboxMode)")
        log.info("SMTP: \(settings.smtpEmail.isEmpty ? "Not configured" : settings.smtpEmail)")
        log.info("Cached contacts: \(contacts.count)")
        log.info("Resume URL: \(resumeFileURL?.path ?? "none")")
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
        if settings.sandboxMode {
            return SMTPEmailProvider(
                providerType: .custom,
                customHost: settings.sandboxHost,
                customPort: settings.sandboxPort
            )
        }
        return SMTPEmailProvider(
            providerType: settings.emailProvider,
            customHost: settings.customSmtpHost,
            customPort: settings.customSmtpPort
        )
    }
    
    // MARK: - Resume Parsing
    
    func parseResume(from url: URL) async {
        guard !isLoading else { return }
        isLoading = true
        loadingMessage = "Reading resume..."
        canRetry = false
        
        do {
            // Offload heavy file I/O to a background thread
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
            
            // Edge case: empty or near-empty resume
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.count >= 50 else {
                isLoading = false
                showErrorWithRetry("The resume appears to be empty or contains very little text (\(trimmed.count) characters).\n\nPlease check that the file is a valid PDF or DOCX with readable text content.") {
                    await self.parseResume(from: url)
                }
                return
            }
            
            loadingMessage = "AI analyzing your resume..."
            log.section("RESUME PARSE")
            log.info("File: \(url.lastPathComponent) (\(fileExtension))")
            log.info("Extracted text: \(trimmed.count) chars")
            let profile = try await resumeAnalyzer.analyze(resumeText: text, ai: aiProvider)
            self.resumeProfile = profile
            log.info("Profile: \(profile.name), \(profile.currentRole), \(profile.yearsExperience) yrs exp")
            log.info("Skills: \(profile.skills.prefix(6).joined(separator: ", "))")
            
            // Copy resume to app support so it's always accessible for SMTP attachment
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            let jobBusDir = appSupport.appendingPathComponent("JobBus", isDirectory: true)
            try? FileManager.default.createDirectory(at: jobBusDir, withIntermediateDirectories: true)
            let destURL = jobBusDir.appendingPathComponent("resume_attachment.\(url.pathExtension)")
            try? FileManager.default.removeItem(at: destURL)
            do {
                _ = url.startAccessingSecurityScopedResource()
                try FileManager.default.copyItem(at: url, to: destURL)
                url.stopAccessingSecurityScopedResource()
                self.resumeFileURL = destURL
                log.info("Resume copied to: \(destURL.path)")
            } catch {
                self.resumeFileURL = url
                log.warn("Resume copy failed: \(error.localizedDescription), using original URL")
            }
            
            loadingMessage = "Generating search strategy..."
            let strategy = try await resumeAnalyzer.generateStrategy(from: profile, ai: aiProvider)
            self.searchStrategy = strategy
            
            // Auto-fill signature from resume
            if settings.signatureName.isEmpty {
                settings.signatureName = profile.name
                settings.signatureTitle = profile.currentRole
                settings.signatureLinkedin = profile.linkedinUrl
                settings.signaturePhone = profile.phone
                settings.save()
            }
            
            isLoading = false
            currentStep = .strategy
        } catch is CancellationError {
            isLoading = false
            showError("Resume parsing was cancelled.")
        } catch let providerError as ProviderError {
            isLoading = false
            let resumeURL = url
            switch providerError {
            case .notConfigured(let msg):
                showErrorWithRetry(msg) { await self.parseResume(from: resumeURL) }
            case .invalidApiKey:
                showErrorWithRetry("Invalid API key for \(settings.aiProvider.rawValue).\n\nGo to Settings → Providers to check your API key.") {
                    await self.parseResume(from: resumeURL)
                }
            case .rateLimited(let msg):
                showErrorWithRetry("Rate limit reached for \(settings.aiProvider.rawValue).\n\n\(msg)\n\nPlease wait a minute or switch to a different provider.") {
                    await self.parseResume(from: resumeURL)
                }
            case .serviceUnavailable(let msg):
                if settings.aiProvider == .ollama {
                    showErrorWithRetry("Ollama is not running.\n\n1. Install: brew install ollama\n2. Start: ollama serve\n3. Pull model: ollama pull llama3.1:8b\n\nOr switch to Gemini/Groq in Settings → Providers.") {
                        await self.parseResume(from: resumeURL)
                    }
                } else {
                    showErrorWithRetry("Service unavailable: \(msg)") {
                        await self.parseResume(from: resumeURL)
                    }
                }
            default:
                showErrorWithRetry(providerError.localizedDescription) {
                    await self.parseResume(from: resumeURL)
                }
            }
        } catch {
            isLoading = false
            let msg = error.localizedDescription
            let resumeURL = url
            if msg.contains("Could not connect") || msg.contains("Connection refused") {
                showErrorWithRetry("Could not connect to \(settings.aiProvider.rawValue). Check your internet connection and try again.") {
                    await self.parseResume(from: resumeURL)
                }
            } else {
                showErrorWithRetry(msg) { await self.parseResume(from: resumeURL) }
            }
        }
    }
    
    // MARK: - Contact Search (delegates to ContactManager)
    
    func searchContacts() async {
        guard let strategy = searchStrategy else { return }
        guard !isSearching else { return }
        
        isSearching = true
        isLoading = true
        loadingMessage = "Searching for contacts via \(settings.searchProvider.rawValue)..."
        canRetry = false
        
        // Track search
        usageTracker.addApolloSearch()
        
        searchTask = Task {
            do {
                let result = try await contactManager.search(
                    strategy: strategy,
                    count: settings.contactCount,
                    provider: searchProvider,
                    enrichment: enrichmentProvider,
                    existingContacts: contacts,
                    onProgress: { [weak self] msg in self?.loadingMessage = msg }
                )
                
                // Score relevance if we have a resume
                if let resume = resumeProfile {
                    contacts = contactManager.scoreRelevance(contacts: result.contacts, resume: resume)
                } else {
                    contacts = result.contacts
                }
                
                contactManager.save(contacts)
                
                isSearching = false
                isLoading = false
                
                if result.contacts.isEmpty {
                    showError("No contacts found matching your search criteria.\n\nTry broadening your filters:\n• Add more target titles\n• Expand company size range\n• Add more locations\n\nOr use CSV Import / Manual Entry instead.")
                } else {
                    currentStep = .contacts
                    if result.dupesRemoved > 0 {
                        showCompletionNotice("Found \(result.newCount) contacts (\(result.dupesRemoved) duplicates removed)")
                    } else {
                        showCompletionNotice("Found \(result.newCount) contacts with verified emails")
                    }
                }
            } catch is CancellationError {
                isSearching = false
                isLoading = false
                showCompletionNotice("Search cancelled")
            } catch let providerError as ProviderError {
                isSearching = false
                isLoading = false
                switch providerError {
                case .notConfigured(let msg):
                    showErrorWithRetry(msg) { await self.searchContacts() }
                case .invalidApiKey:
                    showErrorWithRetry("Invalid \(settings.searchProvider.rawValue) API key.\n\nGo to Settings → Providers to check your API key.") {
                        await self.searchContacts()
                    }
                case .rateLimited(let msg):
                    showErrorWithRetry("\(settings.searchProvider.rawValue) rate limit reached.\n\n\(msg)") {
                        await self.searchContacts()
                    }
                case .creditsExhausted:
                    showError("\(settings.searchProvider.rawValue) credits exhausted.\n\nUpgrade your plan or use CSV import / Manual entry instead.")
                default:
                    showErrorWithRetry(providerError.localizedDescription) { await self.searchContacts() }
                }
            } catch {
                isSearching = false
                isLoading = false
                showErrorWithRetry(error.localizedDescription) { await self.searchContacts() }
            }
        }
    }
    
    func cancelSearch() {
        searchTask?.cancel()
        searchTask = nil
    }
    
    // MARK: - CSV Import (delegates to ContactManager)
    
    func importCSV(from url: URL) {
        do {
            let result = try contactManager.importCSV(from: url, existingContacts: contacts, csvImporter: csvImporter)
            contacts = result.contacts
            showCompletionNotice("Imported \(result.importedCount) contacts from CSV")
        } catch {
            showError(error.localizedDescription)
        }
    }
    
    // MARK: - Manual Add (delegates to ContactManager)
    
    func addManualContact(_ contact: Contact) {
        contacts = contactManager.addManual(contact, existingContacts: contacts)
    }
    
    // MARK: - Generate Drafts (delegates to DraftManager)
    
    func generateDrafts() async {
        guard let profile = resumeProfile else { return }
        guard !isGenerating else { return }
        
        let selectedContacts = contacts.filter { $0.isSelected && !$0.email.isEmpty }
        guard !selectedContacts.isEmpty else {
            showError("No contacts selected for outreach.\n\nGo back to Contacts and select at least one contact with a valid email address.")
            return
        }
        
        // Check if all contacts already have drafts
        let existingContactIds = Set(drafts.filter { $0.status != .failed }.map { $0.contactId })
        let needsDrafts = selectedContacts.filter { !existingContactIds.contains($0.id) }
        if needsDrafts.isEmpty {
            currentStep = .drafts
            return
        }
        
        isGenerating = true
        isLoading = true
        canRetry = false
        
        draftManager.generateDrafts(
            selectedContacts: selectedContacts,
            existingDrafts: drafts,
            resume: profile,
            ai: aiProvider,
            emailWriter: emailWriter,
            customInstructions: settings.customPromptInstructions,
            sampleEmails: settings.sampleEmails,
            aiProviderType: settings.aiProvider,
            onProgress: { [weak self] msg in
                self?.loadingMessage = msg
            },
            onDraftUpdate: { [weak self] updatedDrafts in
                self?.drafts = updatedDrafts
                if self?.currentStep != .drafts {
                    self?.currentStep = .drafts
                }
            },
            onComplete: { [weak self] total, failureCount, passedQuality in
                guard let self = self else { return }
                self.isGenerating = false
                self.isLoading = false
                
                if total == 0 {
                    // All contacts already had drafts — just navigate
                    return
                }
                
                if failureCount == total {
                    self.showErrorWithRetry("All \(total) emails failed to generate.\n\nCheck your \(self.settings.aiProvider.rawValue) API key and connection, then try again.") {
                        await self.generateDrafts()
                    }
                } else if failureCount > 0 {
                    let successCount = total - failureCount
                    self.showCompletionNotice("Generated \(successCount)/\(total) drafts. \(failureCount) failed. \(passedQuality) passed quality checks.")
                    if self.currentStep != .drafts { self.currentStep = .drafts }
                } else {
                    self.showCompletionNotice("Generated \(total) drafts. \(passedQuality)/\(total) passed quality checks.")
                    if self.currentStep != .drafts { self.currentStep = .drafts }
                }
            }
        )
    }
    
    func cancelGeneration() {
        draftManager.cancelGeneration()
    }
    
    /// Clear all existing drafts and regenerate from scratch for all selected contacts
    func generateDraftsFromScratch() async {
        drafts.removeAll()
        await generateDrafts()
    }
    
    // MARK: - Campaign Sending (delegates to SendEngine)
    
    func startCampaign() {
        guard campaignStatus != .running else { return }
        
        campaignStatus = .running
        sentCount = 0
        failedCount = 0
        
        let approvedDrafts = drafts.filter { $0.status == .approved }
        campaignTotal = approvedDrafts.count
        guard !approvedDrafts.isEmpty else {
            showError("No approved emails to send.\n\nGo back to Compose and approve at least one email draft.")
            campaignStatus = .idle
            return
        }
        
        postSystemNotification(title: "Campaign Started", body: "Sending \(approvedDrafts.count) emails...")
        
        sendEngine.startCampaign(
            drafts: drafts,
            sender: emailSender,
            settings: settings,
            resumeFileURL: resumeFileURL,
            onStatusChange: { [weak self] status in
                self?.campaignStatus = status
            },
            onSent: { [weak self] draftId, smtpResponse in
                guard let self = self else { return }
                self.sentCount += 1
                if let idx = self.drafts.firstIndex(where: { $0.id == draftId }) {
                    self.drafts[idx].status = .sent
                }
                self.sendRecords.append(SendRecord(
                    draftId: draftId,
                    recipientEmail: self.drafts.first(where: { $0.id == draftId })?.recipientEmail ?? "",
                    recipientName: self.drafts.first(where: { $0.id == draftId })?.recipientName ?? "",
                    subject: self.drafts.first(where: { $0.id == draftId })?.subject ?? "",
                    sentAt: Date(),
                    status: .sent,
                    smtpResponse: smtpResponse
                ))
            },
            onFailed: { [weak self] draftId, errorMessage in
                guard let self = self else { return }
                self.failedCount += 1
                if let idx = self.drafts.firstIndex(where: { $0.id == draftId }) {
                    self.drafts[idx].status = .failed
                }
                self.sendRecords.append(SendRecord(
                    draftId: draftId,
                    recipientEmail: self.drafts.first(where: { $0.id == draftId })?.recipientEmail ?? "",
                    recipientName: self.drafts.first(where: { $0.id == draftId })?.recipientName ?? "",
                    subject: self.drafts.first(where: { $0.id == draftId })?.subject ?? "",
                    sentAt: Date(),
                    status: .failed,
                    errorMessage: errorMessage
                ))
            },
            onProgress: { [weak self] msg in
                self?.loadingMessage = msg
            },
            onPause: { [weak self] msg in
                self?.loadingMessage = msg
                self?.postSystemNotification(title: "Campaign Paused", body: msg)
            },
            onComplete: { [weak self] sent, failed in
                guard let self = self else { return }
                if self.campaignStatus == .complete {
                    self.postSystemNotification(
                        title: "Campaign Complete",
                        body: "\(sent) sent, \(failed) failed out of \(self.campaignTotal) emails."
                    )
                }
            }
        )
    }
    
    func pauseCampaign() {
        campaignStatus = .paused
        sendEngine.pause()
        log.info("Campaign PAUSED at \(sentCount)/\(campaignTotal)")
    }
    
    func resumeCampaign() {
        campaignStatus = .running
        sendEngine.resume()
        log.info("Campaign RESUMED")
    }
    
    func stopCampaign() {
        campaignStatus = .stopped
        sendEngine.stop()
        log.warn("Campaign STOPPED: \(sentCount) sent, \(failedCount) failed")
        postSystemNotification(title: "Campaign Stopped", body: "\(sentCount) sent, \(failedCount) failed before stop.")
    }
    
    // MARK: - Contact Persistence Shortcuts
    
    func saveContactsCache() { contactManager.save(contacts) }
    func clearContactsCache() {
        contactManager.clearCache()
        contacts = []
    }
    
    // MARK: - Error Helpers
    
    func showError(_ message: String) {
        errorMessage = message
        canRetry = false
        retryAction = nil
        showError = true
    }
    
    func showErrorWithRetry(_ message: String, retry: @escaping () async -> Void) {
        errorMessage = message
        canRetry = true
        retryAction = retry
        showError = true
    }
    
    func performRetry() {
        guard let action = retryAction else { return }
        showError = false
        Task { await action() }
    }
    
    // MARK: - Completion Banner
    
    func showCompletionNotice(_ message: String) {
        completionMessage = message
        withAnimation(.easeInOut(duration: 0.3)) { showCompletionBanner = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
            withAnimation(.easeInOut(duration: 0.3)) { self.showCompletionBanner = false }
        }
    }
    
    // MARK: - System Notifications
    
    private func requestNotificationPermission() {
        guard Bundle.main.bundleIdentifier != nil else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }
    
    func postSystemNotification(title: String, body: String) {
        guard Bundle.main.bundleIdentifier != nil else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
    
    // MARK: - Helpers
    
    /// Restore the resume attachment URL from a previous session.
    private func restoreCachedResumeURL() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let jobBusDir = appSupport.appendingPathComponent("JobBus", isDirectory: true)
        
        for ext in ["pdf", "docx", "doc"] {
            let url = jobBusDir.appendingPathComponent("resume_attachment.\(ext)")
            if FileManager.default.fileExists(atPath: url.path) {
                self.resumeFileURL = url
                return
            }
        }
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
