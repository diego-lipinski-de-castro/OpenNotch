import Foundation

enum Debug {
    static let enabled = ProcessInfo.processInfo.environment["OPENNOTCH_DEBUG"] == "1"
}
