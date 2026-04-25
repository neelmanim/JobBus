import Foundation
import Network

// MARK: - SMTP Email Provider (Gmail/Outlook/Custom)
class SMTPEmailProvider: EmailSenderProvider {
    let name: String
    let providerType: EmailProviderType
    let host: String
    let port: Int
    
    private var password: String { KeychainService.shared.get(key: .smtpPassword) ?? "" }
    
    private var isLocalhost: Bool {
        host == "localhost" || host == "127.0.0.1" || host == "0.0.0.0"
    }
    
    init(providerType: EmailProviderType, customHost: String = "", customPort: Int = 587) {
        self.providerType = providerType
        self.name = providerType.rawValue
        self.host = customHost.isEmpty ? providerType.host : customHost
        self.port = customPort == 587 ? providerType.port : customPort
    }
    
    func send(to: String, toName: String, from: String, fromName: String,
              subject: String, textBody: String, htmlBody: String) async throws -> SendResult {
        // For localhost/MailHog: no password required
        if !isLocalhost {
            guard !password.isEmpty else { throw ProviderError.notConfigured("SMTP password not set. Go to Settings → Email to add your password.") }
        }
        guard !from.isEmpty else { throw ProviderError.notConfigured("Sender email not set. Go to Settings → Email to set your email address.") }
        
        return try await withCheckedThrowingContinuation { continuation in
            let queue = DispatchQueue(label: "smtp.send")
            queue.async {
                do {
                    let smtp = SMTPClient(host: self.host, port: self.port)
                    try smtp.connect()
                    
                    // Skip TLS for localhost (MailHog / test servers)
                    if !self.isLocalhost {
                        try smtp.startTLS()
                    }
                    
                    // Skip auth for servers that don't need it (MailHog)
                    if !self.password.isEmpty {
                        try smtp.authenticate(user: from, password: self.password)
                    }
                    
                    let mime = self.buildMIME(
                        from: from, fromName: fromName,
                        to: to, toName: toName,
                        subject: subject, textBody: textBody, htmlBody: htmlBody
                    )
                    try smtp.sendMail(from: from, to: to, data: mime)
                    smtp.quit()
                    continuation.resume(returning: SendResult.success())
                } catch {
                    continuation.resume(returning: SendResult.failure(error: error.localizedDescription))
                }
            }
        }
    }
    
    func testConnection() async throws -> Bool {
        let result = try await send(
            to: "", toName: "", from: "", fromName: "",
            subject: "", textBody: "", htmlBody: ""
        )
        return result.success
    }
    
    // MARK: - MIME Builder (table-based HTML that won't break)
    
    private func buildMIME(from: String, fromName: String, to: String, toName: String,
                           subject: String, textBody: String, htmlBody: String) -> String {
        let boundary = "----JobBus-\(UUID().uuidString)"
        let date = DateFormatter.rfc2822.string(from: Date())
        
        var mime = ""
        mime += "From: \(fromName) <\(from)>\r\n"
        mime += "To: \(toName) <\(to)>\r\n"
        mime += "Subject: \(subject)\r\n"
        mime += "Date: \(date)\r\n"
        mime += "MIME-Version: 1.0\r\n"
        mime += "Content-Type: multipart/alternative; boundary=\"\(boundary)\"\r\n"
        mime += "X-Mailer: JobBus/1.0\r\n"
        mime += "\r\n"
        
        // Plain text part
        mime += "--\(boundary)\r\n"
        mime += "Content-Type: text/plain; charset=UTF-8\r\n"
        mime += "Content-Transfer-Encoding: quoted-printable\r\n"
        mime += "\r\n"
        mime += textBody + "\r\n"
        mime += "\r\n"
        
        // HTML part — table-based, inline CSS, won't break in any client
        mime += "--\(boundary)\r\n"
        mime += "Content-Type: text/html; charset=UTF-8\r\n"
        mime += "Content-Transfer-Encoding: quoted-printable\r\n"
        mime += "\r\n"
        mime += htmlBody + "\r\n"
        mime += "\r\n"
        
        mime += "--\(boundary)--\r\n"
        return mime
    }
}

// MARK: - HTML Email Template Builder
struct EmailTemplateBuilder {
    
    /// Convert plain text email body to table-based HTML that renders perfectly everywhere
    static func buildHTML(body: String, signature: EmailSignature) -> String {
        let paragraphs = body.components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        
        let bodyHTML = paragraphs.map { para in
            let lines = para.components(separatedBy: "\n").joined(separator: "<br/>")
            return "<p style=\"margin:0 0 16px 0;font-size:15px;line-height:1.6;color:#333333;\">\(lines)</p>"
        }.joined(separator: "\n")
        
        var sigHTML = ""
        if !signature.name.isEmpty {
            sigHTML += "<p style=\"margin:16px 0 0 0;font-size:15px;color:#333333;\">Best regards,<br/>"
            sigHTML += "<strong>\(signature.name)</strong>"
            if !signature.title.isEmpty { sigHTML += "<br/><span style=\"color:#666666;font-size:13px;\">\(signature.title)</span>" }
            if !signature.linkedin.isEmpty { sigHTML += "<br/><a href=\"\(signature.linkedin)\" style=\"color:#0066cc;font-size:13px;text-decoration:none;\">LinkedIn Profile</a>" }
            if !signature.phone.isEmpty { sigHTML += "<br/><span style=\"color:#666666;font-size:13px;\">\(signature.phone)</span>" }
            sigHTML += "</p>"
        }
        
        return """
        <!DOCTYPE html>
        <html>
        <head><meta charset="UTF-8"><meta name="viewport" content="width=device-width,initial-scale=1.0"></head>
        <body style="margin:0;padding:0;background-color:#ffffff;">
        <table width="100%" cellpadding="0" cellspacing="0" border="0" style="max-width:600px;margin:0 auto;font-family:Arial,Helvetica,sans-serif;">
        <tr><td style="padding:24px 16px;">
        \(bodyHTML)
        \(sigHTML)
        </td></tr>
        </table>
        </body>
        </html>
        """
    }
}

struct EmailSignature {
    let name: String
    let title: String
    let linkedin: String
    let phone: String
}

// MARK: - Minimal SMTP Client (using raw sockets)
class SMTPClient {
    private var inputStream: InputStream?
    private var outputStream: OutputStream?
    private let host: String
    private let port: Int
    
    init(host: String, port: Int) {
        self.host = host
        self.port = port
    }
    
    func connect() throws {
        var readStream: Unmanaged<CFReadStream>?
        var writeStream: Unmanaged<CFWriteStream>?
        CFStreamCreatePairWithSocketToHost(nil, host as CFString, UInt32(port), &readStream, &writeStream)
        inputStream = readStream?.takeRetainedValue()
        outputStream = writeStream?.takeRetainedValue()
        inputStream?.open()
        outputStream?.open()
        _ = try readResponse() // Read greeting
        try sendCommand("EHLO localhost")
    }
    
    func startTLS() throws {
        try sendCommand("STARTTLS")
        inputStream?.setProperty(StreamSocketSecurityLevel.negotiatedSSL, forKey: .socketSecurityLevelKey)
        outputStream?.setProperty(StreamSocketSecurityLevel.negotiatedSSL, forKey: .socketSecurityLevelKey)
        try sendCommand("EHLO localhost")
    }
    
    func authenticate(user: String, password: String) throws {
        try sendCommand("AUTH LOGIN")
        try sendCommand(Data(user.utf8).base64EncodedString())
        try sendCommand(Data(password.utf8).base64EncodedString())
    }
    
    func sendMail(from: String, to: String, data: String) throws {
        try sendCommand("MAIL FROM:<\(from)>")
        try sendCommand("RCPT TO:<\(to)>")
        try sendCommand("DATA")
        try sendRaw(data + "\r\n.\r\n")
        _ = try readResponse()
    }
    
    func quit() {
        try? sendCommand("QUIT")
        inputStream?.close()
        outputStream?.close()
    }
    
    @discardableResult
    private func sendCommand(_ command: String) throws -> String {
        try sendRaw(command + "\r\n")
        return try readResponse()
    }
    
    private func sendRaw(_ text: String) throws {
        guard let data = text.data(using: .utf8) else { return }
        data.withUnsafeBytes { ptr in
            if let base = ptr.baseAddress?.assumingMemoryBound(to: UInt8.self) {
                outputStream?.write(base, maxLength: data.count)
            }
        }
    }
    
    private func readResponse() throws -> String {
        var buffer = [UInt8](repeating: 0, count: 4096)
        Thread.sleep(forTimeInterval: 0.3) // Wait for response
        let bytesRead = inputStream?.read(&buffer, maxLength: buffer.count) ?? 0
        guard bytesRead > 0 else { throw ProviderError.networkError("No response from SMTP server") }
        return String(bytes: buffer[0..<bytesRead], encoding: .utf8) ?? ""
    }
}

// MARK: - Date Formatter Extension
extension DateFormatter {
    static let rfc2822: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()
}
