import SwiftUI
import UserNotifications
import Combine

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
    
    // Task handles for cancellation
    private var generateTask: Task<Void, Never>?
    private var searchTask: Task<Void, Never>?
    
    // Forward nested ObservableObject changes so SwiftUI sees them (fixes slider)
    private var settingsSink: AnyCancellable?
    private var sendTask: Task<Void, Never>?
    
    init() {
        self.settings = AppSettings.load()
        
        // Forward settings changes to our objectWillChange so SwiftUI picks them up
        settingsSink = settings.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
        
        // Load cached contacts from previous session
        loadCachedContacts()
        
        // Restore resume attachment URL if a cached copy exists
        restoreCachedResumeURL()
        
        requestNotificationPermission()
        
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
            // (file picker URLs are security-scoped and expire after the session)
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
                // Fallback: use original URL (may work for non-sandboxed access)
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
    
    // MARK: - Contact Search
    
    func searchContacts() async {
        guard let strategy = searchStrategy else { return }
        guard !isSearching else { return }
        
        isSearching = true
        isLoading = true
        loadingMessage = "Searching for contacts via \(settings.searchProvider.rawValue)..."
        canRetry = false
        log.section("CONTACT SEARCH")
        log.info("Provider: \(settings.searchProvider.rawValue), Count: \(settings.contactCount)")
        
        searchTask = Task {
            do {
                let found = try await searchProvider.search(strategy: strategy, count: settings.contactCount)
                
                // Check cancellation
                try Task.checkCancellation()
                
                loadingMessage = "Enriching contacts to get emails..."
                let enriched = try await enrichmentProvider.enrichBatch(contacts: found) { done, total in
                    Task { @MainActor in
                        self.loadingMessage = "Enriching contacts: \(done)/\(total)..."
                    }
                }
                
                // Check cancellation
                try Task.checkCancellation()
                
                // Add to contacts pool (dedup with existing)
                let allContacts = contacts + enriched
                let (unique, dupes) = DuplicateDetector.removeDuplicates(from: allContacts)
                contacts = unique
                
                // Cache contacts to disk for reuse
                self.saveContactsCache()
                log.info("Contacts found: \(enriched.count), unique: \(unique.count), dupes removed: \(dupes.count)")
                
                isSearching = false
                isLoading = false
                
                if unique.isEmpty {
                    showError("No contacts found matching your search criteria.\n\nTry broadening your filters:\n• Add more target titles\n• Expand company size range\n• Add more locations\n\nOr use CSV Import / Manual Entry instead.")
                } else {
                    currentStep = .contacts
                    if dupes.count > 0 {
                        showCompletionNotice("Found \(enriched.count) contacts (\(dupes.count) duplicates removed)")
                    } else {
                        showCompletionNotice("Found \(enriched.count) contacts with verified emails")
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
    
    // MARK: - CSV Import
    
    func importCSV(from url: URL) {
        do {
            let result = try csvImporter.parseCSV(from: url)
            let allContacts = contacts + result.contacts
            let (unique, _) = DuplicateDetector.removeDuplicates(from: allContacts)
            contacts = unique
            showCompletionNotice("Imported \(result.contacts.count) contacts from CSV")
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
        guard !isGenerating else { return }
        
        let selectedContacts = contacts.filter { $0.isSelected && !$0.email.isEmpty }
        guard !selectedContacts.isEmpty else {
            showError("No contacts selected for outreach.\n\nGo back to Contacts and select at least one contact with a valid email address.")
            return
        }
        
        // ── Token conservation: skip contacts that already have valid drafts ──
        let existingContactIds = Set(drafts.filter { $0.status != .failed }.map { $0.contactId })
        let contactsNeedingDrafts = selectedContacts.filter { !existingContactIds.contains($0.id) }
        
        // If all contacts already have drafts, just navigate — no AI calls needed
        if contactsNeedingDrafts.isEmpty {
            currentStep = .drafts
            return
        }
        
        isGenerating = true
        isLoading = true
        canRetry = false
        
        // Preserve existing valid drafts, only regenerate for new/failed contacts
        var updatedDrafts = drafts.filter { $0.status != .failed }
        var failureCount = 0
        let total = contactsNeedingDrafts.count
        
        generateTask = Task {
            for (index, contact) in contactsNeedingDrafts.enumerated() {
                // Check cancellation
                if Task.isCancelled { break }
                
                loadingMessage = "Composing email \(index + 1)/\(total) — \(contact.fullName) @ \(contact.company)..."
                log.info("Generating draft \(index + 1)/\(total): \(contact.fullName) <\(contact.email)> @ \(contact.company)")
                
                do {
                    var draft = try await emailWriter.compose(contact: contact, resume: profile, ai: aiProvider)
                    
                    // ── Validate AI output — catch truly empty/template responses ──
                    let bodyText = draft.body.trimmingCharacters(in: .whitespacesAndNewlines)
                    let placeholders = ["[Company Name]", "[Your Name]", "[Position]", "[Role]", "[Name]", "[Title]", "[Company]"]
                    let subjectHits = placeholders.filter { draft.subject.contains($0) }.count
                    let bodyHits = placeholders.filter { bodyText.contains($0) }.count
                    
                    if bodyText.isEmpty || bodyText.count < 30 {
                        // Truly empty — mark failed with diagnostic info
                        var failedDraft = EmailDraft(contactId: contact.id)
                        failedDraft.status = .failed
                        failedDraft.recipientName = contact.fullName
                        failedDraft.recipientEmail = contact.email
                        failedDraft.recipientCompany = contact.company
                        failedDraft.subject = "(Incomplete — AI returned empty response)"
                        failedDraft.body = "The AI returned an empty or too-short response (\(bodyText.count) chars).\n\nSubject parsed: \"\(draft.subject)\"\nBody parsed: \"\(bodyText.prefix(100))\"\n\nTap Regenerate to try again, or Edit to write manually."
                        updatedDrafts.append(failedDraft)
                        failureCount += 1
                        log.warn("Draft FAILED (empty): \(contact.fullName) — body=\(bodyText.count) chars, subject=\"\(draft.subject)\"")
                    } else if (subjectHits + bodyHits) >= 2 {
                        // Multiple placeholders — template response, reject
                        var failedDraft = EmailDraft(contactId: contact.id)
                        failedDraft.status = .failed
                        failedDraft.recipientName = contact.fullName
                        failedDraft.recipientEmail = contact.email
                        failedDraft.recipientCompany = contact.company
                        failedDraft.subject = "(Incomplete — AI returned placeholders)"
                        failedDraft.body = "The AI returned a template with \(subjectHits + bodyHits) placeholders.\n\nTap Regenerate to try again, or Edit to write manually."
                        updatedDrafts.append(failedDraft)
                        failureCount += 1
                    } else {
                        // Valid (or close enough) — clean any stray single placeholder
                        if subjectHits == 1 || bodyHits == 1 {
                            let fill = contact.company.isEmpty ? "your team" : contact.company
                            for p in placeholders {
                                draft.subject = draft.subject.replacingOccurrences(of: p, with: fill)
                                draft.body = draft.body.replacingOccurrences(of: p, with: fill)
                            }
                        }
                        updatedDrafts.append(draft)
                        log.info("Draft OK: \(contact.fullName) — subject=\"\(draft.subject)\", body=\(bodyText.count) chars, quality=\(draft.qualityScore.grade)")
                    }
                    
                    // Update drafts progressively so user sees them appear
                    drafts = updatedDrafts
                    
                    // Navigate to drafts step after first successful draft
                    if currentStep != .drafts {
                        currentStep = .drafts
                    }
                } catch is CancellationError {
                    break
                } catch {
                    failureCount += 1
                    // Create a failed draft entry so user can see what went wrong
                    var failedDraft = EmailDraft(contactId: contact.id)
                    failedDraft.status = .failed
                    failedDraft.recipientName = contact.fullName
                    failedDraft.recipientEmail = contact.email
                    failedDraft.recipientCompany = contact.company
                    failedDraft.subject = "(Generation failed)"
                    failedDraft.body = "Error: \(error.localizedDescription)\n\nUse the Regenerate button to try again."
                    updatedDrafts.append(failedDraft)
                    drafts = updatedDrafts
                }
                
                // Smart delay between AI calls — provider-specific to avoid rate limits
                let delayMs: Int
                switch self.settings.aiProvider {
                case .groq: delayMs = 2000    // Groq free tier: 30 RPM
                case .gemini: delayMs = 500   // Gemini: generous limits
                case .ollama: delayMs = 200   // Local: no limits
                }
                try? await Task.sleep(for: .milliseconds(delayMs))
            }
            
            isGenerating = false
            isLoading = false
            
            if Task.isCancelled {
                // Keep whatever we generated so far
                showCompletionNotice("Generation cancelled. \(updatedDrafts.count) drafts saved.")
            } else if failureCount == total {
                // All failed
                showErrorWithRetry("All \(total) emails failed to generate.\n\nCheck your \(settings.aiProvider.rawValue) API key and connection, then try again.") {
                    await self.generateDrafts()
                }
            } else if failureCount > 0 {
                // Partial failure
                let successCount = total - failureCount
                let passedQuality = updatedDrafts.filter { $0.qualityScore.grade != .poor && $0.status != .failed }.count
                showCompletionNotice("Generated \(successCount)/\(total) drafts. \(failureCount) failed. \(passedQuality) passed quality checks.")
                if currentStep != .drafts { currentStep = .drafts }
            } else {
                // All succeeded
                let passedQuality = updatedDrafts.filter { $0.qualityScore.grade != .poor }.count
                showCompletionNotice("Generated \(total) drafts. \(passedQuality)/\(total) passed quality checks.")
                if currentStep != .drafts { currentStep = .drafts }
            }
        }
    }
    
    func cancelGeneration() {
        generateTask?.cancel()
        generateTask = nil
    }
    
    // MARK: - Campaign Sending
    
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
            log.warn("Campaign aborted: no approved drafts")
            return
        }
        
        log.section("CAMPAIGN START")
        log.info("Total to send: \(approvedDrafts.count)")
        log.info("SMTP: \(settings.smtpEmail) → \(settings.sandboxMode ? "SANDBOX (localhost:\(settings.sandboxPort))" : "LIVE")")
        log.info("Attachment: \(resumeFileURL?.lastPathComponent ?? "none")")
        log.info("Delay: \(Int(settings.delaySeconds))s between emails")
        
        sendTask = Task {
            for (index, draft) in approvedDrafts.enumerated() {
                // Check pause/stop
                while campaignStatus == .paused {
                    try? await Task.sleep(for: .seconds(1))
                }
                if campaignStatus == .stopped || Task.isCancelled { break }
                
                // Business hours check
                if settings.businessHoursOnly {
                    await waitForBusinessHours()
                }
                
                // Daily limit check
                if sentCount >= settings.maxPerDay {
                    campaignStatus = .paused
                    loadingMessage = "Daily limit reached (\(settings.maxPerDay)). Will resume tomorrow."
                    postSystemNotification(title: "Campaign Paused", body: "Daily send limit of \(settings.maxPerDay) reached.")
                    break
                }
                
                // First-3 hold: pause after sending 3 so user can verify
                if index == 3 && sentCount == 3 {
                    campaignStatus = .paused
                    loadingMessage = "Sent 3 emails. Check your Sent folder — do they look right? Resume when ready."
                    postSystemNotification(title: "Campaign Paused", body: "Sent 3 test emails. Check your Sent folder and resume when ready.")
                    while campaignStatus == .paused {
                        try? await Task.sleep(for: .seconds(1))
                    }
                    if campaignStatus == .stopped { break }
                }
                
                let attachmentInfo = resumeFileURL != nil ? " 📎" : ""
                loadingMessage = "Sending \(sentCount + 1)/\(approvedDrafts.count) — \(draft.recipientName)\(attachmentInfo)..."
                
                // Send (with resume attached if available)
                let result = try? await emailSender.send(
                    to: draft.recipientEmail,
                    toName: draft.recipientName,
                    from: settings.smtpEmail,
                    fromName: settings.smtpDisplayName,
                    subject: draft.subject,
                    textBody: draft.body,
                    htmlBody: draft.htmlBody,
                    attachmentURL: resumeFileURL
                )
                
                if result?.success == true {
                    sentCount += 1
                    // Update draft status
                    if let draftIdx = drafts.firstIndex(where: { $0.id == draft.id }) {
                        drafts[draftIdx].status = .sent
                    }
                    log.info("✅ SENT \(sentCount)/\(approvedDrafts.count): \(draft.recipientName) <\(draft.recipientEmail)> — \"\(draft.subject)\"")
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
                    if let draftIdx = drafts.firstIndex(where: { $0.id == draft.id }) {
                        drafts[draftIdx].status = .failed
                    }
                    log.error("❌ FAILED \(failedCount): \(draft.recipientName) <\(draft.recipientEmail)> — \(result?.errorMessage ?? "unknown error")")
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
                        campaignStatus = .paused
                        loadingMessage = "High failure rate detected (\(failedCount)/\(total) failed). Paused for review."
                        postSystemNotification(title: "Campaign Paused", body: "High failure rate: \(failedCount)/\(total) emails failed.")
                    }
                }
                
                // Delay between emails
                if campaignStatus == .running {
                    try? await Task.sleep(for: .seconds(settings.delaySeconds))
                }
            }
            
            if campaignStatus == .running {
                campaignStatus = .complete
                log.section("CAMPAIGN COMPLETE")
                log.info("Sent: \(sentCount), Failed: \(failedCount), Total: \(approvedDrafts.count)")
                postSystemNotification(
                    title: "Campaign Complete",
                    body: "\(sentCount) sent, \(failedCount) failed out of \(approvedDrafts.count) emails."
                )
            }
        }
    }
    
    func pauseCampaign() { campaignStatus = .paused; log.info("Campaign PAUSED at \(sentCount)/\(campaignTotal)") }
    func resumeCampaign() { campaignStatus = .running; log.info("Campaign RESUMED") }
    func stopCampaign() {
        campaignStatus = .stopped
        sendTask?.cancel()
        log.warn("Campaign STOPPED: \(sentCount) sent, \(failedCount) failed")
        postSystemNotification(title: "Campaign Stopped", body: "\(sentCount) sent, \(failedCount) failed before stop.")
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
    
    private func postSystemNotification(title: String, body: String) {
        guard Bundle.main.bundleIdentifier != nil else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
    
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
    
    // MARK: - Contact Persistence
    
    private static var contactsCacheURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("JobBus", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("contacts_cache.json")
    }
    
    func saveContactsCache() {
        guard !contacts.isEmpty else { return }
        let url = Self.contactsCacheURL
        Task.detached(priority: .utility) { [contacts] in
            if let data = try? JSONEncoder().encode(contacts) {
                try? data.write(to: url, options: .atomic)
            }
        }
    }
    
    private func loadCachedContacts() {
        guard FileManager.default.fileExists(atPath: Self.contactsCacheURL.path),
              let data = try? Data(contentsOf: Self.contactsCacheURL),
              let cached = try? JSONDecoder().decode([Contact].self, from: data),
              !cached.isEmpty
        else { return }
        self.contacts = cached
    }
    
    func clearContactsCache() {
        try? FileManager.default.removeItem(at: Self.contactsCacheURL)
        contacts = []
    }
    
    /// Restore the resume attachment URL from a previous session.
    /// The resume is copied to Application Support on first parse,
    /// but resumeFileURL (@Published) is lost on app restart.
    private func restoreCachedResumeURL() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let jobBusDir = appSupport.appendingPathComponent("JobBus", isDirectory: true)
        
        // Check common resume extensions
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
