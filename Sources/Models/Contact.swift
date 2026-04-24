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
            Write a warm, professional email. Recruiters review hundreds of candidates — make it easy to scan.
            Lead with your strongest skill match, mention specific technologies, and keep it under 120 words.
            Tone: Professional but approachable. They're used to inbound interest.
            CTA: "Would you be open to a quick chat if any of this aligns with what you're hiring for?"
            """
        case .hiringManager:
            return """
            Write a value-focused email. Hiring managers care about what you can DO for their team.
            Reference their team's product/tech stack specifically. Lead with a relevant achievement with numbers.
            Tone: Peer-to-peer, knowledgeable. Show you understand their domain.
            CTA: "Would it make sense to connect briefly about how I could contribute?"
            """
        case .engineering:
            return """
            Write a technically credible email. Engineering leaders (VP/Director) think about architecture and scale.
            Reference a technical challenge relevant to their company. Share a concrete result you achieved.
            Tone: Technical and confident, not salesy. Speak their language.
            CTA: "I'd welcome a conversation about the technical challenges your team is tackling."
            """
        case .cSuite:
            return """
            Write a concise, high-impact email. C-level executives have 30 seconds to read this.
            Lead with business impact, not technical details. Use numbers: revenue, scale, efficiency.
            Tone: Executive-level, strategic. Maximum 80 words in the body.
            CTA: "Would a brief intro be worthwhile?"
            """
        case .hr:
            return """
            Write a polite, structured email. HR professionals appreciate clear communication.
            Mention the role type you're interested in and your key qualifications.
            Tone: Professional and respectful. Reference company culture if possible.
            CTA: "Could you point me to the right person for [role type] opportunities?"
            """
        case .other:
            return """
            Write a professional networking email. Keep it genuine and concise.
            Find a connection point — shared industry, technology, or professional interest.
            Tone: Friendly and authentic. This isn't a job application, it's networking.
            CTA: "Would you be open to connecting?"
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
    
    var fullName: String {
        "\(firstName) \(lastName)".trimmingCharacters(in: .whitespaces)
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
        apolloId: String? = nil
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
    }
}
