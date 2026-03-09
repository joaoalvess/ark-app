import XCTest
@testable import Ark

final class InterviewAssistantEngineTests: XCTestCase {
    func testInterviewerQuestionBuildsAnswerQuestionContext() {
        let entries = [
            makeEntry(.interviewer, "Como funciona o React?")
        ]

        let context = InterviewAssistantEngine.makeContext(from: entries, trigger: .interviewerEntry)

        XCTAssertEqual(context?.mode, .answerQuestion)
        XCTAssertEqual(context?.interviewerPrompt, "Como funciona o React?")
        XCTAssertEqual(context?.candidateResponse, "")
    }

    func testIncompleteCandidateResponseBuildsContinuationContext() {
        let entries = [
            makeEntry(.interviewer, "Como funciona o React?"),
            makeEntry(.me, "O React é importante para o ecossistema JavaScript porque an")
        ]

        let context = InterviewAssistantEngine.makeContext(from: entries, trigger: .candidateSilence)

        XCTAssertEqual(context?.mode, .continueCandidate)
        XCTAssertTrue(context?.candidateResponseLikelyIncomplete ?? false)
        XCTAssertEqual(context?.latestCandidateSegment, "O React é importante para o ecossistema JavaScript porque an")
    }

    func testStateLocksWhenCandidateStartsSpeaking() {
        let turnID = UUID()

        let nextState = InterviewAssistantEngine.stateAfterCandidateSpeech(
            currentState: .live(turnID: turnID),
            turnID: turnID
        )

        XCTAssertEqual(nextState, .locked(turnID: turnID))
    }

    func testSilenceDoesNotRefreshWhileSuggestionIsStillLive() {
        let turnID = UUID()
        let context = InterviewTurnContext(
            turnID: turnID,
            interviewerPrompt: "Me explica closures em Swift",
            candidateResponse: "Closures são blocos de código que você pode passar",
            latestCandidateSegment: "Closures são blocos de código que você pode passar",
            mode: .continueCandidate,
            candidateResponseLikelyIncomplete: true
        )

        let shouldRefresh = InterviewAssistantEngine.shouldRequestSuggestionAfterCandidateSilence(
            currentState: .live(turnID: turnID),
            context: context
        )

        XCTAssertFalse(shouldRefresh)
    }

    func testSilenceRefreshesWhenSuggestionIsLockedAndAnswerIsIncomplete() {
        let turnID = UUID()
        let context = InterviewTurnContext(
            turnID: turnID,
            interviewerPrompt: "Me explica closures em Swift",
            candidateResponse: "Closures são blocos de código que você pode passar",
            latestCandidateSegment: "Closures são blocos de código que você pode passar",
            mode: .continueCandidate,
            candidateResponseLikelyIncomplete: true
        )

        let shouldRefresh = InterviewAssistantEngine.shouldRequestSuggestionAfterCandidateSilence(
            currentState: .locked(turnID: turnID),
            context: context
        )

        XCTAssertTrue(shouldRefresh)
    }

    func testNewQuestionCreatesANewTurnIdentifier() {
        let firstQuestion = makeEntry(.interviewer, "Como funciona o React?")
        let entries = [
            firstQuestion,
            makeEntry(.me, "O React é importante"),
            makeEntry(.interviewer, "E como você lida com estado global?")
        ]

        let context = InterviewAssistantEngine.makeContext(from: entries, trigger: .interviewerEntry)

        XCTAssertNotNil(context)
        XCTAssertNotEqual(context?.turnID, firstQuestion.id)
        XCTAssertEqual(context?.interviewerPrompt, "E como você lida com estado global?")
    }

    private func makeEntry(
        _ speaker: TranscriptEntry.Speaker,
        _ text: String,
        timestamp: Date = Date()
    ) -> TranscriptEntry {
        TranscriptEntry(speaker: speaker, text: text, timestamp: timestamp)
    }
}
