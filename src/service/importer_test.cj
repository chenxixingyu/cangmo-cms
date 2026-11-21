package cangmo.service

import std.unittest.*
import std.unittest.testmacro.*

@Test
func testImportFrontMatter(): Unit {
    let doc = parseMarkdownDocument("---\ntitle: 导入标题\ntags: 仓颉, 博客\npinned: true\n---\n\n## 正文\n\n内容", "fallback.md")
    @Expect(doc.title, "导入标题")
    @Expect(doc.tags.size, 2)
    @Expect(doc.tags[0], "仓颉")
    @Assert(doc.pinned)
    @Assert(doc.content.contains("## 正文"))
}

@Test
func testImportFilenameFallback(): Unit {
    let doc = parseMarkdownDocument("# 只有正文\n\n内容", "my-post.md")
    @Expect(doc.title, "my-post")
    @Assert(doc.content.contains("只有正文"))
}

@Test
func testImportQuotedAndCrlf(): Unit {
    let doc = parseMarkdownDocument("---\r\ntitle: \"带引号\"\r\nsummary: 摘要\r\n---\r\n\r\n正文", "x.md")
    @Expect(doc.title, "带引号")
    @Expect(doc.summary, "摘要")
    @Expect(doc.content, "正文")
}
