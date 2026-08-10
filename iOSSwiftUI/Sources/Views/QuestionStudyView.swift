import AccountingQuestionKit
import SwiftUI

struct QuestionStudyView: View {
    let question: QuestionScreenModel
    let store: AccountingSuiteStore
    @State private var session = QuestionStudySession()
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        @Bindable var store = store
        @Bindable var session = session

        ZStack {
            StudyBackground()

            if question.parts.indices.contains(session.currentPartIndex) {
                let part = question.parts[session.currentPartIndex]
                let key = AnswerKey(questionID: question.questionID, partID: part.id)
                let reviewState = session.reviewState(for: part.id)

                ScrollView {
                    QuestionStudyLayout(
                        title: question.title,
                        shell: question.shell,
                        variation: question.variation,
                        scenarioMarkdown: question.scenarioMarkdown,
                        part: part,
                        partIndex: session.currentPartIndex,
                        partCount: question.parts.count,
                        isWide: horizontalSizeClass == .regular && !dynamicTypeSize.isAccessibilitySize,
                        answer: $store[answerFor: key],
                        selfReviewComplete: $store[selfReviewFor: key],
                        reviewState: reviewState,
                        showScenario: {
                            session.isScenarioPresented = true
                        },
                        checkAnswer: {
                            check(part: part)
                        },
                        revealAnswer: {
                            performAnimated {
                                session.revealSolution(partID: part.id)
                            }
                        },
                        revealRubric: {
                            performAnimated {
                                session.revealRubric(partID: part.id)
                            }
                        },
                        goPrevious: {
                            movePrevious()
                        },
                        goNext: {
                            advance(from: part)
                        }
                    )
                }
                .id(part.id)
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: store[answerFor: key]) { oldAnswer, newAnswer in
                    guard oldAnswer != newAnswer else { return }
                    session.invalidateGrade(partID: part.id)
                    if store[selfReviewFor: key] {
                        store[selfReviewFor: key] = false
                    }
                }
                .sheet(isPresented: $session.isScenarioPresented) {
                    ScenarioSheet(
                        title: question.title,
                        markdown: question.scenarioMarkdown,
                        isPresented: $session.isScenarioPresented
                    )
                }
            } else {
                ContentUnavailableView(
                    "No answerable parts",
                    systemImage: "doc.text.magnifyingglass",
                    description: Text("This question does not contain a response part.")
                )
            }
        }
        .navigationTitle("Study")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    session.isScenarioPresented = true
                } label: {
                    Label("Question facts", systemImage: "doc.text")
                }
                .disabled(question.scenarioMarkdown.isEmpty)
            }
        }
        .task {
            store.beginAttempt(questionID: question.questionID)
            session.chooseInitialPart(
                store.resumePartIndex(for: question),
                partCount: question.parts.count
            )
        }
        .sensoryFeedback(.success, trigger: session.successFeedbackCount)
        .sensoryFeedback(.warning, trigger: session.warningFeedbackCount)
        .sensoryFeedback(.selection, trigger: session.selectionFeedbackCount)
    }

    private func check(part: QuestionPart) {
        guard let result = store.grade(questionID: question.questionID, partID: part.id) else {
            return
        }
        performAnimated {
            session.recordGrade(result, partID: part.id)
        }
    }

    private func advance(from part: QuestionPart) {
        let state = session.reviewState(for: part.id)
        let key = AnswerKey(questionID: question.questionID, partID: part.id)
        guard StudyAdvancePolicy.canAdvance(
            gradeStatus: state.gradeResult?.status,
            selfReviewComplete: store[selfReviewFor: key]
        ) else {
            return
        }

        let nextIndex = session.currentPartIndex + 1
        if question.parts.indices.contains(nextIndex) {
            performAnimated {
                session.move(to: nextIndex)
            }
        } else {
            dismiss()
        }
    }

    private func movePrevious() {
        let previousIndex = session.currentPartIndex - 1
        guard question.parts.indices.contains(previousIndex) else { return }
        performAnimated {
            session.move(to: previousIndex)
        }
    }

    private func performAnimated(_ changes: () -> Void) {
        if reduceMotion {
            changes()
        } else {
            withAnimation(.smooth(duration: 0.28), changes)
        }
    }
}

private struct QuestionStudyLayout: View {
    let title: String
    let shell: QuestionShell
    let variation: VariationStyle
    let scenarioMarkdown: String
    let part: QuestionPart
    let partIndex: Int
    let partCount: Int
    let isWide: Bool
    @Binding var answer: StudentAnswer
    @Binding var selfReviewComplete: Bool
    let reviewState: PartReviewState
    let showScenario: () -> Void
    let checkAnswer: () -> Void
    let revealAnswer: () -> Void
    let revealRubric: () -> Void
    let goPrevious: () -> Void
    let goNext: () -> Void

    var body: some View {
        if isWide {
            HStack(alignment: .top, spacing: 24) {
                ScenarioPanel(markdown: scenarioMarkdown)
                    .frame(width: 300)
                QuestionWorkColumn(
                    title: title,
                    shell: shell,
                    variation: variation,
                    part: part,
                    partIndex: partIndex,
                    partCount: partCount,
                    answer: $answer,
                    selfReviewComplete: $selfReviewComplete,
                    reviewState: reviewState,
                    showScenario: showScenario,
                    checkAnswer: checkAnswer,
                    revealAnswer: revealAnswer,
                    revealRubric: revealRubric,
                    goPrevious: goPrevious,
                    goNext: goNext
                )
                .frame(maxWidth: 760)
            }
            .frame(maxWidth: 1120, alignment: .top)
            .padding(24)
            .frame(maxWidth: .infinity)
        } else {
            QuestionWorkColumn(
                title: title,
                shell: shell,
                variation: variation,
                part: part,
                partIndex: partIndex,
                partCount: partCount,
                answer: $answer,
                selfReviewComplete: $selfReviewComplete,
                reviewState: reviewState,
                showScenario: showScenario,
                checkAnswer: checkAnswer,
                revealAnswer: revealAnswer,
                revealRubric: revealRubric,
                goPrevious: goPrevious,
                goNext: goNext
            )
            .frame(maxWidth: 760)
            .padding(.horizontal, 16)
            .padding(.vertical, 20)
            .frame(maxWidth: .infinity)
        }
    }
}

private struct QuestionWorkColumn: View {
    let title: String
    let shell: QuestionShell
    let variation: VariationStyle
    let part: QuestionPart
    let partIndex: Int
    let partCount: Int
    @Binding var answer: StudentAnswer
    @Binding var selfReviewComplete: Bool
    let reviewState: PartReviewState
    let showScenario: () -> Void
    let checkAnswer: () -> Void
    let revealAnswer: () -> Void
    let revealRubric: () -> Void
    let goPrevious: () -> Void
    let goNext: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            QuestionProgressHeader(
                title: title,
                shell: shell,
                variation: variation,
                partIndex: partIndex,
                partCount: partCount,
                showScenario: showScenario
            )
            PartPromptSection(
                partID: part.id,
                prompt: part.promptMarkdown,
                kind: part.kind,
                format: part.format,
                points: part.points
            )
            ResponseSection(part: part, answer: $answer, onSubmit: checkAnswer)

            if let gradeResult = reviewState.gradeResult {
                GradeFeedbackSection(
                    result: gradeResult,
                    stillNeedsSelfReview: StudyAdvancePolicy.needsSelfReview(gradeResult.status)
                        && !selfReviewComplete
                )
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            if reviewState.isSolutionVisible {
                ExpectedAnswerSection(part: part)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            if reviewState.isRubricVisible, !part.rubricMarkdown.isEmpty {
                RubricSection(markdown: part.rubricMarkdown)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            if StudyAdvancePolicy.needsSelfReview(reviewState.gradeResult?.status),
               reviewState.isSolutionVisible || reviewState.isRubricVisible {
                SelfReviewSection(isComplete: $selfReviewComplete)
            }

            QuestionActionsSection(
                part: part,
                partIndex: partIndex,
                partCount: partCount,
                reviewState: reviewState,
                selfReviewComplete: selfReviewComplete,
                checkAnswer: checkAnswer,
                revealAnswer: revealAnswer,
                revealRubric: revealRubric,
                goPrevious: goPrevious,
                goNext: goNext
            )
        }
    }
}

private struct QuestionProgressHeader: View {
    let title: String
    let shell: QuestionShell
    let variation: VariationStyle
    let partIndex: Int
    let partCount: Int
    let showScenario: () -> Void

    var body: some View {
        StudySurface(prominence: .emphasized) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 8) {
                    Label(shell.localizedTitle, systemImage: shell.symbolName)
                    Text(variation.localizedTitle)
                }
                .font(.caption.smallCaps())
                .foregroundStyle(.secondary)

                Text(title)
                    .font(.largeTitle.bold())
                    .fontDesign(.serif)
                    .accessibilityAddTraits(.isHeader)

                HStack(spacing: 12) {
                    ProgressView(value: Double(partIndex + 1), total: Double(max(partCount, 1)))
                        .tint(.accentColor)
                        .accessibilityLabel("Question progress")
                        .accessibilityValue("Part \(partIndex + 1) of \(partCount)")
                    Text("\(partIndex + 1) / \(partCount)")
                        .font(.subheadline.bold())
                        .fontDesign(.rounded)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }

                Button(action: showScenario) {
                    Label("Review question facts", systemImage: "doc.text.magnifyingglass")
                }
                .buttonStyle(.bordered)
                .accessibilityHint("Opens the scenario without discarding your response.")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct ScenarioPanel: View {
    let markdown: String

    var body: some View {
        StudySurface {
            VStack(alignment: .leading, spacing: 12) {
                SectionEyebrow(title: "QUESTION FACTS", systemImage: "doc.text")
                if markdown.isEmpty {
                    Text("No separate scenario was provided.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                } else {
                    MarkdownProse(markdown: markdown)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .contain)
    }
}

private struct ScenarioSheet: View {
    let title: String
    let markdown: String
    @Binding var isPresented: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(title)
                        .font(.title2.bold())
                        .fontDesign(.serif)
                    ScenarioPanel(markdown: markdown)
                }
                .frame(maxWidth: 680, alignment: .leading)
                .padding(20)
                .frame(maxWidth: .infinity)
            }
            .background {
                StudyBackground()
            }
            .navigationTitle("Question facts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        isPresented = false
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

private struct PartPromptSection: View {
    let partID: String
    let prompt: String
    let kind: ResponseKind
    let format: QuestionFormat
    let points: Double

    var body: some View {
        StudySurface {
            VStack(alignment: .leading, spacing: 13) {
                HStack(alignment: .firstTextBaseline) {
                    SectionEyebrow(title: "REQUIRED", systemImage: kind.symbolName)
                    Spacer()
                    Text("Part \(partID.uppercased())")
                        .font(.caption.bold())
                        .fontDesign(.monospaced)
                        .foregroundStyle(.secondary)
                }
                MarkdownProse(markdown: prompt, style: .title3)
                    .accessibilityAddTraits(.isHeader)
                HStack(spacing: 8) {
                    Text(kind.localizedTitle)
                    Text(format.localizedTitle)
                    Text("\(points, format: .number) points")
                        .monospacedDigit()
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct ResponseSection: View {
    let part: QuestionPart
    @Binding var answer: StudentAnswer
    let onSubmit: () -> Void

    var body: some View {
        StudySurface {
            VStack(alignment: .leading, spacing: 16) {
                SectionEyebrow(title: "YOUR RESPONSE", systemImage: "square.and.pencil")
                PartResponseEditor(part: part, answer: $answer, onSubmit: onSubmit)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct GradeFeedbackSection: View {
    let result: GradeResult
    let stillNeedsSelfReview: Bool

    var body: some View {
        StudySurface(prominence: .inset) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: result.status.symbolName)
                    .font(.title2)
                    .foregroundStyle(result.status.tint)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 5) {
                    Text(result.status.localizedTitle)
                        .font(.headline)
                    Text(result.feedback)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    if stillNeedsSelfReview, result.status == .correct {
                        Text("The objective decision is correct. Compare the explanation with the rubric before continuing.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
        }
    }
}

private struct ExpectedAnswerSection: View {
    let part: QuestionPart

    var body: some View {
        StudySurface(prominence: .inset) {
            VStack(alignment: .leading, spacing: 12) {
                SectionEyebrow(title: "MODEL ANSWER", systemImage: "eye")
                ExpectedAnswerContent(part: part)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct ExpectedAnswerContent: View {
    let part: QuestionPart

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            switch part.kind {
            case .singleChoice, .multipleChoice:
                ForEach(part.expected.selections, id: \.self) { selection in
                    Label(optionTitle(for: selection), systemImage: "checkmark.circle.fill")
                }
            case .number, .formula, .shortText, .longText, .trueFalse, .noEntry:
                MarkdownProse(markdown: part.expected.scalar)
                    .fontDesign(part.kind == .number || part.kind == .formula ? .monospaced : .serif)
            case .journal, .table:
                SolutionTable(
                    partID: part.id,
                    columns: part.stableColumns,
                    values: part.expected.rows
                )
            case .matching:
                ForEach(part.items) { item in
                    HStack(alignment: .firstTextBaseline) {
                        Text(item.text)
                        Spacer(minLength: 16)
                        Text(targetTitle(for: part.expected.pairs[item.id]))
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.tint)
                    }
                }
            case .ordering:
                ForEach(Array(part.expected.order.enumerated()), id: \.element) { index, itemID in
                    HStack(spacing: 10) {
                        Text(index + 1, format: .number)
                            .font(.body.bold())
                            .fontDesign(.monospaced)
                            .monospacedDigit()
                            .foregroundStyle(.tint)
                        Text(itemTitle(for: itemID))
                    }
                }
            }
        }
    }

    private func optionTitle(for selection: String) -> String {
        part.options.first(where: { $0.id == selection })?.text ?? selection
    }

    private func targetTitle(for targetID: String?) -> String {
        guard let targetID else { return "—" }
        return part.targets.first(where: { $0.id == targetID })?.text ?? targetID
    }

    private func itemTitle(for itemID: String) -> String {
        part.items.first(where: { $0.id == itemID })?.text ?? itemID
    }
}

private struct SolutionTable: View {
    let columns: [StableColumn]
    let rows: [SolutionRow]

    init(partID: String, columns: [StableColumn], values: [[String]]) {
        self.columns = columns
        self.rows = values.enumerated().map { index, cells in
            SolutionRow(id: "\(partID)-solution-row-\(index)", cells: cells)
        }
    }

    var body: some View {
        ScrollView(.horizontal) {
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 9) {
                GridRow {
                    ForEach(columns) { column in
                        Text(column.title)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .frame(minWidth: 112, alignment: .leading)
                    }
                }
                ForEach(rows) { row in
                    GridRow {
                        ForEach(Array(columns.enumerated()), id: \.element.id) { index, column in
                            Text(row.cells.indices.contains(index) ? row.cells[index] : "")
                                .font(.body)
                                .fontDesign(.monospaced)
                                .frame(minWidth: 112, alignment: .leading)
                                .accessibilityLabel("\(column.title), \(row.cells.indices.contains(index) ? row.cells[index] : "blank")")
                        }
                    }
                }
            }
        }
        .scrollIndicators(.visible)
    }
}

private struct SolutionRow: Identifiable {
    let id: String
    let cells: [String]
}

private struct RubricSection: View {
    let markdown: String

    var body: some View {
        StudySurface(prominence: .inset) {
            VStack(alignment: .leading, spacing: 12) {
                SectionEyebrow(title: "RUBRIC", systemImage: "checklist")
                MarkdownProse(markdown: markdown)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct SelfReviewSection: View {
    @Binding var isComplete: Bool

    var body: some View {
        Toggle(isOn: $isComplete) {
            VStack(alignment: .leading, spacing: 3) {
                Text("I completed the self-review")
                    .font(.headline)
                Text("I compared my reasoning with the model answer or rubric.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .toggleStyle(.switch)
        .padding(16)
        .background {
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .fill(Color.blue.opacity(0.10))
        }
        .accessibilityHint("Required before moving to the next part.")
        .sensoryFeedback(.selection, trigger: isComplete)
    }
}

private struct QuestionActionsSection: View {
    let part: QuestionPart
    let partIndex: Int
    let partCount: Int
    let reviewState: PartReviewState
    let selfReviewComplete: Bool
    let checkAnswer: () -> Void
    let revealAnswer: () -> Void
    let revealRubric: () -> Void
    let goPrevious: () -> Void
    let goNext: () -> Void

    var body: some View {
        StudySurface(prominence: .emphasized) {
            VStack(alignment: .leading, spacing: 14) {
                ResponsiveActionLayout {
                    Button(action: checkAnswer) {
                        Label(
                            part.startsWithSelfReview ? "Start self-review" : "Check answer",
                            systemImage: part.startsWithSelfReview ? "person.crop.circle.badge.checkmark" : "checkmark.circle"
                        )
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.return, modifiers: [.command])

                    Button(action: revealAnswer) {
                        Label("Reveal answer", systemImage: "eye")
                    }
                    .buttonStyle(.bordered)

                    if !part.rubricMarkdown.isEmpty {
                        Button(action: revealRubric) {
                            Label("Rubric", systemImage: "checklist")
                        }
                        .buttonStyle(.bordered)
                    }
                }

                Text(advanceGuidance)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 12) {
                    if partIndex > 0 {
                        Button(action: goPrevious) {
                            Label("Previous part", systemImage: "arrow.backward")
                        }
                        .buttonStyle(.bordered)
                        .accessibilityHint("Returns to the preceding part without changing this response.")
                    }
                    Spacer(minLength: 0)
                    Button(action: goNext) {
                        Label(
                            partIndex + 1 < partCount ? "Next part" : "Finish",
                            systemImage: partIndex + 1 < partCount ? "arrow.forward" : "checkmark"
                        )
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canAdvance)
                    .accessibilityHint(advanceGuidance)
                }
            }
        }
    }

    private var canAdvance: Bool {
        StudyAdvancePolicy.canAdvance(
            gradeStatus: reviewState.gradeResult?.status,
            selfReviewComplete: selfReviewComplete
        )
    }

    private var advanceGuidance: LocalizedStringResource {
        if reviewState.gradeResult == nil {
            return part.startsWithSelfReview
                ? "Start the self-review before continuing."
                : "Check your response before continuing."
        }
        if StudyAdvancePolicy.needsSelfReview(reviewState.gradeResult?.status),
           !selfReviewComplete {
            return "Reveal the answer or rubric, then complete the self-review."
        }
        return "Your work is saved automatically."
    }
}
