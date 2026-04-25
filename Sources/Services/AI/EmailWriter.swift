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
        let companyInfo: String
        if contact.company.isEmpty {
            companyInfo = "(Company unknown — do NOT use placeholders like [Company Name]. Instead, reference their role or industry.)"
        } else {
            companyInfo = contact.company
        }
        
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
        Company: \(companyInfo)
        Type: \(contact.recipientType.label)
        Location: \(contact.location)
        
        INSTRUCTIONS FOR \(contact.recipientType.label.uppercased()):
        \(contact.recipientType.writingInstructions)
        
        ABSOLUTE RULES:
        1. Email must be under 150 words (body only, excluding signature)
        2. Use the recipient's FIRST NAME only (not full name, not "Dear")
        3. Sound like a real human who researched them, NOT a template
        4. If company name is provided, reference it by name at least once
        5. Include one specific, quantifiable achievement from sender profile
        6. End with a soft, low-commitment call to action
        7. NO buzzwords: "passionate", "motivated", "synergy", "leverage"
        8. NO filler phrases: "I hope this finds you well", "I am writing to", "Please find attached"
        9. NO exclamation marks
        10. NO salary or compensation mentions
        11. Do NOT include a signature block — it will be added automatically
        12. NEVER use square-bracket placeholders like [Company Name], [Your Name], [Position] — use the actual values provided above
        
        FORMAT — Return EXACTLY like this (no markdown, no extra text):
        SUBJECT: [Your subject line here]
        
        BODY:
        [Your email body here]
        """
    }
    
    private func parseEmailResponse(_ response: String) -> (subject: String, body: String) {
        let text = response.trimmingCharacters(in: .whitespacesAndNewlines)
        
        var subject = ""
        var body = ""
        
        // Strategy 1: Look for SUBJECT: ... BODY: markers (case-insensitive)
        if let subjectRange = text.range(of: "SUBJECT:", options: .caseInsensitive) ??
           text.range(of: "Subject:", options: .caseInsensitive) ??
           text.range(of: "**Subject:**", options: .caseInsensitive) {
            let afterSubject = text[subjectRange.upperBound...]
            
            if let bodyRange = afterSubject.range(of: "BODY:", options: .caseInsensitive) ??
               afterSubject.range(of: "Body:", options: .caseInsensitive) ??
               afterSubject.range(of: "**Body:**", options: .caseInsensitive) {
                subject = String(afterSubject[..<bodyRange.lowerBound])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                body = String(afterSubject[bodyRange.upperBound...])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            } else {
                // Has SUBJECT but no BODY marker — subject is first line, rest is body
                let subjectLines = String(afterSubject).components(separatedBy: "\n")
                subject = subjectLines.first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                body = subjectLines.dropFirst().joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        
        // Strategy 2: No markers found — use first line as subject, rest as body
        if subject.isEmpty && body.isEmpty {
            let lines = text.components(separatedBy: "\n")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            
            if lines.count >= 2 {
                subject = lines[0]
                body = lines.dropFirst().joined(separator: "\n")
            } else if lines.count == 1 {
                // Single block of text — try to make the best of it
                subject = "Introduction"
                body = lines[0]
            }
        }
        
        // Strategy 3: If body is still empty but we have text, use ALL text as body
        if body.isEmpty && text.count > 30 {
            body = text
            if subject.isEmpty {
                subject = "Introduction"
            }
        }
        
        // Clean up subject line
        subject = subject
            .replacingOccurrences(of: "Subject:", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "SUBJECT:", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "**", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Clean up body — remove leading "Body:" if accidentally included
        body = body
            .replacingOccurrences(of: "^Body:\\s*", with: "", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: "^BODY:\\s*", with: "", options: [.regularExpression, .caseInsensitive])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        return (subject, body)
    }
}
