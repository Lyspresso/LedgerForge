import AccountingQuestionKit
import SwiftUI

struct LocalizedSystemLabel: View {
    let title: LocalizedStringResource
    let systemImage: String

    var body: some View {
        Label {
            Text(title)
        } icon: {
            Image(systemName: systemImage)
        }
    }
}

struct QuestionDetailView: View {
    let store: AppStore

    var body: some View {
        if let question = store.selectedQuestion {
            QuestionWorkspace(
                question: question,
                progress: store.progress(for: question),
                store: store
            )
            .navigationTitle(question.displayTitle)
        } else {
            QuestionWelcomeView(store: store)
        }
    }
}

private struct QuestionWorkspace: View {
    let question: AccountingQuestion
    let progress: QuestionProgress
    let store: AppStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                QuestionHeader(
                    presentation: question.titlePresentation,
                    shell: question.shell,
                    sourceName: question.sourceName,
                    progress: progress
                )
                QuestionScenario(markdown: question.scenarioMarkdown)
                QuestionParts(
                    questionID: question.id,
                    parts: question.parts,
                    store: store
                )
            }
            .frame(maxWidth: 900, alignment: .leading)
            .padding(.horizontal, 34)
            .padding(.vertical, 30)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .scrollIndicators(.automatic)
        .background {
            LinearGradient(
                colors: [
                    Color.accentColor.opacity(0.035),
                    Color.clear
                ],
                startPoint: .topLeading,
                endPoint: .center
            )
            .ignoresSafeArea()
        }
    }
}

private struct QuestionHeader: View {
    let presentation: QuestionTitlePresentation
    let shell: QuestionShell
    let sourceName: String
    let progress: QuestionProgress

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            Text(presentation.title)
                .font(.largeTitle)
                .fontWeight(.semibold)
                .textSelection(.enabled)

            if presentation.learningObjective != nil || presentation.verification != nil {
                HStack(spacing: 7) {
                    if let objective = presentation.learningObjective {
                        Text(objective)
                            .font(.caption.weight(.medium))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.quaternary, in: Capsule())
                    }
                    if let verification = presentation.verification {
                        Text(verification)
                            .font(.caption.weight(.medium))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.quaternary, in: Capsule())
                    }
                }
                .foregroundStyle(.secondary)
            }

            QuestionMetadata(shell: shell, sourceName: sourceName)

            QuestionProgressView(progress: progress)
        }
    }
}

private struct QuestionMetadata: View {
    let shell: QuestionShell
    let sourceName: String

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                shellLabel
                if !sourceName.isEmpty {
                    Divider()
                        .frame(height: 13)
                    sourceLabel
                }
            }
            VStack(alignment: .leading, spacing: 5) {
                shellLabel
                if !sourceName.isEmpty {
                    sourceLabel
                }
            }
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
    }

    private var shellLabel: some View {
        LocalizedSystemLabel(
            title: shell.localizedName,
            systemImage: "square.stack.3d.up"
        )
    }

    private var sourceLabel: some View {
        Label(sourceName, systemImage: "doc")
    }
}

private struct QuestionProgressView: View {
    let progress: QuestionProgress

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("\(progress.answeredParts) of \(progress.totalParts) parts answered")
                Spacer()
                if progress.isComplete {
                    Label("Complete", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else {
                    Text("\(progress.completedParts) checked")
                        .foregroundStyle(.secondary)
                }
            }
            .font(.caption)

            ProgressView(value: progress.fractionAnswered)
                .accessibilityLabel("Question progress")
                .accessibilityValue("\(progress.answeredParts) of \(progress.totalParts) parts answered")
        }
    }
}

private struct QuestionScenario: View {
    let markdown: String

    var body: some View {
        if !markdown.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Label("Scenario", systemImage: "text.book.closed")
                    .font(.headline)
                MarkdownText(markdown: markdown)
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
        }
    }
}

private struct QuestionParts: View {
    let questionID: String
    let parts: [QuestionPart]
    let store: AppStore

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Required Responses")
                .font(.title2.weight(.semibold))

            if parts.isEmpty {
                ContentUnavailableView(
                    "No Answerable Parts",
                    systemImage: "exclamationmark.triangle",
                    description: Text(
                        "This question contains no response definitions. Re-import a corrected source file."
                    )
                )
            } else if Set(parts.map(\.id)).count != parts.count {
                ContentUnavailableView(
                    "Duplicate Part IDs",
                    systemImage: "exclamationmark.triangle",
                    description: Text(
                        "Each response part needs a unique ID before answers can be stored safely."
                    )
                )
            } else {
                ForEach(Array(parts.enumerated()), id: \.element.id) { position, part in
                    QuestionPartCard(
                        questionID: questionID,
                        position: position,
                        part: part,
                        store: store
                    )
                }
            }
        }
    }
}

private struct QuestionPartCard: View {
    let questionID: String
    let position: Int
    let part: QuestionPart
    let store: AppStore

    var body: some View {
        @Bindable var store = store
        let result = store.gradeResult(for: questionID, partID: part.id)
        let isRevealed = store.isRevealed(questionID: questionID, partID: part.id)
        let isSelfReviewed = store[selfReviewFor: questionID, partID: part.id]
        let canCompleteSelfReview = store.canCompleteSelfReview(
            questionID: questionID,
            partID: part.id
        )

        VStack(alignment: .leading, spacing: 16) {
            QuestionPartHeader(
                position: position,
                format: part.format,
                kind: part.kind,
                points: part.points,
                result: result,
                isSelfReviewed: isSelfReviewed
            )

            MarkdownText(markdown: part.promptPresentation.body)

            if !part.promptPresentation.importDetails.isEmpty {
                DisclosureGroup("Source details") {
                    VStack(alignment: .leading, spacing: 5) {
                        ForEach(
                            Array(part.promptPresentation.importDetails.enumerated()),
                            id: \.offset
                        ) { _, detail in
                            LabeledContent(detail.label, value: detail.value)
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Divider()

            QuestionEditorRouter(
                part: part,
                answer: $store[answerFor: questionID, partID: part.id]
            )
            .focusedValue(
                \.activeQuestionPart,
                QuestionPartKey(questionID: questionID, partID: part.id)
            )

            if let result {
                GradeFeedbackBanner(
                    result: result,
                    isSelfReviewed: isSelfReviewed
                )
            }

            QuestionPartActionBar(
                answerIsReady: store.canCheck(part: part, in: questionID),
                isRevealed: isRevealed,
                check: {
                    store.check(part: part, in: questionID)
                },
                toggleReveal: {
                    store.toggleReveal(partID: part.id, in: questionID)
                }
            )

            if isRevealed {
                AnswerRevealView(part: part)
            }

            if result?.status == .needsSelfReview && isRevealed {
                Toggle(
                    "I compared my response with the model answer and rubric",
                    isOn: $store[selfReviewFor: questionID, partID: part.id]
                )
                .toggleStyle(.checkbox)
                .disabled(!isSelfReviewed && !canCompleteSelfReview)
                .help(
                    canCompleteSelfReview
                        ? "Mark the comparison complete"
                        : "Enter the requested correction or rationale first"
                )
            }
        }
        .padding(20)
        .background(.background, in: RoundedRectangle(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .stroke(
                    store.activePartID == part.id
                        ? Color.accentColor.opacity(0.55)
                        : Color.secondary.opacity(0.16),
                    lineWidth: store.activePartID == part.id ? 1.5 : 1
                )
        }
        .shadow(color: .black.opacity(0.035), radius: 8, y: 3)
        .contentShape(Rectangle())
        .onTapGesture {
            store.activatePart(part.id)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(
            "Part \(position + 1), \(String(localized: part.format.localizedName))"
        )
        .accessibilityAction(named: "Make Current Response") {
            store.activatePart(part.id)
        }
    }
}

private struct QuestionPartHeader: View {
    let position: Int
    let format: QuestionFormat
    let kind: ResponseKind
    let points: Double
    let result: GradeResult?
    let isSelfReviewed: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(position + 1, format: .number)
                .font(.headline.monospaced())
                .frame(width: 30, height: 30)
                .background(Color.accentColor.opacity(0.13), in: Circle())
                .accessibilityLabel("Part \(position + 1)")

            VStack(alignment: .leading, spacing: 4) {
                Text(format.localizedName)
                    .font(.headline)
                HStack(spacing: 7) {
                    Text(kind.localizedName)
                    Text("•")
                    Text("\(points, format: .number) points")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()

            if let result {
                PartStatusBadge(result: result, isSelfReviewed: isSelfReviewed)
            }
        }
    }
}

private struct PartStatusBadge: View {
    let result: GradeResult
    let isSelfReviewed: Bool

    var body: some View {
        let status = result.status == .needsSelfReview && isSelfReviewed
            ? GradeStatus.correct
            : result.status
        LocalizedSystemLabel(title: status.localizedName, systemImage: status.systemImage)
            .font(.caption.weight(.medium))
            .foregroundStyle(status == .correct ? Color.green : .secondary)
            .labelStyle(.iconOnly)
            .help(String(localized: status.localizedName))
    }
}

private struct QuestionPartActionBar: View {
    let answerIsReady: Bool
    let isRevealed: Bool
    let check: () -> Void
    let toggleReveal: () -> Void

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                actionButtons
                Spacer()
            }
            VStack(alignment: .leading, spacing: 8) {
                actionButtons
            }
        }
    }

    @ViewBuilder
    private var actionButtons: some View {
        Button("Check Answer", systemImage: "checkmark.circle", action: check)
            .buttonStyle(.borderedProminent)
            .disabled(!answerIsReady)

        Button(action: toggleReveal) {
            LocalizedSystemLabel(
                title: revealButtonTitle,
                systemImage: isRevealed ? "eye.slash" : "eye"
            )
        }
    }

    private var revealButtonTitle: LocalizedStringResource {
        isRevealed ? "Hide Answer" : "Reveal Answer"
    }
}

private struct QuestionWelcomeView: View {
    let store: AppStore

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "books.vertical.fill")
                .font(.system(.largeTitle, design: .rounded, weight: .semibold))
                .foregroundStyle(Color.accentColor)
            VStack(spacing: 6) {
                Text("Build Your Question Library")
                    .font(.title2.weight(.semibold))
                Text("Import a Markdown pack, or open a bundled sample for every format or spreadsheet practice.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 440)
            }
            QuestionWelcomeActions(store: store)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct QuestionWelcomeActions: View {
    let store: AppStore

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack {
                actionButtons
            }
            VStack {
                actionButtons
            }
        }
    }

    @ViewBuilder
    private var actionButtons: some View {
        Button("Import Markdown…", systemImage: "square.and.arrow.down") {
            store.presentImporter()
        }
        .buttonStyle(.borderedProminent)
        .disabled(store.isImporting)
        Button("Load Complete Sample", systemImage: "sparkles.rectangle.stack") {
            store.loadCompleteFormatSample()
        }
        .disabled(store.isImporting)
        Button("Load Spreadsheet Sample", systemImage: "tablecells") {
            store.loadSpreadsheetPracticeSample()
        }
        .disabled(store.isImporting)
    }
}
