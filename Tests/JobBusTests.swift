import Foundation

// ═══════════════════════════════════════════════════════
// Entry point
// ═══════════════════════════════════════════════════════
@main struct TestRunner {
    static var totalTests = 0, passedTests = 0, failedTests = 0
    static var failedNames: [String] = []
    
    static func check(_ c: Bool, _ m: String = "", line: Int = #line) {
        totalTests += 1
        if c { passedTests += 1 } else {
            failedTests += 1; let l = m.isEmpty ? "Fail" : m
            failedNames.append("  ✗ \(l) (line \(line))"); print("  ✗ FAIL: \(l) — line \(line)")
        }
    }
    static func eq<T: Equatable>(_ a: T, _ b: T, _ m: String = "", line: Int = #line) {
        totalTests += 1
        if a == b { passedTests += 1 } else {
            failedTests += 1; let l = m.isEmpty ? "\(a)≠\(b)" : "\(m): \(a)≠\(b)"
            failedNames.append("  ✗ \(l) (line \(line))"); print("  ✗ FAIL: \(l) — line \(line)")
        }
    }
    static func throws_<T>(_ e: @autoclosure () throws -> T, _ m: String = "", line: Int = #line) {
        totalTests += 1
        do { _ = try e(); failedTests += 1; print("  ✗ Expected throw: \(m) — line \(line)") }
        catch { passedTests += 1 }
    }
    static func run(_ name: String, _ b: () throws -> Void) {
        print("\n━━━ \(name) ━━━")
        do { try b() } catch { failedTests += 1; print("  ✗ Crashed: \(error)") }
    }
    
    static func mkC(fn: String="Sarah",ln: String="Johnson",em: String="sarah@google.com",co: String="Google") -> Contact {
        Contact(firstName:fn,lastName:ln,email:em,company:co,source:.manual,status:.added)
    }
    static func mkD(s: String="Quick question about Google's engineering team",
                    b: String="Hi Sarah,\n\nI noticed Google's cloud infrastructure team has been scaling rapidly. Having led a similar initiative at Stripe — migrating 200+ microservices with zero downtime — I'd love to learn more about your team's approach.\n\nWould you be open to a quick chat if any of this aligns with roles you're working on?") -> EmailDraft {
        EmailDraft(contactId:UUID(),subject:s,body:b)
    }
    static func csv(_ c: String) throws -> URL {
        let f = FileManager.default.temporaryDirectory.appendingPathComponent("t_\(UUID().uuidString).csv")
        try c.write(to:f,atomically:true,encoding:.utf8); return f
    }

    static func main() {
        print("╔══════════════════════════════════════════════╗")
        print("║        JobBus Unit Test Suite                ║")
        print("╚══════════════════════════════════════════════╝")
        
        // ── QualityScorer ──
        run("QualityScorer — Perfect email") {
            let s = QualityScorer.score(draft:mkD(),contact:mkC())
            check(s.nameMatch,"Name"); check(s.companyMatch,"Company"); check(s.lengthOK,"Length")
            check(s.subjectLengthOK,"Subject"); check(s.noPlaceholders,"Placeholders")
            check(s.noSpamWords,"Spam"); check(s.hasCTA,"CTA"); check(s.toneMatch,"Tone")
            eq(s.grade,.excellent,"Grade")
        }
        run("QualityScorer — Spam words") {
            let s = QualityScorer.score(draft:mkD(s:"ACT NOW",b:"Hi Sarah, guaranteed at Google. Click here."),contact:mkC())
            check(!s.noSpamWords,"Spam detected")
        }
        run("QualityScorer — Placeholders") {
            let s = QualityScorer.score(draft:mkD(b:"Hi {{name}}, [Company] [TODO]"),contact:mkC())
            check(!s.noPlaceholders,"Placeholder detected")
        }
        run("QualityScorer — Weak phrases") {
            let s = QualityScorer.score(draft:mkD(b:"I hope this email finds you well. I am writing to express my interest at Google. I look forward to hearing from you."),contact:mkC())
            check(!s.toneMatch,"Weak detected")
        }
        run("QualityScorer — Too short") {
            let s = QualityScorer.score(draft:mkD(b:"Hi Sarah, checking in about Google."),contact:mkC())
            check(!s.lengthOK,"Too short")
        }
        run("QualityScorer — Missing name") {
            let s = QualityScorer.score(draft:mkD(b:"Dear Manager, interested in Google roles. Would you be open to a brief chat?"),contact:mkC())
            check(!s.nameMatch,"Name missing")
        }
        run("QualityScorer — Missing company") {
            let s = QualityScorer.score(draft:mkD(s:"Opportunities",b:"Hi Sarah, your team is scaling. Would you be open to a quick chat?"),contact:mkC())
            check(!s.companyMatch,"Company missing")
        }
        run("QualityScorer — Missing CTA") {
            let s = QualityScorer.score(draft:mkD(b:"Hi Sarah, I noticed Google's cloud team is doing amazing work. I built something similar. Thanks."),contact:mkC())
            check(!s.hasCTA,"No CTA")
        }
        run("QualityScorer — Grade boundaries") {
            let e = EmailQualityScore(nameMatch:true,companyMatch:true,lengthOK:true,subjectLengthOK:true,noPlaceholders:true,noSpamWords:true,hasCTA:true,toneMatch:true)
            eq(e.score,8,"8/8"); eq(e.grade,.excellent)
            let g = EmailQualityScore(nameMatch:true,companyMatch:true,lengthOK:true,subjectLengthOK:true,noPlaceholders:true,noSpamWords:true,hasCTA:false,toneMatch:false)
            eq(g.score,6,"6/8"); eq(g.grade,.good)
            let f = EmailQualityScore(nameMatch:true,companyMatch:true,lengthOK:true,subjectLengthOK:true,noPlaceholders:false,noSpamWords:false,hasCTA:false,toneMatch:false)
            eq(f.score,4,"4/8"); eq(f.grade,.fair)
            let p = EmailQualityScore(nameMatch:true,companyMatch:true,lengthOK:false,subjectLengthOK:false,noPlaceholders:false,noSpamWords:false,hasCTA:false,toneMatch:false)
            eq(p.score,2,"2/8"); eq(p.grade,.poor)
        }
        run("QualityScorer — Issues count") {
            eq(QualityScorer.issues(for:EmailQualityScore()).count,8,"8 issues")
        }
        run("QualityScorer — Empty name passes") {
            let s = QualityScorer.score(draft:mkD(b:"Hi, team growing. Would you be open to a quick chat about roles that benefit from cloud experience?"),contact:mkC(fn:"",ln:""))
            check(s.nameMatch,"Empty→pass")
        }
        run("QualityScorer — Empty company passes") {
            let s = QualityScorer.score(draft:mkD(b:"Hi Sarah, your team growing rapidly. Would you be open to a quick chat about opportunities aligning with my background?"),contact:mkC(co:""))
            check(s.companyMatch,"Empty→pass")
        }
        
        // ── DuplicateDetector ──
        run("DuplicateDetector — Exact dupes") {
            let c = [Contact(firstName:"Alice",email:"alice@t.com",source:.manual,status:.added),
                     Contact(firstName:"Copy",email:"alice@t.com",source:.csv,status:.imported),
                     Contact(firstName:"Bob",email:"bob@t.com",source:.manual,status:.added)]
            let (u,d) = DuplicateDetector.removeDuplicates(from:c)
            eq(u.count,2,"Unique"); eq(d.count,1,"Dupes"); eq(u[0].firstName,"Alice","First kept")
        }
        run("DuplicateDetector — Case insensitive") {
            let (u,d) = DuplicateDetector.removeDuplicates(from:[
                Contact(email:"Alice@T.com",source:.manual,status:.added),
                Contact(email:"alice@t.com",source:.csv,status:.imported)])
            eq(u.count,1); eq(d.count,1)
        }
        run("DuplicateDetector — Empty emails kept") {
            let (u,d) = DuplicateDetector.removeDuplicates(from:[
                Contact(firstName:"A",email:"",source:.manual,status:.added),
                Contact(firstName:"B",email:"",source:.manual,status:.added)])
            eq(u.count,2,"Kept"); eq(d.count,0)
        }
        run("DuplicateDetector — Empty input") {
            let (u,d) = DuplicateDetector.removeDuplicates(from:[])
            check(u.isEmpty); check(d.isEmpty)
        }
        
        // ── EmailTemplateBuilder ──
        run("TemplateBuilder — Body+sig") {
            let h = EmailTemplateBuilder.buildHTML(body:"P1.\n\nP2.",signature:EmailSignature(name:"John",title:"Eng",linkedin:"",phone:""))
            check(h.contains("P1."),"P1"); check(h.contains("P2."),"P2"); check(h.contains("<!DOCTYPE html>"),"HTML"); check(h.contains("John"),"Name")
        }
        run("TemplateBuilder — Full sig") {
            let h = EmailTemplateBuilder.buildHTML(body:"Hi.",signature:EmailSignature(name:"Jane",title:"SE",linkedin:"https://li.com",phone:"+1"))
            check(h.contains("Jane")); check(h.contains("LinkedIn Profile")); check(h.contains("+1"))
        }
        run("TemplateBuilder — Empty sig") {
            let h = EmailTemplateBuilder.buildHTML(body:"Hi.",signature:EmailSignature(name:"",title:"",linkedin:"",phone:""))
            check(!h.contains("Best regards,"),"No sig block")
        }
        run("TemplateBuilder — Line breaks") {
            let h = EmailTemplateBuilder.buildHTML(body:"L1\nL2",signature:EmailSignature(name:"",title:"",linkedin:"",phone:""))
            check(h.contains("<br/>"),"br tag")
        }
        
        // ── Contact Model ──
        run("Contact — Full name") { eq(Contact(firstName:"A",lastName:"B",email:"x@t.com").fullName,"A B") }
        run("Contact — Trim") { eq(Contact(firstName:"A",lastName:"",email:"x@t.com").fullName,"A") }
        run("Contact — Empty") { eq(Contact(email:"x@t.com").fullName,"") }
        run("Contact — Defaults") {
            let c = Contact(email:"x@t.com")
            check(c.isSelected,"Selected"); eq(c.source,.manual); eq(c.recipientType,.other)
        }
        
        // ── EmailDraft Model ──
        run("Draft — Defaults") { let d = EmailDraft(contactId:UUID()); eq(d.status,.pending); eq(d.regenerateCount,0) }
        run("QualityScore — Defaults") { let s = EmailQualityScore(); eq(s.score,0); eq(s.grade,.poor) }
        
        // ── CSV Importer ──
        run("CSV — Basic") {
            let url = try csv("name,email,company\nAlice,alice@ex.com,Acme\nBob,bob@ex.com,Corp")
            defer { try? FileManager.default.removeItem(at:url) }
            let r = try CSVImporter().parseCSV(from:url)
            eq(r.contacts.count,2); eq(r.skippedRows,0); eq(r.contacts[0].email,"alice@ex.com"); eq(r.contacts[0].source,.csv)
        }
        run("CSV — Invalid emails") {
            let url = try csv("name,email\nA,a@ex.com\nB,bad\nC,c@\nD,d@ex.com")
            defer { try? FileManager.default.removeItem(at:url) }
            let r = try CSVImporter().parseCSV(from:url)
            eq(r.contacts.count,2,"Valid only"); eq(r.skippedRows,2)
        }
        run("CSV — Email variants") {
            let url = try csv("full name,e-mail,organization\nAlice,a@ex.com,Acme")
            defer { try? FileManager.default.removeItem(at:url) }
            let r = try CSVImporter().parseCSV(from:url)
            eq(r.contacts[0].email,"a@ex.com"); eq(r.contacts[0].company,"Acme")
        }
        run("CSV — Last,First") {
            let url = try csv("name,email\n\"Smith, Alice\",a@ex.com")
            defer { try? FileManager.default.removeItem(at:url) }
            let r = try CSVImporter().parseCSV(from:url)
            eq(r.contacts[0].firstName,"Alice"); eq(r.contacts[0].lastName,"Smith")
        }
        run("CSV — First Last split") {
            let url = try csv("name,email\nAlice Smith,a@ex.com")
            defer { try? FileManager.default.removeItem(at:url) }
            let r = try CSVImporter().parseCSV(from:url)
            eq(r.contacts[0].firstName,"Alice"); eq(r.contacts[0].lastName,"Smith")
        }
        run("CSV — No email col throws") {
            let url = try csv("name,company\nAlice,Acme")
            defer { try? FileManager.default.removeItem(at:url) }
            throws_(try CSVImporter().parseCSV(from:url),"No email col")
        }
        run("CSV — Header-only throws") {
            let url = try csv("name,email")
            defer { try? FileManager.default.removeItem(at:url) }
            throws_(try CSVImporter().parseCSV(from:url),"No data")
        }
        
        // ── Enum Validation ──
        run("RecipientType — Instructions") {
            for t in RecipientType.allCases { check(!t.writingInstructions.isEmpty,"\(t.rawValue)"); check(!t.label.isEmpty) }
        }
        run("ContactSource — Icons/colors") {
            for s in ContactSource.allCases { check(!s.icon.isEmpty,"\(s.rawValue) icon"); check(!s.color.isEmpty) }
        }
        run("SendResult — Factories") {
            let ok = SendResult.success(response:"250 OK"); check(ok.success); check(ok.errorMessage==nil)
            let fail = SendResult.failure(error:"Refused"); check(!fail.success); eq(fail.errorMessage,"Refused")
        }
        
        // ── Results ──
        print("\n╔══════════════════════════════════════════════╗")
        if failedTests == 0 { print("║  ✅ ALL \(totalTests) TESTS PASSED                     ║") }
        else { print("║  ❌ \(failedTests)/\(totalTests) TESTS FAILED                       ║") }
        print("╚══════════════════════════════════════════════╝")
        print("  Total: \(totalTests)  Passed: \(passedTests) ✅  Failed: \(failedTests) ❌")
        if !failedNames.isEmpty { print("\nFailed:"); for n in failedNames { print(n) } }
        if failedTests > 0 { Foundation.exit(1) }
    }
}
