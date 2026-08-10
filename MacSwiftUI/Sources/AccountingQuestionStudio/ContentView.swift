import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    let store: AppStore
    @FocusedValue(\.activeQuestionPart) private var focusedPart

    var body: some View {
        @Bindable var store = store

        NavigationSplitView {
            QuestionSidebar(store: store)
                .navigationSplitViewColumnWidth(min: 220, ideal: 270, max: 380)
        } detail: {
            QuestionDetailView(store: store)
        }
        .inspector(isPresented: $store.isInspectorPresented) {
            QuestionInspectorView(store: store)
                .inspectorColumnWidth(min: 240, ideal: 280, max: 400)
        }
        .toolbar {
            ToolbarItem {
                ControlGroup {
                    Button("Previous Question", systemImage: "chevron.left") {
                        store.selectAdjacentQuestion(offset: -1)
                    }
                    .disabled(!store.canSelectPreviousQuestion)
                    Button("Next Question", systemImage: "chevron.right") {
                        store.selectAdjacentQuestion(offset: 1)
                    }
                    .disabled(!store.canSelectNextQuestion)
                }
                .labelStyle(.iconOnly)
            }

            ToolbarItemGroup(placement: .primaryAction) {
                Button("Check Current Answer", systemImage: "checkmark.circle") {
                    store.checkActivePart()
                }
                .help("Check the current response (Command-Return)")
                .disabled(!store.canCheckActivePart)

                Button("Reveal Current Answer", systemImage: "eye") {
                    store.toggleActiveReveal()
                }
                .help("Reveal or hide the current model answer (Shift-Command-R)")
                .disabled(!store.canRevealActivePart)

                Button("Import Markdown…", systemImage: "square.and.arrow.down") {
                    store.presentImporter()
                }
                .help("Import Markdown question packs")
                .disabled(store.isImporting)

                Button("Toggle Inspector", systemImage: "sidebar.right") {
                    store.isInspectorPresented.toggle()
                }
                .help("Show or hide the inspector")
            }
        }
        .fileImporter(
            isPresented: $store.isImporterPresented,
            allowedContentTypes: [
                UTType(filenameExtension: "md") ?? .plainText,
                .plainText
            ],
            allowsMultipleSelection: true
        ) { result in
            store.receiveImportSelection(result)
        }
        .onOpenURL { url in
            guard url.isFileURL else { return }
            Task {
                await store.importFiles(at: [url])
            }
        }
        .alert(
            store.alert?.title ?? String(localized: "Notice"),
            isPresented: $store.isAlertPresented,
            presenting: store.alert
        ) { _ in
            Button("OK") {
                store.dismissAlert()
            }
        } message: { alert in
            Text(alert.message)
        }
        .overlay(alignment: .bottom) {
            if store.isImporting {
                ImportProgressView()
                    .padding()
            }
        }
        .frame(minWidth: 760, minHeight: 540)
        .onChange(of: focusedPart) { _, newPart in
            guard let newPart,
                  newPart.questionID == store.selectedQuestionID else { return }
            store.activatePart(newPart.partID)
        }
    }
}

private struct ImportProgressView: View {
    var body: some View {
        HStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)
            Text("Importing questions…")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: Capsule())
        .shadow(radius: 8, y: 3)
        .accessibilityElement(children: .combine)
    }
}
