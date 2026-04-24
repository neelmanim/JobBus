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
        guard String(data: data, encoding: .utf8) != nil else { return "" }
        
        // Use XMLParser for safe, linear-time extraction instead of
        // character-by-character String.Index walking (which is O(n²) on
        // Unicode-correct Swift strings and was the main freeze/crash cause).
        let delegate = WordXMLParserDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.parse()
        
        // Clean up excessive whitespace while preserving paragraph breaks
        let lines = delegate.result
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        
        return lines.joined(separator: "\n")
    }
}

// MARK: - XML Parser Delegate (linear-time, memory-safe)
private class WordXMLParserDelegate: NSObject, XMLParserDelegate {
    var result = ""
    private var inTextTag = false
    private var currentText = ""
    
    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName: String?,
                attributes: [String: String] = [:]) {
        // <w:t> or just <t> depending on namespace handling
        if elementName == "w:t" || elementName == "t" {
            inTextTag = true
            currentText = ""
        } else if elementName == "w:tab" || elementName == "tab" {
            result += "\t"
        } else if elementName == "w:br" || elementName == "br" {
            result += "\n"
        }
    }
    
    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if inTextTag {
            currentText += string
        }
    }
    
    func parser(_ parser: XMLParser, didEndElement elementName: String,
                namespaceURI: String?, qualifiedName: String?) {
        if elementName == "w:t" || elementName == "t" {
            result += currentText
            inTextTag = false
            currentText = ""
        } else if elementName == "w:p" || elementName == "p" {
            result += "\n"
        }
    }
}
