import XCTest
@testable import Ark

final class InterviewAssistantEngineTests: XCTestCase {
    func testIsLikelyQuestionDetectsQuestionMark() {
        XCTAssertTrue(InterviewAssistantEngine.isLikelyQuestion("Como funciona o React?"))
    }

    func testIsLikelyQuestionDetectsQuestionPrefix() {
        XCTAssertTrue(InterviewAssistantEngine.isLikelyQuestion("Como você lida com estado global"))
        XCTAssertTrue(InterviewAssistantEngine.isLikelyQuestion("What is your experience with Swift"))
    }

    func testIsLikelyQuestionReturnsFalseForStatements() {
        XCTAssertFalse(InterviewAssistantEngine.isLikelyQuestion("Ok"))
        XCTAssertFalse(InterviewAssistantEngine.isLikelyQuestion("Muito bem"))
    }

    func testShouldTriggerSuggestionForQuestion() {
        XCTAssertTrue(InterviewAssistantEngine.shouldTriggerSuggestion(for: "Como funciona o React?"))
    }

    func testShouldTriggerSuggestionForLongStatement() {
        XCTAssertTrue(InterviewAssistantEngine.shouldTriggerSuggestion(for: "Vamos falar agora sobre a sua experiência"))
    }

    func testShouldNotTriggerSuggestionForShortStatement() {
        XCTAssertFalse(InterviewAssistantEngine.shouldTriggerSuggestion(for: "Ok"))
    }

    func testIsLikelyIncompleteResponseDetectsEllipsis() {
        XCTAssertTrue(InterviewAssistantEngine.isLikelyIncompleteResponse("O React é importante porque..."))
    }

    func testIsLikelyIncompleteResponseDetectsFillers() {
        XCTAssertTrue(InterviewAssistantEngine.isLikelyIncompleteResponse("O React é importante para o ecossistema JavaScript porque an"))
    }

    func testIsLikelyIncompleteResponseDetectsDanglingConnectors() {
        XCTAssertTrue(InterviewAssistantEngine.isLikelyIncompleteResponse("O React é importante para"))
        XCTAssertTrue(InterviewAssistantEngine.isLikelyIncompleteResponse("Eu uso hooks porque"))
    }

    func testIsLikelyIncompleteResponseReturnsFalseForComplete() {
        XCTAssertFalse(InterviewAssistantEngine.isLikelyIncompleteResponse("O React é muito importante no ecossistema."))
    }

    private func makeEntry(
        _ speaker: TranscriptEntry.Speaker,
        _ text: String,
        timestamp: Date = Date()
    ) -> TranscriptEntry {
        TranscriptEntry(speaker: speaker, text: text, timestamp: timestamp)
    }
}
