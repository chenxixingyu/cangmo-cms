/**
 * Cangmo - TOTP (RFC 6238) with SHA-256, base32 secrets and recovery helpers.
 */
package cangmo.core

import std.collection.*

let TOTP_ALPHABET: String = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567"

public func base32Encode(data: Array<UInt8>): String {
    let sb = StringBuilder()
    var buffer: Int64 = 0
    var bits: Int64 = 0
    for (b in data) {
        buffer = (buffer << 8) | Int64(b)
        bits += 8
        while (bits >= 5) {
            bits -= 5
            let index = (buffer >> bits) & 31
            sb.append(Rune(Int64(TOTP_ALPHABET.toArray()[index])))
        }
    }
    if (bits > 0) {
        let index = (buffer << (5 - bits)) & 31
        sb.append(Rune(Int64(TOTP_ALPHABET.toArray()[index])))
    }
    sb.toString()
}

public func base32Decode(text: String): Array<UInt8> {
    let clean = text.trimAscii().replace("=", "").toAsciiUpper()
    let out = ArrayList<UInt8>()
    var buffer: Int64 = 0
    var bits: Int64 = 0
    for (b in clean.toArray()) {
        var value: Int64 = -1
        if (b >= 65 && b <= 90) {
            value = Int64(b - 65)
        } else if (b >= 50 && b <= 55) {
            value = Int64(b - 50) + 26
        }
        if (value < 0) {
            continue
        }
        buffer = (buffer << 5) | value
        bits += 5
        if (bits >= 8) {
            bits -= 8
            out.add(UInt8((buffer >> bits) & 0xFF))
        }
    }
    out.toArray()
}

public func generateTotpSecret(): String {
    base32Encode(secureRandomBytes(20))
}

private func totpCounterBytes(counter: Int64): Array<UInt8> {
    let bytes = Array<UInt8>(8, repeat: 0)
    var value = counter
    var i = 7
    while (i >= 0) {
        bytes[i] = UInt8(value & 0xFF)
        value = value >> 8
        i -= 1
    }
    bytes
}

public func totpCode(secret: String, at!: Int64 = 0): String {
    let timestamp = if (at > 0) { at } else { nowSeconds() }
    let counter = timestamp / 30
    let digest = hmacSha256(base32Decode(secret), totpCounterBytes(counter))
    let offset = Int64(digest[digest.size - 1] & 0x0F)
    let binary = (Int64(digest[offset]) & 0x7F) << 24 |
                 (Int64(digest[offset + 1]) & 0xFF) << 16 |
                 (Int64(digest[offset + 2]) & 0xFF) << 8 |
                 (Int64(digest[offset + 3]) & 0xFF)
    let code = binary % 1000000
    let text = code.toString()
    let padded = if (text.size >= 6) { text } else { "000000"[0..6 - text.size] + text }
    padded
}

public func verifyTotp(secret: String, code: String, window!: Int64 = 1, at!: Int64 = 0): Bool {
    let value = code.trimAscii()
    if (value.size != 6) {
        return false
    }
    let base = if (at > 0) { at } else { nowSeconds() }
    var delta = -window
    while (delta <= window) {
        if (secureEqualsText(totpCode(secret, at: base + delta * 30), value)) {
            return true
        }
        delta += 1
    }
    false
}

public func totpUri(secret: String, issuer: String, account: String): String {
    "otpauth://totp/" + urlEncode(issuer) + ":" + urlEncode(account) +
        "?secret=" + secret + "&issuer=" + urlEncode(issuer) +
        "&algorithm=SHA256&digits=6&period=30"
}

public func generateRecoveryCodes(count!: Int64 = 8): Array<String> {
    let out = ArrayList<String>()
    for (_ in 0..count) {
        out.add(base32Encode(secureRandomBytes(5)))
    }
    out.toArray()
}

public func hashRecoveryCode(code: String): String {
    sha256Hex(code.trimAscii().replace("-", "").toAsciiUpper())
}
