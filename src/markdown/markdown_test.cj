package cangmo.markdown

import std.unittest.*
import std.unittest.testmacro.*

@Test
func testMarkdownBasics(): Unit {
    let result = MarkdownRenderer().render("# 标题\n\n这是 **加粗** 和 `代码`。\n\n- 一\n- 二\n")
    @Assert(result.html.contains("<h1 id="))
    @Assert(result.html.contains("<strong>加粗</strong>"))
    @Assert(result.html.contains("<code>代码</code>"))
    @Assert(result.html.contains("<li>一</li>"))
}

@Test
func testMarkdownEscapesHtml(): Unit {
    let result = MarkdownRenderer().render("<script>alert(1)</script>\n\n[bad](javascript:alert(1))\n")
    @Assert(!result.html.contains("<script>"))
    @Assert(!result.html.contains("javascript:"))
}

@Test
func testMarkdownCodeFence(): Unit {
    let result = MarkdownRenderer().render("```cangjie\nprintln(\"hi\")\n```\n")
    @Assert(result.html.contains("language-cangjie"))
    @Assert(result.html.contains("println"))
}

@Test
func testMarkdownTable(): Unit {
    let result = MarkdownRenderer().render("| A | B |\n| --- | --- |\n| 1 | 2 |\n")
    @Assert(result.html.contains("<table>"))
    @Assert(result.html.contains("<th>A</th>"))
}

@Test
func testMarkdownHeadingsToc(): Unit {
    let result = MarkdownRenderer().render("## 第一节\n\ntext\n\n## 第二节\n")
    @Expect(result.headings.size, 2)
    @Expect(result.headings[0].text, "第一节")
}
