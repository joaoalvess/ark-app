import Foundation

/// Legacy placeholder kept while the app moves from automatic CoreAudio routing
/// to the guided Multi-Output setup flow.
final class AggregateDeviceManager: @unchecked Sendable {
    func cleanup() {}
    func restoreIfNeeded() {}
}
