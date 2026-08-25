Handoff schema: 1
Handoff state: READY_FOR_FE
Provider Jira: BB-42
Consumer Jira: BF-69
Confluence content ID: 900004
Confluence page version: 1
Owner account ID: account-123
Effective date: 2026-08-25
Supersedes: N/A
Superseded by: N/A
API impact: none
WebSocket impact: affected
Missing sections: None

## Purpose and delivered behavior

The public quote stream publishes quote changes.

## Affected user flows, assumptions, and non-goals

Quote detail screens subscribe while visible; chart history is unchanged.

## Authentication and authorization

Authenticated users with quote-read permission may subscribe.

## Public data types and compatibility

Events use additive fields and decimal-string prices.

## State and delivery semantics

Delivery is at least once and clients deduplicate by event ID.

## Errors and edge cases

Invalid subscriptions receive a stable error event.

## Frontend implementation guidance

Reconnect and resubscribe after a transport interruption.

## Sanitized examples and validation evidence

The sample symbol is public and the stream contract was integration-tested.

## Known limitations and unverified items

Exchange outages can delay new quote events.

## FE acknowledgment

Frontend reviewed the event envelope and can implement the subscriber.

## API impact rationale

No public API operation changes.

## Affected WebSocket inventory

wss://api.example.test/v1/quotes

## WebSocket contract: wss://api.example.test/v1/quotes

Public quote change stream.

### Public connection URL and authentication

Connect to wss://api.example.test/v1/quotes with the documented user session.

### Subscribe and unsubscribe requests

Subscribe with {"type":"subscribe","symbol":"ABC"} and unsubscribe with the matching symbol.

### Event envelope and affected message payloads

Events contain type, eventId, observedAt, and a quote payload.

### Ordering

Ordering is guaranteed only per symbol.

### Deduplication

Deduplicate messages by eventId.

### Replay/resume

Resume from the last acknowledged eventId when available.

### Reconnect

Reconnect with bounded exponential backoff.

### Heartbeat

The server sends a heartbeat every 30 seconds.

### Timeout

Reconnect after 90 seconds without a heartbeat.

### Backpressure

Render the newest quote when the browser falls behind.

### Error events

Invalid subscriptions emit {"type":"error","code":"invalid_symbol"}.

### Close codes

4010 indicates an expired user session.

### Sanitized message examples

{"type":"quote","eventId":"evt-1","symbol":"ABC","price":"12.34"}

## Unaffected WebSocket inventory

All other public WebSocket streams are unchanged.
