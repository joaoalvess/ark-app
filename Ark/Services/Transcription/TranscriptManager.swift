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

    func formattedTranscript(within interval: TimeInterval) -> String {
        entries(within: interval).map(\.formatted).joined(separator: "\n")
    }

    func entries(within interval: TimeInterval) -> [TranscriptEntry] {
        let cutoff = Date().addingTimeInterval(-interval)
        return entries.filter { $0.timestamp >= cutoff }
    }

    var lastInterviewerEntry: TranscriptEntry? {
        entries.last { $0.speaker == .interviewer }
    }

    var lastCandidateEntry: TranscriptEntry? {
        entries.last { $0.speaker == .me }
    }

    @discardableResult
    func addEntry(
        speaker: TranscriptEntry.Speaker,
        text: String,
        timestamp: Date = Date()
    ) -> TranscriptEntry {
        let entry = TranscriptEntry(speaker: speaker, text: text, timestamp: timestamp)
        entries.append(entry)
        trimOldEntries()
        return entry
    }

    @discardableResult
    func upsertLiveEntry(
        id: UUID?,
        speaker: TranscriptEntry.Speaker,
        text: String,
        timestamp: Date = Date()
    ) -> TranscriptEntry {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else {
            return TranscriptEntry(id: id ?? UUID(), speaker: speaker, text: "", timestamp: timestamp)
        }

        if let id, let index = entries.firstIndex(where: { $0.id == id }) {
            let mergedText = TranscriptEntry.mergeText(existing: entries[index].text, incoming: trimmedText)
            let updated = TranscriptEntry(id: id, speaker: speaker, text: mergedText, timestamp: timestamp)
            entries[index] = updated
            trimOldEntries()
            return updated
        }

        let entry = TranscriptEntry(id: id ?? UUID(), speaker: speaker, text: trimmedText, timestamp: timestamp)
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
