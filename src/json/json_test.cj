package cangmo.json

import std.unittest.*
import std.unittest.testmacro.*

@Test
func testJsonRoundTrip(): Unit {
    let input = "{\"title\":\"你好\",\"n\":3,\"ok\":true,\"list\":[1,2,3],\"nested\":{\"x\":null}}"
    let parsed = parseJson(input)
    @Expect(getString(parsed, "title"), "你好")
    @Expect(getInt(parsed, "n"), 3)
    @Assert(getBool(parsed, "ok"))
    let rendered = toJsonCompact(parsed)
    let again = parseJson(rendered)
    @Expect(getString(again, "title"), "你好")
}

@Test
func testJsonEscapes(): Unit {
    let value = jsonObjectOf([("x", jstr("<script>\"&\n"))])
    let text = toJsonCompact(value)
    @Assert(text.contains("\\u003cscript\\u003e"))
    @Assert(text.contains("\\\"") || text.contains("\\u0022"))
    @Expect(getString(parseJson(text), "x"), "<script>\"&\n")
}

@Test
func testJsonDepthLimit(): Unit {
    let sb = StringBuilder()
    for (i in 0..200) {
        sb.append("[")
    }
    @Assert(tryParseJson(sb.toString()).isNone())
}

@Test
func testJsonUnicodeSurrogate(): Unit {
    let parsed = parseJson("\"\\uD83D\\uDE00\"")
    @Expect(getString(jsonObjectOf([("x", parsed)]), "x"), "😀")
}

@Test
func testJsonInvalidInput(): Unit {
    @Assert(tryParseJson("{").isNone())
    @Assert(tryParseJson("{\"a\":1} trailing").isNone())
    @Assert(tryParseJson("[1,2,]").isNone())
}
