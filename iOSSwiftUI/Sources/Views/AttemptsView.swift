import SwiftUI

struct AttemptsView: View {
    let store: AccountingSuiteStore

    var body: some View {
        ScrollView {
            AttemptsBody(attempts: store.attemptSummaries)
        }
        .background {
            StudyBackground()
        }
        .navigationTitle("Attempts")
    }
}

private struct AttemptsBody: View {
    let attempts: [AttemptSummary]

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 14) {
            if attempts.isEmpty {
                StudySurface {
                    ContentUnavailableView(
                        "No attempts yet",
                        systemImage: "pencil.and.list.clipboard",
                        description: Text("Open a question and start an attempt to track your work.")
                    )
                    .frame(maxWidth: .infinity)
                }
            } else {
                ForEach(attempts) { attempt in
                    AttemptRow(attempt: attempt)
                }
            }
        }
        .frame(maxWidth: 720)
        .padding(20)
        .frame(maxWidth: .infinity)
    }
}

private struct AttemptRow: View {
    let attempt: AttemptSummary

    var body: some View {
        StudySurface {
            VStack(alignment: .leading, spacing: 12) {
                if let packID = attempt.packID {
                    NavigationLink(
                        value: AppRoute.question(packID: packID, questionID: attempt.questionID)
                    ) {
                        AttemptRowContent(attempt: attempt)
                    }
                    .buttonStyle(.plain)
                } else {
                    AttemptRowContent(attempt: attempt)
                }
            }
        }
    }
}

private struct AttemptRowContent: View {
    let attempt: AttemptSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(attempt.title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Spacer()
                Image(systemName: "chevron.forward")
                    .font(.caption.bold())
                    .foregroundStyle(.tertiary)
                    .opacity(attempt.packID == nil ? 0 : 1)
            }

            ProgressView(value: attempt.progress)
                .tint(.accentColor)
                .accessibilityLabel("Attempt progress")
                .accessibilityValue("\(attempt.answeredPartCount) of \(attempt.totalPartCount) parts answered")

            HStack {
                Text("\(attempt.answeredPartCount) of \(attempt.totalPartCount) parts answered")
                Spacer()
                Text(attempt.updatedAt, format: .relative(presentation: .named))
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }
}
