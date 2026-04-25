import Foundation

// =============================================================================
// MARK: - Lightweight Test Runner
// =============================================================================

var totalTests = 0
var passedTests = 0
var failedTests = 0

func assertEqual<T: Equatable>(_ a: T, _ b: T, _ msg: String = "", file: String = #file, line: Int = #line) {
    totalTests += 1
    if a == b { passedTests += 1 }
    else { failedTests += 1; print("  ❌ FAIL [\(line)]: \(msg.isEmpty ? "\(a) != \(b)" : msg)") }
}

func assertTrue(_ v: Bool, _ msg: String = "", file: String = #file, line: Int = #line) {
    totalTests += 1
    if v { passedTests += 1 }
    else { failedTests += 1; print("  ❌ FAIL [\(line)]: \(msg.isEmpty ? "Expected true" : msg)") }
}

func assertFalse(_ v: Bool, _ msg: String = "", file: String = #file, line: Int = #line) {
    assertTrue(!v, msg.isEmpty ? "Expected false" : msg, file: file, line: line)
}

func assertNil<T>(_ v: T?, _ msg: String = "", file: String = #file, line: Int = #line) {
    totalTests += 1
    if v == nil { passedTests += 1 }
    else { failedTests += 1; print("  ❌ FAIL [\(line)]: \(msg.isEmpty ? "Expected nil, got \(v!)" : msg)") }
}

func runSuite(_ name: String, _ block: () -> Void) {
    print("\n🧪 \(name)")
    block()
}

// =============================================================================
// MARK: - Quality Scorer Logic
// =============================================================================

struct QS {
    static let spamWords = ["act now","guaranteed","click here","free money","no obligation","limited time","congratulations","winner","urgent","buy now","dear sir","dear madam","dear sir/madam","to whom it may concern","best price","order now","special offer"]
    static let placeholders = ["{{","}}","[first_name]","[last_name]","[company]","[Company]","[Name]","[COMPANY]","[NAME]","INSERT","PLACEHOLDER","[TODO]","XXX"]
    static let weakPhrases = ["i hope this email finds you well","i am writing to express my interest","i would be a great fit","please find attached my resume","as per my resume","i look forward to hearing from you","i am a highly motivated professional"]
    
    static func score(body: String, subject: String, firstName: String, company: String) -> (Int, [String]) {
        let bl = body.lowercased(), sl = subject.lowercased(), wc = body.split(separator: " ").count
        var checks: [(Bool, String)] = []
        checks.append((firstName.isEmpty || bl.contains(firstName.lowercased()), "nameMatch"))
        checks.append((company.isEmpty || bl.contains(company.lowercased()) || sl.contains(company.lowercased()), "companyMatch"))
        checks.append((wc >= 30 && wc <= 250, "lengthOK"))
        checks.append((subject.count >= 5 && subject.count <= 100, "subjectLengthOK"))
        checks.append((!placeholders.contains { bl.contains($0.lowercased()) || sl.contains($0.lowercased()) }, "noPlaceholders"))
        checks.append((!spamWords.contains { bl.contains($0) || sl.contains($0) }, "noSpamWords"))
        let cta = ["would you be open","would it make sense","would a brief","could we","can we","would you like","interested in","happy to chat","open to","connect","conversation","grab a coffee","quick call","15 minutes","brief chat"]
        checks.append((cta.contains { bl.contains($0) }, "hasCTA"))
        checks.append((!weakPhrases.contains { bl.contains($0) }, "toneMatch"))
        let passed = checks.filter { $0.0 }.count
        let failed = checks.filter { !$0.0 }.map { $0.1 }
        return (passed, failed)
    }
    
    static func grade(_ score: Int) -> String {
        switch score { case 7...8: return "Excellent"; case 5...6: return "Good"; case 3...4: return "Fair"; default: return "Poor" }
    }
}

// =============================================================================
// MARK: - Email Response Parser Logic
// =============================================================================

struct EP {
    static func parse(_ response: String) -> (subject: String, body: String) {
        let text = response.trimmingCharacters(in: .whitespacesAndNewlines)
        var subject = "", body = ""
        if let sr = text.range(of: "SUBJECT:", options: .caseInsensitive) ?? text.range(of: "**Subject:**", options: .caseInsensitive) {
            let after = text[sr.upperBound...]
            if let br = after.range(of: "BODY:", options: .caseInsensitive) ?? after.range(of: "**Body:**", options: .caseInsensitive) {
                subject = String(after[..<br.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                body = String(after[br.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            } else {
                let lines = String(after).components(separatedBy: "\n")
                subject = lines.first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                body = lines.dropFirst().joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        if subject.isEmpty && body.isEmpty {
            let lines = text.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
            if lines.count >= 2 { subject = lines[0]; body = lines.dropFirst().joined(separator: "\n") }
            else if lines.count == 1 { subject = "Introduction"; body = lines[0] }
        }
        if body.isEmpty && text.count > 30 { body = text; if subject.isEmpty { subject = "Introduction" } }
        subject = subject.replacingOccurrences(of: "**", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
        return (subject, body)
    }
}

// =============================================================================
// MARK: - CSV Helpers
// =============================================================================

struct CSV {
    static let emailVars = ["email","e-mail","email address","email_address","mail","e_mail"]
    static let nameVars = ["name","full name","full_name","first name","first_name","contact","contact name"]
    
    static func detectEmailCol(_ h: [String]) -> Int? { h.map { $0.lowercased().trimmingCharacters(in: .whitespaces) }.firstIndex { emailVars.contains($0) } }
    static func detectNameCol(_ h: [String]) -> Int? { h.map { $0.lowercased().trimmingCharacters(in: .whitespaces) }.firstIndex { nameVars.contains($0) } }
    
    static func detectDelimiter(_ line: String) -> Character {
        let c = line.filter { $0 == "," }.count, t = line.filter { $0 == "\t" }.count, s = line.filter { $0 == ";" }.count
        if t > c && t > s { return "\t" }; if s > c { return ";" }; return ","
    }
    
    static func isValidEmail(_ e: String) -> Bool { e.range(of: #"^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$"#, options: .regularExpression) != nil }
    
    static func parseName(_ n: String) -> (String, String) {
        if n.contains(",") { let p = n.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }; if p.count >= 2 { return (p[1], p[0]) } }
        else if n.contains(" ") { let p = n.split(separator: " ", maxSplits: 1); if p.count >= 2 { return (String(p[0]), String(p[1])) } }
        return (n, "")
    }
}

// Duplicate detector
struct DD {
    static func dedup(_ emails: [String]) -> (unique: [String], dups: Int) {
        var seen = Set<String>(); var u: [String] = []; var d = 0
        for e in emails { let k = e.lowercased(); if k.isEmpty { u.append(e); continue }; if seen.contains(k) { d += 1 } else { seen.insert(k); u.append(e) } }
        return (u, d)
    }
}

// =============================================================================
// MARK: - RUN ALL TESTS
// =============================================================================

print("═══════════════════════════════════════════")
print("  JobBus Unit Tests")
print("═══════════════════════════════════════════")

// --- Quality Scorer ---
runSuite("QualityScorer — Perfect Score") {
    let (s, fails) = QS.score(body: "Sarah, I noticed Acme Corp is scaling its platform team. With 8 years building distributed systems and having reduced API latency by 40% at my current role, I think there could be a strong fit. Would you be open to a quick call to discuss?", subject: "Quick question about Acme Corp engineering", firstName: "Sarah", company: "Acme Corp")
    assertEqual(s, 8, "Perfect email should score 8/8")
    assertEqual(QS.grade(s), "Excellent")
    assertTrue(fails.isEmpty, "No checks should fail")
}

runSuite("QualityScorer — Spam Detection") {
    let (s, fails) = QS.score(body: "John, this is a guaranteed opportunity. Click here to learn more. " + String(repeating: "word ", count: 30), subject: "Act now", firstName: "John", company: "")
    assertTrue(fails.contains("noSpamWords"), "Should detect spam")
    assertTrue(s < 8)
}

runSuite("QualityScorer — Placeholder Detection") {
    let (_, fails) = QS.score(body: "Jane, I'd love to work at [Company]. I have {{exp}} years. " + String(repeating: "word ", count: 30), subject: "Hello", firstName: "Jane", company: "TestCo")
    assertTrue(fails.contains("noPlaceholders"), "Should detect placeholders")
}

runSuite("QualityScorer — Weak Phrases") {
    let (_, fails) = QS.score(body: "Bob, I hope this email finds you well. I am a highly motivated professional. " + String(repeating: "word ", count: 30), subject: "Hello Bob", firstName: "Bob", company: "")
    assertTrue(fails.contains("toneMatch"), "Should detect weak phrases")
}

runSuite("QualityScorer — Empty Company Passes") {
    let (_, fails) = QS.score(body: "Alice, " + String(repeating: "word ", count: 35) + " Would you be open to a quick call?", subject: "Hello from me", firstName: "Alice", company: "")
    assertFalse(fails.contains("companyMatch"), "Empty company should auto-pass")
}

runSuite("QualityScorer — Body Too Short") {
    let (_, fails) = QS.score(body: "X, short.", subject: "Hello", firstName: "X", company: "")
    assertTrue(fails.contains("lengthOK"), "Short body should fail")
}

runSuite("QualityScorer — Subject Too Short") {
    let (_, fails) = QS.score(body: String(repeating: "word ", count: 40), subject: "Hi", firstName: "", company: "")
    assertTrue(fails.contains("subjectLengthOK"), "Short subject should fail")
}

// --- Grade Boundaries ---
runSuite("Grade Boundaries") {
    assertEqual(QS.grade(8), "Excellent"); assertEqual(QS.grade(7), "Excellent")
    assertEqual(QS.grade(6), "Good"); assertEqual(QS.grade(5), "Good")
    assertEqual(QS.grade(4), "Fair"); assertEqual(QS.grade(3), "Fair")
    assertEqual(QS.grade(2), "Poor"); assertEqual(QS.grade(0), "Poor")
}

// --- CTA Detection ---
runSuite("CTA Detection") {
    let (_, f1) = QS.score(body: String(repeating: "word ", count: 35) + "Would you be open to a quick call?", subject: "Hello there", firstName: "", company: "")
    assertFalse(f1.contains("hasCTA"), "Should detect CTA")
    let (_, f2) = QS.score(body: String(repeating: "word ", count: 35) + "Thanks for reading.", subject: "Hello there", firstName: "", company: "")
    assertTrue(f2.contains("hasCTA"), "Should fail without CTA")
}

// --- Duplicate Detector ---
runSuite("DuplicateDetector — Basic") {
    let (u, d) = DD.dedup(["a@x.com", "b@x.com", "a@x.com"])
    assertEqual(u.count, 2); assertEqual(d, 1)
}

runSuite("DuplicateDetector — Case Insensitive") {
    let (u, d) = DD.dedup(["A@X.com", "a@x.com"])
    assertEqual(u.count, 1); assertEqual(d, 1)
}

runSuite("DuplicateDetector — Empty Emails Kept") {
    let (u, _) = DD.dedup(["", "", "a@x.com"])
    assertEqual(u.count, 3, "Empty emails should not be deduped")
}

runSuite("DuplicateDetector — No Duplicates") {
    let (u, d) = DD.dedup(["a@x.com", "b@x.com", "c@x.com"])
    assertEqual(u.count, 3); assertEqual(d, 0)
}

// --- Email Parser ---
runSuite("EmailParser — Standard SUBJECT/BODY") {
    let (s, b) = EP.parse("SUBJECT: Hello from me\n\nBODY:\nHi Sarah, this is a test.")
    assertEqual(s, "Hello from me")
    assertTrue(b.contains("Hi Sarah"))
}

runSuite("EmailParser — Case Insensitive") {
    let (s, b) = EP.parse("subject: My Subject\n\nbody:\nThe content here.")
    assertEqual(s, "My Subject")
    assertTrue(b.contains("content"))
}

runSuite("EmailParser — Markdown Markers") {
    let (s, b) = EP.parse("**Subject:** Bold Subject\n\n**Body:**\nFormatted body.")
    assertEqual(s, "Bold Subject")
    assertTrue(b.contains("Formatted"))
}

runSuite("EmailParser — No Markers Fallback") {
    let (s, b) = EP.parse("First Line Subject\nThis is the body without any markers.")
    assertEqual(s, "First Line Subject")
    assertTrue(b.contains("body without"))
}

runSuite("EmailParser — Single Long Line") {
    let long = String(repeating: "This is a long response without structure. ", count: 3)
    let (s, b) = EP.parse(long)
    assertEqual(s, "Introduction")
    assertFalse(b.isEmpty)
}

// --- CSV Detection ---
runSuite("CSV — Email Column Detection") {
    assertEqual(CSV.detectEmailCol(["Name", "Email", "Company"]), 1)
    assertEqual(CSV.detectEmailCol(["name", "e-mail", "org"]), 1)
    assertEqual(CSV.detectEmailCol(["name", "mail", "org"]), 1)
    assertNil(CSV.detectEmailCol(["name", "phone", "company"]))
}

runSuite("CSV — Name Column Detection") {
    assertEqual(CSV.detectNameCol(["Full Name", "Email"]), 0)
    assertEqual(CSV.detectNameCol(["email", "first_name", "company"]), 1)
    assertEqual(CSV.detectNameCol(["email", "contact name"]), 1)
}

runSuite("CSV — Delimiter Detection") {
    assertEqual(CSV.detectDelimiter("name,email,company"), Character(","))
    assertEqual(CSV.detectDelimiter("name\temail\tcompany"), Character("\t"))
    assertEqual(CSV.detectDelimiter("name;email;company"), Character(";"))
}

runSuite("CSV — Email Validation") {
    assertTrue(CSV.isValidEmail("user@example.com"))
    assertTrue(CSV.isValidEmail("first.last@company.co.uk"))
    assertFalse(CSV.isValidEmail("notanemail"))
    assertFalse(CSV.isValidEmail("@missing.com"))
    assertFalse(CSV.isValidEmail(""))
}

runSuite("CSV — Name Parsing (First Last)") {
    let (f, l) = CSV.parseName("John Smith")
    assertEqual(f, "John"); assertEqual(l, "Smith")
}

runSuite("CSV — Name Parsing (Last, First)") {
    let (f, l) = CSV.parseName("Smith, John")
    assertEqual(f, "John"); assertEqual(l, "Smith")
}

runSuite("CSV — Name Parsing (Single Name)") {
    let (f, l) = CSV.parseName("Madonna")
    assertEqual(f, "Madonna"); assertEqual(l, "")
}

// =============================================================================
// MARK: - RESULTS
// =============================================================================

print("\n═══════════════════════════════════════════")
if failedTests == 0 {
    print("  ✅ ALL \(totalTests) TESTS PASSED")
} else {
    print("  ❌ \(failedTests)/\(totalTests) TESTS FAILED")
}
print("  📊 \(passedTests) passed, \(failedTests) failed, \(totalTests) total")
print("═══════════════════════════════════════════\n")

exit(failedTests > 0 ? 1 : 0)
