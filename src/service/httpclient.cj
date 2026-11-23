/**
 * Cangmo - small outbound HTTP client backed by curl.
 * Keeps network access in one place for webhooks, OAuth and federation.
 */
package cangmo.service

import cangmo.core.*
import cangmo.json.*
import std.collection.*
import std.process.*

public class HttpClient {
    public func postJson(url: String, body: String, headers: HashMap<String, String>): Int64 {
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
