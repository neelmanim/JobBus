import Foundation

// MARK: - Token Usage Notification
extension Notification.Name {
    static let aiTokensUsed = Notification.Name("aiTokensUsed")
}

// MARK: - Ollama AI Provider (Local LLM)
class OllamaProvider: AIProvider {
    let name = "Ollama (Local)"
    let providerType: AIProviderType = .ollama
    var model: String
    var baseURL: String
    
    init(model: String = "llama3.1:8b", baseURL: String = "http://localhost:11434") {
        self.model = model
        self.baseURL = baseURL
    }
    
    func generate(prompt: String) async throws -> String {
        guard let url = URL(string: "\(baseURL)/api/generate") else {
            throw ProviderError.notConfigured("Invalid Ollama URL")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 60
        let body: [String: Any] = [
            "model": model, "prompt": prompt, "stream": false,
            "options": ["temperature": 0.7, "top_p": 0.9, "num_predict": 1024]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw ProviderError.serviceUnavailable("Ollama not responding. Start with: ollama serve")
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let text = json["response"] as? String
        else { throw ProviderError.parseError("Invalid Ollama response") }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    func isAvailable() async -> Bool {
        guard let url = URL(string: "\(baseURL)/api/tags") else { return false }
        return (try? await URLSession.shared.data(from: url)) != nil
    }
}

// MARK: - Gemini AI Provider (Dynamic Model Discovery)
class GeminiFlashProvider: AIProvider {
    let name = "Gemini"
    let providerType: AIProviderType = .gemini
    
    private var apiKey: String { KeychainService.shared.get(key: .geminiApiKey) ?? "" }
    
    /// Cached list of available models — fetched once per app session
    private var cachedModels: [String]?
    
    /// Preference order: lightweight/fast models first, expensive last
    /// Models containing these substrings are sorted accordingly
    private let modelPreference = ["flash-lite", "flash", "pro"]
    
    func generate(prompt: String) async throws -> String {
        guard !apiKey.isEmpty else {
            throw ProviderError.notConfigured("Gemini API key not set. Go to Settings → Providers to add your key from aistudio.google.com/apikey")
        }
        
        let models = try await getAvailableModels()
        guard !models.isEmpty else {
            throw ProviderError.serviceUnavailable("No Gemini models available for generateContent. Check your API key permissions.")
        }
        
        var lastError: Error?
        log.debug("Gemini: starting generation (\(models.count) models: \(models.joined(separator: ", ")))")
        
        for model in models {
            do {
                let result = try await callModel(model: model, prompt: prompt)
                log.debug("Gemini: \(model) returned \(result.count) chars")
                return result
            } catch ProviderError.rateLimited(let msg) {
                lastError = ProviderError.rateLimited(msg)
                log.warn("Gemini: \(model) rate limited, trying next...")
                continue
            } catch {
                throw error
            }
        }
        
        throw lastError ?? ProviderError.serviceUnavailable("All Gemini models exhausted")
    }
    
    // MARK: - Dynamic Model Discovery
    
    /// Fetches available models from Gemini's ListModels API, filters for generateContent support,
    /// and sorts by preference (flash-lite → flash → pro). Cached for the session.
    private func getAvailableModels() async throws -> [String] {
        if let cached = cachedModels { return cached }
        
        let fallback = ["gemini-2.5-flash-lite", "gemini-2.5-flash", "gemini-2.5-pro"]
        
        // Fetch with pageSize=100 to avoid pagination truncating the list
        let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models?key=\(apiKey)&pageSize=100")!
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        
        // Wrap in do/catch — network errors (no internet, DNS, timeout) should not crash generation
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            log.warn("Gemini: ListModels network error (\(error.localizedDescription)), using fallback")
            cachedModels = fallback
            return fallback
        }
        
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            log.warn("Gemini: ListModels failed, using fallback model names")
            cachedModels = fallback
            return fallback
        }
        
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let modelList = json["models"] as? [[String: Any]]
        else {
            log.warn("Gemini: ListModels parse failed, using fallback model names")
            cachedModels = fallback
            return fallback
        }
        
        // Filter for models that support generateContent and extract short names
        let available = modelList.compactMap { model -> String? in
            guard let name = model["name"] as? String,
                  let methods = model["supportedGenerationMethods"] as? [String],
                  methods.contains("generateContent")
            else { return nil }
            // API returns "models/gemini-2.5-flash" — strip the "models/" prefix
            return name.hasPrefix("models/") ? String(name.dropFirst(7)) : name
        }
        // Filter to only "gemini-" models (skip embedding-only, legacy, etc.)
        .filter { $0.hasPrefix("gemini-") }
        
        // If filtering removed everything, use fallback
        guard !available.isEmpty else {
            log.warn("Gemini: no generateContent models found, using fallback")
            cachedModels = fallback
            return fallback
        }
        
        // Sort by preference: flash-lite first, then flash, then pro, then everything else
        let sorted = available.sorted { a, b in
            let aIdx = modelPreference.firstIndex(where: { a.contains($0) }) ?? modelPreference.count
            let bIdx = modelPreference.firstIndex(where: { b.contains($0) }) ?? modelPreference.count
            return aIdx < bIdx
        }
        
        log.info("Gemini: discovered \(sorted.count) models: \(sorted.joined(separator: ", "))")
        cachedModels = sorted
        return sorted
    }
    
    // MARK: - Model Call
    
    private func callModel(model: String, prompt: String) async throws -> String {
        let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent?key=\(apiKey)")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 60
        let body: [String: Any] = [
            "contents": [["parts": [["text": prompt]]]],
            "generationConfig": ["temperature": 0.7, "topP": 0.9, "maxOutputTokens": 1024]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let http = response as? HTTPURLResponse else {
            throw ProviderError.serviceUnavailable("No response from Gemini")
        }
        
        // Handle non-200 responses
        if http.statusCode != 200 {
            let errorBody = String(data: data, encoding: .utf8) ?? ""
            
            switch http.statusCode {
            case 429:
                throw ProviderError.rateLimited("Gemini quota exceeded for \(model). Trying next model...")
            case 503:
                throw ProviderError.rateLimited("Gemini model \(model) overloaded. Trying next model...")
            case 404:
                // Model removed since we last fetched — invalidate cache and try next
                cachedModels = nil
                throw ProviderError.rateLimited("Gemini model \(model) not found. Trying next...")
            case 401, 403:
                throw ProviderError.invalidApiKey
            default:
                throw ProviderError.serviceUnavailable("Gemini returned \(http.statusCode): \(errorBody.prefix(200))")
            }
        }
        
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let candidates = json["candidates"] as? [[String: Any]],
              let content = candidates.first?["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]],
              let text = parts.first?["text"] as? String
        else { throw ProviderError.parseError("Invalid Gemini response") }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    

    func isAvailable() async -> Bool { !apiKey.isEmpty }
}

// MARK: - Groq AI Provider (Dynamic Model Discovery)
class GroqProvider: AIProvider {
    let name = "Groq"
    let providerType: AIProviderType = .groq
    
    private var apiKey: String { KeychainService.shared.get(key: .groqApiKey) ?? "" }
    
    /// Cached list of available models — fetched once per app session
    private var cachedModels: [String]?
    
    /// Preference order: fast/small models first (for email generation, we don't need massive models)
    /// Models containing these substrings are sorted accordingly
    private let modelPreference = ["instant", "versatile", "preview"]
    
    /// Model IDs to skip (not suitable for chat/email generation)
    private let skipPatterns = ["whisper", "tts", "guard", "embed", "vision", "tool-use"]
    
    func generate(prompt: String) async throws -> String {
        let key = apiKey
        guard !key.isEmpty else {
            throw ProviderError.notConfigured("Groq API key not set. Go to Settings → Providers to add your key.")
        }
        
        let models = try await getAvailableModels(key: key)
        guard !models.isEmpty else {
            throw ProviderError.serviceUnavailable("No Groq models available. Check your API key permissions.")
        }
        
        // Retry with exponential backoff on rate limit
        var lastError: Error?
        for attempt in 0..<3 {
            if attempt > 0 {
                let backoffMs = 3000 * (1 << (attempt - 1))  // 3s, 6s
                try? await Task.sleep(for: .milliseconds(backoffMs))
            }
            
            // On retries after rate limit, try the next model if available
            let modelIndex = min(attempt, models.count - 1)
            let model = models[modelIndex]
            
            do {
                let result = try await callGroq(model: model, prompt: prompt, key: key)
                log.debug("Groq: \(model) returned \(result.count) chars")
                return result
            } catch ProviderError.rateLimited(let msg) {
                lastError = ProviderError.rateLimited(msg)
                log.warn("Groq: \(model) rate limited (attempt \(attempt + 1)/3), backing off...")
                continue
            } catch {
                throw error
            }
        }
        throw lastError ?? ProviderError.serviceUnavailable("Groq rate limit exceeded after retries")
    }
    
    // MARK: - Dynamic Model Discovery
    
    /// Fetches available models from Groq's OpenAI-compatible /models endpoint,
    /// filters for chat-capable models, and sorts by preference. Cached for the session.
    private func getAvailableModels(key: String) async throws -> [String] {
        if let cached = cachedModels { return cached }
        
        let fallback = ["llama-3.3-70b-versatile", "llama-3.1-8b-instant"]
        
        let url = URL(string: "https://api.groq.com/openai/v1/models")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 15
        
        // Wrap in do/catch — network errors should not crash generation
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            log.warn("Groq: ListModels network error (\(error.localizedDescription)), using fallback")
            cachedModels = fallback
            return fallback
        }
        
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            log.warn("Groq: ListModels failed, using fallback model name")
            cachedModels = fallback
            return fallback
        }
        
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let modelList = json["data"] as? [[String: Any]]
        else {
            log.warn("Groq: ListModels parse failed, using fallback model name")
            cachedModels = fallback
            return fallback
        }
        
        // Extract model IDs, filter out non-chat models (whisper, tts, guard, etc.)
        // Also check "active" status if present in the response
        let available = modelList.compactMap { model -> String? in
            guard let id = model["id"] as? String else { return nil }
            // Skip inactive models if the API reports status
            if let active = model["active"] as? Bool, !active { return nil }
            // Skip models not suitable for text generation
            let lower = id.lowercased()
            if skipPatterns.contains(where: { lower.contains($0) }) { return nil }
            return id
        }
        
        // If filtering removed everything, use fallback
        guard !available.isEmpty else {
            log.warn("Groq: no chat models found after filtering, using fallback")
            cachedModels = fallback
            return fallback
        }
        
        // Sort by preference: instant (fast) first, then versatile, then preview, then rest
        let sorted = available.sorted { a, b in
            let aLower = a.lowercased()
            let bLower = b.lowercased()
            let aIdx = modelPreference.firstIndex(where: { aLower.contains($0) }) ?? modelPreference.count
            let bIdx = modelPreference.firstIndex(where: { bLower.contains($0) }) ?? modelPreference.count
            return aIdx < bIdx
        }
        
        log.info("Groq: discovered \(sorted.count) models: \(sorted.joined(separator: ", "))")
        cachedModels = sorted
        return sorted
    }
    
    // MARK: - Model Call
    
    private func callGroq(model: String, prompt: String, key: String) async throws -> String {
        let url = URL(string: "https://api.groq.com/openai/v1/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 60
        
        let body: [String: Any] = [
            "model": model,
            "messages": [["role": "user", "content": prompt]],
            "temperature": 0.7,
            "top_p": 0.9,
            "max_tokens": 1024
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let http = response as? HTTPURLResponse else {
            throw ProviderError.serviceUnavailable("No response from Groq")
        }
        
        if http.statusCode != 200 {
            let errorBody = String(data: data, encoding: .utf8) ?? ""
            switch http.statusCode {
            case 429:
                throw ProviderError.rateLimited("Groq rate limit exceeded. Retrying with backoff...")
            case 503:
                throw ProviderError.rateLimited("Groq model \(model) overloaded. Trying next...")
            case 404:
                // Model removed — invalidate cache and try next
                cachedModels = nil
                throw ProviderError.rateLimited("Groq model \(model) not found. Trying next...")
            case 401, 403:
                throw ProviderError.invalidApiKey
            default:
                throw ProviderError.serviceUnavailable("Groq returned \(http.statusCode): \(errorBody.prefix(200))")
            }
        }
        
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let text = message["content"] as? String
        else { throw ProviderError.parseError("Invalid Groq response") }
        
        // Extract and report token usage for tracking
        if let usage = json["usage"] as? [String: Any],
           let totalTokens = usage["total_tokens"] as? Int {
            NotificationCenter.default.post(
                name: .aiTokensUsed,
                object: nil,
                userInfo: ["tokens": totalTokens, "provider": "groq"]
            )
        }
        
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    func isAvailable() async -> Bool { !apiKey.isEmpty }
}
