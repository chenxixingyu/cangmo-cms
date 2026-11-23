/**
 * Cangmo - small outbound HTTP client backed by curl.
 * Keeps network access in one place for webhooks, OAuth and federation.
 */
package cangmo.service

import cangmo.core.*
import cangmo.json.*
import std.collection.*
import std.fs.*
import std.process.*

public class HttpClient {
    private let tempDir: String

    public init(tempDir!: String = "") {
        this.tempDir = tempDir
    }

    public func getText(url: String): ?String {
        getText(url, HashMap<String, String>())
    }

    public func getText(url: String, headers: HashMap<String, String>): ?String {
        let args = ArrayList<String>()
        args.add("-sS")
        args.add("-L")
        args.add("--max-time")
        args.add("10")
        for ((name, value) in headers) {
            if (name.size > 0 && value.size > 0 && !name.contains("\n") && !value.contains("\n")) {
                args.add("-H")
                args.add(name + ": " + value)
            }
        }
        args.add(url)
        curlBody(args)
    }

    public func postFormText(url: String, form: HashMap<String, String>): ?String {
        let args = ArrayList<String>()
        args.add("-sS")
        args.add("-L")
        args.add("--max-time")
        args.add("10")
        args.add("-X")
        args.add("POST")
        args.add("-H")
        args.add("content-type: application/x-www-form-urlencoded")
        for ((name, value) in form) {
            args.add("--data-urlencode")
            args.add(name + "=" + value)
        }
        args.add(url)
        curlBody(args)
    }

    private func curlBody(args: ArrayList<String>): ?String {
        if (tempDir.size == 0) {
            return None
        }
        ensureDir(tempDir)
        let path = tempDir + "/http-" + randomHex(bytes: 8) + ".tmp"
        let full = ArrayList<String>()
        for (arg in args) {
            full.add(arg)
        }
        full.add("-o")
        full.add(path)
        let code = try {
            execute("curl", full.toArray())
        } catch (e: Exception) {
            -1
        }
        if (code != 0 || !exists(path)) {
            if (exists(path)) {
                remove(path, recursive: false)
            }
            return None
        }
        let text = try {
            readTextFile(path)
        } catch (e: Exception) {
            ""
        }
        remove(path, recursive: false)
        if (text.size == 0) { None } else { Some(text) }
    }

    public func postJson(modelUrl: String, body: String, headers: HashMap<String, String>): Int64 {
        let url = modelUrl
        let args = ArrayList<String>()
        args.add("-sS")
        args.add("--max-time")
        args.add("8")
        args.add("-X")
        args.add("POST")
        args.add("-H")
        args.add("content-type: application/json")
        for ((name, value) in headers) {
            if (name.size > 0 && value.size > 0 && !name.contains("\n") && !value.contains("\n")) {
                args.add("-H")
                args.add(name + ": " + value)
            }
        }
        args.add("--data-binary")
        args.add(body)
        args.add(url)
        try {
            execute("curl", args.toArray())
        } catch (e: Exception) {
            -1
        }
    }
}
