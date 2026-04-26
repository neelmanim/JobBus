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

// MARK: - Gemini Flash AI Provider
class GeminiFlashProvider: AIProvider {
    let name = "Gemini Flash"
    let providerType: AIProviderType = .gemini
    
    private var apiKey: String { KeychainService.shared.get(key: .geminiApiKey) ?? "" }
    
    // Models to try in order (different quota buckets)
    private let models = ["gemini-2.0-flash-lite", "gemini-2.0-flash", "gemini-1.5-flash"]
    
    func generate(prompt: String) async throws -> String {
        guard !apiKey.isEmpty else { throw ProviderError.notConfigured("Gemini API key not set. Go to Settings → Providers to add your key from aistudio.google.com/apikey") }
        
        var lastError: Error?
        log.debug("Gemini: starting generation (\(models.count) models available)")
        
        for model in models {
            do {
                let result = try await callModel(model: model, prompt: prompt)
                log.debug("Gemini: \(model) returned \(result.count) chars")
                return result
            } catch ProviderError.rateLimited(let msg) {
                // Try next model (different quota bucket)
                lastError = ProviderError.rateLimited(msg)
                log.warn("Gemini: \(model) rate limited, trying next...")
                continue
            } catch {
                throw error
            }
        }
        
        throw lastError ?? ProviderError.serviceUnavailable("All Gemini models exhausted")
    }
    
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
        
        // Handle non-200 responses with actual error info
        if http.statusCode != 200 {
            let errorBody = String(data: data, encoding: .utf8) ?? ""
            
            switch http.statusCode {
            case 429:
                throw ProviderError.rateLimited("Gemini quota exceeded for \(model). Retrying with fallback model...")
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

// MARK: - Groq AI Provider
class GroqProvider: AIProvider {
    let name = "Groq"
    let providerType: AIProviderType = .groq
    
    private var apiKey: String { KeychainService.shared.get(key: .groqApiKey) ?? "" }
    
    func generate(prompt: String) async throws -> String {
        let key = apiKey
        guard !key.isEmpty else { throw ProviderError.notConfigured("Groq API key not set. Go to Settings → Providers to add your key.") }
        
        // Retry with exponential backoff on rate limit
        var lastError: Error?
        for attempt in 0..<3 {
            if attempt > 0 {
                let backoffMs = 3000 * (1 << (attempt - 1))  // 3s, 6s
                try? await Task.sleep(for: .milliseconds(backoffMs))
            }
            
            do {
                let result = try await callGroq(prompt: prompt, key: key)
                log.debug("Groq: returned \(result.count) chars")
                return result
            } catch ProviderError.rateLimited(let msg) {
                lastError = ProviderError.rateLimited(msg)
                log.warn("Groq: rate limited (attempt \(attempt + 1)/3), backing off...")
                continue
            } catch {
                throw error
            }
        }
        throw lastError ?? ProviderError.serviceUnavailable("Groq rate limit exceeded after retries")
    }
    
    private func callGroq(prompt: String, key: String) async throws -> String {
        let url = URL(string: "https://api.groq.com/openai/v1/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 60
        
        let body: [String: Any] = [
            "model": "llama-3.1-8b-instant",
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
