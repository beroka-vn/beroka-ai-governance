# Jira Summary Naming Contract Design

**Date:** 2026-07-31
**Issue:** [GitHub #39](https://github.com/beroka-vn/beroka-ai-governance/issues/39)
**Status:** Ready for review
**Target release:** `v1.0.5`

## Goal

Give every AI client one unambiguous Jira summary format for Epic, Feature,
Task, and Bug while keeping conformance instruction-driven.

## Contract

All Jira summaries default to English sentence case, have no trailing
punctuation, and omit Jira keys and type prefixes such as `[Epic]`, `[Feature]`,
`[Task]`, or `[Bug]`.

| Jira type | Summary format |
| --- | --- |
| Epic | `<Domain or module> — <Business outcome>` |
| Feature | `<Capability> — <Observable outcome>` |
| Task | `<Action verb> <Outcome or deliverable>` |
| Bug | `<Actual symptom> when <condition>` |

The Jira template carries two Frontend and two Backend examples for each type:

| Type | Frontend examples | Backend examples |
| --- | --- | --- |
| Epic | `Market overview — Faster investment discovery`; `Portfolio — Clear real-time performance visibility` | `Market data — Reliable real-time price delivery`; `Order management — Consistent trade execution` |
| Feature | `Market charts — Display continuous historical price trends`; `Watchlist — Reflect live price changes without manual refresh` | `Historical candles API — Return complete time-bucketed market data`; `Order events WebSocket — Publish deterministic order status updates` |
| Task | `Add empty-state guidance to the market watchlist`; `Validate chart rendering across supported time ranges` | `Add idempotency protection to order submission`; `Validate trading sessions before candle aggregation` |
| Bug | `Chart shows duplicate candles when the WebSocket reconnects`; `Watchlist loses selected symbols when the page refreshes` | `Order submission creates duplicates when clients retry timed-out requests`; `Candle API omits the latest interval when the market session crosses midnight` |

## Delivery

Add the compact contract to `runtime/rules/work-items.md`, durable policy to
`governance.md` and `workflow.md`, and explicit type-specific guidance to
`templates/jira-confluence.md`. Feature and Bug stop falling back to the nearest
generic Jira structure.

Extend `tests/documentation-architecture.sh` with exact assertions for all four
formats, the global language/prefix/punctuation rules, and complete FE/BE
example coverage.

Do not add a runtime parser, language detector, dependency, Jira configuration,
or release metadata change. Existing create-metadata, duplicate-search,
parenting, ownership, and readback gates remain unchanged.

## Validation

- The focused documentation architecture test fails before the contract exists.
- The focused test passes after every required rule and example is present.
- The complete shell suite remains green.

