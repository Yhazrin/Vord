import XCTest
@testable import Vord

final class CompanionMarkdownTests: XCTestCase {
    func testReplyStructureKeepsWordsListsAndCode() {
        let blocks = CompanionMarkdown.blocks("""
        ## 今天先看这两个
        **mitigate** 是减轻，不是消灭。

        - 先回忆中文
        - 再看例句

        1. exacerbate
        2. deteriorate

        `due` 只表示到期。

        ```
        mitigate the risk
        ```
        """)
        XCTAssertEqual(blocks.count, 8)
        guard case .heading(2, let title) = blocks[0] else { return XCTFail("heading") }
        XCTAssertEqual(title, [.plain("今天先看这两个")])
        guard case .paragraph(let meaning) = blocks[1] else { return XCTFail("paragraph") }
        XCTAssertEqual(meaning.first, .bold([.plain("mitigate")]))
        guard case .bullet(let first) = blocks[2], case .bullet = blocks[3] else { return XCTFail("bullets") }
        XCTAssertEqual(first, [.plain("先回忆中文")])
        guard case .numbered(1, _) = blocks[4], case .numbered(2, _) = blocks[5] else { return XCTFail("numbers") }
        guard case .paragraph(let codeLine) = blocks[6] else { return XCTFail("inline code") }
        XCTAssertTrue(codeLine.contains(.code("due")))
        guard case .code(let fenced) = blocks[7] else { return XCTFail("code block") }
        XCTAssertEqual(fenced, "mitigate the risk")
    }

    func testLinksAndTablesStayStructured() {
        let blocks = CompanionMarkdown.blocks("""
        参见 [用法](https://example.com/usage)

        | 词 | 方向 |
        | --- | --- |
        | mitigate | 英 → 中 |
        """)
        XCTAssertEqual(blocks.count, 2)
        guard case .paragraph(let line) = blocks[0] else { return XCTFail("link paragraph") }
        XCTAssertEqual(line, [
            .plain("参见 "),
            .link(label: "用法", url: URL(string: "https://example.com/usage")!)
        ])
        guard case .table(let headers, let rows) = blocks[1] else { return XCTFail("table") }
        XCTAssertEqual(headers, ["词", "方向"])
        XCTAssertEqual(rows, [["mitigate", "英 → 中"]])
    }

    func testBrokenMarkersStayVisible() {
        let blocks = CompanionMarkdown.blocks("记住 **这个词\n\nsnake_case 和 <b>标签</b> 都原样保留")
        XCTAssertEqual(blocks.count, 2)
        guard case .paragraph(let first) = blocks[0] else { return XCTFail("open marker") }
        XCTAssertEqual(first, [.plain("记住 **这个词")])
        guard case .paragraph(let second) = blocks[1] else { return XCTFail("literal markup") }
        XCTAssertEqual(second, [.plain("snake_case 和 <b>标签</b> 都原样保留")])
    }
}
