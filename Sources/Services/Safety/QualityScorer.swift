import Foundation

// MARK: - Quality Scorer
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
            toneMatch: !weakPhrases.contains { bodyLower.contains($0) }
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
        return issues
    }
}

// MARK: - Duplicate Detector
class DuplicateDetector {
    static func removeDuplicates(from contacts: [Contact]) -> (unique: [Contact], duplicates: [Contact]) {
        var seen = Set<String>()
        var unique: [Contact] = []
        var duplicates: [Contact] = []
        
        for contact in contacts {
            let key = contact.email.lowercased()
            if key.isEmpty { unique.append(contact); continue }
            if seen.contains(key) {
                duplicates.append(contact)
            } else {
                seen.insert(key)
                unique.append(contact)
            }
        }
        return (unique, duplicates)
    }
}
