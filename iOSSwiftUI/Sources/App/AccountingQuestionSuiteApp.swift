import SwiftUI

@main
struct AccountingQuestionSuiteApp: App {
    @State private var store = AccountingSuiteStore()

    var body: some Scene {
        WindowGroup {
            AppShellView(store: store)
        }
    }
}

