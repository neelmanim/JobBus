import Foundation

// MARK: - Resume Profile
struct ResumeProfile: Codable {
    var name: String
    var currentRole: String
    var yearsExperience: Int
    var skills: [String]
    var industries: [String]
    var achievements: [String]
    var education: String
    var emailContext: String
    var linkedinUrl: String
    var phone: String
    var rawText: String
    
    init(
        name: String = "",
        currentRole: String = "",
        yearsExperience: Int = 0,
        skills: [String] = [],
        industries: [String] = [],
        achievements: [String] = [],
        education: String = "",
        emailContext: String = "",
        linkedinUrl: String = "",
        phone: String = "",
        rawText: String = ""
    ) {
        self.name = name
        self.currentRole = currentRole
        self.yearsExperience = yearsExperience
        self.skills = skills
        self.industries = industries
        self.achievements = achievements
        self.education = education
        self.emailContext = emailContext
        self.linkedinUrl = linkedinUrl
        self.phone = phone
        self.rawText = rawText
    }
}

// MARK: - Search Strategy
struct SearchStrategy: Codable {
    var targetTitles: [String]
    var targetSeniorities: [String]
    var companySizes: [String]
    var industries: [String]
    var locations: [String]
    var locationMode: LocationSearchMode
    var keywords: [String]
    
    init(
        targetTitles: [String] = ["Technical Recruiter", "Engineering Manager", "VP Engineering", "CTO"],
        targetSeniorities: [String] = ["manager", "director", "vp", "c_suite"],
        companySizes: [String] = ["51,200", "201,1000"],
        industries: [String] = [],
        locations: [String] = ["United States"],
        locationMode: LocationSearchMode = .companyHQ,
        keywords: [String] = []
    ) {
        self.targetTitles = targetTitles
        self.targetSeniorities = targetSeniorities
        self.companySizes = companySizes
        self.industries = industries
        self.locations = locations
        self.locationMode = locationMode
        self.keywords = keywords
    }
}

enum LocationSearchMode: String, Codable, CaseIterable {
    case personLocation = "Person Location"
    case companyHQ = "Company HQ"
    case both = "Both"
}
