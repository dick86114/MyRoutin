import AppKit
import SwiftUI

enum UpdateNotesRenderer {
    static func attributedText(notes: String) -> AttributedString? {
        if let html = htmlAttributedText(notes: notes) {
            return AttributedString(html)
        }
        return markdownAttributedText(notes: notes)
    }

    static func plainText(notes: String) -> String {
        if let html = htmlAttributedText(notes: notes) {
            return html.string.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return notes
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .map { line in
                if let markdown = try? AttributedString(markdown: line) {
                    return String(markdown.characters)
                }
                return line
            }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func htmlAttributedText(notes: String) -> NSAttributedString? {
        guard notes.contains("<"), notes.contains(">"),
              let data = notes.data(using: .utf8) else {
            return nil
        }
        return try? NSAttributedString(
            data: data,
            options: [
                .documentType: NSAttributedString.DocumentType.html,
                .characterEncoding: String.Encoding.utf8.rawValue
            ],
            documentAttributes: nil
        )
    }

    private static func markdownAttributedText(notes: String) -> AttributedString {
        var result = AttributedString()
        var isInsideCodeBlock = false

        for line in notes.components(separatedBy: .newlines) {
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)

            if trimmedLine.hasPrefix("```") {
                isInsideCodeBlock.toggle()
                continue
            }

            if isInsideCodeBlock {
                var codeLine = AttributedString(line)
                codeLine.font = .system(size: 12, weight: .regular, design: .monospaced)
                codeLine.foregroundColor = .primary
                result += codeLine
                appendNewline(to: &result)
                continue
            }

            if trimmedLine.isEmpty {
                continue
            }

            let headingMarkerCount = trimmedLine.prefix(while: { $0 == "#" }).count
            if headingMarkerCount >= 1, headingMarkerCount <= 6,
               trimmedLine.dropFirst(headingMarkerCount).hasPrefix(" ") {
                let content = String(trimmedLine.dropFirst(headingMarkerCount + 1))
                appendInlineText(content, to: &result, font: headingFont(level: headingMarkerCount))
                appendNewline(to: &result)
                continue
            }

            if let marker = trimmedLine.first, marker == "-" || marker == "*" || marker == "+",
               trimmedLine.dropFirst().hasPrefix(" ") {
                let content = String(trimmedLine.dropFirst(2))
                appendInlineText(
                    content,
                    to: &result,
                    prefix: "•  ",
                    font: .callout
                )
                appendNewline(to: &result)
                continue
            }

            let digits = trimmedLine.prefix(while: \.isNumber)
            if !digits.isEmpty, trimmedLine.dropFirst(digits.count).hasPrefix(". ") {
                let content = String(trimmedLine.dropFirst(digits.count + 2))
                appendInlineText(
                    content,
                    to: &result,
                    prefix: "\(digits). ",
                    font: .callout
                )
                appendNewline(to: &result)
                continue
            }

            appendInlineText(trimmedLine, to: &result, font: .callout)
            appendNewline(to: &result)
        }

        result.characters.removeLast(result.characters.isEmpty ? 0 : 1)
        return result
    }

    private static func appendInlineText(
        _ content: String,
        to result: inout AttributedString,
        prefix: String = "",
        font: Font
    ) {
        if !prefix.isEmpty {
            var marker = AttributedString(prefix)
            marker.font = font
            marker.foregroundColor = .secondary
            result += marker
        }

        guard let inlineText = try? AttributedString(
            markdown: content,
            options: .init(allowsExtendedAttributes: true)
        ) else {
            var plain = AttributedString(content)
            plain.font = font
            result += plain
            return
        }

        var styledText = inlineText
        for run in styledText.runs {
            styledText[run.range].font = font
        }
        result += styledText
    }

    private static func headingFont(level: Int) -> Font {
        switch level {
        case 1: .title3.weight(.bold)
        case 2: .headline
        case 3: .subheadline.weight(.semibold)
        case 4: .callout.weight(.semibold)
        default: .caption.weight(.semibold)
        }
    }

    private static func appendNewline(to result: inout AttributedString) {
        result += AttributedString("\n")
    }
}

enum UpdateNotesAccessibility {
    static func label(notes: String) -> String {
        let trimmed = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return "更新日志，此版本未提供更新日志"
        }
        let readableText = UpdateNotesRenderer.plainText(notes: notes)
        return "更新日志，\(readableText)"
    }
}

struct UpdateNotesView: View {
    let notes: String

    var body: some View {
        Group {
            if notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text("此版本未提供更新日志")
            } else if let attributedText = UpdateNotesRenderer.attributedText(notes: notes) {
                Text(attributedText)
            } else {
                Text(notes)
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityLabel(UpdateNotesAccessibility.label(notes: notes))
    }
}
