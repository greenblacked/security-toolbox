# Threat model to backlog

Turn a service diagram into owned backlog items with testable security outcomes. Allow 35 minutes and use a local text editor.

## Scenario

An order API receives requests from customers, writes a queue message, and returns a tracking ID. A worker reads the queue and writes order status to a datastore. Operators access a separate dashboard. A third-party mail service sends customer notifications. The team owns the API and worker. The platform team owns the queue identity and telemetry. The third party operates its mail service.

## Exercise

1. Draw the customer-to-API, API-to-queue, queue-to-worker, worker-to-store, and operator-to-dashboard flows. Label the data, identity, and trust boundaries.
2. Compare your diagram with the scenario and add the notification service flow. Record who owns the integration and who owns the service.
3. Choose three control decisions. For each, record a risk, owner, expected allowed behavior, expected denied behavior, and the evidence that would support both decisions.
4. Ask a reviewer to remove one boundary from a working copy. Use the scenario to identify the omission before accepting the model.

## Verify and clean up

The model accounts for the mail dependency and separate operator authority. Each backlog item names an owner and observable evidence, such as an access decision or redacted audit record. Keep the final diagram and risk register if useful. Delete temporary copies.

Related reading: [Data flow model](/skills/threat-model/data-flow-model/) and [Threat model procedure](/skills/threat-model/).
