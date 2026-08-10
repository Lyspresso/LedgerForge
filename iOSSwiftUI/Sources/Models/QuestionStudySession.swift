import AccountingQuestionKit
import Foundation
import Observation

struct PartReviewState: Equatable, Sendable {
    var gradeResult: GradeResult?
    var isSolutionVisible = false
    var isRubricVisible = false
}

enum StudyAdvancePolicy {
    static func needsSelfReview(_ status: GradeStatus?) -> Bool {
        status == .needsSelfReview
    }

    static func canAdvance(
        gradeStatus: GradeStatus?,
        selfReviewComplete: Bool
    ) -> Bool {
        guard let gradeStatus, gradeStatus != .unanswered else { return false }
        return !needsSelfReview(gradeStatus) || selfReviewComplete
    }
}

@MainActor
@Observable
final class QuestionStudySession {
    var currentPartIndex = 0
    var isScenarioPresented = false
    private(set) var didChooseInitialPart = false
    private(set) var reviewStates: [String: PartReviewState] = [:]
    private(set) var successFeedbackCount = 0
    private(set) var warningFeedbackCount = 0
    private(set) var selectionFeedbackCount = 0

    func reviewState(for partID: String) -> PartReviewState {
        reviewStates[partID] ?? PartReviewState()
    }

    func recordGrade(_ result: GradeResult, partID: String) {
        var state = reviewState(for: partID)
        state.gradeResult = result
        reviewStates[partID] = state

        switch result.status {
        case .correct:
            successFeedbackCount += 1
        case .incorrect, .unanswered:
            warningFeedbackCount += 1
        case .needsSelfReview:
            selectionFeedbackCount += 1
        }
    }

    func invalidateGrade(partID: String) {
        guard reviewStates[partID]?.gradeResult != nil else { return }
        reviewStates[partID]?.gradeResult = nil
    }

    func revealSolution(partID: String) {
        reviewStates[partID, default: PartReviewState()].isSolutionVisible = true
        selectionFeedbackCount += 1
    }

    func revealRubric(partID: String) {
        reviewStates[partID, default: PartReviewState()].isRubricVisible = true
        selectionFeedbackCount += 1
    }

    func move(to index: Int) {
        currentPartIndex = index
        selectionFeedbackCount += 1
    }

    func chooseInitialPart(_ index: Int, partCount: Int) {
        guard !didChooseInitialPart else { return }
        didChooseInitialPart = true
        guard partCount > 0 else {
            currentPartIndex = 0
            return
        }
        currentPartIndex = min(max(index, 0), partCount - 1)
    }
}
