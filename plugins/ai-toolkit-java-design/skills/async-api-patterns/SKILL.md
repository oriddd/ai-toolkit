---
name: async-api-patterns
description: >
  Java / Spring Boot: Handle long-running operations (> 2s) in a RESTful way. Covers the "Submit-Poll-Result" pattern, Webhooks, and SSE (Server-Sent Events). Includes guidance on job state management, cleanup of abandoned jobs, and designing for idempotency. Use when an endpoint would run longer than ~2 seconds or must return a job handle instead of blocking.
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
`POST /exports`
- Returns **`202 Accepted`**.
- Body includes a `jobId`; the `Operation-Location` header points at the status endpoint (same contract as `api-design` §2).

### Step 2: Poll
`GET /exports/{jobId}`
- Returns the current state: `RUNNING`, `SUCCEEDED`, `FAILED` (the same states `api-design` uses; add `PENDING` only if you queue before starting).

**Optimization**: long polling — let the client send `Prefer: wait=<seconds>` (RFC 7240) and hold the request until the state changes or the wait expires. (`Prefer: respond-async` is the opposite: it asks the server to answer `202` instead of waiting. There is no standard `Wait-For` header.)

### Step 3: Result
- Once status is `SUCCEEDED`, the body contains a URL to retrieve the artifact (e.g., `GET /exports/{jobId}/download`).

## 2. Notification: Webhooks

Instead of forcing the client to poll, let them provide a `callbackUrl`.
- Once the job is done, the service makes a `POST` request to the `callbackUrl`.
- **SSRF guard**: the URL is attacker-supplied. Accept `https` only, register and verify it when the subscription is created (or allow-list hosts), resolve the host and refuse private / loopback / link-local addresses, and never follow redirects.
- **Security**: Sign the webhook payload (e.g., HMAC-SHA256) so the client can verify it came from us. Include a `X-Hub-Signature` header.

### 2b. Callback Reliability
If the client's `callbackUrl` is down, use an **exponential backoff retry** (see resilience-patterns). If all retries fail, move the notification to a Dead Letter Queue (DLQ, see messaging).

## 3. Real-time: Server-Sent Events (SSE)

For UI clients, use SSE to push status updates over a single HTTP connection.
- Spring Boot `SseEmitter` makes this easy in a `@RestController`.

## 4. Job Management & Cleanup

Async jobs consume resources (DB rows, storage).
- **TTL**: Automatically Delete job metadata and artifacts after N days.
- **Cancellation**: Allow clients to `DELETE` a job to stop processing.

## 5. Design for Idempotency

If a client submits the same job twice (same input hash), return the existing `jobId` instead of starting a new process (see idempotency in spring-boot-conventions §9).

## Do / Don't

✅ Use 202 Accepted for any request that takes > 2s.
✅ Provide a status endpoint with a clear state machine.
✅ Implement automatic cleanup of old jobs.
❌ Never block an HTTP thread while waiting for a long-running process to finish.
❌ Never return the final large artifact directly in the status poll response.
❌ Never use polling for high-frequency updates (use SSE or WebSockets).

