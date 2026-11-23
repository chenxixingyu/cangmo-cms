/**
 * Cangmo - event bus. Domain events are published here; webhooks and sidecar plugins consume them.
 */
package cangmo.service

import cangmo.json.*

public class EventBus {
    private let webhooks: WebhookService
    private let plugins: PluginService

    public init(webhooks: WebhookService, plugins: PluginService) {
        this.webhooks = webhooks
        this.plugins = plugins
    }

    public func publish(event: String, payload: JsonValue, siteId!: String = ""): Int64 {
        let webhookCount = webhooks.dispatch(event, payload)
        let pluginCount = plugins.dispatch(event, payload, siteId)
        webhookCount + pluginCount
    }
}
