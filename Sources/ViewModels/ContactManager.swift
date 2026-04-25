import Foundation

// MARK: - Contact Manager
/// Handles contact search, import, deduplication, and persistence.
/// Business logic extracted from AppViewModel for testability and separation of concerns.
@MainActor
class ContactManager {
    
    private var searchTask: Task<Void, Never>?
    
    // MARK: - Search
    
    /// Search for contacts via the configured provider and enrich with emails.
    /// Returns the deduplicated contact list and any duplicates removed.
    func search(
        strategy: SearchStrategy,
        count: Int,
        provider: ContactSearchProvider,
        enrichment: EmailEnrichmentProvider,
        existingContacts: [Contact],
        onProgress: @escaping (String) -> Void
    ) async throws -> (contacts: [Contact], newCount: Int, dupesRemoved: Int) {
        
        log.section("CONTACT SEARCH")
        log.info("Provider: \(provider.name), Count: \(count)")
        
        let found = try await provider.search(strategy: strategy, count: count)
        try Task.checkCancellation()
        
        onProgress("Enriching contacts to get emails...")
        let enriched = try await enrichment.enrichBatch(contacts: found) { done, total in
            Task { @MainActor in
                onProgress("Enriching contacts: \(done)/\(total)...")
            }
        }
        try Task.checkCancellation()
        
        // Deduplicate against existing contacts
        let allContacts = existingContacts + enriched
        let (unique, dupes) = DuplicateDetector.removeDuplicates(from: allContacts)
        
        log.info("Contacts found: \(enriched.count), unique: \(unique.count), dupes removed: \(dupes.count)")
        
        return (unique, enriched.count, dupes.count)
    }
    
    // MARK: - CSV Import
    
    func importCSV(from url: URL, existingContacts: [Contact], csvImporter: CSVImporter) throws -> (contacts: [Contact], importedCount: Int) {
        let result = try csvImporter.parseCSV(from: url)
        let allContacts = existingContacts + result.contacts
        let (unique, _) = DuplicateDetector.removeDuplicates(from: allContacts)
        return (unique, result.contacts.count)
    }
    
    // MARK: - Manual Add
    
    func addManual(_ contact: Contact, existingContacts: [Contact]) -> [Contact] {
        let allContacts = existingContacts + [contact]
        let (unique, _) = DuplicateDetector.removeDuplicates(from: allContacts)
        return unique
    }
    
    // MARK: - Relevance Scoring
    
    /// Score each contact's relevance to the candidate's profile.
    func scoreRelevance(contacts: [Contact], resume: ResumeProfile) -> [Contact] {
        let skillsLower = Set(resume.skills.map { $0.lowercased() })
        let industriesLower = Set(resume.industries.map { $0.lowercased() })
        
        return contacts.map { contact in
            var c = contact
            var score: Double = 0.0
            var reasons: [String] = []
            
            // Title keyword match (0.3 weight)
            let titleLower = contact.title.lowercased()
            let titleMatchCount = skillsLower.filter { titleLower.contains($0) }.count
            let titleScore = min(Double(titleMatchCount) * 0.15, 0.3)
            score += titleScore
            if titleMatchCount > 0 { reasons.append("Title matches \(titleMatchCount) skill(s)") }
            
            // Industry match (0.2 weight)
            let companyLower = contact.company.lowercased()
            let industryMatch = industriesLower.contains(where: { companyLower.contains($0) })
            if industryMatch {
                score += 0.2
                reasons.append("Industry alignment")
            }
            
            // Seniority alignment (0.3 weight)
            let seniorityScore: Double
            switch contact.recipientType {
            case .recruiter: seniorityScore = 0.3; reasons.append("Direct recruiter")
            case .hiringManager: seniorityScore = 0.3; reasons.append("Direct hiring manager")
            case .engineering: seniorityScore = 0.25; reasons.append("Engineering leader")
            case .hr: seniorityScore = 0.15; reasons.append("HR contact")
            case .cSuite: seniorityScore = 0.1; reasons.append("C-level executive")
            case .other: seniorityScore = 0.05
            }
            score += seniorityScore
            
            // Has verified email (0.2 weight)
            if !contact.email.isEmpty && contact.email.contains("@") {
                score += 0.2
                reasons.append("Verified email")
            }
            
            c.relevanceScore = min(score, 1.0)
            c.relevanceReason = reasons.isEmpty ? "No specific match" : reasons.joined(separator: " · ")
            return c
        }
    }
    
    // MARK: - Persistence
    
    private static var contactsCacheURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("JobBus", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("contacts_cache.json")
    }
    
    func save(_ contacts: [Contact]) {
        guard !contacts.isEmpty else { return }
        let url = Self.contactsCacheURL
        Task.detached(priority: .utility) {
            if let data = try? JSONEncoder().encode(contacts) {
                try? data.write(to: url, options: .atomic)
            }
        }
    }
    
    func loadCached() -> [Contact] {
        guard FileManager.default.fileExists(atPath: Self.contactsCacheURL.path),
              let data = try? Data(contentsOf: Self.contactsCacheURL),
              let cached = try? JSONDecoder().decode([Contact].self, from: data),
              !cached.isEmpty
        else { return [] }
        return cached
    }
    
    func clearCache() {
        try? FileManager.default.removeItem(at: Self.contactsCacheURL)
    }
}
