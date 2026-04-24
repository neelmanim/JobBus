import Foundation

// MARK: - RocketReach Search Provider
/// Uses RocketReach API v2 for person search and email lookup.
/// API docs: https://rocketreach.co/api
class RocketReachSearchProvider: ContactSearchProvider, EmailEnrichmentProvider {
    let name = "RocketReach"
    let providerType: SearchProviderType = .rocketReach
    
    private let baseURL = "https://api.rocketreach.co/v2/api"
    private var apiKey: String {
        KeychainService.shared.get(key: .rocketReachApiKey) ?? ""
    }
    
    // MARK: - Search
    
    func search(strategy: SearchStrategy, count: Int) async throws -> [Contact] {
        guard !apiKey.isEmpty else {
            throw ProviderError.notConfigured("RocketReach API key not set.\n\nGo to Settings → Providers to add your RocketReach key.")
        }
        
        var allContacts: [Contact] = []
        let perPage = min(100, count)
        var start = 1
        
        while allContacts.count < count {
            let remaining = count - allContacts.count
            let result = try await searchPage(
                strategy: strategy,
                start: start,
                pageSize: min(perPage, remaining)
            )
            
            if result.isEmpty { break }
            allContacts.append(contentsOf: result)
            start += result.count
            
            if allContacts.count < count {
                try await Task.sleep(for: .milliseconds(500))
            }
        }
        
        return Array(allContacts.prefix(count))
    }
    
    private func searchPage(strategy: SearchStrategy, start: Int, pageSize: Int) async throws -> [Contact] {
        let url = URL(string: "\(baseURL)/search")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "Api-Key")
        request.timeoutInterval = 30
        
        var query: [String: Any] = [
            "start": start,
            "page_size": pageSize
        ]
        
        if !strategy.targetTitles.isEmpty {
            query["current_title"] = strategy.targetTitles
        }
        if !strategy.locations.isEmpty {
            query["current_location"] = strategy.locations
        }
        if !strategy.keywords.isEmpty {
            query["keyword"] = strategy.keywords
        }
        if !strategy.industries.isEmpty {
            query["company_industry"] = strategy.industries
        }
        
        request.httpBody = try JSONSerialization.data(withJSONObject: ["query": query])
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ProviderError.networkError("Invalid response from RocketReach")
        }
        
        switch httpResponse.statusCode {
        case 200:
            return try parseSearchResponse(data)
        case 401, 403:
            throw ProviderError.invalidApiKey
        case 429:
            throw ProviderError.rateLimited("RocketReach rate limit reached. Wait a moment and try again.")
        default:
            let body = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw ProviderError.networkError("RocketReach HTTP \(httpResponse.statusCode): \(body.prefix(200))")
        }
    }
    
    private func parseSearchResponse(_ data: Data) throws -> [Contact] {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let profiles = json["profiles"] as? [[String: Any]]
        else { throw ProviderError.parseError("Invalid RocketReach response format") }
        
        return profiles.compactMap { person in
            let firstName = person["first_name"] as? String ?? ""
            let lastName = person["last_name"] as? String ?? ""
            let title = person["current_title"] as? String ?? ""
            let company = person["current_employer"] as? String ?? ""
            let location = person["location"] as? String ?? ""
            let linkedinUrl = person["linkedin_url"] as? String ?? ""
            let profileId = person["id"] as? Int
            
            // RocketReach may include emails in search results
            var email = ""
            if let emails = person["emails"] as? [[String: Any]],
               let firstEmail = emails.first?["email"] as? String {
                email = firstEmail
            } else if let directEmail = person["email"] as? String {
                email = directEmail
            }
            
            return Contact(
                firstName: firstName,
                lastName: lastName,
                email: email,
                title: title,
                company: company,
                location: location,
                linkedinUrl: linkedinUrl,
                source: .rocketReach,
                status: email.isEmpty ? .discovered : .enriched,
                recipientType: classifyTitle(title),
                apolloId: profileId.map { String($0) }
            )
        }
    }
    
    // MARK: - Enrichment
    
    func enrich(contact: Contact) async throws -> Contact {
        guard !apiKey.isEmpty else {
            throw ProviderError.notConfigured("RocketReach API key not set.\n\nGo to Settings → Providers to add your RocketReach key.")
        }
        
        let url = URL(string: "\(baseURL)/lookupProfile")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "Api-Key")
        request.timeoutInterval = 15
        
        var body: [String: Any] = [:]
        if !contact.firstName.isEmpty { body["first_name"] = contact.firstName }
        if !contact.lastName.isEmpty { body["last_name"] = contact.lastName }
        if !contact.company.isEmpty { body["current_employer"] = contact.company }
        if !contact.linkedinUrl.isEmpty { body["linkedin_url"] = contact.linkedinUrl }
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ProviderError.networkError("Invalid response")
        }
        
        switch httpResponse.statusCode {
        case 200:
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { throw ProviderError.parseError("Invalid RocketReach enrichment response") }
            
            var enriched = contact
            if let emails = json["emails"] as? [[String: Any]],
               let firstEmail = emails.first?["email"] as? String, !firstEmail.isEmpty {
                enriched.email = firstEmail
                enriched.status = .enriched
            } else if let email = json["email"] as? String, !email.isEmpty {
                enriched.email = email
                enriched.status = .enriched
            } else {
                enriched.status = .noEmail
            }
            if let title = json["current_title"] as? String, !title.isEmpty {
                enriched.title = title
                enriched.recipientType = classifyTitle(title)
            }
            return enriched
            
        case 401, 403: throw ProviderError.invalidApiKey
        case 429: throw ProviderError.rateLimited("RocketReach rate limit. Wait a moment.")
        default: throw ProviderError.networkError("RocketReach HTTP \(httpResponse.statusCode)")
        }
    }
    
    func enrichBatch(contacts: [Contact], progress: @escaping (Int, Int) -> Void) async throws -> [Contact] {
        var enriched: [Contact] = []
        let needsEnrichment = contacts.filter { $0.email.isEmpty }
        let alreadyHaveEmail = contacts.filter { !$0.email.isEmpty }
        
        for (index, contact) in needsEnrichment.enumerated() {
            do {
                let result = try await enrich(contact: contact)
                enriched.append(result)
            } catch ProviderError.rateLimited(_) {
                try await Task.sleep(for: .seconds(10))
                let result = try await enrich(contact: contact)
                enriched.append(result)
            } catch {
                var failed = contact
                failed.status = .failed
                enriched.append(failed)
            }
            progress(index + 1, needsEnrichment.count)
            try await Task.sleep(for: .milliseconds(300))
        }
        
        return alreadyHaveEmail + enriched
    }
    
    // MARK: - Validation
    
    func validateKey(_ key: String) async throws -> Bool {
        let url = URL(string: "\(baseURL)/account")!
        var request = URLRequest(url: url)
        request.setValue(key, forHTTPHeaderField: "Api-Key")
        request.timeoutInterval = 10
        
        let (_, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else { return false }
        return httpResponse.statusCode == 200
    }
    
    // MARK: - Title Classification
    
    private func classifyTitle(_ title: String) -> RecipientType {
        let lower = title.lowercased()
        if lower.contains("recruit") || lower.contains("talent") { return .recruiter }
        if lower.contains("cto") || lower.contains("ceo") || lower.contains("chief") || lower.contains("founder") { return .cSuite }
        if lower.contains("vp") || lower.contains("director") || lower.contains("head of") { return .engineering }
        if lower.contains("manager") && (lower.contains("engineer") || lower.contains("tech")) { return .hiringManager }
        if lower.contains("hr") || lower.contains("human resource") || lower.contains("people") { return .hr }
        return .other
    }
}
