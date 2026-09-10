import Foundation

enum ChatMarkdownRenderer {
    static func attributed(_ source: String) -> AttributedString {
        guard !source.isEmpty else { return AttributedString("…") }
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .full,
            failurePolicy: .returnPartiallyParsedIfPossible
        )
        return (try? AttributedString(markdown: source, options: options)) ?? AttributedString(source)
    }
}
