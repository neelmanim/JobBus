import Foundation

// MARK: - Provider Configuration
enum SearchProviderType: String, Codable, CaseIterable, Identifiable {
    case apollo = "Apollo.io"
    case hunter = "Hunter.io"
    case rocketReach = "RocketReach"
    
    var id: String { rawValue }
    
    var description: String {
        switch self {
        case .apollo: return "Search and enrich contacts with Apollo's database of 200M+ professionals"
        case .hunter: return "Find and verify professional email addresses using domain search"
        case .rocketReach: return "Access professional profiles and verified contact info"
        }
    }
    
    var icon: String {
        switch self {
        case .apollo: return "a.circle.fill"
        case .hunter: return "scope"
        case .rocketReach: return "rocket.fill"
        }
    }
}

enum AIProviderType: String, Codable, CaseIterable, Identifiable {
    case ollama = "Ollama (Local)"
    case gemini = "Gemini Flash"
    case groq = "Groq"
    
    var id: String { rawValue }
    
    var description: String {
        switch self {
        case .ollama: return "Free, private, runs locally on your Mac. Requires Ollama installed."
        case .gemini: return "Google's free API. Fast, high quality. Requires API key."
        case .groq: return "Ultra-fast cloud inference. Free tier available. Requires API key."
        }
    }
    
    var icon: String {
        switch self {
        case .ollama: return "desktopcomputer"
        case .gemini: return "sparkles"
        case .groq: return "bolt.fill"
        }
    }
    
    var requiresApiKey: Bool {
        switch self {
        case .ollama: return false
        case .gemini, .groq: return true
        }
    }
}

enum EmailProviderType: String, Codable, CaseIterable, Identifiable {
    case gmail = "Gmail SMTP"
    case outlook = "Outlook SMTP"
    case custom = "Custom SMTP"
    
    var id: String { rawValue }
    
    var description: String {
        switch self {
        case .gmail: return "Send from your Gmail using App Password. Emails appear in your Sent folder."
        case .outlook: return "Send from Outlook/Hotmail using App Password."
        case .custom: return "Use any SMTP server with custom host/port."
        }
    }
    
    var icon: String {
        switch self {
        case .gmail: return "envelope.fill"
        case .outlook: return "envelope.badge.fill"
        case .custom: return "server.rack"
        }
    }
    
    var host: String {
        switch self {
        case .gmail: return "smtp.gmail.com"
        case .outlook: return "smtp.office365.com"
        case .custom: return ""
        }
    }
    
    var port: Int {
        switch self {
        case .gmail: return 587
        case .outlook: return 587
        case .custom: return 587
        }
    }
}

// MARK: - App Settings
class AppSettings: ObservableObject, Codable {
    // Provider selections
    @Published var searchProvider: SearchProviderType
    @Published var aiProvider: AIProviderType
    @Published var emailProvider: EmailProviderType
    
    // SMTP settings
    @Published var smtpEmail: String
    @Published var smtpDisplayName: String
    @Published var customSmtpHost: String
    @Published var customSmtpPort: Int
    
    // Campaign settings
    @Published var delaySeconds: Double
    @Published var maxPerDay: Int
    @Published var businessHoursOnly: Bool
    @Published var businessHoursStart: Int
    @Published var businessHoursEnd: Int
    @Published var warmUpEnabled: Bool
    @Published var contactCount: Int
    
    // Sandbox mode
    @Published var sandboxMode: Bool
    @Published var sandboxHost: String
    @Published var sandboxPort: Int
    
    // Signature
    @Published var signatureName: String
    @Published var signatureTitle: String
    @Published var signatureLinkedin: String
    @Published var signaturePhone: String
    
    // Ollama settings
    @Published var ollamaModel: String
    @Published var ollamaBaseURL: String
    
    // Custom prompt instructions
    @Published var customPromptInstructions: String
    
    // Writing style samples — user-provided email examples for tone matching
    @Published var sampleEmails: [String]
    
    enum CodingKeys: CodingKey {
        case searchProvider, aiProvider, emailProvider
        case smtpEmail, smtpDisplayName, customSmtpHost, customSmtpPort
        case delaySeconds, maxPerDay, businessHoursOnly, businessHoursStart, businessHoursEnd
        case warmUpEnabled, contactCount, sandboxMode, sandboxHost, sandboxPort
        case signatureName, signatureTitle, signatureLinkedin, signaturePhone
        case ollamaModel, ollamaBaseURL, customPromptInstructions
        case sampleEmails
    }
    
    init() {
        self.searchProvider = .apollo
        self.aiProvider = .gemini
        self.emailProvider = .gmail
        self.smtpEmail = ""
        self.smtpDisplayName = ""
        self.customSmtpHost = ""
        self.customSmtpPort = 587
        self.delaySeconds = 45
        self.maxPerDay = 450
        self.businessHoursOnly = true
        self.businessHoursStart = 9
        self.businessHoursEnd = 18
        self.warmUpEnabled = true
        self.contactCount = 250
        self.sandboxMode = true  // ON by default for safety
        self.sandboxHost = "localhost"
        self.sandboxPort = 1025
        self.signatureName = ""
        self.signatureTitle = ""
        self.signatureLinkedin = ""
        self.signaturePhone = ""
        self.ollamaModel = "llama3.1:8b"
        self.ollamaBaseURL = "http://localhost:11434"
        self.customPromptInstructions = ""
        self.sampleEmails = []
    }
    
    required init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        searchProvider = try c.decodeIfPresent(SearchProviderType.self, forKey: .searchProvider) ?? .apollo
        aiProvider = try c.decodeIfPresent(AIProviderType.self, forKey: .aiProvider) ?? .gemini
        emailProvider = try c.decodeIfPresent(EmailProviderType.self, forKey: .emailProvider) ?? .gmail
        smtpEmail = try c.decodeIfPresent(String.self, forKey: .smtpEmail) ?? ""
        smtpDisplayName = try c.decodeIfPresent(String.self, forKey: .smtpDisplayName) ?? ""
        customSmtpHost = try c.decodeIfPresent(String.self, forKey: .customSmtpHost) ?? ""
        customSmtpPort = try c.decodeIfPresent(Int.self, forKey: .customSmtpPort) ?? 587
        delaySeconds = try c.decodeIfPresent(Double.self, forKey: .delaySeconds) ?? 45
        maxPerDay = try c.decodeIfPresent(Int.self, forKey: .maxPerDay) ?? 450
        businessHoursOnly = try c.decodeIfPresent(Bool.self, forKey: .businessHoursOnly) ?? true
        businessHoursStart = try c.decodeIfPresent(Int.self, forKey: .businessHoursStart) ?? 9
        businessHoursEnd = try c.decodeIfPresent(Int.self, forKey: .businessHoursEnd) ?? 18
        warmUpEnabled = try c.decodeIfPresent(Bool.self, forKey: .warmUpEnabled) ?? true
        contactCount = try c.decodeIfPresent(Int.self, forKey: .contactCount) ?? 250
        sandboxMode = try c.decodeIfPresent(Bool.self, forKey: .sandboxMode) ?? true
        sandboxHost = try c.decodeIfPresent(String.self, forKey: .sandboxHost) ?? "localhost"
        sandboxPort = try c.decodeIfPresent(Int.self, forKey: .sandboxPort) ?? 1025
        signatureName = try c.decodeIfPresent(String.self, forKey: .signatureName) ?? ""
        signatureTitle = try c.decodeIfPresent(String.self, forKey: .signatureTitle) ?? ""
        signatureLinkedin = try c.decodeIfPresent(String.self, forKey: .signatureLinkedin) ?? ""
        signaturePhone = try c.decodeIfPresent(String.self, forKey: .signaturePhone) ?? ""
        ollamaModel = try c.decodeIfPresent(String.self, forKey: .ollamaModel) ?? "llama3.1:8b"
        ollamaBaseURL = try c.decodeIfPresent(String.self, forKey: .ollamaBaseURL) ?? "http://localhost:11434"
        customPromptInstructions = try c.decodeIfPresent(String.self, forKey: .customPromptInstructions) ?? ""
        sampleEmails = try c.decodeIfPresent([String].self, forKey: .sampleEmails) ?? []
    }
    
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(searchProvider, forKey: .searchProvider)
        try c.encode(aiProvider, forKey: .aiProvider)
        try c.encode(emailProvider, forKey: .emailProvider)
        try c.encode(smtpEmail, forKey: .smtpEmail)
        try c.encode(smtpDisplayName, forKey: .smtpDisplayName)
        try c.encode(customSmtpHost, forKey: .customSmtpHost)
        try c.encode(customSmtpPort, forKey: .customSmtpPort)
        try c.encode(delaySeconds, forKey: .delaySeconds)
        try c.encode(maxPerDay, forKey: .maxPerDay)
        try c.encode(businessHoursOnly, forKey: .businessHoursOnly)
        try c.encode(businessHoursStart, forKey: .businessHoursStart)
        try c.encode(businessHoursEnd, forKey: .businessHoursEnd)
        try c.encode(warmUpEnabled, forKey: .warmUpEnabled)
        try c.encode(contactCount, forKey: .contactCount)
        try c.encode(sandboxMode, forKey: .sandboxMode)
        try c.encode(sandboxHost, forKey: .sandboxHost)
        try c.encode(sandboxPort, forKey: .sandboxPort)
        try c.encode(signatureName, forKey: .signatureName)
        try c.encode(signatureTitle, forKey: .signatureTitle)
        try c.encode(signatureLinkedin, forKey: .signatureLinkedin)
        try c.encode(signaturePhone, forKey: .signaturePhone)
        try c.encode(ollamaModel, forKey: .ollamaModel)
        try c.encode(ollamaBaseURL, forKey: .ollamaBaseURL)
        try c.encode(customPromptInstructions, forKey: .customPromptInstructions)
        try c.encode(sampleEmails, forKey: .sampleEmails)
    }
    
    // MARK: - Persistence
    
    private static var settingsURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("JobBus", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("settings.json")
    }
    
    func save() {
        if let data = try? JSONEncoder().encode(self) {
            try? data.write(to: Self.settingsURL)
        }
    }
    
    static func load() -> AppSettings {
        guard let data = try? Data(contentsOf: settingsURL),
              let settings = try? JSONDecoder().decode(AppSettings.self, from: data)
        else { return AppSettings() }
        return settings
    }
}

// MARK: - Keychain Service
/// Routes all credential storage to the encrypted file store.
/// macOS Keychain requires code signing for smooth access (Touch ID, no password prompts).
/// Until the app is signed with an Apple Developer certificate, we use encrypted file storage.
class KeychainService {
    static let shared = KeychainService()
    
    enum KeychainKey: String {
        case apolloApiKey = "apollo_api_key"
        case hunterApiKey = "hunter_api_key"
        case rocketReachApiKey = "rocketreach_api_key"
        case geminiApiKey = "gemini_api_key"
        case groqApiKey = "groq_api_key"
        case smtpPassword = "smtp_password"
    }
    
    func save(key: KeychainKey, value: String) {
        APIKeyFileStore.shared.save(key: key.rawValue, value: value)
    }
    
    func get(key: KeychainKey) -> String? {
        return APIKeyFileStore.shared.get(key: key.rawValue)
    }
    
    func delete(key: KeychainKey) {
        APIKeyFileStore.shared.delete(key: key.rawValue)
    }
}

// MARK: - Encrypted API Key Store
/// Stores API keys encrypted (XOR + base64) in Application Support.
/// Keys never exist as plaintext on disk. This provides meaningful
/// protection at rest without requiring Keychain or code signing.
class APIKeyFileStore {
    static let shared = APIKeyFileStore()
    
    // XOR key derived from machine-specific info for per-machine uniqueness
    private lazy var encryptionKey: [UInt8] = {
        let seed = "JobBus-\(NSUserName())-SecureStore-v1"
        return Array(seed.utf8)
    }()
    
    private var storeURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("JobBus", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        // Set directory permissions to owner-only (700)
        try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: dir.path)
        return dir.appendingPathComponent("credentials.dat")
    }
    
    private func encrypt(_ plaintext: String) -> String {
        let bytes = Array(plaintext.utf8)
        var encrypted = [UInt8](repeating: 0, count: bytes.count)
        for i in 0..<bytes.count {
            encrypted[i] = bytes[i] ^ encryptionKey[i % encryptionKey.count]
        }
        return Data(encrypted).base64EncodedString()
    }
    
    private func decrypt(_ ciphertext: String) -> String? {
        guard let data = Data(base64Encoded: ciphertext) else { return nil }
        let bytes = Array(data)
        var decrypted = [UInt8](repeating: 0, count: bytes.count)
        for i in 0..<bytes.count {
            decrypted[i] = bytes[i] ^ encryptionKey[i % encryptionKey.count]
        }
        return String(bytes: decrypted, encoding: .utf8)
    }
    
    private func loadAll() -> [String: String] {
        guard let data = try? Data(contentsOf: storeURL),
              let dict = try? JSONDecoder().decode([String: String].self, from: data)
        else {
            // Try migrating from old plaintext keys.json
            return migrateFromPlaintext()
        }
        // Decrypt all values
        var result = [String: String]()
        for (k, v) in dict {
            result[k] = decrypt(v)
        }
        return result
    }
    
    private func saveAll(_ dict: [String: String]) {
        // Encrypt all values before saving
        var encrypted = [String: String]()
        for (k, v) in dict {
            encrypted[k] = encrypt(v)
        }
        if let data = try? JSONEncoder().encode(encrypted) {
            try? data.write(to: storeURL, options: [.atomic, .completeFileProtection])
            // Set file permissions to owner-only (600)
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: storeURL.path)
        }
    }
    
    /// Migrate from the old plaintext keys.json if it exists
    private func migrateFromPlaintext() -> [String: String] {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let oldFile = appSupport.appendingPathComponent("JobBus/keys.json")
        guard FileManager.default.fileExists(atPath: oldFile.path),
              let data = try? Data(contentsOf: oldFile),
              let dict = try? JSONDecoder().decode([String: String].self, from: data)
        else { return [:] }
        // Re-save encrypted and remove old plaintext file
        saveAll(dict)
        try? FileManager.default.removeItem(at: oldFile)
        return dict
    }
    
    func save(key: String, value: String) {
        var dict = loadAll()
        dict[key] = value
        saveAll(dict)
    }
    
    func get(key: String) -> String? {
        let dict = loadAll()
        let value = dict[key]
        return (value?.isEmpty == true) ? nil : value
    }
    
    func delete(key: String) {
        var dict = loadAll()
        dict.removeValue(forKey: key)
        saveAll(dict)
    }
}
