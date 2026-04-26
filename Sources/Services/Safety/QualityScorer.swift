import Foundation

// MARK: - Quality Scorer
/// Validates AI-generated email drafts across 11 quality dimensions.
/// Upgraded from 8-point to include hook, achievement count, and opening checks.
struct QualityScorer {
    
    private static let spamWords = [
        "act now", "guaranteed", "click here", "free money", "no obligation",
        "limited time", "congratulations", "winner", "urgent", "buy now",
        "dear sir", "dear madam", "dear sir/madam", "to whom it may concern",
        "best price", "order now", "special offer"
    ]
    
    private static let placeholderPatterns = [
        "{{", "}}", "[first_name]", "[last_name]", "[company]",
        "[Company]", "[Name]", "[COMPANY]", "[NAME]", "INSERT",
        "PLACEHOLDER", "[TODO]", "XXX"
    ]
    
    private static let weakPhrases = [
        "i hope this email finds you well",
        "i am writing to express my interest",
        "i would be a great fit",
        "please find attached my resume",
        "as per my resume",
        "i look forward to hearing from you",
        "i am a highly motivated professional"
    ]
    
    private static let genericOpenings = [
        "i came across your profile",
        "i noticed your profile",
        "i hope this finds you",
        "i am writing to",
        "i am reaching out",
        "i wanted to reach out"
    ]
    
    static func score(draft: EmailDraft, contact: Contact) -> EmailQualityScore {
        let bodyLower = draft.body.lowercased()
        let subjectLower = draft.subject.lowercased()
        let wordCount = draft.body.split(separator: " ").count
        
        return EmailQualityScore(
            nameMatch: checkNameMatch(draft: draft, contact: contact),
            companyMatch: checkCompanyMatch(draft: draft, contact: contact),
            lengthOK: wordCount >= 30 && wordCount <= 250,
            subjectLengthOK: draft.subject.count >= 5 && draft.subject.count <= 100,
            noPlaceholders: !placeholderPatterns.contains { bodyLower.contains($0.lowercased()) || subjectLower.contains($0.lowercased()) },
            noSpamWords: !spamWords.contains { bodyLower.contains($0) || subjectLower.contains($0) },
            hasCTA: detectCTA(bodyLower),
            toneMatch: !weakPhrases.contains { bodyLower.contains($0) },
            hookPresent: checkHookPresent(draft: draft, contact: contact),
            singleAchievement: checkSingleAchievement(bodyLower),
            noGenericOpening: !genericOpenings.contains { bodyLower.hasPrefix($0) || bodyLower.starts(with: $0) }
        )
    }
    
    private static func checkNameMatch(draft: EmailDraft, contact: Contact) -> Bool {
        if contact.firstName.isEmpty { return true } // Can't check
        let bodyLower = draft.body.lowercased()
        return bodyLower.contains(contact.firstName.lowercased())
    }
    
    private static func checkCompanyMatch(draft: EmailDraft, contact: Contact) -> Bool {
        if contact.company.isEmpty { return true } // Can't check
        let bodyLower = draft.body.lowercased()
        let subjectLower = draft.subject.lowercased()
        let companyLower = contact.company.lowercased()
        return bodyLower.contains(companyLower) || subjectLower.contains(companyLower)
    }
    
    private static func detectCTA(_ body: String) -> Bool {
        let ctaPatterns = [
            "would you be open", "would it make sense", "would a brief",
            "could we", "can we", "would you like", "interested in",
            "happy to chat", "open to", "connect", "conversation",
            "grab a coffee", "quick call", "15 minutes", "brief chat"
        ]
        return ctaPatterns.contains { body.contains($0) }
    }
    
    /// Check if first line is about the recipient (contains their name or company)
    private static func checkHookPresent(draft: EmailDraft, contact: Contact) -> Bool {
        let lines = draft.body.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard let firstLine = lines.first?.lowercased() else { return false }
        
        // First line should reference the recipient or their company
        let recipientName = contact.firstName.lowercased()
        let companyName = contact.company.lowercased()
        
        if !recipientName.isEmpty && firstLine.contains(recipientName) { return true }
        if !companyName.isEmpty && firstLine.contains(companyName) { return true }
        
        // Also pass if first word is NOT "I" (shows the email leads with the recipient)
        let firstWord = firstLine.components(separatedBy: " ").first ?? ""
        return firstWord != "i"
    }
    
    /// Check that the email doesn't contain more than one quantified achievement.
    /// Quantified = contains a number followed by a unit/descriptor (%, million, x, etc.)
    private static func checkSingleAchievement(_ body: String) -> Bool {
        let quantifiedPattern = #"\d+[%xX]|\d+\s*(million|billion|percent|users|customers|increase|decrease|improvement|reduction|growth)"#
        guard let regex = try? NSRegularExpression(pattern: quantifiedPattern, options: .caseInsensitive) else {
            return true // Can't check — assume OK
        }
        let matches = regex.numberOfMatches(in: body, range: NSRange(body.startIndex..., in: body))
        return matches <= 2 // Allow up to 2 numbers (one achievement can have 2 metrics)
    }
    
    // MARK: - Issues Report
    
    static func issues(for score: EmailQualityScore) -> [String] {
        var issues: [String] = []
        if !score.nameMatch { issues.append("Email may not address the recipient by name") }
        if !score.companyMatch { issues.append("Email doesn't mention the recipient's company") }
        if !score.lengthOK { issues.append("Email length is outside the optimal 30-250 word range") }
        if !score.subjectLengthOK { issues.append("Subject line is too short or too long") }
        if !score.noPlaceholders { issues.append("Email contains placeholder text that wasn't replaced") }
        if !score.noSpamWords { issues.append("Email contains spam trigger words") }
        if !score.hasCTA { issues.append("Email lacks a clear call-to-action") }
        if !score.toneMatch { issues.append("Email uses overused/generic phrases") }
        if !score.hookPresent { issues.append("Email doesn't start with a hook about the recipient") }
        if !score.singleAchievement { issues.append("Email contains too many achievements — keep it to one") }
        if !score.noGenericOpening { issues.append("Email starts with a generic opener (e.g., 'I came across your profile')") }
        return issues
    }
}

// MARK: - Duplicate Detector
class DuplicateDetector {
    static func removeDuplicates(from contacts: [Contact]) -> (unique: [Contact], duplicates: [Contact]) {
        var seenEmails = Set<String>()
        var seenNameCompany = Set<String>()
        var unique: [Contact] = []
        var duplicates: [Contact] = []
        
        for contact in contacts {
            if !contact.email.isEmpty {
                // Deduplicate by email
                let key = contact.email.lowercased()
                if seenEmails.contains(key) {
                    duplicates.append(contact)
                } else {
                    seenEmails.insert(key)
                    unique.append(contact)
                }
            } else {
                // No email — deduplicate by name + company
                let nameKey = "\(contact.firstName.lowercased())_\(contact.lastName.lowercased())_\(contact.company.lowercased())"
                if seenNameCompany.contains(nameKey) {
                    duplicates.append(contact)
                } else {
                    seenNameCompany.insert(nameKey)
                    unique.append(contact)
                }
            }
        }
        return (unique, duplicates)
    }
}
