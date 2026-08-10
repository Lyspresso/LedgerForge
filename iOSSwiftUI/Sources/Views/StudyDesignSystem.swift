import Foundation
import SwiftUI

struct StudyBackground: View {
    var body: some View {
        ZStack {
            Color(uiColor: .systemGroupedBackground)
            LinearGradient(
                colors: [
                    Color.accentColor.opacity(0.10),
                    Color(uiColor: .systemGroupedBackground).opacity(0)
                ],
                startPoint: .topLeading,
                endPoint: .center
            )
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

struct StudySurface<Content: View>: View {
    let prominence: Prominence
    let content: Content

    enum Prominence {
        case standard
        case emphasized
        case inset
    }

    init(
        prominence: Prominence = .standard,
        @ViewBuilder content: () -> Content
    ) {
        self.prominence = prominence
        self.content = content()
    }

    var body: some View {
        content
            .padding(prominence == .inset ? 14 : 18)
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(backgroundColor)
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(borderColor, lineWidth: prominence == .emphasized ? 1 : 0.5)
            }
            .shadow(
                color: prominence == .emphasized ? .black.opacity(0.07) : .clear,
                radius: 3,
                y: 1
            )
    }

    private var cornerRadius: CGFloat {
        prominence == .inset ? 13 : 19
    }

    private var backgroundColor: Color {
        switch prominence {
        case .standard, .emphasized:
            Color(uiColor: .secondarySystemGroupedBackground)
        case .inset:
            Color(uiColor: .tertiarySystemGroupedBackground)
        }
    }

    private var borderColor: Color {
        switch prominence {
        case .emphasized:
            Color.accentColor.opacity(0.24)
        case .standard, .inset:
            Color(uiColor: .separator).opacity(0.28)
        }
    }
}

struct SectionEyebrow: View {
    let title: LocalizedStringResource
    let systemImage: String

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.caption.smallCaps().weight(.semibold))
            .foregroundStyle(.tint)
            .accessibilityAddTraits(.isHeader)
    }
}

struct MarkdownProse: View {
    let markdown: String
    var style: Font = .body

    var body: some View {
        if let attributed = try? AttributedString(
            markdown: markdown,
            options: .init(interpretedSyntax: .full)
        ) {
            Text(attributed)
                .font(style)
                .fontDesign(.serif)
                .textSelection(.enabled)
        } else {
            Text(markdown)
                .font(style)
                .fontDesign(.serif)
                .textSelection(.enabled)
        }
    }
}

struct ResponsiveActionLayout<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                content
            }
            VStack(alignment: .leading, spacing: 10) {
                content
            }
        }
    }
}
