import Foundation

// MARK: - Draft Manager
/// Handles email draft generation, quality validation, achievement rotation,
/// and progressive UI updates. Extracted from AppViewModel for testability.
@MainActor
class DraftManager {
    
    private var generateTask: Task<Void, Never>?
    
    /// Tracks which achievements have been used to enable round-robin rotation
    private(set) var usedAchievements: Set<String> = []
    
    // MARK: - Achievement Rotation
    
    /// Select the next achievement to use, round-robin style.
    /// Returns a different achievement each time until all are exhausted, then cycles.
    func nextAchievement(from achievements: [String]) -> String {
        guard !achievements.isEmpty else { return "" }
        
        // Find unused achievements
        let unused = achievements.filter { !usedAchievements.contains($0) }
        
        if let next = unused.first {
            usedAchievements.insert(next)
            return next
        }
        
        // All used — reset and start over (round-robin)
        usedAchievements.removeAll()
        let next = achievements[0]
        usedAchievements.insert(next)
        return next
    }
    
    /// Reset achievement tracking (e.g., new campaign)
    func resetAchievementTracking() {
        usedAchievements.removeAll()
    }
    
    // MARK: - Generate Drafts
    
    /// Generate email drafts for contacts that don't already have one.
    /// Uses progressive callbacks so the UI updates as each draft completes.
    func generateDrafts(
        selectedContacts: [Contact],
        existingDrafts: [EmailDraft],
        resume: ResumeProfile,
        ai: AIProvider,
        emailWriter: EmailWriter,
        customInstructions: String,
        aiProviderType: AIProviderType,
        onProgress: @escaping (String) -> Void,
        onDraftUpdate: @escaping ([EmailDraft]) -> Void,
        onComplete: @escaping (Int, Int, Int) -> Void  // (total, failures, passedQuality)
    ) {
        // Skip contacts that already have valid drafts
        let existingContactIds = Set(existingDrafts.filter { $0.status != .failed }.map { $0.contactId })
        let contactsNeedingDrafts = selectedContacts.filter { !existingContactIds.contains($0.id) }
        
        guard !contactsNeedingDrafts.isEmpty else {
            onComplete(0, 0, 0)
            return
        }
        
        var updatedDrafts = existingDrafts.filter { $0.status != .failed }
        var failureCount = 0
        let total = contactsNeedingDrafts.count
        
        // Reset achievement tracking for new generation batch
        resetAchievementTracking()
        
        generateTask = Task {
            for (index, contact) in contactsNeedingDrafts.enumerated() {
                if Task.isCancelled { break }
                
                onProgress("Composing email \(index + 1)/\(total) — \(contact.fullName) @ \(contact.company)...")
                log.info("Generating draft \(index + 1)/\(total): \(contact.fullName) <\(contact.email)> @ \(contact.company)")
                
                // Pick achievement for this email
                let achievement = nextAchievement(from: resume.achievements)
                
                do {
                    var draft = try await emailWriter.compose(
                        contact: contact,
                        resume: resume,
                        ai: ai,
                        customInstructions: customInstructions,
                        selectedAchievement: achievement
                    )
                    
                    // Set resume attachment based on contact type
                    draft.shouldAttachResume = contact.shouldAttachResume
                    draft.usedAchievement = achievement
                    
                    // Validate AI output
                    let result = validateDraft(&draft, contact: contact, failureCount: &failureCount)
                    updatedDrafts.append(result)
                    onDraftUpdate(updatedDrafts)
                    
                } catch is CancellationError {
                    break
                } catch {
                    failureCount += 1
                    var failedDraft = EmailDraft(contactId: contact.id)
                    failedDraft.status = .failed
                    failedDraft.recipientName = contact.fullName
                    failedDraft.recipientEmail = contact.email
                    failedDraft.recipientCompany = contact.company
                    failedDraft.subject = "(Generation failed)"
                    failedDraft.body = "Error: \(error.localizedDescription)\n\nUse the Regenerate button to try again."
                    updatedDrafts.append(failedDraft)
                    onDraftUpdate(updatedDrafts)
                }
                
                // Provider-specific rate limit delay
                let delayMs: Int
                switch aiProviderType {
                case .groq: delayMs = 2000
                case .gemini: delayMs = 500
                case .ollama: delayMs = 200
                }
                try? await Task.sleep(for: .milliseconds(delayMs))
            }
            
            let passedQuality = updatedDrafts.filter { $0.qualityScore.grade != .poor && $0.status != .failed }.count
            onComplete(total, failureCount, passedQuality)
        }
    }
    
    func cancelGeneration() {
        generateTask?.cancel()
        generateTask = nil
    }
    
    // MARK: - Validation Pipeline
    
    /// Validate an AI-generated draft: check for empty content, placeholders, and quality.
    private func validateDraft(_ draft: inout EmailDraft, contact: Contact, failureCount: inout Int) -> EmailDraft {
        let bodyText = draft.body.trimmingCharacters(in: .whitespacesAndNewlines)
        let placeholders = ["[Company Name]", "[Your Name]", "[Position]", "[Role]", "[Name]", "[Title]", "[Company]"]
        let subjectHits = placeholders.filter { draft.subject.contains($0) }.count
        let bodyHits = placeholders.filter { bodyText.contains($0) }.count
        
        if bodyText.isEmpty || bodyText.count < 30 {
            // Empty response
            var failedDraft = EmailDraft(contactId: contact.id)
            failedDraft.status = .failed
            failedDraft.recipientName = contact.fullName
            failedDraft.recipientEmail = contact.email
            failedDraft.recipientCompany = contact.company
            failedDraft.subject = "(Incomplete — AI returned empty response)"
            failedDraft.body = "The AI returned an empty or too-short response (\(bodyText.count) chars).\n\nSubject parsed: \"\(draft.subject)\"\nBody parsed: \"\(bodyText.prefix(100))\"\n\nTap Regenerate to try again, or Edit to write manually."
            failureCount += 1
            log.warn("Draft FAILED (empty): \(contact.fullName) — body=\(bodyText.count) chars, subject=\"\(draft.subject)\"")
            return failedDraft
        } else if (subjectHits + bodyHits) >= 2 {
            // Multiple placeholders — template response
            var failedDraft = EmailDraft(contactId: contact.id)
            failedDraft.status = .failed
            failedDraft.recipientName = contact.fullName
            failedDraft.recipientEmail = contact.email
            failedDraft.recipientCompany = contact.company
            failedDraft.subject = "(Incomplete — AI returned placeholders)"
            failedDraft.body = "The AI returned a template with \(subjectHits + bodyHits) placeholders.\n\nTap Regenerate to try again, or Edit to write manually."
            failureCount += 1
            return failedDraft
        } else {
            // Valid — clean any stray single placeholder
            if subjectHits == 1 || bodyHits == 1 {
                let fill = contact.company.isEmpty ? "your team" : contact.company
                for p in placeholders {
                    draft.subject = draft.subject.replacingOccurrences(of: p, with: fill)
                    draft.body = draft.body.replacingOccurrences(of: p, with: fill)
                }
            }
            log.info("Draft OK: \(contact.fullName) — subject=\"\(draft.subject)\", body=\(bodyText.count) chars, quality=\(draft.qualityScore.grade)")
            return draft
        }
    }
}
