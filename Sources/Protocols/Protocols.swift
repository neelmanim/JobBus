import Foundation

// MARK: - Contact Search Provider Protocol
/// Implement this protocol to add a new contact search provider (Apollo, Hunter, etc.)
protocol ContactSearchProvider {
    var name: String { get }
    var providerType: SearchProviderType { get }
    
    /// Search for people matching the given strategy
    func search(strategy: SearchStrategy, count: Int) async throws -> [Contact]
    
    /// Validate the API key
    func validateKey(_ key: String) async throws -> Bool
}

// MARK: - Email Enrichment Provider Protocol
/// Implement this protocol to add a new enrichment provider
protocol EmailEnrichmentProvider {
    var name: String { get }
    
    /// Enrich a contact to get their verified email address
    func enrich(contact: Contact) async throws -> Contact
    
    /// Batch enrich multiple contacts
    func enrichBatch(contacts: [Contact], progress: @escaping (Int, Int) -> Void) async throws -> [Contact]
}

// MARK: - AI Provider Protocol
/// Implement this protocol to add a new AI/LLM provider (Ollama, Gemini, Groq, etc.)
protocol AIProvider {
    var name: String { get }
    var providerType: AIProviderType { get }
    
    /// Generate text from a prompt
    func generate(prompt: String) async throws -> String
    
    /// Check if the provider is available and configured
    func isAvailable() async -> Bool
}

// MARK: - Email Sender Provider Protocol
/// Implement this protocol to add a new email sending method (Gmail SMTP, SendGrid, etc.)
protocol EmailSenderProvider {
    var name: String { get }
    var providerType: EmailProviderType { get }
    
    /// Send a single email
    func send(
        to: String,
        toName: String,
        from: String,
        fromName: String,
        subject: String,
        textBody: String,
        htmlBody: String
    ) async throws -> SendResult
    
    /// Test the connection/credentials
    func testConnection() async throws -> Bool
}

// MARK: - Send Result
struct SendResult {
    let success: Bool
    let smtpResponse: String
    let errorMessage: String?
    
    static func success(response: String = "250 OK") -> SendResult {
        SendResult(success: true, smtpResponse: response, errorMessage: nil)
    }
    
    static func failure(error: String) -> SendResult {
        SendResult(success: false, smtpResponse: "", errorMessage: error)
    }
}

// MARK: - Provider Errors
enum ProviderError: LocalizedError {
    case invalidApiKey
    case rateLimited(String)
    case creditsExhausted
    case networkError(String)
    case parseError(String)
    case notConfigured(String)
    case authenticationFailed
    case serviceUnavailable(String)
    case unknown(String)
    
    var errorDescription: String? {
        switch self {
        case .invalidApiKey: return "Invalid API key. Please check and re-enter."
        case .rateLimited(let msg): return "Rate limited: \(msg)"
        case .creditsExhausted: return "API credits exhausted. Please add more credits or switch provider."
        case .networkError(let msg): return "Network error: \(msg)"
        case .parseError(let msg): return "Failed to parse response: \(msg)"
        case .notConfigured(let msg): return "Not configured: \(msg)"
        case .authenticationFailed: return "Authentication failed. Please check your credentials."
        case .serviceUnavailable(let msg): return "Service unavailable: \(msg)"
        case .unknown(let msg): return "Unknown error: \(msg)"
        }
    }
}
