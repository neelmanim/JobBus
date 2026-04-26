import Foundation

// MARK: - Apollo Credit Usage Notification
extension Notification.Name {
    static let apolloCreditUsed = Notification.Name("apolloCreditUsed")
}

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
        guard !apiKey.isEmpty else { throw ProviderError.notConfigured("Apollo API key not set.\n\nGo to Settings → Providers to add your Apollo.io key.") }
        
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
        let url = URL(string: "\(baseURL)/mixed_people/api_search")!
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
        // NOTE: We intentionally don't send strategy.keywords or strategy.industries
        // as q_keywords because combining them with titles + seniorities + location +
        // company size creates overly narrow filters that return 0 results.
        // Skills/industries inform email personalization, not contact discovery.
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        // Debug: log the request body
        if let bodyStr = String(data: request.httpBody ?? Data(), encoding: .utf8) {
            log.debug("Apollo request body: \(bodyStr)")
        }
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ProviderError.networkError("Invalid response")
        }
        
        switch httpResponse.statusCode {
        case 200:
            // Debug: log the raw response structure to help diagnose parsing issues
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                let keys = json.keys.sorted().joined(separator: ", ")
                log.debug("Apollo response keys: [\(keys)]")
                let totalEntries = json["total_entries"] as? Int ?? -1
                log.debug("Apollo total_entries: \(totalEntries)")
                if let people = json["people"] as? [[String: Any]] {
                    log.debug("Apollo 'people' count: \(people.count)")
                } else {
                    log.warn("Apollo response has NO 'people' key — raw keys: [\(keys)]")
                }
            }
            
            let results = try parseSearchResponse(data)
            
            // If no results and we had restrictive filters, retry with broader search
            if results.isEmpty {
                log.warn("Apollo returned 0 results — retrying with broader filters (no keywords, expanded company sizes)")
                var broadBody: [String: Any] = [
                    "page": page,
                    "per_page": perPage
                ]
                if !strategy.targetTitles.isEmpty {
                    broadBody["person_titles"] = strategy.targetTitles
                }
                if !strategy.targetSeniorities.isEmpty {
                    broadBody["person_seniorities"] = strategy.targetSeniorities
                }
                if !strategy.locations.isEmpty {
                    switch strategy.locationMode {
                    case .personLocation:
                        broadBody["person_locations"] = strategy.locations
                    case .companyHQ:
                        broadBody["organization_locations"] = strategy.locations
                    case .both:
                        broadBody["person_locations"] = strategy.locations
                        broadBody["organization_locations"] = strategy.locations
                    }
                }
                // Skip keywords and company sizes for broader results
                
                var broadRequest = URLRequest(url: url)
                broadRequest.httpMethod = "POST"
                broadRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
                broadRequest.setValue(apiKey, forHTTPHeaderField: "x-api-key")
                broadRequest.timeoutInterval = 30
                broadRequest.httpBody = try JSONSerialization.data(withJSONObject: broadBody)
                
                if let bodyStr = String(data: broadRequest.httpBody ?? Data(), encoding: .utf8) {
                    log.debug("Apollo BROAD request body: \(bodyStr)")
                }
                
                let (broadData, broadResponse) = try await URLSession.shared.data(for: broadRequest)
                if let broadHttp = broadResponse as? HTTPURLResponse, broadHttp.statusCode == 200 {
                    if let json = try? JSONSerialization.jsonObject(with: broadData) as? [String: Any] {
                        let total = json["total_entries"] as? Int ?? -1
                        log.debug("Apollo BROAD total_entries: \(total)")
                    }
                    let broadResults = try parseSearchResponse(broadData)
                    if !broadResults.isEmpty {
                        log.info("Apollo broad search found \(broadResults.count) contacts")
                        return broadResults
                    }
                }
            }
            
            return results
        case 401:
            throw ProviderError.invalidApiKey
        case 429:
            let retryAfter = httpResponse.value(forHTTPHeaderField: "Retry-After") ?? "60"
            throw ProviderError.rateLimited("Rate limited. Retry after \(retryAfter) seconds.")
        default:
            let body = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw ProviderError.networkError("HTTP \(httpResponse.statusCode): \(body)")
        }
    }
    
    private func parseSearchResponse(_ data: Data) throws -> [Contact] {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let people = json["people"] as? [[String: Any]]
        else { throw ProviderError.parseError("Invalid Apollo response format") }
        
        // The new /mixed_people/api_search endpoint returns discovery-only data:
        //   Available: id, first_name, last_name_obfuscated, title, has_email, organization.name
        //   Missing:   last_name, email, linkedin_url, city, state, country
        // Full data (email, last_name, location) comes from the /people/match enrichment step.
        
        if let first = people.first {
            let personKeys = first.keys.sorted().joined(separator: ", ")
            log.debug("Apollo search person keys: [\(personKeys)]")
        }
        
        return people.compactMap { person in
            let apolloId = person["id"] as? String
            let firstName = person["first_name"] as? String ?? ""
            // New endpoint uses last_name_obfuscated (e.g. "Pa***n") instead of last_name
            let lastNameObfuscated = person["last_name_obfuscated"] as? String ?? ""
            let title = person["title"] as? String ?? ""
            let hasEmail = person["has_email"] as? Bool ?? false
            
            let org = person["organization"] as? [String: Any]
            let company = org?["name"] as? String ?? ""
            
            // Skip contacts that Apollo indicates have no email — saves enrichment credits
            guard hasEmail else {
                log.debug("Apollo: skipping \(firstName) \(lastNameObfuscated) @ \(company) — no email available")
                return nil
            }
            
            return Contact(
                firstName: firstName,
                lastName: lastNameObfuscated, // Placeholder; real last name comes from enrichment
                email: "",                    // Email comes from enrichment
                title: title,
                company: company,
                location: "",                 // Location comes from enrichment
                linkedinUrl: "",              // LinkedIn comes from enrichment
                source: .apollo,
                status: .discovered,
                recipientType: classifyTitle(title),
                apolloId: apolloId
            )
        }
    }
    
    // MARK: - Enrichment
    
    func enrich(contact: Contact) async throws -> Contact {
        guard !apiKey.isEmpty else { throw ProviderError.notConfigured("Apollo API key not set.\n\nGo to Settings → Providers to add your Apollo.io key.") }
        
        let url = URL(string: "\(baseURL)/people/match")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.timeoutInterval = 15
        
        // Use Apollo ID for enrichment — this is the reliable way to reveal contacts.
        // The search endpoint returns the ID; /people/match with {"id": ...} reveals
        // the full profile including email, last_name, linkedin, and location.
        var body: [String: Any] = [:]
        if let apolloId = contact.apolloId, !apolloId.isEmpty {
            body["id"] = apolloId
        } else {
            // Fallback: match by name + company (less reliable, may create new records)
            if !contact.firstName.isEmpty { body["first_name"] = contact.firstName }
            if !contact.lastName.isEmpty { body["last_name"] = contact.lastName }
            if !contact.company.isEmpty { body["organization_name"] = contact.company }
            if !contact.linkedinUrl.isEmpty { body["linkedin_url"] = contact.linkedinUrl }
        }
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        if let bodyStr = String(data: request.httpBody ?? Data(), encoding: .utf8) {
            log.debug("Apollo enrich request: \(bodyStr)")
        }
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ProviderError.networkError("Invalid response")
        }
        
        switch httpResponse.statusCode {
        case 200:
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let person = json["person"] as? [String: Any]
            else {
                let snippet = String(data: data.prefix(300), encoding: .utf8) ?? "binary"
                log.warn("Apollo enrich: no 'person' key in response: \(snippet)")
                throw ProviderError.parseError("Invalid enrichment response")
            }
            
            var enriched = contact
            // Backfill all fields from enrichment response
            if let email = person["email"] as? String, !email.isEmpty {
                enriched.email = email
                enriched.status = .enriched
            } else {
                enriched.status = .noEmail
            }
            if let lastName = person["last_name"] as? String, !lastName.isEmpty {
                enriched.lastName = lastName
            }
            if let title = person["title"] as? String, !title.isEmpty {
                enriched.title = title
                enriched.recipientType = classifyTitle(title)
            }
            if let linkedin = person["linkedin_url"] as? String, !linkedin.isEmpty {
                enriched.linkedinUrl = linkedin
            }
            let city = person["city"] as? String ?? ""
            let state = person["state"] as? String ?? ""
            let country = person["country"] as? String ?? ""
            let location = [city, state, country].filter { !$0.isEmpty }.joined(separator: ", ")
            if !location.isEmpty {
                enriched.location = location
            }
            
            log.debug("Apollo enrich: \(enriched.firstName) \(enriched.lastName) → \(enriched.email.isEmpty ? "NO email" : "✓ email")")
            return enriched
            
        case 401:
            throw ProviderError.invalidApiKey
        case 403:
            // 403 can occur when reveal credits are exhausted or temporary rate block
            log.warn("Apollo enrich 403 for \(contact.firstName) — may be credits exhausted or temp rate block")
            throw ProviderError.rateLimited("Temporarily blocked. Retry after 60 seconds.")
        case 429:
            throw ProviderError.rateLimited("Rate limited. Retry after 60 seconds.")
        default:
            throw ProviderError.networkError("HTTP \(httpResponse.statusCode)")
        }
    }
    
    func enrichBatch(contacts: [Contact], progress: @escaping (Int, Int) -> Void) async throws -> [Contact] {
        var enriched: [Contact] = []
        let needsEnrichment = contacts.filter { $0.email.isEmpty }
        let alreadyHaveEmail = contacts.filter { !$0.email.isEmpty }
        
        log.info("Enrichment: \(needsEnrichment.count) contacts need email, \(alreadyHaveEmail.count) already have")
        for (index, contact) in needsEnrichment.enumerated() {
            do {
                let result = try await enrich(contact: contact)
                enriched.append(result)
                // Track credit usage: each successful enrichment costs 1 credit
                if result.status == .enriched {
                    NotificationCenter.default.post(name: .apolloCreditUsed, object: nil)
                }
            } catch ProviderError.rateLimited(_) {
                log.warn("Enrichment: rate limited, waiting 60s")
                try await Task.sleep(for: .seconds(60))
                let result = try await enrich(contact: contact)
                enriched.append(result)
            } catch ProviderError.creditsExhausted {
                log.warn("Enrichment: credits exhausted at \(index + 1)/\(needsEnrichment.count)")
                var remaining = Array(needsEnrichment[(index + 1)...])
                remaining = remaining.map { var c = $0; c.status = .noEmail; return c }
                enriched.append(contentsOf: remaining)
                break
            } catch {
                log.warn("Enrichment failed for \(contact.firstName) \(contact.lastName): \(error)")
                var failed = contact
                failed.status = .failed
                enriched.append(failed)
            }
            
            progress(index + 1, needsEnrichment.count)
            
            // 1.5s delay between enrichment calls — Apollo's /people/match can
            // return 403 under rapid sequential calls even within rate limits
            try await Task.sleep(for: .milliseconds(1500))
        }
        
        return alreadyHaveEmail + enriched
    }
    
    // MARK: - Validation
    
    func validateKey(_ key: String) async throws -> Bool {
        let url = URL(string: "\(baseURL)/mixed_people/api_search")!
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
