import AccountingQuestionKit
import SwiftUI

struct QuestionInspectorView: View {
    let store: AppStore

    var body: some View {
        if let question = store.selectedQuestion {
            QuestionInspectorContent(
                question: question,
                progress: store.progress(for: question),
                store: store
            )
        } else {
            ContentUnavailableView(
                "No Selection",
                systemImage: "info.circle"
            )
        }
    }
}

private struct QuestionInspectorContent: View {
    let question: AccountingQuestion
    let progress: QuestionProgress
    let store: AppStore

    var body: some View {
        let activePart = question.parts.first(where: {
            $0.id == store.activePartID
        }) ?? question.parts.first

        Form {
            InspectorProgressSection(progress: progress)

            if let activePart {
                ActivePartInspectorSection(
                    questionID: question.id,
                    part: activePart,
                    store: store
                )
            }

            QuestionIdentityInspector(
                id: QuestionIdentity.originalID(from: question.id),
                sourceName: question.sourceName
            )
            QuestionStructureInspector(
                shell: question.shell,
                variation: question.variation,
                partCount: question.parts.count
            )
            QuestionTaxonomyInspector(
                formats: question.formats,
                tags: question.tags
            )

            if !store.lastImportWarnings.isEmpty {
                ImportWarningsInspector(warnings: store.lastImportWarnings)
            }
        }
        .formStyle(.grouped)
    }
}

private struct InspectorProgressSection: View {
    let progress: QuestionProgress

    var body: some View {
        Section("Progress") {
            ProgressView(value: progress.fractionAnswered)
            LabeledContent("Answered") {
                Text("\(progress.answeredParts) of \(progress.totalParts)")
                    .monospacedDigit()
            }
            LabeledContent("Checked") {
                Text("\(progress.completedParts) of \(progress.totalParts)")
                    .monospacedDigit()
            }
            LabeledContent("Points") {
                Text("\(progress.earnedPoints, format: .number) / \(progress.totalPoints, format: .number)")
                    .monospacedDigit()
            }
        }
    }
}

private struct ActivePartInspectorSection: View {
    let questionID: String
    let part: QuestionPart
    let store: AppStore

    var body: some View {
        @Bindable var store = store
        let result = store.gradeResult(for: questionID, partID: part.id)
        let isRevealed = store.isRevealed(questionID: questionID, partID: part.id)
        let isReviewed = store[selfReviewFor: questionID, partID: part.id]
        let canCompleteSelfReview = store.canCompleteSelfReview(
            questionID: questionID,
            partID: part.id
        )

        Section("Current Response") {
            LabeledContent("Part", value: part.id)
            LabeledContent("Format") {
                Text(part.format.localizedName)
                    .multilineTextAlignment(.trailing)
            }
            LabeledContent("Editor") {
                Text(part.kind.localizedName)
            }

            if let result {
                InspectorGradeSummary(
                    result: result,
                    isReviewed: isReviewed
                )
                Text(result.feedback)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                Label("Not checked yet", systemImage: "circle.dashed")
                    .foregroundStyle(.secondary)
            }

            HStack {
                Button("Check", systemImage: "checkmark.circle") {
                    store.check(part: part, in: questionID)
                }
                .disabled(!store.canCheck(part: part, in: questionID))

                Button(
                    revealButtonTitle(isRevealed: isRevealed),
                    systemImage: isRevealed ? "eye.slash" : "eye"
                ) {
                    store.toggleReveal(partID: part.id, in: questionID)
                }
            }

            if result?.status == .needsSelfReview && isRevealed {
                Toggle(
                    "Self-review complete",
                    isOn: $store[selfReviewFor: questionID, partID: part.id]
                )
                .toggleStyle(.checkbox)
                .disabled(!isReviewed && !canCompleteSelfReview)
                .help(
                    canCompleteSelfReview
                        ? "Mark the comparison complete"
                        : "Enter the requested correction or rationale first"
                )
            }

            if isRevealed && !part.rubricMarkdown.isEmpty {
                DisclosureGroup("Rubric") {
                    MarkdownText(
                        markdown: part.rubricMarkdown,
                        font: .callout,
                        fontDesign: .default
                    )
                }
            }
        }
    }

    private func revealButtonTitle(
        isRevealed: Bool
    ) -> LocalizedStringResource {
        isRevealed ? "Hide" : "Reveal"
    }
}

private struct InspectorGradeSummary: View {
    let result: GradeResult
    let isReviewed: Bool

    var body: some View {
        let status = result.status == .needsSelfReview && isReviewed
            ? GradeStatus.correct
            : result.status
        Label(status.localizedName, systemImage: status.systemImage)
            .foregroundStyle(statusColor(for: status))
    }

    private func statusColor(for status: GradeStatus) -> Color {
        switch status {
        case .correct: .green
        case .incorrect: .red
        case .needsSelfReview: .orange
        case .unanswered: .secondary
        }
    }
}

private struct QuestionIdentityInspector: View {
    let id: String
    let sourceName: String

    var body: some View {
        Section("Identity") {
            LabeledContent("Question ID") {
                Text(id)
                    .font(.callout.monospaced())
                    .textSelection(.enabled)
            }
            LabeledContent("Source") {
                Text(sourceName.isEmpty ? String(localized: "Unknown") : sourceName)
                    .multilineTextAlignment(.trailing)
            }
        }
    }
}

private struct QuestionStructureInspector: View {
    let shell: QuestionShell
    let variation: VariationStyle
    let partCount: Int

    var body: some View {
        Section("Structure") {
            LabeledContent("Shell") {
                Text(shell.localizedName)
            }
            LabeledContent("Variation") {
                Text(variation.localizedName)
            }
            LabeledContent("Parts") {
                Text(partCount, format: .number)
            }
        }
    }
}

private struct QuestionTaxonomyInspector: View {
    let formats: [QuestionFormat]
    let tags: [String]

    var body: some View {
        Section("Taxonomy") {
            if formats.isEmpty {
                LabeledContent("Formats", value: String(localized: "None"))
            } else {
                ForEach(uniqueFormats, id: \.self) { format in
                    Label(format.localizedName, systemImage: "tag")
                }
            }

            LabeledContent("Tags") {
                Text(tags.isEmpty ? String(localized: "None") : tags.formatted())
                    .multilineTextAlignment(.trailing)
            }
        }
    }

    private var uniqueFormats: [QuestionFormat] {
        var seen = Set<QuestionFormat>()
        return formats.filter { seen.insert($0).inserted }
    }
}

private struct ImportWarningsInspector: View {
    let warnings: [ImportNotice]

    var body: some View {
        Section("Last Import Warnings") {
            ForEach(warnings.prefix(200)) { notice in
                Label {
                    if let line = notice.warning.line {
                        Text(
                            "\(notice.sourceName), line \(line): \(notice.warning.message)"
                        )
                    } else {
                        Text("\(notice.sourceName): \(notice.warning.message)")
                    }
                } icon: {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                }
            }
            if warnings.count > 200 {
                Text("\(warnings.count - 200) additional warnings are not shown.")
                    .foregroundStyle(.secondary)
            }
        }
    }
}
