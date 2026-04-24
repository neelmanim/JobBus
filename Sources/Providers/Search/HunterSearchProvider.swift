import Foundation

// MARK: - Hunter.io Search Provider
/// Uses Hunter.io's Domain Search and Email Finder APIs to find contacts.
/// API docs: https://hunter.io/api-documentation/v2
class HunterSearchProvider: ContactSearchProvider, EmailEnrichmentProvider {
    let name = "Hunter.io"
    let providerType: SearchProviderType = .hunter
    
    private let baseURL = "https://api.hunter.io/v2"
    private var apiKey: String {
        KeychainService.shared.get(key: .hunterApiKey) ?? ""
    }
    
    // MARK: - Search
    
    func search(strategy: SearchStrategy, count: Int) async throws -> [Contact] {
        guard !apiKey.isEmpty else {
            throw ProviderError.notConfigured("Hunter.io API key not set.\n\nGo to Settings → Providers to add your Hunter.io key.")
        }
        
        // Hunter works by domain search — we use keywords + industries to find companies,
        // then search each domain. For a more direct approach, we use their email-finder
        // by searching for common company domains derived from the strategy.
        // Hunter's domain-search returns emails at a given domain.
        
        var allContacts: [Contact] = []
        let perPage = min(100, count)
        var offset = 0
        
        // Use the first keyword or industry as a company hint
        let searchTerms = strategy.keywords + strategy.industries
        
        // If we have no keywords, use a generic people search via domain-search
        // Hunter's main strength is domain-based search
        if searchTerms.isEmpty {
            // Without domain info, Hunter can't effectively search. Return empty with guidance.
            throw ProviderError.notConfigured(
                "Hunter.io requires company domains or keywords to search.\n\n" +
                "Add target industries or keywords in the Strategy step, or switch to Apollo for title-based search."
            )
        }
        
        // Use domain-search for each keyword/company
        for term in searchTerms.prefix(5) {
            if allContacts.count >= count { break }
            
            let remaining = count - allContacts.count
            let result = try await domainSearch(
                domain: term,
                limit: min(perPage, remaining),
                offset: offset
            )
            allContacts.append(contentsOf: result)
            
            if allContacts.count < count {
                try await Task.sleep(for: .milliseconds(200))
            }
        }
        
        return Array(allContacts.prefix(count))
    }
    
    private func domainSearch(domain: String, limit: Int, offset: Int) async throws -> [Contact] {
        var components = URLComponents(string: "\(baseURL)/domain-search")!
        components.queryItems = [
            URLQueryItem(name: "domain", value: domain),
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "offset", value: String(offset)),
            URLQueryItem(name: "api_key", value: apiKey)
        ]
        
        guard let url = components.url else {
            throw ProviderError.networkError("Invalid URL for Hunter domain search")
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 30
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ProviderError.networkError("Invalid response from Hunter.io")
        }
        
        switch httpResponse.statusCode {
        case 200:
            return try parseSearchResponse(data, domain: domain)
        case 401:
            throw ProviderError.invalidApiKey
        case 429:
            throw ProviderError.rateLimited("Hunter.io rate limit reached. Wait a moment and try again.")
        case 403:
            throw ProviderError.creditsExhausted
        default:
            let body = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw ProviderError.networkError("Hunter HTTP \(httpResponse.statusCode): \(body.prefix(200))")
        }
    }
    
    private func parseSearchResponse(_ data: Data, domain: String) throws -> [Contact] {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let dataObj = json["data"] as? [String: Any],
              let emails = dataObj["emails"] as? [[String: Any]]
        else { throw ProviderError.parseError("Invalid Hunter.io response format") }
        
        let organization = dataObj["organization"] as? String ?? domain
        
        return emails.compactMap { entry in
            let email = entry["value"] as? String ?? ""
            let firstName = entry["first_name"] as? String ?? ""
            let lastName = entry["last_name"] as? String ?? ""
            let position = entry["position"] as? String ?? ""
            let department = entry["department"] as? String ?? ""
            let confidence = entry["confidence"] as? Int ?? 0
            let linkedin = entry["linkedin"] as? String ?? ""
            
            guard !email.isEmpty else { return nil }
            
            return Contact(
                firstName: firstName,
                lastName: lastName,
                email: email,
                title: position.isEmpty ? department : position,
                company: organization,
                location: "",
                linkedinUrl: linkedin,
                source: .hunter,
                status: confidence > 70 ? .enriched : .discovered,
                recipientType: classifyTitle(position.isEmpty ? department : position)
            )
        }
    }
    
    // MARK: - Enrichment
    
    func enrich(contact: Contact) async throws -> Contact {
        guard !apiKey.isEmpty else {
            throw ProviderError.notConfigured("Hunter.io API key not set.\n\nGo to Settings → Providers to add your Hunter.io key.")
        }
        
        // Use email-finder endpoint
        var components = URLComponents(string: "\(baseURL)/email-finder")!
        var queryItems = [URLQueryItem(name: "api_key", value: apiKey)]
        
        if !contact.company.isEmpty {
            queryItems.append(URLQueryItem(name: "company", value: contact.company))
        }
        if !contact.firstName.isEmpty {
            queryItems.append(URLQueryItem(name: "first_name", value: contact.firstName))
        }
        if !contact.lastName.isEmpty {
            queryItems.append(URLQueryItem(name: "last_name", value: contact.lastName))
        }
        
        components.queryItems = queryItems
        
        guard let url = components.url else {
            throw ProviderError.networkError("Invalid URL for Hunter email finder")
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 15
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ProviderError.networkError("Invalid response")
        }
        
        switch httpResponse.statusCode {
        case 200:
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let dataObj = json["data"] as? [String: Any]
            else { throw ProviderError.parseError("Invalid Hunter enrichment response") }
            
            var enriched = contact
            if let email = dataObj["email"] as? String, !email.isEmpty {
                enriched.email = email
                enriched.status = .enriched
            } else {
                enriched.status = .noEmail
            }
            return enriched
            
        case 401: throw ProviderError.invalidApiKey
        case 429: throw ProviderError.rateLimited("Hunter.io rate limit. Wait a moment.")
        default: throw ProviderError.networkError("Hunter HTTP \(httpResponse.statusCode)")
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
            try await Task.sleep(for: .milliseconds(200))
        }
        
        return alreadyHaveEmail + enriched
    }
    
    // MARK: - Validation
    
    func validateKey(_ key: String) async throws -> Bool {
        var components = URLComponents(string: "\(baseURL)/account")!
        components.queryItems = [URLQueryItem(name: "api_key", value: key)]
        
        guard let url = components.url else { return false }
        let (_, response) = try await URLSession.shared.data(from: url)
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
