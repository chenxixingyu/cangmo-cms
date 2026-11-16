package cangmo.core

import std.unittest.*
import std.unittest.testmacro.*

@Test
func testSha256KnownVector(): Unit {
    @Expect(sha256Hex("abc"), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
}

@Test
func testHmacKnownVector(): Unit {
    @Expect(hmacSha256Hex("key", "The quick brown fox jumps over the lazy dog"),
            "f7bc83f430538424b13298e6aa6fb143ef4d59a14946175997479dbc2d1a3cd8")
}

@Test
func testPasswordRoundTrip(): Unit {
    let encoded = hashPassword("Cangmo-Test-2026!", iterations: 2000)
    @Assert(verifyPassword("Cangmo-Test-2026!", encoded))
    @Assert(!verifyPassword("wrong-password", encoded))
}

@Test
func testBase64RoundTrip(): Unit {
    let data = "你好，仓墨".toArray()
    let encoded = base64Encode(data)
    @Expect(String.fromUtf8(base64Decode(encoded)), "你好，仓墨")
}

@Test
func testUrlRoundTrip(): Unit {
    let value = "仓颉 a&b+c"
    @Expect(urlDecode(urlEncode(value)), value)
}

@Test
func testUtf8Helpers(): Unit {
    @Expect(runeCount("你好abc"), 5)
    @Expect(truncateRunes("你好世界", 2), "你好…")
    @Expect(escapeHtml("<a href=\"x\">"), "&lt;a href=&quot;x&quot;&gt;")
}

@Test
func testPasswordPolicy(): Unit {
    @Assert(passwordProblem("short").isSome())
    @Assert(passwordProblem("Cangmo-Strong-2026").isNone())
}
