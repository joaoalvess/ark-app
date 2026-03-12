import Foundation
import Observation

@Observable
final class TranscriptManager {
    private(set) var entries: [TranscriptEntry] = []

    var formattedTranscript: String {
        entries.map(\.formatted).joined(separator: "\n")
    }

    var recentTranscript: String {
        let recent = entries.suffix(20)
        return recent.map(\.formatted).joined(separator: "\n")
    }

    var lastInterviewerEntry: TranscriptEntry? {
        entries.last { $0.speaker == .interviewer }
    }

    var lastCandidateEntry: TranscriptEntry? {
        entries.last { $0.speaker == .me }
    }

    @discardableResult
    func addEntry(speaker: TranscriptEntry.Speaker, text: String) -> TranscriptEntry {
        let entry = TranscriptEntry(speaker: speaker, text: text, timestamp: Date())
        entries.append(entry)
        trimOldEntries()
        return entry
    }

    func clear() {
        entries.removeAll()
    }

    private func trimOldEntries() {
        let cutoff = Date().addingTimeInterval(-Constants.transcriptMaxDuration)
        entries.removeAll { $0.timestamp < cutoff }
    }

}
