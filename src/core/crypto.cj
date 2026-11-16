/**
 * Cangmo - cryptography.
 *
 * SHA-256 / HMAC-SHA256 / PBKDF2-HMAC-SHA256 implemented from the public
 * FIPS 180-4 and RFC 8018 specifications. No third-party code is copied.
 * The operating system CSPRNG is used through the documented Windows CNG
 * SystemFunction036 interface (advapi32).
 */
package cangmo.core

import std.collection.*
import std.overflow.*

// Windows CNG (bcrypt.dll) - modern, FIPS-validated OS cryptography.
foreign func BCryptGenRandom(hAlgorithm: CPointer<Byte>, pbBuffer: CPointer<Byte>, cbBuffer: UInt32, dwFlags: UInt32): Int32
foreign func BCryptOpenAlgorithmProvider(phAlgorithm: CPointer<CPointer<Unit>>, pszAlgId: CPointer<UInt16>, pszImplementation: CPointer<UInt16>, dwFlags: UInt32): Int32
foreign func BCryptDeriveKeyPBKDF2(hPrf: CPointer<Unit>, pbPassword: CPointer<Byte>, cbPassword: UInt32, pbSalt: CPointer<Byte>, cbSalt: UInt32, cIterations: UInt64, pbDerivedKey: CPointer<Byte>, cbDerivedKey: UInt32, dwFlags: UInt32): Int32
foreign func BCryptCloseAlgorithmProvider(hAlgorithm: CPointer<Unit>, dwFlags: UInt32): Int32

let BCRYPT_USE_SYSTEM_PREFERRED_RNG: UInt32 = 0x00000002
let BCRYPT_ALG_HANDLE_HMAC_FLAG: UInt32 = 0x00000008

func utf16z(text: String): Array<UInt16> {
    let chars = text.toArray()
    let out = Array<UInt16>(chars.size + 1, repeat: 0)
    for (i in 0..chars.size) {
        out[i] = UInt16(chars[i])
    }
    return out
}

/**
 * Fill an array with cryptographically secure random bytes.
 */
public func secureRandomBytes(count: Int64): Array<UInt8> {
    if (count <= 0) {
        return Array<UInt8>(0, repeat: 0)
    }
    let out = Array<UInt8>(count, repeat: 0)
    let status = unsafe {
        let handle = acquireArrayRawData(out)
        let r = BCryptGenRandom(CPointer<Byte>(), handle.pointer, UInt32(count), BCRYPT_USE_SYSTEM_PREFERRED_RNG)
        releaseArrayRawData(handle)
        r
    }
    if (status != 0) {
        throw AppError("internal", "operating system secure random source is unavailable")
    }
    return out
}

public func secureEqualsBytes(a: Array<UInt8>, b: Array<UInt8>): Bool {
    if (a.size != b.size) {
        return false
    }
    var diff: UInt8 = 0
    for (i in 0..a.size) {
        diff = diff | (a[i] ^ b[i])
    }
    return diff == 0
}

// ---------------------------------------------------------------------------
// SHA-256
// ---------------------------------------------------------------------------

let SHA256_K: Array<UInt32> = [
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5,
    0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
    0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3,
    0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
    0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc,
    0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
    0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7,
    0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
    0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13,
    0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
    0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3,
    0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
    0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5,
    0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
    0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208,
    0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2
]

func rotr(x: UInt32, n: Int64): UInt32 {
    (x >> n) | (x << (32 - n))
}

public class Sha256 {
    private var h: Array<UInt32>
    private var buffer: Array<UInt8>
    private var bufferLen: Int64
    private var totalLen: Int64
    private var finished: Bool

    public init() {
        h = Array<UInt32>(8, repeat: 0)
        h[0] = 0x6a09e667
        h[1] = 0xbb67ae85
        h[2] = 0x3c6ef372
        h[3] = 0xa54ff53a
        h[4] = 0x510e527f
        h[5] = 0x9b05688c
        h[6] = 0x1f83d9ab
        h[7] = 0x5be0cd19
        buffer = Array<UInt8>(64, repeat: 0)
        bufferLen = 0
        totalLen = 0
        finished = false
    }

    public func update(data: Array<UInt8>): Unit {
        if (finished) {
            throw AppError("internal", "sha256 already finalized")
        }
        var i = 0
        while (i < data.size) {
            let space = 64 - bufferLen
            var take = data.size - i
            if (take > space) {
                take = space
            }
            for (j in 0..take) {
                buffer[bufferLen + j] = data[i + j]
            }
            bufferLen += take
            totalLen += take
            i += take
            if (bufferLen == 64) {
                compress()
                bufferLen = 0
            }
        }
    }

    public func updateText(text: String): Unit {
        update(text.toArray())
    }

    private func compress(): Unit {
        let w = Array<UInt32>(64, repeat: 0)
        for (i in 0..16) {
            let j = i * 4
            w[i] = (UInt32(buffer[j]) << 24) | (UInt32(buffer[j + 1]) << 16) |
                   (UInt32(buffer[j + 2]) << 8) | UInt32(buffer[j + 3])
        }
        for (i in 16..64) {
            let x = w[i - 15]
            let y = w[i - 2]
            let s0 = rotr(x, 7) ^ rotr(x, 18) ^ (x >> 3)
            let s1 = rotr(y, 17) ^ rotr(y, 19) ^ (y >> 10)
            w[i] = w[i - 16].wrappingAdd(s0).wrappingAdd(w[i - 7]).wrappingAdd(s1)
        }
        var a = h[0]
        var b = h[1]
        var c = h[2]
        var d = h[3]
        var e = h[4]
        var f = h[5]
        var g = h[6]
        var hh = h[7]
        for (i in 0..64) {
            let s1 = rotr(e, 6) ^ rotr(e, 11) ^ rotr(e, 25)
            let ch = (e & f) ^ ((e ^ 0xFFFFFFFF) & g)
            let temp1 = hh.wrappingAdd(s1).wrappingAdd(ch).wrappingAdd(SHA256_K[i]).wrappingAdd(w[i])
            let s0 = rotr(a, 2) ^ rotr(a, 13) ^ rotr(a, 22)
            let maj = (a & b) ^ (a & c) ^ (b & c)
            let temp2 = s0.wrappingAdd(maj)
            hh = g
            g = f
            f = e
            e = d.wrappingAdd(temp1)
            d = c
            c = b
            b = a
            a = temp1.wrappingAdd(temp2)
        }
        h[0] = h[0].wrappingAdd(a)
        h[1] = h[1].wrappingAdd(b)
        h[2] = h[2].wrappingAdd(c)
        h[3] = h[3].wrappingAdd(d)
        h[4] = h[4].wrappingAdd(e)
        h[5] = h[5].wrappingAdd(f)
        h[6] = h[6].wrappingAdd(g)
        h[7] = h[7].wrappingAdd(hh)
    }

    public func finish(): Array<UInt8> {
        if (finished) {
            throw AppError("internal", "sha256 already finalized")
        }
        let bitLen = UInt64(totalLen) * 8
        let pad = ArrayList<UInt8>()
        pad.add(0x80)
        let rem = (totalLen + 1) % 64
        let zeros = if (rem <= 56) { 56 - rem } else { 120 - rem }
        for (i in 0..zeros) {
            pad.add(0)
        }
        for (i in 0..8) {
            pad.add(UInt8((bitLen >> (56 - i * 8)) & 0xFF))
        }
        update(pad.toArray())
        finished = true
        let out = Array<UInt8>(32, repeat: 0)
        for (i in 0..8) {
            out[i * 4] = UInt8((h[i] >> 24) & 0xFF)
            out[i * 4 + 1] = UInt8((h[i] >> 16) & 0xFF)
            out[i * 4 + 2] = UInt8((h[i] >> 8) & 0xFF)
            out[i * 4 + 3] = UInt8(h[i] & 0xFF)
        }
        return out
    }
}

public func sha256(data: Array<UInt8>): Array<UInt8> {
    let d = Sha256()
    d.update(data)
    return d.finish()
}

public func sha256Text(text: String): Array<UInt8> {
    sha256(text.toArray())
}

public func sha256Hex(text: String): String {
    hexEncode(sha256Text(text)).toAsciiLower()
}

func concatBytes(a: Array<UInt8>, b: Array<UInt8>): Array<UInt8> {
    let out = Array<UInt8>(a.size + b.size, repeat: 0)
    for (i in 0..a.size) {
        out[i] = a[i]
    }
    for (i in 0..b.size) {
        out[a.size + i] = b[i]
    }
    return out
}

func copyBytes(a: Array<UInt8>): Array<UInt8> {
    let out = Array<UInt8>(a.size, repeat: 0)
    for (i in 0..a.size) {
        out[i] = a[i]
    }
    return out
}

// ---------------------------------------------------------------------------
// HMAC-SHA256
// ---------------------------------------------------------------------------

public func hmacSha256(key: Array<UInt8>, message: Array<UInt8>): Array<UInt8> {
    var k = key
    if (k.size > 64) {
        k = sha256(k)
    }
    let ipad = Array<UInt8>(64, repeat: 0x36)
    let opad = Array<UInt8>(64, repeat: 0x5C)
    for (i in 0..k.size) {
        ipad[i] = ipad[i] ^ k[i]
        opad[i] = opad[i] ^ k[i]
    }
    let inner = Sha256()
    inner.update(ipad)
    inner.update(message)
    let innerHash = inner.finish()
    let outer = Sha256()
    outer.update(opad)
    outer.update(innerHash)
    return outer.finish()
}

public func hmacSha256Hex(key: String, message: String): String {
    hexEncode(hmacSha256(key.toArray(), message.toArray())).toAsciiLower()
}

// ---------------------------------------------------------------------------
// PBKDF2-HMAC-SHA256
// ---------------------------------------------------------------------------

/**
 * PBKDF2 using the operating system CNG implementation (fast, FIPS validated).
 * Returns None when CNG is unavailable so the caller can fall back to the
 * portable pure-Cangjie implementation.
 */
func cngPbkdf2(password: String, salt: Array<UInt8>, iterations: Int64, keyLength: Int64): ?Array<UInt8> {
    if (keyLength < 1 || keyLength > 0xFFFFFFFF || iterations < 1) {
        return None
    }
    let algName = utf16z("SHA256")
    let handles = Array<CPointer<Unit>>(1, repeat: CPointer<Unit>())
    let openStatus = unsafe {
        let hn = acquireArrayRawData(algName)
        let hh = acquireArrayRawData(handles)
        let st = BCryptOpenAlgorithmProvider(hh.pointer, hn.pointer, CPointer<UInt16>(), BCRYPT_ALG_HANDLE_HMAC_FLAG)
        releaseArrayRawData(hn)
        releaseArrayRawData(hh)
        st
    }
    let handle = handles[0]
    if (openStatus != 0 || handle.isNull()) {
        return None
    }
    let pw = password.toArray()
    let out = Array<UInt8>(keyLength, repeat: 0)
    let status = unsafe {
        let hp = acquireArrayRawData(pw)
        let hs = acquireArrayRawData(salt)
        let ho = acquireArrayRawData(out)
        let st = BCryptDeriveKeyPBKDF2(handle, hp.pointer, UInt32(pw.size), hs.pointer, UInt32(salt.size),
                                       UInt64(iterations), ho.pointer, UInt32(keyLength), 0)
        releaseArrayRawData(hp)
        releaseArrayRawData(hs)
        releaseArrayRawData(ho)
        st
    }
    unsafe {
        BCryptCloseAlgorithmProvider(handle, 0)
    }
    if (status != 0) {
        return None
    }
    return Some(out)
}

public func pbkdf2Sha256(password: String, salt: Array<UInt8>, iterations: Int64, keyLength: Int64): Array<UInt8> {
    if (iterations < 1 || keyLength < 1) {
        throw AppError("internal", "invalid pbkdf2 parameters")
    }
    match (cngPbkdf2(password, salt, iterations, keyLength)) {
        case Some(value) => return value
        case None => ()
    }
    return pbkdf2Sha256Pure(password, salt, iterations, keyLength)
}

/**
 * Portable fallback implementation of PBKDF2-HMAC-SHA256 (RFC 8018).
 */
func pbkdf2Sha256Pure(password: String, salt: Array<UInt8>, iterations: Int64, keyLength: Int64): Array<UInt8> {
    let pw = password.toArray()
    let out = ArrayList<UInt8>()
    var block: Int64 = 1
    while (out.size < keyLength) {
        let idx = Array<UInt8>(4, repeat: 0)
        idx[0] = UInt8((block >> 24) & 0xFF)
        idx[1] = UInt8((block >> 16) & 0xFF)
        idx[2] = UInt8((block >> 8) & 0xFF)
        idx[3] = UInt8(block & 0xFF)
        var u = hmacSha256(pw, concatBytes(salt, idx))
        var t = copyBytes(u)
        var iter: Int64 = 1
        while (iter < iterations) {
            u = hmacSha256(pw, u)
            for (j in 0..t.size) {
                t[j] = t[j] ^ u[j]
            }
            iter += 1
        }
        for (b in t) {
            if (out.size < keyLength) {
                out.add(b)
            }
        }
        block += 1
    }
    return out.toArray()
}

public let PASSWORD_PREFIX: String = "pbkdf2_sha256"
public let DEFAULT_PBKDF2_ITERATIONS: Int64 = 120000

public func hashPassword(password: String, iterations!: Int64 = DEFAULT_PBKDF2_ITERATIONS): String {
    let salt = secureRandomBytes(16)
    let hash = pbkdf2Sha256(password, salt, iterations, 32)
    let sb = StringBuilder()
    sb.append(PASSWORD_PREFIX)
    sb.append("$")
    sb.append(iterations.toString())
    sb.append("$")
    sb.append(base64Encode(salt))
    sb.append("$")
    sb.append(base64Encode(hash))
    return sb.toString()
}

public func verifyPassword(password: String, encoded: String): Bool {
    let parts = encoded.split("$")
    if (parts.size != 4 || parts[0] != PASSWORD_PREFIX) {
        return false
    }
    let iterations = parseIntOr(parts[1], 0)
    if (iterations < 1000 || iterations > 5000000) {
        return false
    }
    try {
        let salt = base64Decode(parts[2])
        let expected = base64Decode(parts[3])
        if (salt.size < 8 || expected.size < 16) {
            return false
        }
        let actual = pbkdf2Sha256(password, salt, iterations, expected.size)
        return secureEqualsBytes(actual, expected)
    } catch (e: Exception) {
        return false
    }
}

public func passwordNeedsRehash(encoded: String, iterations!: Int64 = DEFAULT_PBKDF2_ITERATIONS): Bool {
    let parts = encoded.split("$")
    if (parts.size != 4 || parts[0] != PASSWORD_PREFIX) {
        return true
    }
    return parseIntOr(parts[1], 0) < iterations
}

/**
 * Return a human readable problem, or None when the password is acceptable.
 */
public func passwordProblem(password: String, username!: String = "", email!: String = ""): ?String {
    if (password.size < 10) {
        return "密码至少需要 10 个字符"
    }
    if (password.size > 200) {
        return "密码过长"
    }
    var hasLower = false
    var hasUpper = false
    var hasDigit = false
    var hasOther = false
    for (b in password.toArray()) {
        if (b >= 0x61 && b <= 0x7A) {
            hasLower = true
        } else if (b >= 0x41 && b <= 0x5A) {
            hasUpper = true
        } else if (b >= 0x30 && b <= 0x39) {
            hasDigit = true
        } else {
            hasOther = true
        }
    }
    var classes = 0
    if (hasLower) { classes += 1 }
    if (hasUpper) { classes += 1 }
    if (hasDigit) { classes += 1 }
    if (hasOther) { classes += 1 }
    if (classes < 2) {
        return "密码需要至少包含字母、数字、符号中的两类"
    }
    let lowerPw = password.toAsciiLower()
    if (username.size >= 3 && lowerPw.contains(username.toAsciiLower())) {
        return "密码不能包含用户名"
    }
    if (email.size >= 5 && lowerPw.contains(email.toAsciiLower())) {
        return "密码不能包含邮箱地址"
    }
    let weak = ["password", "123456", "qwerty", "admin", "letmein", "welcome", "cangmo", "888888", "666666"]
    for (w in weak) {
        if (lowerPw == w) {
            return "密码过于常见"
        }
    }
    return None
}

public func hashApiToken(token: String): String {
    sha256Hex("cangmo-api-token:" + token)
}
