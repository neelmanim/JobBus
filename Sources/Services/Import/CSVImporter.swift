import Foundation

// MARK: - CSV Importer
class CSVImporter {
    
    static let nameVariants = ["name", "full name", "full_name", "first name", "first_name", "contact", "contact name"]
    static let lastNameVariants = ["last name", "last_name", "surname", "family name"]
    static let emailVariants = ["email", "e-mail", "email address", "email_address", "mail", "e_mail"]
    static let companyVariants = ["company", "organization", "org", "employer", "company name", "organisation"]
    static let titleVariants = ["title", "job title", "job_title", "role", "position", "designation"]
    static let locationVariants = ["location", "city", "country", "region", "address"]
    
    struct ColumnMapping {
        var nameColumn: Int?
        var lastNameColumn: Int?
        var emailColumn: Int?
        var companyColumn: Int?
        var titleColumn: Int?
        var locationColumn: Int?
    }
    
    struct ImportResult {
        let contacts: [Contact]
        let totalRows: Int
        let skippedRows: Int
        let mapping: ColumnMapping
        let headers: [String]
    }
    
    func parseCSV(from url: URL) throws -> ImportResult {
        // Try multiple encodings
        let content: String
        if let utf8 = try? String(contentsOf: url, encoding: .utf8) {
            content = utf8
        } else if let latin1 = try? String(contentsOf: url, encoding: .isoLatin1) {
            content = latin1
        } else {
            throw NSError(domain: "CSVImporter", code: 1,
                         userInfo: [NSLocalizedDescriptionKey: "Unable to read CSV file. Unsupported encoding."])
        }
        
        // Detect delimiter
        let delimiter = detectDelimiter(content)
        let rows = parseRows(content, delimiter: delimiter)
        
        guard rows.count >= 2 else {
            throw NSError(domain: "CSVImporter", code: 2,
                         userInfo: [NSLocalizedDescriptionKey: "CSV file must have a header row and at least one data row."])
        }
        
        let headers = rows[0].map { $0.lowercased().trimmingCharacters(in: .whitespaces) }
        let mapping = autoDetectColumns(headers: headers)
        
        guard mapping.emailColumn != nil else {
            throw NSError(domain: "CSVImporter", code: 3,
                         userInfo: [NSLocalizedDescriptionKey: "No email column found. CSV must have a column named 'email', 'e-mail', or 'mail'."])
        }
        
        var contacts: [Contact] = []
        var skipped = 0
        
        for row in rows[1...] {
            let email = safeGet(row, at: mapping.emailColumn)
            guard isValidEmail(email) else { skipped += 1; continue }
            
            var firstName = safeGet(row, at: mapping.nameColumn)
            var lastName = safeGet(row, at: mapping.lastNameColumn)
            
            // Handle "Last, First" or "First Last" in name column
            if lastName.isEmpty && firstName.contains(",") {
                let parts = firstName.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                if parts.count >= 2 {
                    lastName = String(parts[0])
                    firstName = String(parts[1])
                }
            } else if lastName.isEmpty && firstName.contains(" ") {
                let parts = firstName.split(separator: " ", maxSplits: 1)
                if parts.count >= 2 {
                    firstName = String(parts[0])
                    lastName = String(parts[1])
                }
            }
            
            contacts.append(Contact(
                firstName: firstName,
                lastName: lastName,
                email: email,
                title: safeGet(row, at: mapping.titleColumn),
                company: safeGet(row, at: mapping.companyColumn),
                location: safeGet(row, at: mapping.locationColumn),
                source: .csv,
                status: .imported
            ))
        }
        
        return ImportResult(
            contacts: contacts,
            totalRows: rows.count - 1,
            skippedRows: skipped,
            mapping: mapping,
            headers: rows[0]
        )
    }
    
    private func detectDelimiter(_ content: String) -> Character {
        let firstLine = content.prefix(while: { $0 != "\n" && $0 != "\r" })
        let commas = firstLine.filter { $0 == "," }.count
        let tabs = firstLine.filter { $0 == "\t" }.count
        let semicolons = firstLine.filter { $0 == ";" }.count
        if tabs > commas && tabs > semicolons { return "\t" }
        if semicolons > commas { return ";" }
        return ","
    }
    
    private func parseRows(_ content: String, delimiter: Character) -> [[String]] {
        let lines = content.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        return lines.map { line in
            // Simple CSV parsing (handles basic quoting)
            var fields: [String] = []
            var current = ""
            var inQuotes = false
            for char in line {
                if char == "\"" { inQuotes.toggle() }
                else if char == delimiter && !inQuotes {
                    fields.append(current.trimmingCharacters(in: .whitespaces))
                    current = ""
                } else { current += String(char) }
            }
            fields.append(current.trimmingCharacters(in: .whitespaces))
            return fields
        }
    }
    
    private func autoDetectColumns(headers: [String]) -> ColumnMapping {
        ColumnMapping(
            nameColumn: headers.firstIndex { Self.nameVariants.contains($0) },
            lastNameColumn: headers.firstIndex { Self.lastNameVariants.contains($0) },
            emailColumn: headers.firstIndex { Self.emailVariants.contains($0) },
            companyColumn: headers.firstIndex { Self.companyVariants.contains($0) },
            titleColumn: headers.firstIndex { Self.titleVariants.contains($0) },
            locationColumn: headers.firstIndex { Self.locationVariants.contains($0) }
        )
    }
    
    private func safeGet(_ row: [String], at index: Int?) -> String {
        guard let i = index, i < row.count else { return "" }
        return row[i].trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    private func isValidEmail(_ email: String) -> Bool {
        let pattern = #"^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$"#
        return email.range(of: pattern, options: .regularExpression) != nil
    }
}
