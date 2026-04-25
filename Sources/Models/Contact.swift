import Foundation

// MARK: - Contact Source
enum ContactSource: String, Codable, CaseIterable {
    case apollo = "Apollo"
    case hunter = "Hunter.io"
    case rocketReach = "RocketReach"
    case csv = "CSV Import"
    case manual = "Manual Entry"
    
    var icon: String {
        switch self {
        case .apollo: return "magnifyingglass.circle.fill"
        case .hunter: return "target"
        case .rocketReach: return "rocket.fill"
        case .csv: return "doc.text.fill"
        case .manual: return "pencil.circle.fill"
        }
    }
    
    var color: String {
        switch self {
        case .apollo: return "#8b5cf6"
        case .hunter: return "#f97316"
        case .rocketReach: return "#06b6d4"
        case .csv: return "#3b82f6"
        case .manual: return "#10b981"
        }
    }
}

// MARK: - Contact Status
enum ContactStatus: String, Codable {
    case discovered = "Discovered"
    case enriched = "Enriched"
    case imported = "Imported"
    case added = "Added"
    case noEmail = "No Email"
    case failed = "Failed"
}

// MARK: - Recipient Type
enum RecipientType: String, Codable, CaseIterable {
    case recruiter = "Recruiter"
    case hiringManager = "Hiring Manager"
    case engineering = "Engineering Leader"
    case cSuite = "C-Suite"
    case hr = "HR"
    case other = "Other"
    
    var label: String { rawValue }
    
    var writingInstructions: String {
        switch self {
        case .recruiter:
            return """
            HOOK: Reference their recruiting focus area or a recent role they posted. Ask what they're currently prioritizing.
            CONTEXT: Mention your core skill stack in one sentence — make it scannable.
            CREDIBILITY: Use the provided achievement — frame it as a result, not a resume line.
            CTA: "Would you be open to a quick chat if any of this aligns with what you're hiring for?"
            TONE: Professional but approachable. They review hundreds of candidates — be easy to scan.
            MAX WORDS: 120
            """
        case .hiringManager:
            return """
            HOOK: Reference their team's product, a feature launch, or a technical direction. Show you've done research.
            CONTEXT: Connect YOUR experience to THEIR team's specific needs in one line.
            CREDIBILITY: Use the provided achievement — frame it as impact you delivered that's relevant to their team.
            CTA: "Would it make sense to connect briefly about how I could contribute?"
            TONE: Peer-to-peer, knowledgeable. You understand their domain.
            MAX WORDS: 120
            """
        case .engineering:
            return """
            HOOK: Reference a technical challenge relevant to their company's scale or architecture.
            CONTEXT: Show you understand their engineering domain — mention specific tech or problems.
            CREDIBILITY: Use the provided achievement — frame it as a technical win with measurable impact.
            CTA: "I'd welcome a conversation about the technical challenges your team is tackling."
            TONE: Technical and confident, not salesy. Speak their language.
            MAX WORDS: 100
            """
        case .cSuite:
            return """
            HOOK: Reference a strategic initiative, market move, or company milestone. Be concise.
            CONTEXT: One line connecting your expertise to their business priorities.
            CREDIBILITY: Use the provided achievement — frame it as business impact (revenue, efficiency, scale).
            CTA: "Would a brief intro be worthwhile?"
            TONE: Executive-level, strategic. Maximum brevity.
            MAX WORDS: 80
            """
        case .hr:
            return """
            HOOK: Reference the company culture or a recent company initiative.
            CONTEXT: Mention the type of role you're exploring and why their company interests you.
            CREDIBILITY: Use the provided achievement — frame it to show cultural fit and professionalism.
            CTA: "Could you point me to the right person for these types of opportunities?"
            TONE: Professional and respectful. Clear communication.
            MAX WORDS: 120
            """
        case .other:
            return """
            HOOK: Find a connection point — shared industry, technology, or professional interest.
            CONTEXT: Explain why you're reaching out to THEM specifically.
            CREDIBILITY: Use the provided achievement — frame it as a shared professional interest.
            CTA: "Would you be open to connecting?"
            TONE: Friendly and authentic. This is networking, not a job application.
            MAX WORDS: 120
            """
        }
    }
}

// MARK: - Contact Model
struct Contact: Identifiable, Codable, Hashable {
    let id: UUID
    var firstName: String
    var lastName: String
    var email: String
    var title: String
    var company: String
    var location: String
    var linkedinUrl: String
    var source: ContactSource
    var status: ContactStatus
    var recipientType: RecipientType
    var isSelected: Bool
    var apolloId: String?
    
    // Intelligence layer: contact relevance scoring
    var relevanceScore: Double
    var relevanceReason: String
    
    var fullName: String {
        "\(firstName) \(lastName)".trimmingCharacters(in: .whitespaces)
    }
    
    /// Whether a resume should be attached when emailing this contact
    var shouldAttachResume: Bool {
        switch recipientType {
        case .recruiter, .hiringManager: return true
        case .cSuite: return false
        case .engineering, .hr, .other: return false
        }
    }
    
    init(
        id: UUID = UUID(),
        firstName: String = "",
        lastName: String = "",
        email: String = "",
        title: String = "",
        company: String = "",
        location: String = "",
        linkedinUrl: String = "",
        source: ContactSource = .manual,
        status: ContactStatus = .added,
        recipientType: RecipientType = .other,
        isSelected: Bool = true,
        apolloId: String? = nil,
        relevanceScore: Double = 0.0,
        relevanceReason: String = ""
    ) {
        self.id = id
        self.firstName = firstName
        self.lastName = lastName
        self.email = email
        self.title = title
        self.company = company
        self.location = location
        self.linkedinUrl = linkedinUrl
        self.source = source
        self.status = status
        self.recipientType = recipientType
        self.isSelected = isSelected
        self.apolloId = apolloId
        self.relevanceScore = relevanceScore
        self.relevanceReason = relevanceReason
    }
}
