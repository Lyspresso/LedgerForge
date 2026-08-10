import Foundation
import SwiftUI

struct MarkdownText: View {
    let markdown: String
    var font: Font = .body
    var fontDesign: Font.Design = .serif

    @State private var rendered: AttributedString?

    var body: some View {
        Text(rendered ?? AttributedString(markdown))
            .font(font)
            .fontDesign(fontDesign)
            .lineSpacing(4)
            .textSelection(.enabled)
            .task(id: markdown) {
                rendered = nil
                let result = await MarkdownRenderer.render(markdown)
                guard !Task.isCancelled else { return }
                rendered = result
            }
    }
}

private enum MarkdownRenderer {
    static func render(_ source: String) async -> AttributedString {
        await Task.detached(priority: .userInitiated) {
            let options = AttributedString.MarkdownParsingOptions(
                interpretedSyntax: .full,
                failurePolicy: .returnPartiallyParsedIfPossible
            )
            return (try? AttributedString(markdown: source, options: options))
                ?? AttributedString(source)
        }.value
    }
}
