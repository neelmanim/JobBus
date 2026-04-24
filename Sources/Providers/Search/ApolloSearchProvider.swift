import Foundation

// MARK: - Apollo Search Provider
class ApolloSearchProvider: ContactSearchProvider, EmailEnrichmentProvider {
    let name = "Apollo.io"
    let providerType: SearchProviderType = .apollo
    
    private let baseURL = "https://api.apollo.io/api/v1"
    private var apiKey: String {
        KeychainService.shared.get(key: .apolloApiKey) ?? ""
    }
    
    // MARK: - Search
    
    func search(strategy: SearchStrategy, count: Int) async throws -> [Contact] {
        guard !apiKey.isEmpty else { throw ProviderError.notConfigured("Apollo API key not set") }
        
        var allContacts: [Contact] = []
        let perPage = min(100, count)
        let totalPages = max(1, (count + perPage - 1) / perPage)
        
        for page in 1...totalPages {
            let remaining = count - allContacts.count
            if remaining <= 0 { break }
            
            let result = try await searchPage(
                strategy: strategy,
                page: page,
                perPage: min(perPage, remaining)
            )
            allContacts.append(contentsOf: result)
            
            // Small delay between pages to avoid rate limiting
            if page < totalPages {
                try await Task.sleep(for: .milliseconds(500))
            }
        }
        
        return Array(allContacts.prefix(count))
    }
    
    private func searchPage(strategy: SearchStrategy, page: Int, perPage: Int) async throws -> [Contact] {
        let url = URL(string: "\(baseURL)/mixed_people/search")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.timeoutInterval = 30
        
        // Build search body
        var body: [String: Any] = [
            "page": page,
            "per_page": perPage
        ]
        
        if !strategy.targetTitles.isEmpty {
            body["person_titles"] = strategy.targetTitles
        }
        if !strategy.targetSeniorities.isEmpty {
            body["person_seniorities"] = strategy.targetSeniorities
        }
        if !strategy.locations.isEmpty {
            switch strategy.locationMode {
            case .personLocation:
                body["person_locations"] = strategy.locations
            case .companyHQ:
                body["organization_locations"] = strategy.locations
            case .both:
                body["person_locations"] = strategy.locations
                body["organization_locations"] = strategy.locations
            }
        }
        if !strategy.companySizes.isEmpty {
            body["organization_num_employees_ranges"] = strategy.companySizes
        }
        if !strategy.keywords.isEmpty {
            body["q_keywords"] = strategy.keywords.joined(separator: " ")
        }
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ProviderError.networkError("Invalid response")
        }
        
        switch httpResponse.statusCode {
        case 200:
            return try parseSearchResponse(data)
        case 401:
            throw ProviderError.invalidApiKey
        case 429:
            let retryAfter = Int(httpResponse.value(forHTTPHeaderField: "Retry-After") ?? "60") ?? 60
            throw ProviderError.rateLimited(retryAfter: retryAfter)
        default:
            let body = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw ProviderError.networkError("HTTP \(httpResponse.statusCode): \(body)")
        }
    }
    
    private func parseSearchResponse(_ data: Data) throws -> [Contact] {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let people = json["people"] as? [[String: Any]]
        else { throw ProviderError.parseError("Invalid Apollo response format") }
        
        return people.compactMap { person in
            let firstName = person["first_name"] as? String ?? ""
            let lastName = person["last_name"] as? String ?? ""
            let title = person["title"] as? String ?? ""
            let email = person["email"] as? String ?? ""
            let linkedinUrl = person["linkedin_url"] as? String ?? ""
            let apolloId = person["id"] as? String
            
            let org = person["organization"] as? [String: Any]
            let company = org?["name"] as? String ?? ""
            
            let city = person["city"] as? String ?? ""
            let state = person["state"] as? String ?? ""
            let country = person["country"] as? String ?? ""
            let location = [city, state, country].filter { !$0.isEmpty }.joined(separator: ", ")
            
            return Contact(
                firstName: firstName,
                lastName: lastName,
                email: email,
                title: title,
                company: company,
                location: location,
                linkedinUrl: linkedinUrl,
                source: .apollo,
                status: email.isEmpty ? .discovered : .enriched,
                recipientType: classifyTitle(title),
                apolloId: apolloId
            )
        }
    }
    
    // MARK: - Enrichment
    
    func enrich(contact: Contact) async throws -> Contact {
        guard !apiKey.isEmpty else { throw ProviderError.notConfigured("Apollo API key not set") }
        
        let url = URL(string: "\(baseURL)/people/match")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.timeoutInterval = 15
        
        var body: [String: Any] = [:]
        if !contact.firstName.isEmpty { body["first_name"] = contact.firstName }
        if !contact.lastName.isEmpty { body["last_name"] = contact.lastName }
        if !contact.company.isEmpty {
            // Extract domain from company name — Apollo prefers domain
            body["organization_name"] = contact.company
        }
        if !contact.linkedinUrl.isEmpty { body["linkedin_url"] = contact.linkedinUrl }
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ProviderError.networkError("Invalid response")
        }
        
        switch httpResponse.statusCode {
        case 200:
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let person = json["person"] as? [String: Any]
            else { throw ProviderError.parseError("Invalid enrichment response") }
            
            var enriched = contact
            if let email = person["email"] as? String, !email.isEmpty {
                enriched.email = email
                enriched.status = .enriched
            } else {
                enriched.status = .noEmail
            }
            if let title = person["title"] as? String, !title.isEmpty {
                enriched.title = title
                enriched.recipientType = classifyTitle(title)
            }
            return enriched
            
        case 401:
            throw ProviderError.invalidApiKey
        case 429:
            throw ProviderError.rateLimited(retryAfter: 60)
        default:
            throw ProviderError.networkError("HTTP \(httpResponse.statusCode)")
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
            } catch ProviderError.rateLimited(let retryAfter) {
                // Wait and retry once
                try await Task.sleep(for: .seconds(retryAfter))
                let result = try await enrich(contact: contact)
                enriched.append(result)
            } catch ProviderError.creditsExhausted {
                // Stop enrichment, return what we have
                var remaining = Array(needsEnrichment[(index + 1)...])
                remaining = remaining.map { var c = $0; c.status = .noEmail; return c }
                enriched.append(contentsOf: remaining)
                break
            } catch {
                var failed = contact
                failed.status = .failed
                enriched.append(failed)
            }
            
            progress(index + 1, needsEnrichment.count)
            
            // Small delay to avoid rate limits
            try await Task.sleep(for: .milliseconds(300))
        }
        
        return alreadyHaveEmail + enriched
    }
    
    // MARK: - Validation
    
    func validateKey(_ key: String) async throws -> Bool {
        let url = URL(string: "\(baseURL)/mixed_people/search")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(key, forHTTPHeaderField: "x-api-key")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "page": 1, "per_page": 1, "person_titles": ["CEO"]
        ] as [String: Any])
        
        let (_, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else { return false }
        return httpResponse.statusCode == 200
    }
    
    // MARK: - Title Classification
    
    private func classifyTitle(_ title: String) -> RecipientType {
        let lower = title.lowercased()
        
        if lower.contains("recruit") || lower.contains("talent acquisition") || lower.contains("sourcer") {
            return .recruiter
        }
        if lower.contains("cto") || lower.contains("ceo") || lower.contains("coo") ||
           lower.contains("chief") || lower.contains("founder") || lower.contains("co-founder") {
            return .cSuite
        }
        if lower.contains("vp") || lower.contains("vice president") || lower.contains("director") ||
           lower.contains("head of engineering") || lower.contains("head of product") {
            return .engineering
        }
        if lower.contains("manager") && (lower.contains("engineer") || lower.contains("software") ||
                                          lower.contains("develop") || lower.contains("tech")) {
            return .hiringManager
        }
        if lower.contains("hr") || lower.contains("human resource") || lower.contains("people") {
            return .hr
        }
        return .other
    }
}
