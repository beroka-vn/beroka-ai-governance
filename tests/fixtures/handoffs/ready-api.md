Handoff schema: 1
Handoff state: READY_FOR_FE
Provider Jira: BB-42
Consumer Jira: BF-69
Scope: Shared
Domain: Market
Confluence content ID: 900001
Confluence page version: 1
Owner account ID: account-123
Effective date: 2026-08-25
Supersedes: N/A
Superseded by: N/A
API impact: affected
WebSocket impact: none
Missing sections: None

## Purpose and delivered behavior

The public quote endpoint returns the latest market quote.

## Affected user flows, assumptions, and non-goals

Quote detail screens refresh the displayed quote; historical charts are unchanged.

## Authentication and authorization

Authenticated users with quote-read permission may call the endpoint.

## Public data types and compatibility

Quote uses decimal strings and the additive response fields preserve compatibility.

## State and delivery semantics

The response is a current snapshot and repeated reads are safe.

## Errors and edge cases

Unknown symbols return a stable not-found error.

## Frontend implementation guidance

Refresh the displayed quote after a successful user action.

## Sanitized examples and validation evidence

The example uses a public symbol and the contract was checked by an integration test.

## Known limitations and unverified items

Delayed exchange data is outside this handoff.

## FE acknowledgment

Frontend reviewed the contract shape and can implement the displayed quote.

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

200 returns a quote object with symbol, price, and observedAt.

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

GET /v1/quotes/ABC returns {"symbol":"ABC","price":"12.34"}.

## Unaffected API inventory

All other public API operations are unchanged.

## WebSocket impact rationale

No public WebSocket contract changes.
