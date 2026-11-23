/**
 * Cangmo - generic OIDC/OAuth login providers.
 */
package cangmo.service

import cangmo.core.*
import cangmo.json.*
import cangmo.store.*
import std.collection.*

public class OAuthProviderService {
    private let store: Store
    private let audit: AuditService
    private let http: HttpClient

    public init(store: Store, audit: AuditService, http: HttpClient) {
        this.store = store
        this.audit = audit
        this.http = http
    }

    public func list(): Array<JsonValue> {
        let items = ArrayList<JsonValue>()
        for (provider in store.list(COL_OAUTH_PROVIDERS)) {
            items.add(provider)
        }
        sortDocsDesc(items, "created_at")
        items.toArray()
    }

    public func get(id: String): ?JsonValue {
        store.get(COL_OAUTH_PROVIDERS, id)
    }

    public func create(name: String, clientId: String, clientSecret: String, authUrl: String,
                       tokenUrl: String, userinfoUrl: String, scopes: String, actor: JsonValue,
                       ip: String): String {
        let label = name.trimAscii()
        let auth = authUrl.trimAscii()
        let token = tokenUrl.trimAscii()
        let info = userinfoUrl.trimAscii()
        if (label.size == 0 || label.size > 80) {
            throw AppError("validation", "Provider 名称长度无效")
        }
        for (url in [auth, token, info]) {
            if (!url.startsWith("http://") && !url.startsWith("https://")) {
                throw AppError("validation", "OAuth 端点需为 http(s) URL")
            }
        }
        let id = newId("oauth")
        let doc = JsonObject()
        doc.set("id", JStr(id))
        doc.set("name", JStr(label))
        doc.set("client_id", JStr(clientId.trimAscii()))
        doc.set("client_secret", JStr(truncateUtf8(clientSecret.trimAscii(), 300)))
        doc.set("authorize_url", JStr(auth))
        doc.set("token_url", JStr(token))
        doc.set("userinfo_url", JStr(info))
        doc.set("scopes", JStr(if (scopes.trimAscii().size > 0) { scopes.trimAscii() } else { "openid email profile" }))
        doc.set("created_at", JInt(nowSeconds()))
        store.put(COL_OAUTH_PROVIDERS, id, JObj(doc))
        audit.log(docStr(actor, "id"), docStr(actor, "username"), "oauth_provider_created", "oauth", id, ip, label)
        id
    }

    public func delete(id: String, actor: JsonValue, ip: String): Unit {
        if (store.get(COL_OAUTH_PROVIDERS, id).isNone()) {
            throw AppError("not_found", "Provider 不存在")
        }
        store.delete(COL_OAUTH_PROVIDERS, id)
        audit.log(docStr(actor, "id"), docStr(actor, "username"), "oauth_provider_deleted", "oauth", id, ip, "")
    }

    public func authorizeUrl(provider: JsonValue, redirectUri: String, state: String): String {
        docStr(provider, "authorize_url") + "?response_type=code&client_id=" +
            urlEncode(docStr(provider, "client_id")) + "&redirect_uri=" + urlEncode(redirectUri) +
            "&scope=" + urlEncode(docStr(provider, "scopes")) + "&state=" + urlEncode(state)
    }

    public func exchange(provider: JsonValue, code: String, redirectUri: String): ?JsonValue {
        let form = HashMap<String, String>()
        form["grant_type"] = "authorization_code"
        form["code"] = code
        form["client_id"] = docStr(provider, "client_id")
        form["client_secret"] = docStr(provider, "client_secret")
        form["redirect_uri"] = redirectUri
        let text = match (http.postFormText(docStr(provider, "token_url"), form)) {
            case Some(value) => value
            case None => return None
        }
        tryParseJson(text)
    }

    public func userInfo(provider: JsonValue, accessToken: String): ?JsonValue {
        let headers = HashMap<String, String>()
        headers["authorization"] = "Bearer " + accessToken
        headers["accept"] = "application/json"
        let text = match (http.getText(docStr(provider, "userinfo_url"), headers)) {
            case Some(value) => value
            case None => return None
        }
        tryParseJson(text)
    }
}
