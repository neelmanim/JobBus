#!/usr/bin/env swift
// Standalone SMTP test: sends an email WITH attachment to MailHog
// This mimics the exact MIME structure from SMTPEmailProvider.swift

import Foundation

// ─── Config ───
let smtpHost = "localhost"
let smtpPort: UInt32 = 1025
let fromEmail = "test@jobbus.local"
let fromName = "JobBus Test"
let toEmail = "recruiter@test.com"
let toName = "Test Recruiter"
let subject = "DRY RUN: Resume Attachment Test"
let textBody = "Hi Test Recruiter,\n\nThis is a dry-run test email from JobBus.\nIt should include a PDF resume attachment.\n\nBest regards,\nJobBus Test Script"

// ─── Find resume ───
let resumePath: String
let appSupportResume = NSHomeDirectory() + "/Library/Application Support/JobBus/resume_attachment.pdf"
let testFileResume = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "TestFiles/Neelmani Resume 2026_Apr.pdf"

if FileManager.default.fileExists(atPath: appSupportResume) {
    resumePath = appSupportResume
    print("✅ Found cached resume: \(appSupportResume)")
} else if FileManager.default.fileExists(atPath: testFileResume) {
    resumePath = testFileResume
    print("✅ Found test resume: \(testFileResume)")
} else {
    print("❌ No resume file found!")
    print("   Checked: \(appSupportResume)")
    print("   Checked: \(testFileResume)")
    exit(1)
}

// ─── Read resume file ───
guard let fileData = try? Data(contentsOf: URL(fileURLWithPath: resumePath)) else {
    print("❌ Failed to read resume file at: \(resumePath)")
    exit(1)
}
print("✅ Resume loaded: \(fileData.count) bytes (\(fileData.count / 1024) KB)")

// ─── Build MIME ───
let boundary = "----JobBus-TEST-\(UUID().uuidString)"
let altBoundary = "----JobBus-Alt-TEST-\(UUID().uuidString)"
let filename = URL(fileURLWithPath: resumePath).lastPathComponent
let base64 = fileData.base64EncodedString(options: .lineLength76Characters)

let dateFormatter = DateFormatter()
dateFormatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
dateFormatter.locale = Locale(identifier: "en_US_POSIX")
let dateStr = dateFormatter.string(from: Date())

var mime = ""
mime += "From: \(fromName) <\(fromEmail)>\r\n"
mime += "To: \(toName) <\(toEmail)>\r\n"
mime += "Subject: \(subject)\r\n"
mime += "Date: \(dateStr)\r\n"
mime += "MIME-Version: 1.0\r\n"
mime += "X-Mailer: JobBus/1.0-test\r\n"

// multipart/mixed wraps body + attachment
mime += "Content-Type: multipart/mixed; boundary=\"\(boundary)\"\r\n"
mime += "\r\n"

// Part 1: Email body (alternative — plain + HTML)
mime += "--\(boundary)\r\n"
mime += "Content-Type: multipart/alternative; boundary=\"\(altBoundary)\"\r\n"
mime += "\r\n"

// Plain text
mime += "--\(altBoundary)\r\n"
mime += "Content-Type: text/plain; charset=UTF-8\r\n"
mime += "Content-Transfer-Encoding: quoted-printable\r\n"
mime += "\r\n"
mime += textBody + "\r\n\r\n"

// HTML
let htmlBody = "<html><body><p>" + textBody.replacingOccurrences(of: "\n\n", with: "</p><p>").replacingOccurrences(of: "\n", with: "<br/>") + "</p></body></html>"
mime += "--\(altBoundary)\r\n"
mime += "Content-Type: text/html; charset=UTF-8\r\n"
mime += "Content-Transfer-Encoding: quoted-printable\r\n"
mime += "\r\n"
mime += htmlBody + "\r\n\r\n"

mime += "--\(altBoundary)--\r\n"

// Part 2: File attachment
let ext = URL(fileURLWithPath: resumePath).pathExtension.lowercased()
let mimeType: String
switch ext {
case "pdf": mimeType = "application/pdf"
case "docx": mimeType = "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
default: mimeType = "application/octet-stream"
}

mime += "--\(boundary)\r\n"
mime += "Content-Type: \(mimeType); name=\"\(filename)\"\r\n"
mime += "Content-Disposition: attachment; filename=\"\(filename)\"\r\n"
mime += "Content-Transfer-Encoding: base64\r\n"
mime += "\r\n"
mime += base64 + "\r\n\r\n"
mime += "--\(boundary)--\r\n"

print("✅ MIME built: \(mime.count) chars")
print("   Content-Type: multipart/mixed")
print("   Attachment: \(filename) (\(mimeType))")
print("   Base64 size: \(base64.count) chars")

// ─── SMTP Send ───
print("\n📤 Connecting to \(smtpHost):\(smtpPort)...")

var readStream: Unmanaged<CFReadStream>?
var writeStream: Unmanaged<CFWriteStream>?
CFStreamCreatePairWithSocketToHost(nil, smtpHost as CFString, smtpPort, &readStream, &writeStream)

guard let inputStream = readStream?.takeRetainedValue() as InputStream?,
      let outputStream = writeStream?.takeRetainedValue() as OutputStream? else {
    print("❌ Failed to create streams")
    exit(1)
}

inputStream.open()
outputStream.open()

func readResponse() -> String {
    var buffer = [UInt8](repeating: 0, count: 4096)
    Thread.sleep(forTimeInterval: 0.3)
    let bytesRead = inputStream.read(&buffer, maxLength: buffer.count)
    guard bytesRead > 0 else { return "(no response)" }
    return String(bytes: buffer[0..<bytesRead], encoding: .utf8) ?? "(unreadable)"
}

func sendCommand(_ cmd: String) {
    let data = (cmd + "\r\n").data(using: .utf8)!
    data.withUnsafeBytes { ptr in
        if let base = ptr.baseAddress?.assumingMemoryBound(to: UInt8.self) {
            outputStream.write(base, maxLength: data.count)
        }
    }
    let response = readResponse()
    let short = cmd.prefix(60)
    print("   > \(short)... → \(response.trimmingCharacters(in: .whitespacesAndNewlines).prefix(60))")
}

func sendRaw(_ text: String) {
    let data = text.data(using: .utf8)!
    data.withUnsafeBytes { ptr in
        if let base = ptr.baseAddress?.assumingMemoryBound(to: UInt8.self) {
            outputStream.write(base, maxLength: data.count)
        }
    }
}

// Read greeting
let greeting = readResponse()
print("   Server: \(greeting.trimmingCharacters(in: .whitespacesAndNewlines))")

sendCommand("EHLO localhost")
sendCommand("MAIL FROM:<\(fromEmail)>")
sendCommand("RCPT TO:<\(toEmail)>")
sendCommand("DATA")

// Send MIME data
sendRaw(mime + "\r\n.\r\n")
let dataResponse = readResponse()
print("   DATA response: \(dataResponse.trimmingCharacters(in: .whitespacesAndNewlines))")

sendCommand("QUIT")

inputStream.close()
outputStream.close()

print("\n✅ Done! Check MailHog at http://localhost:8025")
print("   Look for email to: \(toEmail)")
print("   Subject: \(subject)")
print("   Click MIME tab to verify attachment")
