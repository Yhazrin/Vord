import SwiftUI

/// Block structure for companion replies. Inline emphasis is parsed here so a
/// broken marker cannot swallow the rest of the message the way a full
/// Markdown document parser does.
enum CompanionMarkdown {
    enum Inline: Equatable {
        case plain(String)
        case bold([Inline])
        case italic([Inline])
        case strike([Inline])
        case code(String)
        case link(label: String, url: URL)
    }

    enum Block: Equatable {
        case heading(level: Int, inlines: [Inline])
        case paragraph([Inline])
        case bullet([Inline])
        case numbered(Int, [Inline])
        case quote([Inline])
        case code(String)
        case rule
        case table(headers: [String], rows: [[String]])
    }

    static func blocks(_ source: String) -> [Block] {
        let normalized = source.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        let lines = normalized.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var result: [Block] = []
        var paragraph: [String] = []
        var index = 0

        func flushParagraph() {
            let text = paragraph.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            paragraph.removeAll()
            if !text.isEmpty { result.append(.paragraph(inlines(text))) }
        }

        while index < lines.count {
            let raw = lines[index]
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("```") {
                flushParagraph()
                var code: [String] = []
                index += 1
                while index < lines.count, !lines[index].trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                    code.append(lines[index])
                    index += 1
                }
                if index < lines.count { index += 1 }
                result.append(.code(code.joined(separator: "\n")))
                continue
            }
            if line.isEmpty {
                flushParagraph()
                index += 1
                continue
            }
            if line == "---" || line == "***" {
                flushParagraph()
                result.append(.rule)
                index += 1
                continue
            }
            if let heading = heading(line) {
                flushParagraph()
                result.append(.heading(level: heading.level, inlines: inlines(heading.text)))
                index += 1
                continue
            }
            if let table = table(lines, from: index) {
                flushParagraph()
                result.append(table.block)
                index = table.next
                continue
            }
            if let item = bullet(line) {
                flushParagraph()
                result.append(.bullet(inlines(item)))
                index += 1
                continue
            }
            if let item = numbered(line) {
                flushParagraph()
                result.append(.numbered(item.number, inlines(item.text)))
                index += 1
                continue
            }
            if line.hasPrefix(">") {
                flushParagraph()
                let quoted = line.dropFirst()
                let text = quoted.first == " " ? String(quoted.dropFirst()) : String(quoted)
                result.append(.quote(inlines(text)))
                index += 1
                continue
            }
            paragraph.append(raw)
            index += 1
        }
        flushParagraph()
        return result
    }

    static func inlines(_ source: String) -> [Inline] {
        var output: [Inline] = []
        var buffer = ""
        var index = source.startIndex

        func flush() {
            guard !buffer.isEmpty else { return }
            output.append(.plain(buffer))
            buffer = ""
        }

        while index < source.endIndex {
            if let taken = take(source, from: index) {
                flush()
                output.append(taken.inline)
                index = taken.next
                continue
            }
            buffer.append(source[index])
            index = source.index(after: index)
        }
        flush()
        return output
    }

    static func attributed(_ items: [Inline], size: CGFloat, weight: Font.Weight = .regular, italic: Bool = false) -> AttributedString {
        var result = AttributedString()
        for item in items {
            switch item {
            case .plain(let text):
                result += run(text, size: size, weight: weight, italic: italic)
            case .bold(let inner):
                result += attributed(inner, size: size, weight: .semibold, italic: italic)
            case .italic(let inner):
                result += attributed(inner, size: size, weight: weight, italic: true)
            case .strike(let inner):
                var piece = attributed(inner, size: size, weight: weight, italic: italic)
                piece.strikethroughStyle = .single
                result += piece
            case .code(let text):
                var piece = AttributedString(text)
                piece.font = .system(size: max(size - 1, 11), weight: .regular, design: .monospaced)
                piece.backgroundColor = AppColors.accentWash
                result += piece
            case .link(let label, let url):
                var piece = run(label, size: size, weight: weight, italic: italic)
                piece.link = url
                piece.underlineStyle = .single
                result += piece
            }
        }
        return result
    }

    private static func run(_ text: String, size: CGFloat, weight: Font.Weight, italic: Bool) -> AttributedString {
        var piece = AttributedString(text)
        let base = AppTypography.ui(size: size, weight: weight)
        piece.font = italic ? base.italic() : base
        return piece
    }

    private static func take(_ source: String, from index: String.Index) -> (inline: Inline, next: String.Index)? {
        if source[index] == "`" {
            let start = source.index(after: index)
            guard start < source.endIndex, let close = source[start...].firstIndex(of: "`"), close > start else { return nil }
            return (.code(String(source[start..<close])), source.index(after: close))
        }
        if let wrapped = wrapped(source, from: index, token: "**") ?? wrapped(source, from: index, token: "__") {
            return (.bold(inlines(wrapped.inner)), wrapped.next)
        }
        if let wrapped = wrapped(source, from: index, token: "~~") {
            return (.strike(inlines(wrapped.inner)), wrapped.next)
        }
        if let wrapped = wrapped(source, from: index, token: "*") {
            return (.italic(inlines(wrapped.inner)), wrapped.next)
        }
        if source[index] == "[" { return link(source, from: index) }
        return nil
    }

    private static func wrapped(_ source: String, from index: String.Index, token: String) -> (inner: String, next: String.Index)? {
        guard source[index...].hasPrefix(token) else { return nil }
        if token == "*", source[index...].hasPrefix("**") { return nil }
        let start = source.index(index, offsetBy: token.count)
        guard start < source.endIndex, !source[start].isWhitespace else { return nil }
        var cursor = start
        while cursor < source.endIndex {
            if source[cursor...].hasPrefix(token) {
                if token == "*", source[cursor...].hasPrefix("**") {
                    cursor = source.index(cursor, offsetBy: 2)
                    continue
                }
                let previous = source.index(before: cursor)
                if previous >= start, !source[previous].isWhitespace, cursor > start {
                    return (String(source[start..<cursor]), source.index(cursor, offsetBy: token.count))
                }
            }
            cursor = source.index(after: cursor)
        }
        return nil
    }

    private static func link(_ source: String, from index: String.Index) -> (inline: Inline, next: String.Index)? {
        guard let bracket = source[index...].firstIndex(of: "]") else { return nil }
        let labelStart = source.index(after: index)
        guard bracket > labelStart else { return nil }
        let paren = source.index(after: bracket)
        guard paren < source.endIndex, source[paren] == "(" else { return nil }
        let urlStart = source.index(after: paren)
        guard let close = source[urlStart...].firstIndex(of: ")"), close > urlStart else { return nil }
        let label = String(source[labelStart..<bracket])
        let raw = String(source[urlStart..<close])
        guard let url = URL(string: raw), let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else { return nil }
        return (.link(label: label, url: url), source.index(after: close))
    }

    private static func heading(_ line: String) -> (level: Int, text: String)? {
        let marks = line.prefix { $0 == "#" }
        let level = marks.count
        guard (1...3).contains(level) else { return nil }
        let rest = line.dropFirst(level)
        guard rest.first == " " else { return nil }
        let text = rest.dropFirst().trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return nil }
        return (level, text)
    }

    private static func bullet(_ line: String) -> String? {
        for prefix in ["- ", "* ", "• "] where line.hasPrefix(prefix) {
            let text = String(line.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
            return text.isEmpty ? nil : text
        }
        return nil
    }

    private static func numbered(_ line: String) -> (number: Int, text: String)? {
        var digits = ""
        var cursor = line.startIndex
        while cursor < line.endIndex, line[cursor].isNumber {
            digits.append(line[cursor])
            cursor = line.index(after: cursor)
        }
        guard !digits.isEmpty, cursor < line.endIndex, line[cursor] == "." else { return nil }
        let afterDot = line.index(after: cursor)
        guard afterDot < line.endIndex, line[afterDot] == " " else { return nil }
        let text = line[line.index(after: afterDot)...].trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty, let number = Int(digits) else { return nil }
        return (number, text)
    }

    private static func table(_ lines: [String], from index: Int) -> (block: Block, next: Int)? {
        guard index + 1 < lines.count, isRow(lines[index]), isSeparator(lines[index + 1]) else { return nil }
        let headers = cells(lines[index])
        guard !headers.isEmpty else { return nil }
        var rows: [[String]] = []
        var cursor = index + 2
        while cursor < lines.count, isRow(lines[cursor]), !isSeparator(lines[cursor]) {
            var row = cells(lines[cursor])
            if row.count < headers.count { row += Array(repeating: "", count: headers.count - row.count) }
            rows.append(Array(row.prefix(headers.count)))
            cursor += 1
        }
        return (.table(headers: headers, rows: rows), cursor)
    }

    private static func isRow(_ line: String) -> Bool {
        line.contains("|")
    }

    private static func isSeparator(_ line: String) -> Bool {
        let parts = cells(line)
        guard !parts.isEmpty else { return false }
        return parts.allSatisfy { cell in
            let marks = cell.filter { $0 != ":" && $0 != " " }
            return !marks.isEmpty && marks.allSatisfy { $0 == "-" }
        }
    }

    private static func cells(_ line: String) -> [String] {
        var text = line.trimmingCharacters(in: .whitespaces)
        if text.hasPrefix("|") { text.removeFirst() }
        if text.hasSuffix("|") { text.removeLast() }
        return text.split(separator: "|", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
    }
}

struct CompanionRichText: View {
    var text: String
    var compact = false

    private var size: CGFloat { compact ? 13 : 15 }

    var body: some View {
        let blocks = CompanionMarkdown.blocks(text)
        if blocks.isEmpty {
            Text(text).font(AppTypography.ui(size: size)).lineSpacing(5)
        } else {
            VStack(alignment: .leading, spacing: compact ? 8 : 12) {
                ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                    blockView(block)
                }
            }
        }
    }

    @ViewBuilder private func blockView(_ block: CompanionMarkdown.Block) -> some View {
        switch block {
        case .heading(let level, let items):
            Text(CompanionMarkdown.attributed(items, size: headingSize(level), weight: .semibold))
                .lineSpacing(3).fixedSize(horizontal: false, vertical: true)
        case .paragraph(let items):
            Text(CompanionMarkdown.attributed(items, size: size))
                .lineSpacing(5).fixedSize(horizontal: false, vertical: true)
        case .bullet(let items):
            labelRow("•", CompanionMarkdown.attributed(items, size: size))
        case .numbered(let number, let items):
            labelRow("\(number).", CompanionMarkdown.attributed(items, size: size))
        case .quote(let items):
            HStack(alignment: .top, spacing: 10) {
                RoundedRectangle(cornerRadius: 1).fill(AppColors.hairline).frame(width: 2)
                Text(CompanionMarkdown.attributed(items, size: size))
                    .foregroundStyle(AppColors.secondaryText)
                    .lineSpacing(5).fixedSize(horizontal: false, vertical: true)
            }
        case .code(let code):
            Text(code.isEmpty ? " " : code)
                .font(.system(size: max(size - 1, 11), design: .monospaced))
                .lineSpacing(3).textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(AppColors.elevatedSurface, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(AppColors.hairline, lineWidth: 1))
        case .rule:
            Hairline().padding(.vertical, 2)
        case .table(let headers, let rows):
            VStack(alignment: .leading, spacing: 0) {
                tableRow(headers, header: true)
                Hairline()
                ForEach(Array(rows.enumerated()), id: \.offset) { offset, row in
                    tableRow(row, header: false)
                    if offset < rows.count - 1 { Hairline() }
                }
            }
            .background(AppColors.elevatedSurface, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(AppColors.hairline, lineWidth: 1))
        }
    }

    private func labelRow(_ marker: String, _ content: AttributedString) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(marker).font(AppTypography.ui(size: size)).foregroundStyle(AppColors.secondaryText)
                .frame(minWidth: compact ? 14 : 16, alignment: .trailing)
            Text(content).lineSpacing(5).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func tableRow(_ cells: [String], header: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ForEach(Array(cells.enumerated()), id: \.offset) { _, cell in
                Text(CompanionMarkdown.attributed(CompanionMarkdown.inlines(cell), size: compact ? 12 : 13, weight: header ? .semibold : .regular))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
    }

    private func headingSize(_ level: Int) -> CGFloat {
        switch level {
        case 1: return size + 4
        case 2: return size + 2
        default: return size
        }
    }
}
