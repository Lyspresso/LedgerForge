import SwiftUI

struct AppShellView: View {
    let store: AccountingSuiteStore
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            LibraryView(store: store)
                .navigationDestination(for: AppRoute.self) { route in
                    AppDestinationView(route: route, store: store)
                }
        }
        .task {
            await store.loadIfNeeded()
        }
        .onOpenURL { url in
            guard url.isFileURL else { return }
            Task {
                await store.loadIfNeeded()
                await store.importMarkdown(from: url)
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase != .active else { return }
            Task {
                await store.flushPersistence()
            }
        }
    }
}

private struct AppDestinationView: View {
    let route: AppRoute
    let store: AccountingSuiteStore

    var body: some View {
        VStack(spacing: 0) {
            switch route {
            case .attempts:
                AttemptsView(store: store)
            case .question:
                if let question = store.questionScreen(for: route) {
                    QuestionStudyView(question: question, store: store)
                } else {
                    ContentUnavailableView(
                        "Question unavailable",
                        systemImage: "questionmark.folder",
                        description: Text("The imported pack may have been replaced.")
                    )
                }
            }
        }
    }
}
