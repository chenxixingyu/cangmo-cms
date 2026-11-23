/**
 * Cangmo - event bus. Domain events are published here; webhooks are the first consumer.
 */
package cangmo.service

import cangmo.json.*

public class EventBus {
    private let webhooks: WebhookService

    public init(webhooks: WebhookService) {
        this.webhooks = webhooks
    }

    public func publish(event: String, payload: JsonValue): Int64 {
        webhooks.dispatch(event, payload)
    }
}
