---
name: async-api-patterns
description: Handle long-running operations (> 2s) in a RESTful way. Covers the "Submit-Poll-Result" pattern, Webhooks, and SSE (Server-Sent Events). Includes guidance on job state management, cleanup of abandoned jobs, and designing for idempotency.
tier: should
applies_to: [rest, event, monolith]
depends_on: [code-structure, persistence]
ships_templates: false
hitl: false
version: 1.0
last_reviewed: 2026-06-28
---

# Async API Patterns Skill

Standard REST calls should return within 1-2 seconds. For operations that take longer (PDF generation, data export), use an asynchronous pattern.

## 1. Pattern: Submit → Poll → Result

### Step 1: Submit
`POST /conversions`
- Returns **`202 Accepted`**.
- Body includes a `jobId` and a `Location` header to the status endpoint.

### Step 2: Poll
`GET /conversions/{jobId}`
- Returns the current state: `PENDING`, `PROCESSING`, `COMPLETED`, `FAILED`.

**Optimization**: Use `Wait-For` or `Prefer: respond-async` headers to allow "long polling" where the server holds the request until the state changes or a timeout occurs.

### Step 3: Result
- Once status is `COMPLETED`, the body contains a URL to retrieve the artifact (e.g., `GET /conversions/{jobId}/download`).

## 2. Notification: Webhooks

Instead of forcing the client to poll, let them provide a `callbackUrl`.
- Once the job is done, the service makes a `POST` request to the `callbackUrl`.
- **Security**: Sign the webhook payload (e.g., HMAC-SHA256) so the client can verify it came from us. Include a `X-Hub-Signature` header.

### 2b. Callback Reliability
If the client's `callbackUrl` is down, use an **exponential backoff retry** (see [resilience-patterns](../resilience-patterns/SKILL.md)). If all retries fail, move the notification to a Dead Letter Queue (DLQ, see [messaging](../messaging/SKILL.md)).

## 3. Real-time: Server-Sent Events (SSE)

For UI clients, use SSE to push status updates over a single HTTP connection.
- Spring Boot `SseEmitter` makes this easy in a `@RestController`.

## 4. Job Management & Cleanup

Async jobs consume resources (DB rows, storage).
- **TTL**: Automatically Delete job metadata and artifacts after N days.
- **Cancellation**: Allow clients to `DELETE` a job to stop processing.

## 5. Design for Idempotency

If a client submits the same job twice (same input hash), return the existing `jobId` instead of starting a new process (see [idempotency in spring-boot-conventions](../spring-boot-conventions/SKILL.md#9-idempotency)).

## Do / Don't

✅ Use 202 Accepted for any request that takes > 2s.
✅ Provide a status endpoint with a clear state machine.
✅ Implement automatic cleanup of old jobs.
❌ Never block an HTTP thread while waiting for a long-running process to finish.
❌ Never return the final large artifact directly in the status poll response.
❌ Never use polling for high-frequency updates (use SSE or WebSockets).

