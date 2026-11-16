package cangmo.web

import cangmo.core.*
import cangmo.json.*
import std.unittest.*
import std.unittest.testmacro.*

@Test
func testDateTimeInput(): Unit {
    @Assert(parseDateTimeInput("2026-11-17T05:06") > 0)
    @Assert(parseDateTimeInput("2026-11-17 05:06") > 0)
    @Expect(parseDateTimeInput(""), 0)
    var rejected = false
    try {
        parseDateTimeInput("not-a-date")
    } catch (e: AppError) {
        rejected = true
    }
    @Assert(rejected)
}

@Test
func testSafeNext(): Unit {
    @Expect(safeNext("/admin/posts"), "/admin/posts")
    @Expect(safeNext("//evil.example"), "")
    @Expect(safeNext("https://evil.example"), "")
    @Expect(safeNext("/a\r\nSet-Cookie: x"), "")
    @Expect(safeNext(""), "")
}

@Test
func testInitialOf(): Unit {
    @Expect(initialOf("仓墨"), "仓")
    @Expect(initialOf(""), "?")
}

@Test
func testPaginationUrls(): Unit {
    let data = buildPagination(2, 5, 42, "/posts", 10)
    @Expect(getString(data, "prev_url"), "/posts")
    @Expect(getString(data, "next_url"), "/posts?page=3")
    @Expect(getInt(data, "pages"), 5)
}
