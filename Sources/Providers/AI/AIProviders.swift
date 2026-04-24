import Foundation

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
        request.timeoutInterval = 120
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
    
    func generate(prompt: String) async throws -> String {
        guard !apiKey.isEmpty else { throw ProviderError.notConfigured("Gemini API key not set") }
        let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent?key=\(apiKey)")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30
        let body: [String: Any] = [
            "contents": [["parts": [["text": prompt]]]],
            "generationConfig": ["temperature": 0.7, "topP": 0.9, "maxOutputTokens": 1024]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw ProviderError.invalidApiKey
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
