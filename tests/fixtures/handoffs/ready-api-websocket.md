Handoff schema: 1
Handoff state: READY_FOR_FE
Provider Jira: BB-42
Consumer Jira: BF-69
Confluence content ID: 900007
Confluence page version: 1
Owner account ID: account-123
Effective date: 2026-08-25
Supersedes: N/A
Superseded by: N/A
API impact: affected
WebSocket impact: affected
Missing sections: None

## Purpose and delivered behavior

The quote contract supports both snapshots and live changes.

## Affected user flows, assumptions, and non-goals

Quote detail screens read once and then subscribe; history is unchanged.

## Authentication and authorization

Authenticated users with quote-read permission may use both transports.

## Public data types and compatibility

Both transports use the same additive quote type.

## State and delivery semantics

Snapshots are current and stream delivery is at least once.

## Errors and edge cases

Unknown symbols have stable errors on both transports.

## Frontend implementation guidance

Load a snapshot before subscribing for later changes.

## Sanitized examples and validation evidence

Public sample values were exercised by contract tests.

## Known limitations and unverified items

Exchange outages can delay updates.

## FE acknowledgment

Frontend reviewed both public contracts.

## Affected API inventory

GET /v1/quotes/{symbol}

## API operation: GET /v1/quotes/{symbol}

Public quote lookup.

### Permissions

quote-read permission is required.

### Headers

Accept: application/json.

### Path parameters

symbol is the public market symbol.

### Query parameters

None are accepted.

### Request payload

No request body is accepted.

### Success status and payload

200 returns a quote object.

### Stable public errors

404 is returned for an unknown symbol.

### Pagination

This single-resource operation is not paginated.

### Idempotency

GET is idempotent.

### Retry

Retry transient 503 responses with bounded backoff.

### Cache

Clients may cache the response for one second.

### Timestamp semantics

observedAt is an ISO-8601 UTC timestamp.

### Sanitized request/response examples

GET /v1/quotes/ABC returns {"symbol":"ABC"}.

## Unaffected API inventory

All other public API operations are unchanged.

## Affected WebSocket inventory

wss://api.example.test/v1/quotes

## WebSocket contract: wss://api.example.test/v1/quotes

Public quote change stream.

### Public connection URL and authentication

Connect with the documented user session.

### Subscribe and unsubscribe requests

Subscribe and unsubscribe with the public symbol.

### Event envelope and affected message payloads

Events contain type, eventId, observedAt, and quote payload.

### Ordering

Ordering is guaranteed per symbol.

### Deduplication

Deduplicate by eventId.

### Replay/resume

Resume from the last acknowledged eventId.

### Reconnect

Reconnect with bounded exponential backoff.

### Heartbeat

The server sends a heartbeat every 30 seconds.

### Timeout

Reconnect after 90 seconds without a heartbeat.

### Backpressure

Render the newest quote when behind.

### Error events

Invalid subscriptions emit a stable error event.

### Close codes

4010 indicates an expired user session.

### Sanitized message examples

{"type":"quote","eventId":"evt-1","symbol":"ABC"}

## Unaffected WebSocket inventory

All other public WebSocket streams are unchanged.
