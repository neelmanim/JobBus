import Foundation

// MARK: - Resume Analyzer
class ResumeAnalyzer {
    
    func analyze(resumeText: String, ai: AIProvider) async throws -> ResumeProfile {
        let prompt = """
        You are analyzing a resume to create a job search outreach strategy.
        
        RESUME TEXT:
        \(resumeText.prefix(4000))
        
        Return ONLY a valid JSON object with these exact keys (no markdown, no explanation):
        {
            "name": "Full Name from resume",
            "current_role": "Most recent job title",
            "years_experience": 5,
            "skills": ["Skill1", "Skill2", "Skill3"],
            "industries": ["Industry1", "Industry2"],
            "achievements": ["Achievement 1 with numbers", "Achievement 2"],
            "education": "Degree, University",
            "email_context": "Brief 2-sentence summary of candidate for email personalization",
            "linkedin_url": "LinkedIn URL if found, empty string otherwise",
            "phone": "Phone if found, empty string otherwise"
        }
        
        Rules:
        - Extract REAL data from the resume, do not make up information
        - For skills, list specific technologies and tools (e.g., "Python", "React", "AWS")
        - For achievements, include quantifiable results where possible
        - For email_context, write how you'd describe this person to a recruiter in 2 sentences
        - Return ONLY the JSON, no other text
        """
        
        let response = try await ai.generate(prompt: prompt)
        return try parseResumeJSON(response, rawText: resumeText)
    }
    
    func generateStrategy(from profile: ResumeProfile, ai: AIProvider) async throws -> SearchStrategy {
        let prompt = """
        Based on this candidate profile, generate an optimal recruiter search strategy.
        
        CANDIDATE:
        Name: \(profile.name)
        Role: \(profile.currentRole)
        Experience: \(profile.yearsExperience) years
        Skills: \(profile.skills.joined(separator: ", "))
        Industries: \(profile.industries.joined(separator: ", "))
        
        Return ONLY a valid JSON object (no markdown):
        {
            "target_titles": ["Title1", "Title2", "Title3", "Title4", "Title5"],
            "target_seniorities": ["manager", "director", "vp", "c_suite"],
            "company_sizes": ["51,200", "201,1000"],
            "industries": ["Industry1", "Industry2"],
            "locations": ["United States"],
            "keywords": ["keyword1", "keyword2"]
        }
        
        Rules:
        - target_titles: 4-6 titles of people who would hire this candidate (recruiters, managers, VPs)
        - target_seniorities: Apollo seniority values (entry, senior, manager, director, vp, c_suite, owner)
        - company_sizes: Apollo ranges like "1,10", "11,50", "51,200", "201,1000", "1001,5000", "5001,10000"
        - industries: relevant industries based on candidate's background
        - locations: default to ["United States"] unless resume suggests otherwise
        - Return ONLY the JSON
        """
        
        let response = try await ai.generate(prompt: prompt)
        return try parseStrategyJSON(response)
    }
    
    // MARK: - JSON Parsing Helpers
    
    private func parseResumeJSON(_ response: String, rawText: String) throws -> ResumeProfile {
        let cleaned = extractJSON(from: response)
        guard let data = cleaned.data(using: .utf8),
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { throw ProviderError.parseError("AI returned invalid JSON for resume analysis") }
        
        return ResumeProfile(
            name: json["name"] as? String ?? "",
            currentRole: json["current_role"] as? String ?? "",
            yearsExperience: json["years_experience"] as? Int ?? 0,
            skills: json["skills"] as? [String] ?? [],
            industries: json["industries"] as? [String] ?? [],
            achievements: json["achievements"] as? [String] ?? [],
            education: json["education"] as? String ?? "",
            emailContext: json["email_context"] as? String ?? "",
            linkedinUrl: json["linkedin_url"] as? String ?? "",
            phone: json["phone"] as? String ?? "",
            rawText: rawText
        )
    }
    
    private func parseStrategyJSON(_ response: String) throws -> SearchStrategy {
        let cleaned = extractJSON(from: response)
        guard let data = cleaned.data(using: .utf8),
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { throw ProviderError.parseError("AI returned invalid JSON for strategy") }
        
        return SearchStrategy(
            targetTitles: json["target_titles"] as? [String] ?? [],
            targetSeniorities: json["target_seniorities"] as? [String] ?? [],
            companySizes: json["company_sizes"] as? [String] ?? [],
            industries: json["industries"] as? [String] ?? [],
            locations: json["locations"] as? [String] ?? ["United States"],
            keywords: json["keywords"] as? [String] ?? []
        )
    }
    
    /// Extract JSON from AI response that might include markdown fences
    private func extractJSON(from text: String) -> String {
        var cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // Remove markdown code fences
        if cleaned.hasPrefix("```json") { cleaned = String(cleaned.dropFirst(7)) }
        if cleaned.hasPrefix("```") { cleaned = String(cleaned.dropFirst(3)) }
        if cleaned.hasSuffix("```") { cleaned = String(cleaned.dropLast(3)) }
        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        // Find first { and last }
        if let start = cleaned.firstIndex(of: "{"), let end = cleaned.lastIndex(of: "}") {
            cleaned = String(cleaned[start...end])
        }
        return cleaned
    }
}
