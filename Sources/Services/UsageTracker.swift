import Foundation

// MARK: - Usage Stats (Cumulative, Persisted)
/// Tracks cumulative API usage across sessions. Persisted to disk in the JobBus app support directory.
struct UsageStats: Codable {
    var apolloCreditsUsed: Int = 0
    var apolloSearches: Int = 0
    var groqTokensUsed: Int = 0
    var groqCalls: Int = 0
    var lastResetDate: Date? = nil
    
    mutating func addApolloCredits(_ count: Int) {
        apolloCreditsUsed += max(0, count)
    }
    
    mutating func addApolloSearch() {
        apolloSearches += 1
    }
    
    mutating func addGroqTokens(_ count: Int) {
        groqTokensUsed += max(0, count)
        groqCalls += 1
    }
    
    mutating func reset() {
        apolloCreditsUsed = 0
        apolloSearches = 0
        groqTokensUsed = 0
        groqCalls = 0
        lastResetDate = Date()
    }
    
    /// Human-readable token count (e.g. "2.1K", "156")
    var groqTokensFormatted: String {
        if groqTokensUsed >= 1_000_000 {
            return String(format: "%.1fM", Double(groqTokensUsed) / 1_000_000)
        } else if groqTokensUsed >= 1_000 {
            return String(format: "%.1fK", Double(groqTokensUsed) / 1_000)
        } else {
            return "\(groqTokensUsed)"
        }
    }
}

// MARK: - Usage Tracker (Persistence Manager)
@MainActor
class UsageTracker: ObservableObject {
    @Published var stats: UsageStats
    
    private static var fileURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("JobBus", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("usage_stats.json")
    }
    
    init() {
        if let data = try? Data(contentsOf: Self.fileURL),
           let loaded = try? JSONDecoder().decode(UsageStats.self, from: data) {
            self.stats = loaded
        } else {
            self.stats = UsageStats()
        }
    }
    
    func addApolloCredits(_ count: Int) {
        stats.addApolloCredits(count)
        save()
    }
    
    func addApolloSearch() {
        stats.addApolloSearch()
        save()
    }
    
    func addGroqTokens(_ count: Int) {
        stats.addGroqTokens(count)
        save()
    }
    
    func reset() {
        stats.reset()
        save()
    }
    
    private func save() {
        let url = Self.fileURL
        Task.detached(priority: .utility) {
            let stats = await self.stats
            if let data = try? JSONEncoder().encode(stats) {
                try? data.write(to: url, options: .atomic)
            }
        }
    }
}
