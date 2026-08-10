import SwiftUI

// The deployment target is macOS 14, so this key uses the pre-@Entry form.
private struct ActiveQuestionPartFocusedKey: FocusedValueKey {
    typealias Value = QuestionPartKey
}

extension FocusedValues {
    var activeQuestionPart: QuestionPartKey? {
        get { self[ActiveQuestionPartFocusedKey.self] }
        set { self[ActiveQuestionPartFocusedKey.self] = newValue }
    }
}
