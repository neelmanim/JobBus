import Foundation
import PDFKit

// MARK: - PDF Parser
class PDFParserService {
    
    enum ParserError: LocalizedError {
        case invalidFile
        case emptyContent
        case passwordProtected
        
        var errorDescription: String? {
            switch self {
            case .invalidFile: return "Unable to read this PDF. Try re-saving it or using DOCX format."
            case .emptyContent: return "This appears to be a scanned PDF with no extractable text. Please use a text-based PDF or DOCX."
            case .passwordProtected: return "This PDF is password-protected. Please remove the password and try again."
            }
        }
    }
    
    func extractText(from url: URL) throws -> String {
        guard let document = PDFDocument(url: url) else {
            throw ParserError.invalidFile
        }
        
        if document.isLocked {
            throw ParserError.passwordProtected
        }
        
        var fullText = ""
        for i in 0..<document.pageCount {
            if let page = document.page(at: i), let text = page.string {
                fullText += text + "\n"
            }
        }
        
        let cleaned = fullText.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.count < 50 {
            throw ParserError.emptyContent
        }
        
        return cleaned
    }
}
