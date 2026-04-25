import Foundation

// MARK: - Send Engine
/// Handles campaign execution: sending emails, duplicate prevention,
/// adaptive delays, anomaly detection, and campaign lifecycle.
/// Extracted from AppViewModel for testability and separation of concerns.
@MainActor
class SendEngine {
    
    private var sendTask: Task<Void, Never>?
    
    /// Tracks emails already sent in this session to prevent duplicates
    private var sentAddresses: Set<String> = []
    
    /// Consecutive failure counter for adaptive delay
    private var consecutiveFailures = 0
    
    /// Current delay between emails (adapts based on failure rate)
    private var currentDelay: Double = 0
    
    // MARK: - Campaign Execution
    
    /// Start sending approved drafts.
    /// Reports progress via callbacks; does not own any @Published state.
    func startCampaign(
        drafts: [EmailDraft],
        sender: SMTPEmailProvider,
        settings: AppSettings,
        resumeFileURL: URL?,
        onStatusChange: @escaping (CampaignStatus) -> Void,
        onSent: @escaping (UUID, String) -> Void,         // (draftId, smtpResponse)
        onFailed: @escaping (UUID, String) -> Void,        // (draftId, errorMessage)
        onProgress: @escaping (String) -> Void,
        onPause: @escaping (String) -> Void,
        onComplete: @escaping (Int, Int) -> Void            // (sent, failed)
    ) {
        let approvedDrafts = drafts.filter { $0.status == .approved }
        guard !approvedDrafts.isEmpty else {
            log.warn("Campaign aborted: no approved drafts")
            return
        }
        
        // Reset session state
        sentAddresses.removeAll()
        consecutiveFailures = 0
        currentDelay = settings.delaySeconds
        
        var sentCount = 0
        var failedCount = 0
        var status: CampaignStatus = .running
        
        log.section("CAMPAIGN START")
        log.info("Total to send: \(approvedDrafts.count)")
        log.info("SMTP: \(settings.smtpEmail) → \(settings.sandboxMode ? "SANDBOX (localhost:\(settings.sandboxPort))" : "LIVE")")
        log.info("Attachment: \(resumeFileURL?.lastPathComponent ?? "none")")
        log.info("Base delay: \(Int(settings.delaySeconds))s between emails")
        
        sendTask = Task {
            for (index, draft) in approvedDrafts.enumerated() {
                // Check pause/stop
                while status == .paused {
                    try? await Task.sleep(for: .seconds(1))
                }
                if status == .stopped || Task.isCancelled { break }
                
                // Business hours check
                if settings.businessHoursOnly {
                    await waitForBusinessHours(settings: settings, onProgress: onProgress)
                }
                
                // Daily limit check
                if sentCount >= settings.maxPerDay {
                    status = .paused
                    onStatusChange(.paused)
                    onPause("Daily limit reached (\(settings.maxPerDay)). Will resume tomorrow.")
                    break
                }
                
                // First-3 hold: pause after sending 3 so user can verify
                if index == 3 && sentCount == 3 {
                    status = .paused
                    onStatusChange(.paused)
                    onPause("Sent 3 emails. Check your Sent folder — do they look right? Resume when ready.")
                    while status == .paused {
                        try? await Task.sleep(for: .seconds(1))
                    }
                    if status == .stopped { break }
                }
                
                // Duplicate prevention: skip if we already sent to this address
                let emailLower = draft.recipientEmail.lowercased()
                if sentAddresses.contains(emailLower) {
                    log.warn("SKIPPED (duplicate): \(draft.recipientName) <\(draft.recipientEmail)>")
                    continue
                }
                
                // Determine attachment: based on draft's shouldAttachResume flag
                let attachmentURL = draft.shouldAttachResume ? resumeFileURL : nil
                let attachmentInfo = attachmentURL != nil ? " 📎" : ""
                onProgress("Sending \(sentCount + 1)/\(approvedDrafts.count) — \(draft.recipientName)\(attachmentInfo)...")
                
                // Send
                let result = try? await sender.send(
                    to: draft.recipientEmail,
                    toName: draft.recipientName,
                    from: settings.smtpEmail,
                    fromName: settings.smtpDisplayName,
                    subject: draft.subject,
                    textBody: draft.body,
                    htmlBody: draft.htmlBody,
                    attachmentURL: attachmentURL
                )
                
                if result?.success == true {
                    sentCount += 1
                    sentAddresses.insert(emailLower)
                    consecutiveFailures = 0
                    // Reset delay after 3 consecutive successes
                    if currentDelay > settings.delaySeconds {
                        currentDelay = settings.delaySeconds
                        log.info("Adaptive delay reset to base: \(Int(currentDelay))s")
                    }
                    log.info("✅ SENT \(sentCount)/\(approvedDrafts.count): \(draft.recipientName) <\(draft.recipientEmail)> — \"\(draft.subject)\"\(attachmentInfo)")
                    onSent(draft.id, result?.smtpResponse ?? "250 OK")
                } else {
                    failedCount += 1
                    consecutiveFailures += 1
                    
                    // Adaptive delay: increase by 50% per failure
                    currentDelay = min(currentDelay * 1.5, 120)
                    log.info("Adaptive delay increased to \(Int(currentDelay))s (consecutive failures: \(consecutiveFailures))")
                    
                    log.error("❌ FAILED \(failedCount): \(draft.recipientName) <\(draft.recipientEmail)> — \(result?.errorMessage ?? "unknown error")")
                    onFailed(draft.id, result?.errorMessage ?? "unknown error")
                    
                    // Anomaly detection: >20% failure → auto-pause
                    let total = sentCount + failedCount
                    if total >= 5 && Double(failedCount) / Double(total) > 0.2 {
                        status = .paused
                        onStatusChange(.paused)
                        onPause("High failure rate detected (\(failedCount)/\(total) failed). Paused for review.")
                    }
                }
                
                // Delay between emails (adaptive)
                if status == .running {
                    try? await Task.sleep(for: .seconds(currentDelay))
                }
            }
            
            if status == .running {
                status = .complete
                log.section("CAMPAIGN COMPLETE")
                log.info("Sent: \(sentCount), Failed: \(failedCount), Total: \(approvedDrafts.count)")
                onStatusChange(.complete)
            }
            
            onComplete(sentCount, failedCount)
        }
    }
    
    func pause() {
        log.info("Campaign PAUSED")
    }
    
    func resume() {
        log.info("Campaign RESUMED")
    }
    
    func stop() {
        sendTask?.cancel()
        log.warn("Campaign STOPPED")
    }
    
    // MARK: - Helpers
    
    private func waitForBusinessHours(settings: AppSettings, onProgress: @escaping (String) -> Void) async {
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: Date())
        if hour < settings.businessHoursStart || hour >= settings.businessHoursEnd {
            let nextStart = calendar.nextDate(
                after: Date(),
                matching: DateComponents(hour: settings.businessHoursStart),
                matchingPolicy: .nextTime
            )!
            let waitTime = nextStart.timeIntervalSince(Date())
            onProgress("Waiting for business hours (\(settings.businessHoursStart):00)...")
            try? await Task.sleep(for: .seconds(max(1, waitTime)))
        }
    }
}
