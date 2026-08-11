import AccountingQuestionKit
import SwiftUI

@main
struct AccountingQuestionStudioApp: App {
    @State private var store = AppStore()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView(store: store)
                .task {
                    await store.restore()
                }
                .onChange(of: scenePhase) { _, newPhase in
                    guard newPhase != .active else { return }
                    Task {
                        await store.flushPendingSave()
                    }
                }
        }
        .defaultSize(width: 1_180, height: 760)
        .windowResizability(.contentMinSize)
        .commands {
            SidebarCommands()
            QuestionLibraryCommands(store: store)
        }
    }
}

struct QuestionLibraryCommands: Commands {
    let store: AppStore

    var body: some Commands {
        CommandGroup(after: .importExport) {
            Button("Import Markdown…", systemImage: "square.and.arrow.down") {
                store.presentImporter()
            }
            .keyboardShortcut("i", modifiers: [.command, .shift])
            .disabled(store.isImporting)

            Button("Load Complete Format Sample", systemImage: "sparkles.rectangle.stack") {
                store.loadCompleteFormatSample()
            }
            .keyboardShortcut("l", modifiers: [.command, .shift])
            .disabled(store.isImporting)

            Button("Load Spreadsheet Practice Sample", systemImage: "tablecells") {
                store.loadSpreadsheetPracticeSample()
            }
            .keyboardShortcut("l", modifiers: [.command, .option])
            .disabled(store.isImporting)
        }

        CommandMenu("Questions") {
            Button("Check Current Answer", systemImage: "checkmark.circle") {
                store.checkActivePart()
            }
            .keyboardShortcut(.return, modifiers: [.command])
            .disabled(!store.canCheckActivePart)

            Button("Reveal Current Answer", systemImage: "eye") {
                store.toggleActiveReveal()
            }
            .keyboardShortcut("r", modifiers: [.command, .shift])
            .disabled(!store.canRevealActivePart)

            Divider()

            Button("Previous Question", systemImage: "chevron.left") {
                store.selectAdjacentQuestion(offset: -1)
            }
            .keyboardShortcut("[", modifiers: [.command])
            .disabled(!store.canSelectPreviousQuestion)

            Button("Next Question", systemImage: "chevron.right") {
                store.selectAdjacentQuestion(offset: 1)
            }
            .keyboardShortcut("]", modifiers: [.command])
            .disabled(!store.canSelectNextQuestion)

            Menu("Filter by Format", systemImage: "line.3.horizontal.decrease") {
                Button("All Formats") {
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
            }

            Divider()

            Button("Toggle Inspector", systemImage: "sidebar.right") {
                store.isInspectorPresented.toggle()
            }
            .keyboardShortcut("i", modifiers: [.command, .option])
        }
    }
}
