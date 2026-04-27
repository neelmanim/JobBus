import Foundation

// MARK: - Application Logger
/// Thread-safe logger that writes to both console and rotating log files.
/// Log files are stored in ~/Library/Application Support/JobBus/logs/
/// Each app session creates a new log file with timestamp.
final class AppLogger {
    
    static let shared = AppLogger()
    
    enum Level: String {
        case debug = "DEBUG"
        case info  = "INFO "
        case warn  = "WARN "
        case error = "ERROR"
    }
    
    private let queue = DispatchQueue(label: "com.jobbus.logger", qos: .utility)
    private var fileHandle: FileHandle?
    private var currentLogPath: URL?
    private let dateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "HH:mm:ss.SSS"
        df.locale = Locale(identifier: "en_US_POSIX")
        return df
    }()
    
    private init() {
        setupLogFile()
    }
    
    deinit {
        fileHandle?.closeFile()
    }
    
    // MARK: - Setup
    
    private func setupLogFile() {
        let logsDir = Self.logsDirectory
        try? FileManager.default.createDirectory(at: logsDir, withIntermediateDirectories: true)
        
        // Create log file with session timestamp
        let fileDateFormatter = DateFormatter()
        fileDateFormatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        fileDateFormatter.locale = Locale(identifier: "en_US_POSIX")
        let timestamp = fileDateFormatter.string(from: Date())
        
        let logFile = logsDir.appendingPathComponent("jobbus_\(timestamp).log")
        FileManager.default.createFile(atPath: logFile.path, contents: nil)
        fileHandle = FileHandle(forWritingAtPath: logFile.path)
        currentLogPath = logFile
        
        // Write header
        let appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
        let buildNumber = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "local"
        let header = """
        ═══════════════════════════════════════════════════════
        JobBus Session Log
        Started: \(Date())
        App Version: \(appVersion) (build \(buildNumber))
        OS: \(ProcessInfo.processInfo.operatingSystemVersionString)
        ═══════════════════════════════════════════════════════
        
        """
        fileHandle?.write(header.data(using: .utf8) ?? Data())
        
        // Clean up old logs (keep last 20)
        cleanOldLogs(keep: 20)
    }
    
    // MARK: - Public API
    
    func debug(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(.debug, message, file: file, function: function, line: line)
    }
    
    func info(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(.info, message, file: file, function: function, line: line)
    }
    
    func warn(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(.warn, message, file: file, function: function, line: line)
    }
    
    func error(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(.error, message, file: file, function: function, line: line)
    }
    
    /// Log a section divider for major operations
    func section(_ title: String) {
        let divider = "\n── \(title) ──────────────────────────────────────"
        queue.async { [weak self] in
            guard let self = self else { return }
            let entry = divider + "\n"
            print(entry, terminator: "")
            self.fileHandle?.write(entry.data(using: .utf8) ?? Data())
        }
    }
    
    /// Get the path to the current log file
    var logFilePath: URL? { currentLogPath }
    
    /// Get paths to all log files, newest first
    static var allLogFiles: [URL] {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: logsDirectory, includingPropertiesForKeys: [.creationDateKey],
            options: .skipsHiddenFiles
        ) else { return [] }
        
        return files
            .filter { $0.pathExtension == "log" }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
    }
    
    // MARK: - Private
    
    private func log(_ level: Level, _ message: String, file: String, function: String, line: Int) {
        let timestamp = dateFormatter.string(from: Date())
        let filename = URL(fileURLWithPath: file).deletingPathExtension().lastPathComponent
        let shortFunc = function.components(separatedBy: "(").first ?? function
        
        let entry = "[\(timestamp)] \(level.rawValue) \(filename).\(shortFunc):\(line) │ \(message)\n"
        
        queue.async { [weak self] in
            // Console output
            print(entry, terminator: "")
            // File output
            self?.fileHandle?.write(entry.data(using: .utf8) ?? Data())
        }
    }
    
    private static var logsDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("JobBus/logs", isDirectory: true)
    }
    
    private func cleanOldLogs(keep: Int) {
        let all = Self.allLogFiles
        guard all.count > keep else { return }
        for old in all.dropFirst(keep) {
            try? FileManager.default.removeItem(at: old)
        }
    }
    
    /// Write a session summary at the end of a run
    func writeSummary(contacts: Int, draftsGenerated: Int, draftsFailed: Int,
                      emailsSent: Int, emailsFailed: Int, duration: TimeInterval) {
        let summary = """
        
        ═══════════════════════════════════════════════════════
        SESSION SUMMARY
        ═══════════════════════════════════════════════════════
        Duration:         \(String(format: "%.1f", duration)) seconds
        Contacts loaded:  \(contacts)
        Drafts generated: \(draftsGenerated)
        Drafts failed:    \(draftsFailed)
        Emails sent:      \(emailsSent)
        Emails failed:    \(emailsFailed)
        ═══════════════════════════════════════════════════════
        Log file: \(currentLogPath?.path ?? "unknown")
        
        """
        queue.async { [weak self] in
            print(summary)
            self?.fileHandle?.write(summary.data(using: .utf8) ?? Data())
        }
    }
}

// MARK: - Convenience global function
/// Shorthand for AppLogger.shared
let log = AppLogger.shared
