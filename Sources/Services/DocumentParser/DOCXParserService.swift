import Foundation
import ZIPFoundation

// MARK: - DOCX Parser
class DOCXParserService {
    
    enum ParserError: LocalizedError {
        case invalidFile
        case noContent
        
        var errorDescription: String? {
            switch self {
            case .invalidFile: return "Unable to read this DOCX file. It may be corrupted."
            case .noContent: return "No text content found in this DOCX file."
            }
        }
    }
    
    func extractText(from url: URL) throws -> String {
        guard let archive = Archive(url: url, accessMode: .read) else {
            throw ParserError.invalidFile
        }
        
        guard let entry = archive["word/document.xml"] else {
            throw ParserError.invalidFile
        }
        
        var xmlData = Data()
        _ = try archive.extract(entry) { chunk in
            xmlData.append(chunk)
        }
        
        let text = extractTextFromWordXML(xmlData)
        guard text.count >= 50 else { throw ParserError.noContent }
        return text
    }
    
    private func extractTextFromWordXML(_ data: Data) -> String {
        guard let xmlString = String(data: data, encoding: .utf8) else { return "" }
        
        // Extract text from <w:t> tags and <w:p> (paragraph) boundaries
        var result = ""
        var inTextTag = false
        var currentText = ""
        var i = xmlString.startIndex
        
        while i < xmlString.endIndex {
            let remaining = xmlString[i...]
            
            if remaining.hasPrefix("<w:t") {
                // Find the end of the opening tag
                if let closeIndex = remaining.firstIndex(of: ">") {
                    i = xmlString.index(after: closeIndex)
                    inTextTag = true
                    continue
                }
            }
            
            if remaining.hasPrefix("</w:t>") {
                inTextTag = false
                result += currentText
                currentText = ""
                i = xmlString.index(i, offsetBy: 6)
                continue
            }
            
            if remaining.hasPrefix("</w:p>") {
                result += "\n"
                i = xmlString.index(i, offsetBy: 6)
                continue
            }
            
            if remaining.hasPrefix("<w:tab/>") || remaining.hasPrefix("<w:tab />") {
                result += "\t"
                i = xmlString.index(i, offsetBy: remaining.hasPrefix("<w:tab/>") ? 8 : 9)
                continue
            }
            
            if inTextTag {
                currentText += String(xmlString[i])
            }
            
            i = xmlString.index(after: i)
        }
        
        // Clean up excessive whitespace while preserving paragraph breaks
        let lines = result.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        
        return lines.joined(separator: "\n")
    }
}
