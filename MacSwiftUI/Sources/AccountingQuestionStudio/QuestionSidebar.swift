import AccountingQuestionKit
import SwiftUI

struct QuestionSidebar: View {
    let store: AppStore

    var body: some View {
        @Bindable var store = store

        VStack(spacing: 0) {
            QuestionFilterBar(store: store)
            Divider()
            List(selection: $store.selectedQuestionID) {
                ForEach(store.visibleQuestions) { question in
                    QuestionSidebarRow(
                        title: question.title,
                        shell: question.shell,
                        progress: store.progress(for: question)
                    )
                    .tag(question.id)
                }
            }
            .overlay {
                if store.visibleQuestions.isEmpty {
                    QuestionSidebarEmptyView(
                        hasQuestions: !store.questions.isEmpty,
                        isFiltered: store.hasActiveFilters,
                        clearFilters: store.clearAllFilters
                    )
                }
            }
        }
        .navigationTitle("Question Library")
        .searchable(text: $store.searchText, prompt: "Search questions")
    }
}

private struct QuestionFilterBar: View {
    let store: AppStore

    var body: some View {
        HStack(spacing: 8) {
            Menu {
                Button("All Formats", systemImage: "line.3.horizontal.decrease.circle") {
                    store.clearFormatFilters()
                }
                .disabled(store.selectedFormats.isEmpty)

                Divider()

                ForEach(QuestionFormat.allCases, id: \.self) { format in
                    Button {
                        store.toggleFormat(format)
                    } label: {
                        LocalizedSystemLabel(
                            title: format.localizedName,
                            systemImage: store.selectedFormats.contains(format)
                                ? "checkmark"
                                : "circle"
                        )
                    }
                }
            } label: {
                Label("Formats", systemImage: "line.3.horizontal.decrease")
            }
            .menuStyle(.button)
            .buttonStyle(.borderless)

            if !store.selectedFormats.isEmpty {
                Text(store.selectedFormats.count, format: .number)
                    .font(.caption.monospacedDigit())
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Color.accentColor.opacity(0.13), in: Capsule())
                    .accessibilityLabel(
                        "\(store.selectedFormats.count) selected format filters"
                    )

                Button("Clear Format Filters", systemImage: "xmark.circle.fill") {
                    store.clearFormatFilters()
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
            }

            Spacer()

            Text(store.visibleQuestions.count, format: .number)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .accessibilityLabel("\(store.visibleQuestions.count) visible questions")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }
}

private struct QuestionSidebarRow: View {
    let title: String
    let shell: QuestionShell
    let progress: QuestionProgress

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: progress.isComplete ? "checkmark.circle.fill" : "doc.text")
                .foregroundStyle(progress.isComplete ? Color.green : .secondary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .lineLimit(2)
                HStack(spacing: 6) {
                    Text(shell.localizedName)
                    Text("•")
                    Text("\(progress.answeredParts)/\(progress.totalParts)")
                        .monospacedDigit()
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                ProgressView(value: progress.fractionAnswered)
                    .controlSize(.mini)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityValue("\(progress.answeredParts) of \(progress.totalParts) parts answered")
    }
}

private struct QuestionSidebarEmptyView: View {
    let hasQuestions: Bool
    let isFiltered: Bool
    let clearFilters: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            if hasQuestions && isFiltered {
                ContentUnavailableView.search
                Button("Clear Search and Filters", action: clearFilters)
            } else {
                ContentUnavailableView(
                    "No Questions Yet",
                    systemImage: "tray",
                    description: Text("Import a Markdown question pack to begin.")
                )
            }
        }
    }
}
