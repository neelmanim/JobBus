import Foundation

// MARK: - Email Draft
struct EmailDraft: Identifiable, Codable {
    let id: UUID
    var contactId: UUID
    var recipientName: String
    var recipientEmail: String
    var recipientCompany: String
    var recipientTitle: String
    var recipientType: RecipientType
    var subject: String
    var body: String
    var htmlBody: String
    var qualityScore: EmailQualityScore
    var status: DraftStatus
    var regenerateCount: Int
    
    // Intelligence: which achievement was used in this email (for rotation)
    var usedAchievement: String?
    // Whether resume should be attached (based on recipient type)
    var shouldAttachResume: Bool
    
    init(
        id: UUID = UUID(),
        contactId: UUID,
        recipientName: String = "",
        recipientEmail: String = "",
        recipientCompany: String = "",
        recipientTitle: String = "",
        recipientType: RecipientType = .other,
        subject: String = "",
        body: String = "",
        htmlBody: String = "",
        qualityScore: EmailQualityScore = EmailQualityScore(),
        status: DraftStatus = .pending,
        regenerateCount: Int = 0,
        usedAchievement: String? = nil,
        shouldAttachResume: Bool = false
    ) {
        self.id = id
        self.contactId = contactId
        self.recipientName = recipientName
        self.recipientEmail = recipientEmail
        self.recipientCompany = recipientCompany
        self.recipientTitle = recipientTitle
        self.recipientType = recipientType
        self.subject = subject
        self.body = body
        self.htmlBody = htmlBody
        self.qualityScore = qualityScore
        self.status = status
        self.regenerateCount = regenerateCount
        self.usedAchievement = usedAchievement
        self.shouldAttachResume = shouldAttachResume
    }
}

enum DraftStatus: String, Codable {
    case pending = "Pending"
    case generating = "Generating"
    case review = "Needs Review"
    case approved = "Approved"
    case rejected = "Rejected"
    case sent = "Sent"
    case failed = "Failed"
}

// MARK: - Email Quality Score
struct EmailQualityScore: Codable {
    var nameMatch: Bool
    var companyMatch: Bool
    var lengthOK: Bool
    var subjectLengthOK: Bool
    var noPlaceholders: Bool
    var noSpamWords: Bool
    var hasCTA: Bool
    var toneMatch: Bool
    // New quality dimensions (Tier 2)
    var hookPresent: Bool
    var singleAchievement: Bool
    var noGenericOpening: Bool
    
    init(
        nameMatch: Bool = false,
        companyMatch: Bool = false,
        lengthOK: Bool = false,
        subjectLengthOK: Bool = false,
        noPlaceholders: Bool = false,
        noSpamWords: Bool = false,
        hasCTA: Bool = false,
        toneMatch: Bool = false,
        hookPresent: Bool = false,
        singleAchievement: Bool = false,
        noGenericOpening: Bool = false
    ) {
        self.nameMatch = nameMatch
        self.companyMatch = companyMatch
        self.lengthOK = lengthOK
        self.subjectLengthOK = subjectLengthOK
        self.noPlaceholders = noPlaceholders
        self.noSpamWords = noSpamWords
        self.hasCTA = hasCTA
        self.toneMatch = toneMatch
        self.hookPresent = hookPresent
        self.singleAchievement = singleAchievement
        self.noGenericOpening = noGenericOpening
    }
    
    var score: Int {
        [nameMatch, companyMatch, lengthOK, subjectLengthOK,
         noPlaceholders, noSpamWords, hasCTA, toneMatch,
         hookPresent, singleAchievement, noGenericOpening]
            .filter { $0 }.count
    }
    
    var grade: QualityGrade {
        switch score {
        case 9...11: return .excellent
        case 7...8: return .good
        case 5...6: return .fair
        default: return .poor
        }
    }
}

enum QualityGrade: String, Codable {
    case excellent = "Excellent"
    case good = "Good"
    case fair = "Fair"
    case poor = "Poor"
    
    var icon: String {
        switch self {
        case .excellent: return "checkmark.seal.fill"
        case .good: return "checkmark.circle.fill"
        case .fair: return "exclamationmark.triangle.fill"
        case .poor: return "xmark.octagon.fill"
        }
    }
    
    var colorHex: String {
        switch self {
        case .excellent: return "#10b981"
        case .good: return "#3b82f6"
        case .fair: return "#f59e0b"
        case .poor: return "#ef4444"
        }
    }
}

// MARK: - Send Record
struct SendRecord: Identifiable, Codable {
    let id: UUID
    var draftId: UUID
    var recipientEmail: String
    var recipientName: String
    var subject: String
    var sentAt: Date?
    var status: SendStatus
    var errorMessage: String?
    var smtpResponse: String?
    
    init(
        id: UUID = UUID(),
        draftId: UUID,
        recipientEmail: String = "",
        recipientName: String = "",
        subject: String = "",
        sentAt: Date? = nil,
        status: SendStatus = .queued,
        errorMessage: String? = nil,
        smtpResponse: String? = nil
    ) {
        self.id = id
        self.draftId = draftId
        self.recipientEmail = recipientEmail
        self.recipientName = recipientName
        self.subject = subject
        self.sentAt = sentAt
        self.status = status
        self.errorMessage = errorMessage
        self.smtpResponse = smtpResponse
    }
}

enum SendStatus: String, Codable {
    case queued = "Queued"
    case sending = "Sending"
    case sent = "Sent"
    case failed = "Failed"
    case bounced = "Bounced"
    case skipped = "Skipped"
}

// MARK: - Campaign Status
enum CampaignStatus: String, Codable {
    case idle = "Idle"
    case running = "Running"
    case paused = "Paused"
    case stopped = "Stopped"
    case complete = "Complete"
}
