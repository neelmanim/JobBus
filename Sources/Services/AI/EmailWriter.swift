import Foundation

// MARK: - Email Writer
/// Generates personalized cold outreach emails using the Hook → Context → Credibility → CTA structure.
/// Each email uses a single, rotated achievement to prevent resume-dumping.
class EmailWriter {
    
    func compose(contact: Contact, resume: ResumeProfile,
                 ai: AIProvider, customInstructions: String = "",
                 selectedAchievement: String = "",
                 sampleEmails: [String] = []) async throws -> EmailDraft {
        let prompt = buildPrompt(contact: contact, resume: resume,
                                 customInstructions: customInstructions,
                                 selectedAchievement: selectedAchievement,
                                 sampleEmails: sampleEmails)
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
            status: .pending,
            usedAchievement: selectedAchievement.isEmpty ? nil : selectedAchievement,
            shouldAttachResume: contact.shouldAttachResume
        )
        
        // Run quality check
        draft.qualityScore = QualityScorer.score(draft: draft, contact: contact)
        draft.status = draft.qualityScore.grade == .poor ? .review : .pending
        
        return draft
    }
    
    private func buildPrompt(contact: Contact, resume: ResumeProfile,
                             customInstructions: String = "",
                             selectedAchievement: String = "",
                             sampleEmails: [String] = []) -> String {
        let companyInfo: String
        if contact.company.isEmpty {
            companyInfo = "(Company unknown — do NOT use placeholders like [Company Name]. Instead, reference their role or industry.)"
        } else {
            companyInfo = contact.company
        }
        
        let customBlock: String
        if !customInstructions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            customBlock = """
            
            ADDITIONAL INSTRUCTIONS FROM USER:
            \(customInstructions)
            
            """
        } else {
            customBlock = ""
        }
        
        // Select achievement — use the rotated one, or pick the first
        let achievement = selectedAchievement.isEmpty
            ? (resume.achievements.first ?? "Experienced professional")
            : selectedAchievement
        
        // Pick 3 most relevant skills (not all 6)
        let relevantSkills = resume.skills.prefix(3).joined(separator: ", ")
        
        return """
        Write a personalized cold outreach email from a job seeker to a professional.
        
        MANDATORY EMAIL STRUCTURE — Follow this EXACTLY:
        
        1. HOOK (First 1-2 lines):
           - Start with something about the RECIPIENT — their company, role, or team
           - Ask a relevant question OR make an observation about their work
           - This line must contain "\(contact.firstName)" or "\(contact.company)"
           - NEVER start with "I" as the first word
        
        2. CONTEXT (1-2 lines):
           - Why you're reaching out — connect YOUR experience to THEIR role
           - Be specific about what drew you to them
        
        3. CREDIBILITY (1-2 lines):
           - Use this ONE specific achievement: "\(achievement)"
           - Present it naturally, not as a resume bullet point
           - Do NOT add any other achievements or metrics
        
        4. CTA (1 line):
           - Light, low-commitment ask
           - A question, not a demand
        
        SENDER PROFILE:
        Name: \(resume.name)
        Current Role: \(resume.currentRole)
        Experience: \(resume.yearsExperience) years
        Key Skills: \(relevantSkills)
        Context: \(resume.emailContext)
        
        RECIPIENT:
        Name: \(contact.firstName) \(contact.lastName)
        Title: \(contact.title)
        Company: \(companyInfo)
        Type: \(contact.recipientType.label)
        Location: \(contact.location)
        
        TONE INSTRUCTIONS FOR \(contact.recipientType.label.uppercased()):
        \(contact.recipientType.writingInstructions)
        \(buildStyleBlock(sampleEmails: sampleEmails))\(customBlock)
        ABSOLUTE RULES:
        1. Total body MUST be under 120 words (excluding signature)
        2. Use the recipient's FIRST NAME only (not full name, not "Dear")
        3. Sound like a real human, NOT a template
        4. If company name is provided, reference it naturally at least once
        5. Use ONLY the ONE achievement provided above — no others
        6. End with a soft, low-commitment call to action
        7. NO buzzwords: "passionate", "motivated", "synergy", "leverage", "dynamic"
        8. NO filler: "I hope this finds you well", "I am writing to", "Please find attached"
        9. NO "I came across your profile" or "I noticed your profile"
        10. NO exclamation marks
        11. NO salary or compensation mentions
        12. Do NOT include a signature block — it will be added automatically
        13. NEVER use square-bracket placeholders like [Company Name], [Your Name] — use actual values
        14. First word of the email must NOT be "I"
        15. Each paragraph must be 3 lines or fewer
        16. Vary sentence length — mix short punchy sentences with longer ones
        
        FORMAT — Return EXACTLY like this (no markdown, no extra text):
        SUBJECT: [Your subject line here — 5-8 words, no clickbait]
        
        BODY:
        [Your email body here]
        """
    }
    
    /// Builds the writing style reference block from user-provided email samples.
    private func buildStyleBlock(sampleEmails: [String]) -> String {
        let validSamples = sampleEmails
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        
        guard !validSamples.isEmpty else { return "" }
        
        var block = """
        
        WRITING STYLE REFERENCE:
        The user has provided sample emails they've written. You MUST match their writing style:
        - Match their sentence length patterns (short/punchy vs. flowing)
        - Match their greeting style (casual "Hey" vs. semi-formal "Hi" vs. formal salutation)
        - Match their level of formality and directness
        - Match their paragraph structure (short paragraphs vs. dense blocks)
        - Match how they transition between topics
        - Do NOT copy their content — only mimic the style, rhythm, and tone
        
        """
        
        for (i, sample) in validSamples.enumerated() {
            block += "--- SAMPLE EMAIL \(i + 1) ---\n\(sample)\n--- END SAMPLE \(i + 1) ---\n\n"
        }
        
        return block
    }
    
    func parseEmailResponse(_ response: String) -> (subject: String, body: String) {
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
