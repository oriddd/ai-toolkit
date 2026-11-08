---
name: async-api-patterns
description: >
  Java / Spring Boot long-running operations — submit-poll-result jobs, webhooks, SSE, job state, cleanup of abandoned
  jobs, idempotent submits. Use when an endpoint would run longer than ~2 seconds or must return a job handle instead
  of blocking.
tier: should
applies_to: [rest, event, monolith]
depends_on: [code-structure]
ships_templates: false
hitl: false
version: 1.0
last_reviewed: 2026-06-28
---

# Async API Patterns Skill

Standard REST calls should return within 1-2 seconds. For operations that take longer (PDF generation, data export), use an asynchronous pattern.

## 1. Pattern: Submit → Poll → Result

### Step 1: Submit
`POST /api/v1/invoices/{id}/exports`
- Returns **`202 Accepted`**.
- Body includes a `jobId`; the `Operation-Location` header points at the status endpoint (same contract as `api-design` §2).

### Step 2: Poll
`GET /api/v1/operations/{jobId}` (the operation resource from `api-design` §8)
- Returns the current state: `RUNNING`, `SUCCEEDED`, `FAILED` (the same states `api-design` uses; add `PENDING` only if you queue before starting, and `CANCELLED` if clients may cancel — §4).
- **Authorize every poll**: only the caller (or tenant) that submitted the job may read its status or result — an unknown or foreign `jobId` returns `404` (`permissions`).

**Optimization**: long polling — let the client send `Prefer: wait=<seconds>` (RFC 7240) and hold the request until the state changes or the wait expires. Hold it **without blocking a servlet thread**: return a `DeferredResult` / `CompletableFuture` (async servlet) completed by the job, or run on virtual threads (`spring.threads.virtual.enabled=true`); cap the wait (e.g. 30 s). (`Prefer: respond-async` is the opposite: it asks the server to answer `202` instead of waiting. There is no standard `Wait-For` header.)

### Step 3: Result
- Once status is `SUCCEEDED`, the body contains a URL to retrieve the artifact (e.g., `GET /api/v1/operations/{jobId}/download`).

## 2. Notification: Webhooks

Instead of forcing the client to poll, let them provide a `callbackUrl`.
- Once the job is done, the service makes a `POST` request to the `callbackUrl`.
- **SSRF guard**: the URL is attacker-supplied. Accept `https` only, register and verify it when the subscription is created (or allow-list hosts), resolve the host and refuse private / loopback / link-local addresses, and never follow redirects. Connect to the **IP you validated** (pin the resolved address for the call, sending the original `Host` / SNI) — re-resolving at send time lets DNS rebinding swap in an internal address.
- **Security**: Sign the webhook payload (HMAC-SHA256) so the client can verify it came from us. Follow the [Standard Webhooks](https://www.standardwebhooks.com/) headers instead of the legacy GitHub-style `X-Hub-Signature`:
  - `webhook-id` (unique per message, lets the receiver de-duplicate), `webhook-timestamp` (Unix seconds) and `webhook-signature` (`v1,<base64 HMAC-SHA256 of "<id>.<timestamp>.<body>">`).
  - The receiver rejects timestamps outside a tolerance window (e.g. ±5 min) to stop replays, and compares signatures in constant time (`MessageDigest.isEqual`).
  - **Key rotation**: a per-subscriber secret from the secret store; during rotation send one signature per active key (space-separated) so the receiver accepts either.

### 2b. Callback Reliability
If the client's `callbackUrl` is down, use an **exponential backoff retry** (see resilience-patterns). If all retries fail, move the notification to a Dead Letter Queue (DLQ, see messaging).

## 3. Real-time: Server-Sent Events (SSE)

For UI clients, use SSE to push status updates over a single HTTP connection.
- Spring Boot `SseEmitter` makes this easy in a `@RestController`.
- Give every emitter an explicit **timeout** (`new SseEmitter(Duration.ofMinutes(5).toMillis())`); the client reconnects with `Last-Event-ID`.
- Send a **heartbeat** comment (`emitter.send(SseEmitter.event().comment("keep-alive"))`) every ~15–30 s so proxies and load balancers do not cut idle connections.
- Keep emitters in a registry and **remove them** in `onCompletion`, `onTimeout` and `onError` — otherwise they leak.
- **Cross-pod delivery**: the job may finish on another pod than the one holding the connection. Publish status changes on a pub/sub channel (Redis pub/sub, a broker topic — `messaging`) and let every pod forward to its own emitters.

## 4. Job Management & Cleanup

Async jobs consume resources (DB rows, storage).
- **Durable, shared job state**: store jobs in the database (`persistence`), never in an in-memory map — any pod must answer the poll, and state must survive a restart.
- **State machine**: `PENDING → RUNNING → SUCCEEDED | FAILED | CANCELLED`; transitions are conditional updates (`UPDATE … WHERE state = 'RUNNING'`) so two pods cannot both move a job.
- **Recovery of orphaned jobs**: the worker holds a **lease** (`leaseOwner`, `leaseExpiresAt`) and renews it while running. A scheduled sweeper (`spring-boot-conventions` §7b, ShedLock) re-queues or fails `RUNNING` jobs whose lease expired because their pod died.
- **Execution**: run the work on a named, bounded executor (`spring-boot-conventions` §7, `@Async("exportExecutor")`) or a queue consumer (`messaging`) — never on the request thread.
- **TTL**: Automatically Delete job metadata and artifacts after N days.
- **Cancellation**: Allow clients to `DELETE` a job to stop processing; the job moves to `CANCELLED` and the worker checks the state between steps.

## 5. Design for Idempotency

If a client submits the same job twice, return the existing `jobId` instead of starting a new process (see idempotency in spring-boot-conventions §9). Scope the de-duplication key to the **caller** (principal / tenant) plus the `Idempotency-Key` header (or the input hash) — a key on the input hash alone would hand one user's `jobId`, and its result, to another.

## Do / Don't

✅ Use 202 Accepted for any request that takes > 2s.
✅ Provide a status endpoint with a clear state machine.
✅ Implement automatic cleanup of old jobs.
❌ Never block an HTTP thread while waiting for a long-running process to finish.
❌ Never return the final large artifact directly in the status poll response.
❌ Never use polling for high-frequency updates (use SSE or WebSockets).

