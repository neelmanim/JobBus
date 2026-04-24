import Foundation

// MARK: - Email Writer
class EmailWriter {
    
    func compose(contact: Contact, resume: ResumeProfile,
                 ai: AIProvider) async throws -> EmailDraft {
        let prompt = buildPrompt(contact: contact, resume: resume)
        let response = try await ai.generate(prompt: prompt)
        
        let (subject, body) = parseEmailResponse(response)
        let htmlBody = EmailTemplateBuilder.buildHTML(
            body: body,
            signature: EmailSignature(
                name: resume.name,
                title: resume.currentRole,
                linkedin: resume.linkedinUrl,
                phone: resume.phone
            )
        )
        
        var draft = EmailDraft(
            contactId: contact.id,
            recipientName: contact.fullName,
            recipientEmail: contact.email,
            recipientCompany: contact.company,
            recipientTitle: contact.title,
            recipientType: contact.recipientType,
            subject: subject,
            body: body,
            htmlBody: htmlBody,
            status: .pending
        )
        
        // Run quality check
        draft.qualityScore = QualityScorer.score(draft: draft, contact: contact)
        draft.status = draft.qualityScore.grade == .poor ? .review : .pending
        
        return draft
    }
    
    private func buildPrompt(contact: Contact, resume: ResumeProfile) -> String {
        return """
        Write a personalized cold outreach email from a job seeker to a professional.
        
        SENDER PROFILE:
        Name: \(resume.name)
        Current Role: \(resume.currentRole)
        Experience: \(resume.yearsExperience) years
        Key Skills: \(resume.skills.prefix(6).joined(separator: ", "))
        Top Achievements: \(resume.achievements.prefix(3).joined(separator: "; "))
        Context: \(resume.emailContext)
        
        RECIPIENT:
        Name: \(contact.firstName) \(contact.lastName)
        Title: \(contact.title)
        Company: \(contact.company)
        Type: \(contact.recipientType.label)
        Location: \(contact.location)
        
        INSTRUCTIONS FOR \(contact.recipientType.label.uppercased()):
        \(contact.recipientType.writingInstructions)
        
        ABSOLUTE RULES:
        1. Email must be under 150 words (body only, excluding signature)
        2. Use the recipient's FIRST NAME only (not full name, not "Dear")
        3. Sound like a real human who researched them, NOT a template
        4. Reference their company by name at least once
        5. Include one specific, quantifiable achievement from sender profile
        6. End with a soft, low-commitment call to action
        7. NO buzzwords: "passionate", "motivated", "synergy", "leverage"
        8. NO filler phrases: "I hope this finds you well", "I am writing to", "Please find attached"
        9. NO exclamation marks
        10. NO salary or compensation mentions
        11. Do NOT include a signature block — it will be added automatically
        
        FORMAT — Return EXACTLY like this (no markdown):
        SUBJECT: [Your subject line here]
        
        BODY:
        [Your email body here]
        """
    }
    
    private func parseEmailResponse(_ response: String) -> (subject: String, body: String) {
        let text = response.trimmingCharacters(in: .whitespacesAndNewlines)
        
        var subject = ""
        var body = ""
        
        // Extract subject
        if let subjectRange = text.range(of: "SUBJECT:", options: .caseInsensitive) {
            let afterSubject = text[subjectRange.upperBound...]
            if let bodyRange = afterSubject.range(of: "BODY:", options: .caseInsensitive) {
                subject = String(afterSubject[..<bodyRange.lowerBound])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                body = String(afterSubject[bodyRange.upperBound...])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            } else {
                subject = String(afterSubject.prefix(100))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        
        // Fallback: first line is subject, rest is body
        if subject.isEmpty {
            let lines = text.components(separatedBy: "\n").filter { !$0.isEmpty }
            subject = lines.first ?? "Introduction"
            body = lines.dropFirst().joined(separator: "\n")
        }
        
        // Clean up
        subject = subject.replacingOccurrences(of: "Subject:", with: "", options: .caseInsensitive)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        return (subject, body)
    }
}
