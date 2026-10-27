import OSLog

enum AppLog {
    static let lifecycle = Logger(subsystem: "com.huanqiu.FileCompare", category: "lifecycle")
    static let comparison = Logger(subsystem: "com.huanqiu.FileCompare", category: "comparison")
}
