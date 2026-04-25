import Foundation

// MARK: - Campaign Intelligence
/// Pre-send campaign analysis: quality scoring, risk detection, and actionable suggestions.
/// Gives users confidence (or appropriate caution) before launching a campaign.
struct CampaignIntelligence {
    
    let qualityScore: Int         // 0-100
    let riskIndicators: [Risk]
    let suggestions: [Suggestion]
    let breakdown: Breakdown
    
    // MARK: - Risk Types
    
    struct Risk: Identifiable {
        let id = UUID()
        let level: RiskLevel
        let title: String
        let detail: String
    }
    
    enum RiskLevel: String {
        case high = "High"
        case medium = "Medium"
        case low = "Low"
        
        var icon: String {
            switch self {
            case .high: return "exclamationmark.triangle.fill"
            case .medium: return "exclamationmark.circle.fill"
            case .low: return "info.circle.fill"
            }
        }
        
        var colorHex: String {
            switch self {
            case .high: return "#ef4444"
            case .medium: return "#f59e0b"
            case .low: return "#3b82f6"
            }
        }
    }
    
    struct Suggestion: Identifiable {
        let id = UUID()
        let text: String
        let icon: String
    }
    
    struct Breakdown {
        let avgDraftQuality: Double    // 0-11 scale
        let avgRelevanceScore: Double  // 0-1 scale
        let resumeAttachCount: Int
        let linkOnlyCount: Int
        let totalApproved: Int
    }
    
    // MARK: - Analyze Campaign
    
    /// Analyze a campaign before launch. Returns a quality score (0-100),
    /// risk indicators, and actionable suggestions.
    static func analyze(
        drafts: [EmailDraft],
        contacts: [Contact],
        settings: AppSettings,
        resumeFileURL: URL?
    ) -> CampaignIntelligence {
        
        let approved = drafts.filter { $0.status == .approved }
        guard !approved.isEmpty else {
            return CampaignIntelligence(
                qualityScore: 0,
                riskIndicators: [Risk(level: .high, title: "No Approved Emails", detail: "Go back to Compose and approve at least one draft.")],
                suggestions: [],
                breakdown: Breakdown(avgDraftQuality: 0, avgRelevanceScore: 0, resumeAttachCount: 0, linkOnlyCount: 0, totalApproved: 0)
            )
        }
        
        var risks: [Risk] = []
        var suggestions: [Suggestion] = []
        
        // ── Draft Quality ──
        let avgQuality = Double(approved.reduce(0) { $0 + $1.qualityScore.score }) / Double(approved.count)
        let poorDrafts = approved.filter { $0.qualityScore.grade == .poor }.count
        let fairDrafts = approved.filter { $0.qualityScore.grade == .fair }.count
        
        if poorDrafts > 0 {
            risks.append(Risk(level: .high, title: "Poor Quality Drafts",
                            detail: "\(poorDrafts) email(s) scored 'Poor' — consider regenerating them."))
        }
        if fairDrafts > approved.count / 2 {
            risks.append(Risk(level: .medium, title: "Many Fair-Quality Drafts",
                            detail: "\(fairDrafts)/\(approved.count) emails scored only 'Fair'. Review and edit them for better results."))
        }
        
        // ── Contact Relevance ──
        let contactsWithDrafts = contacts.filter { c in approved.contains(where: { $0.contactId == c.id }) }
        let avgRelevance = contactsWithDrafts.isEmpty ? 0.0 :
            contactsWithDrafts.reduce(0.0) { $0 + $1.relevanceScore } / Double(contactsWithDrafts.count)
        
        let lowRelevanceCount = contactsWithDrafts.filter { $0.relevanceScore < 0.3 }.count
        if lowRelevanceCount > approved.count / 3 {
            suggestions.append(Suggestion(
                text: "\(lowRelevanceCount) contact(s) have low relevance to your profile. Consider prioritizing higher-relevance contacts.",
                icon: "person.fill.questionmark"
            ))
        }
        
        // ── Configuration Safety ──
        if settings.smtpEmail.isEmpty {
            risks.append(Risk(level: .high, title: "No Sender Email",
                            detail: "SMTP email not configured. Go to Settings → Email."))
        }
        
        if !settings.sandboxMode && KeychainService.shared.get(key: .smtpPassword)?.isEmpty ?? true {
            risks.append(Risk(level: .high, title: "No SMTP Password",
                            detail: "SMTP password not set. Go to Settings → Email."))
        }
        
        // ── Volume Risks ──
        if approved.count > 20 && !settings.sandboxMode {
            risks.append(Risk(level: .medium, title: "Large Campaign",
                            detail: "Sending \(approved.count) emails in one batch. Consider splitting into smaller batches for better deliverability."))
        }
        
        if approved.count > settings.maxPerDay {
            risks.append(Risk(level: .high, title: "Exceeds Daily Limit",
                            detail: "Campaign has \(approved.count) emails but daily limit is \(settings.maxPerDay). Some emails won't be sent today."))
        }
        
        // ── C-Suite volume warning ──
        let cSuiteCount = contactsWithDrafts.filter { $0.recipientType == .cSuite }.count
        if cSuiteCount > approved.count / 2 {
            suggestions.append(Suggestion(
                text: "\(cSuiteCount)/\(approved.count) recipients are C-level. C-suite emails have lower response rates — consider adding more recruiters/managers.",
                icon: "person.crop.circle.badge.exclamationmark"
            ))
        }
        
        // ── Missing company info ──
        let noCompany = contactsWithDrafts.filter { $0.company.isEmpty }.count
        if noCompany > 0 {
            suggestions.append(Suggestion(
                text: "\(noCompany) contact(s) have no company info — emails may lack personalization.",
                icon: "building.2"
            ))
        }
        
        // ── Resume attachment ──
        let resumeAttachCount = approved.filter { $0.shouldAttachResume }.count
        let linkOnlyCount = approved.count - resumeAttachCount
        
        if resumeAttachCount > 0 && resumeFileURL == nil {
            risks.append(Risk(level: .medium, title: "No Resume File",
                            detail: "\(resumeAttachCount) email(s) are set to attach resume, but no resume file is loaded."))
        }
        
        // ── First campaign suggestion ──
        if approved.count > 10 {
            suggestions.append(Suggestion(
                text: "For your first campaign, consider sending to 5-10 contacts first to verify deliverability.",
                icon: "arrow.up.right.circle"
            ))
        }
        
        // ── Calculate overall quality score (0-100) ──
        let draftScore = (avgQuality / 11.0) * 40      // 40% weight: draft quality
        let relevanceScore = avgRelevance * 25           // 25% weight: contact relevance
        let configScore = configurationScore(settings: settings) * 20 // 20% weight: config safety
        let volumeScore = volumeScore(count: approved.count) * 15    // 15% weight: batch size
        let overall = Int(min(draftScore + relevanceScore + configScore + volumeScore, 100))
        
        let breakdown = Breakdown(
            avgDraftQuality: avgQuality,
            avgRelevanceScore: avgRelevance,
            resumeAttachCount: resumeAttachCount,
            linkOnlyCount: linkOnlyCount,
            totalApproved: approved.count
        )
        
        return CampaignIntelligence(
            qualityScore: overall,
            riskIndicators: risks.sorted { riskOrder($0.level) < riskOrder($1.level) },
            suggestions: suggestions,
            breakdown: breakdown
        )
    }
    
    // MARK: - Helpers
    
    private static func configurationScore(settings: AppSettings) -> Double {
        var score = 1.0
        if settings.smtpEmail.isEmpty { score -= 0.4 }
        if !settings.sandboxMode && (KeychainService.shared.get(key: .smtpPassword)?.isEmpty ?? true) { score -= 0.3 }
        if !settings.businessHoursOnly { score -= 0.1 }
        if settings.delaySeconds < 30 { score -= 0.1 }
        return max(0, score)
    }
    
    private static func volumeScore(count: Int) -> Double {
        if count <= 10 { return 1.0 }
        if count <= 25 { return 0.8 }
        if count <= 50 { return 0.5 }
        return 0.3
    }
    
    private static func riskOrder(_ level: RiskLevel) -> Int {
        switch level {
        case .high: return 0
        case .medium: return 1
        case .low: return 2
        }
    }
}
