import AccountingQuestionKit
import SwiftUI
import UniformTypeIdentifiers

struct LibraryView: View {
    let store: AccountingSuiteStore
    @State private var isShowingImporter = false

    var body: some View {
        @Bindable var store = store

        ScrollView {
            LibraryBody(
                loadPhase: store.loadPhase,
                importPhase: store.importPhase,
                saveFailureMessage: store.saveFailureMessage,
                questionCount: store.questionCount,
                packCount: store.librarySections.count,
                attemptCount: store.attemptSummaries.count,
                sections: store.visibleLibrarySections,
                hasActiveFilters: store.hasActiveLibraryFilters,
                formatFilter: $store.libraryFormatFilter,
                shellFilter: $store.libraryShellFilter,
                statusFilter: $store.libraryStatusFilter,
                isShowingImporter: $isShowingImporter,
                clearFilters: store.clearLibraryFilters,
                dismissImportStatus: store.clearImportStatus
            )
        }
        .background {
            StudyBackground()
        }
        .navigationTitle("Question Library")
        .searchable(
            text: $store.librarySearchText,
            placement: .automatic,
            prompt: "Search questions, packs, or formats"
        )
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                NavigationLink(value: AppRoute.attempts) {
                    Label("Attempts", systemImage: "clock.arrow.circlepath")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Section("Built-in Samples") {
                        ForEach(BundledSample.allCases) { sample in
                            Button {
                                Task {
                                    await store.importBundledSample(sample)
                                }
                            } label: {
                                LocalizedSystemLabel(
                                    title: sample.title,
                                    systemImage: sample.systemImage
                                )
                            }
                        }
                    }

                    Divider()

                    Button {
                        isShowingImporter = true
                    } label: {
                        Label("Import from Files", systemImage: "folder.badge.plus")
                    }
                } label: {
                    Label("Add Questions", systemImage: "plus")
                }
            }
        }
        .fileImporter(
            isPresented: $isShowingImporter,
            allowedContentTypes: [.accountingMarkdown, .plainText]
        ) { result in
            switch result {
            case let .success(url):
                Task {
                    await store.importMarkdown(from: url)
                }
            case let .failure(error):
                store.reportImportPickerFailure(error)
            }
        }
    }
}

private extension UTType {
    static let accountingMarkdown = UTType(
        importedAs: "net.daringfireball.markdown",
        conformingTo: .plainText
    )
}

private struct LibraryBody: View {
    let loadPhase: AppLoadPhase
    let importPhase: MarkdownImportPhase
    let saveFailureMessage: String?
    let questionCount: Int
    let packCount: Int
    let attemptCount: Int
    let sections: [LibrarySectionModel]
    let hasActiveFilters: Bool
    @Binding var formatFilter: QuestionFormat?
    @Binding var shellFilter: QuestionShell?
    @Binding var statusFilter: LibraryStudyStatus?
    @Binding var isShowingImporter: Bool
    let clearFilters: () -> Void
    let dismissImportStatus: () -> Void

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 22) {
            LibraryHero(
                questionCount: questionCount,
                packCount: packCount,
                attemptCount: attemptCount
            )

            LibraryFilterBar(
                formatFilter: $formatFilter,
                shellFilter: $shellFilter,
                statusFilter: $statusFilter,
                hasActiveFilters: hasActiveFilters,
                clearFilters: clearFilters
            )

            ImportStatusBanner(
                phase: importPhase,
                onDismiss: dismissImportStatus
            )

            if let saveFailureMessage {
                SaveFailureBanner(message: saveFailureMessage)
            }

            switch loadPhase {
            case .idle, .loading:
                LoadingLibraryCard()
            case let .failed(message):
                LibraryFailureState(message: message)
            case .ready:
                if sections.isEmpty, hasActiveFilters {
                    FilteredLibraryEmptyState(clearFilters: clearFilters)
                } else if sections.isEmpty {
                    EmptyLibraryState(isShowingImporter: $isShowingImporter)
                } else {
                    ForEach(sections) { section in
                        QuestionPackSection(section: section)
                    }
                }
            }
        }
        .frame(maxWidth: 1040)
        .padding(.horizontal, 18)
        .padding(.vertical, 24)
        .frame(maxWidth: .infinity)
    }
}

private struct LibraryHero: View {
    let questionCount: Int
    let packCount: Int
    let attemptCount: Int

    var body: some View {
        StudySurface(prominence: .emphasized) {
            VStack(alignment: .leading, spacing: 17) {
                SectionEyebrow(title: "ACCOUNTING PRACTICE STUDIO", systemImage: "sum")
                Text("Practice the whole accounting workflow.")
                    .font(.largeTitle.bold())
                    .fontDesign(.serif)
                    .accessibilityAddTraits(.isHeader)
                Text("Work through objective checks, journal entries, schedules, and judgment responses. Everything stays on this device.")
                    .font(.body)
                    .foregroundStyle(.secondary)

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) {
                        LibraryMetric(value: questionCount, label: "Questions")
                        LibraryMetric(value: packCount, label: "Packs")
                        LibraryMetric(value: attemptCount, label: "Attempts")
                    }
                    VStack(spacing: 10) {
                        LibraryMetric(value: questionCount, label: "Questions")
                        LibraryMetric(value: packCount, label: "Packs")
                        LibraryMetric(value: attemptCount, label: "Attempts")
                    }
                }
            }
        }
    }
}

private struct LibraryMetric: View {
    let value: Int
    let label: LocalizedStringResource

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value, format: .number)
                .font(.title3.bold())
                .fontDesign(.rounded)
                .monospacedDigit()
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(uiColor: .tertiarySystemGroupedBackground))
        }
        .accessibilityElement(children: .combine)
    }
}

private struct LibraryFilterBar: View {
    @Binding var formatFilter: QuestionFormat?
    @Binding var shellFilter: QuestionShell?
    @Binding var statusFilter: LibraryStudyStatus?
    let hasActiveFilters: Bool
    let clearFilters: () -> Void

    var body: some View {
        StudySurface(prominence: .inset) {
            ScrollView(.horizontal) {
                HStack(spacing: 10) {
                    FilterPicker(
                        title: "Format",
                        allTitle: "All formats",
                        systemImage: "rectangle.3.group",
                        selection: $formatFilter
                    )
                    FilterPicker(
                        title: "Shell",
                        allTitle: "All shells",
                        systemImage: "square.stack.3d.up",
                        selection: $shellFilter
                    )
                    FilterPicker(
                        title: "Status",
                        allTitle: "All statuses",
                        systemImage: "progress.indicator",
                        selection: $statusFilter
                    )

                    if hasActiveFilters {
                        Button("Clear", action: clearFilters)
                            .buttonStyle(.bordered)
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Library filters")
    }
}

private struct FilterPicker<Value: Hashable & CaseIterable>: View where Value.AllCases: RandomAccessCollection {
    let title: LocalizedStringResource
    let allTitle: LocalizedStringResource
    let systemImage: String
    @Binding var selection: Value?

    var body: some View {
        Picker(
            selection: $selection,
            content: {
                LocalizedSystemLabel(title: allTitle, systemImage: systemImage)
                    .tag(nil as Value?)
                ForEach(Value.allCases, id: \.self) { value in
                    FilterValueLabel(value: value).tag(Optional(value))
                }
            },
            label: {
                LocalizedSystemLabel(title: title, systemImage: systemImage)
            }
        )
        .pickerStyle(.menu)
        .buttonStyle(.bordered)
    }
}

private struct FilterValueLabel<Value>: View {
    let value: Value

    var body: some View {
        if let format = value as? QuestionFormat {
            Text(format.localizedTitle)
        } else if let shell = value as? QuestionShell {
            Text(shell.localizedTitle)
        } else if let status = value as? LibraryStudyStatus {
            Text(status.localizedTitle)
        } else {
            Text(verbatim: String(describing: value))
        }
    }
}

private struct ImportStatusBanner: View {
    let phase: MarkdownImportPhase
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            switch phase {
            case .idle:
                EmptyView()
            case let .importing(fileName):
                StudySurface(prominence: .inset) {
                    HStack(spacing: 12) {
                        ProgressView()
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Importing Markdown…")
                                .font(.headline)
                            Text(fileName)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            case let .succeeded(fileName, questionCount, warnings):
                ImportSuccessCard(
                    fileName: fileName,
                    questionCount: questionCount,
                    warnings: warnings,
                    onDismiss: onDismiss
                )
            case let .failed(message):
                StatusMessageRow(
                    symbolName: "exclamationmark.triangle.fill",
                    tint: .orange,
                    title: "Import failed",
                    message: message,
                    onDismiss: onDismiss
                )
            }
        }
    }
}

private struct ImportSuccessCard: View {
    let fileName: String
    let questionCount: Int
    let warnings: [ImportNotice]
    let onDismiss: () -> Void

    var body: some View {
        StudySurface(prominence: .inset) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: warnings.isEmpty ? "checkmark.circle.fill" : "checkmark.circle.badge.exclamationmark")
                        .foregroundStyle(warnings.isEmpty ? Color.green : .orange)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(warnings.isEmpty ? "Import complete" : "Imported with notes")
                            .font(.headline)
                        Text("\(fileName): \(questionCount) questions")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 8)
                    Button("Dismiss", action: onDismiss)
                        .font(.caption)
                }

                if !warnings.isEmpty {
                    VStack(alignment: .leading, spacing: 7) {
                        ForEach(warnings) { warning in
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: "exclamationmark.bubble")
                                    .foregroundStyle(.orange)
                                    .accessibilityHidden(true)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(warning.message)
                                        .font(.subheadline)
                                    if let line = warning.line {
                                        Text("Line \(line)")
                                            .font(.caption)
                                            .fontDesign(.monospaced)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                    .padding(12)
                    .background {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.orange.opacity(0.08))
                    }
                    .accessibilityElement(children: .contain)
                    .accessibilityLabel("Import warnings")
                }
            }
        }
    }
}

private struct StatusMessageRow: View {
    let symbolName: String
    let tint: Color
    let title: LocalizedStringResource
    let message: String
    let onDismiss: () -> Void

    var body: some View {
        StudySurface(prominence: .inset) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: symbolName)
                    .foregroundStyle(tint)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.headline)
                    Text(message)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Button("Dismiss", action: onDismiss)
                    .font(.caption)
            }
        }
    }
}

private struct SaveFailureBanner: View {
    let message: String

    var body: some View {
        Label {
            Text("Changes remain in memory, but saving failed: \(message)")
        } icon: {
            Image(systemName: "externaldrive.badge.exclamationmark")
        }
        .font(.subheadline)
        .foregroundStyle(.orange)
        .padding(14)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.orange.opacity(0.08))
        }
    }
}

private struct LoadingLibraryCard: View {
    var body: some View {
        StudySurface {
            HStack(spacing: 12) {
                ProgressView()
                Text("Loading your local library…")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct LibraryFailureState: View {
    let message: String

    var body: some View {
        StudySurface {
            ContentUnavailableView {
                Label("Library unavailable", systemImage: "externaldrive.badge.xmark")
            } description: {
                Text(message)
            }
        }
    }
}

private struct FilteredLibraryEmptyState: View {
    let clearFilters: () -> Void

    var body: some View {
        StudySurface {
            ContentUnavailableView {
                Label("No matching questions", systemImage: "line.3.horizontal.decrease.circle")
            } description: {
                Text("Try a different search or clear one of the filters.")
            } actions: {
                Button("Clear filters", action: clearFilters)
                    .buttonStyle(.borderedProminent)
            }
        }
    }
}

private struct EmptyLibraryState: View {
    @Binding var isShowingImporter: Bool

    var body: some View {
        StudySurface {
            ContentUnavailableView {
                Label("Import a question pack", systemImage: "doc.badge.plus")
            } description: {
                Text("Choose a structured or legacy Markdown file from Files.")
            } actions: {
                Button("Choose Markdown") {
                    isShowingImporter = true
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }
}

private struct QuestionPackSection: View {
    let section: LibrarySectionModel

    var body: some View {
        StudySurface {
            VStack(alignment: .leading, spacing: 16) {
                PackSectionHeader(
                    title: section.title,
                    sourceFileName: section.sourceFileName,
                    importedAt: section.importedAt,
                    questionCount: section.questions.count
                )

                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 290), spacing: 12)],
                    spacing: 12
                ) {
                    ForEach(section.questions) { question in
                        NavigationLink(
                            value: AppRoute.question(packID: section.id, questionID: question.id)
                        ) {
                            LibraryQuestionRow(
                                title: question.title,
                                shell: question.shell,
                                status: question.status,
                                firstFormat: question.formats.first,
                                answeredPartCount: question.answeredPartCount,
                                partCount: question.partCount
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}

private struct PackSectionHeader: View {
    let title: String
    let sourceFileName: String
    let importedAt: Date
    let questionCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.title3.bold())
                    .fontDesign(.serif)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Text(questionCount, format: .number)
                    .font(.subheadline.bold())
                    .fontDesign(.rounded)
                    .monospacedDigit()
            }
            Text("\(sourceFileName) · imported \(importedAt, format: .dateTime.month(.abbreviated).day().year())")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private struct LibraryQuestionRow: View {
    let title: String
    let shell: QuestionShell
    let status: LibraryStudyStatus
    let firstFormat: QuestionFormat?
    let answeredPartCount: Int
    let partCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: shell.symbolName)
                    .font(.title3)
                    .foregroundStyle(.tint)
                    .frame(width: 28)
                    .accessibilityHidden(true)
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.forward")
                    .font(.caption.bold())
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }

            HStack(spacing: 7) {
                LocalizedSystemLabel(
                    title: status.localizedTitle,
                    systemImage: status.symbolName
                )
                if let firstFormat {
                    Text(firstFormat.localizedTitle)
                }
            }
            .font(.caption)
            .foregroundStyle(status == .completed ? Color.green : .secondary)

            ProgressView(value: Double(answeredPartCount), total: Double(max(partCount, 1)))
                .tint(status == .completed ? .green : .accentColor)
                .accessibilityLabel("Question completion")
                .accessibilityValue("\(answeredPartCount) of \(partCount) parts answered")
        }
        .padding(14)
        .background {
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .fill(Color(uiColor: .tertiarySystemGroupedBackground))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .strokeBorder(Color(uiColor: .separator).opacity(0.25), lineWidth: 0.5)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens this question at the current part.")
    }
}
