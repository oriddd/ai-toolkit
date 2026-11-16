---
name: python-graceful-shutdown
description: >
  Python / FastAPI graceful shutdown on Kubernetes — uvicorn's SIGTERM drain and --timeout-graceful-shutdown, preStop
  sleep, the grace-period budget, lifespan closing tasks, clients and pools, and a SIGTERM-aware worker entrypoint.
  Use when deploying a Python service or worker to Kubernetes.
tier: should
applies_to: [rest, worker]
depends_on: [python-ci]
ships_templates: false
hitl: false
version: 1.2
last_reviewed: 2026-11-15
---

> ⚠️ **Experimental.** Not yet validated on production projects; conventions may change before promotion to stable.

# Python Graceful Shutdown Skill
## When to use
When a FastAPI service or a Python worker runs on Kubernetes, or when a rolling update shows 5xx responses,
connection resets, duplicate events or a pod that always waits out its whole grace period.

## Layout

```
src/my_service/
├── main.py                 # create_app(): the lifespan closes tasks, clients and pools on shutdown (§4)
├── worker.py               # main(): the worker process — outbox relay and consumers, stops on SIGTERM (§5)
└── liveness.py             # heartbeat files + the worker's exec liveness probe (§5)
Dockerfile                  # exec-form CMD with --timeout-graceful-shutdown (`python-ci` §3)
deploy/                     # api and worker Deployments: preStop, terminationGracePeriodSeconds (§3, `python-cd`)
```

## 1. What uvicorn does on SIGTERM
1. It closes the listening socket at once: a new connection is **refused**, not queued.
2. It waits for in-flight requests to finish, for at most `--timeout-graceful-shutdown` seconds. Without the flag
   it waits forever, so the kubelet's `SIGKILL` ends the pod before the lifespan shutdown runs.
3. When the timeout expires it cancels the remaining requests: the handler gets `CancelledError` and the client a
   `500` with `Connection: close`.
4. Only then does the lifespan's shutdown half (the code after `yield`) run, and the process exits.

Step 1 is why the pod needs a `preStop` sleep (§3); step 2 is why the timeout must fit the grace period.

## 2. Run uvicorn so it receives the signal
- Exec-form `CMD ["uvicorn", ..., "--timeout-graceful-shutdown", "20"]` (`python-ci` §3). In shell form,
  `/bin/sh` is PID 1 and does not forward `SIGTERM`; uvicorn never hears it and the pod is killed after the grace period.
- One uvicorn process per container; scale with replicas, not `--workers`.
- PID 1 ignores any signal it installed no handler for. uvicorn installs one; your own worker process must too (§5).

## 3. Kubernetes contract and budget
```yaml
spec:
  terminationGracePeriodSeconds: 45
  containers:
    - name: api
      lifecycle:
        preStop:
          sleep:
            seconds: 5          # native sleep action (Kubernetes >= 1.30); older: exec ["sleep", "5"]
      livenessProbe:  { httpGet: { path: /health/live,  port: 8000 } }
      readinessProbe: { httpGet: { path: /health/ready, port: 8000 } }
```

1. The pod is marked Terminating and removed from the Service endpoints; kube-proxy and the ingress catch up
   over the next seconds.
2. `preStop` sleeps, so requests routed by stale endpoints still find an open socket.
3. Then `SIGTERM`: uvicorn drains (§1), the lifespan closes resources (§4).
4. `SIGKILL` when `terminationGracePeriodSeconds` has elapsed, counted from step 1.

```
terminationGracePeriodSeconds  >  preStop sleep + --timeout-graceful-shutdown + lifespan shutdown
                                   5            + 20                         + 10   = 35  <  45
```

The pod leaves the endpoints because it is terminating, not because a probe failed, so the app does not need to
fail readiness during shutdown (it receives `SIGTERM` only after `preStop` anyway). Liveness keeps answering:
a restart mid-drain drops the requests the drain protects. Keep `--timeout-graceful-shutdown` above the slowest
normal request; long work belongs in a `202 Accepted` job, not in a request that must survive a deploy.

## 4. Lifespan: stop tasks first, close pools last
```python
async def stop_and_wait(task: asyncio.Task[None], stop: asyncio.Event) -> None:
    stop.set()
    await task                                       # the in-flight relay batch finishes

@asynccontextmanager
async def lifespan(app: FastAPI) -> AsyncIterator[None]:
    async with AsyncExitStack() as stack:            # closes in reverse order, also when one close fails
        engine = create_async_engine(resolved.db.sqlalchemy_url(), pool_size=resolved.db.pool_size)
        stack.push_async_callback(engine.dispose)                            # closed last
        session_factory = async_sessionmaker(engine, expire_on_commit=False)
        billing_http = await stack.enter_async_context(build_billing_http_client(resolved.billing))
        producer = await stack.enter_async_context(AIOKafkaProducer(  # started now, stopped on exit
            bootstrap_servers=resolved.kafka.bootstrap_servers, enable_idempotence=True, acks="all"))
        relay = OutboxRelay(session_factory, KafkaEventPublisher(producer), batch_size=100)
        stop = asyncio.Event()
        relay_task = asyncio.create_task(run_relay(relay, stop, idle_seconds=1.0))
        stack.push_async_callback(stop_and_wait, relay_task, stop)          # stopped first
        app.state.session_factory = session_factory
        app.state.billing = HttpBillingClient(billing_http, RetryPolicy(max_attempts=3))
        yield
```

- Register each resource on the stack right after creating it; the shutdown order is then the reverse of the
  startup order: background tasks, then producers and HTTP clients, then the engine they use.
- A background task in the API process (the outbox relay, `python-messaging` §3) takes the same `stop` event and
  finishes its current batch; never leave it to be garbage-collected or cancelled mid-transaction.
- Shutdown code must be quick and bounded: no retries against a dependency that is already gone.

## 5. The worker process: own entrypoint, own Deployment
Consumers and a dedicated relay (`applies_to: worker`) run in a separate process from the same image and
package, with no HTTP server: `[project.scripts] my-service-worker = "my_service.worker:main"`
(`python-code-structure` §1b) and a second Deployment whose container runs `command: ["my-service-worker"]`.

```python
async def run_worker(settings: AppSettings) -> None:
    stop = asyncio.Event()
    loop = asyncio.get_running_loop()
    for sig in (signal.SIGTERM, signal.SIGINT):
        loop.add_signal_handler(sig, stop.set)       # PID 1: without a handler SIGTERM is ignored
    start_http_server(settings.metrics_port)         # prometheus_client: /metrics for the PodMonitor (`python-cd` §5)
    async with worker_resources(settings) as resources:   # engine, producer, consumer; closed on exit
        relay = asyncio.create_task(
            run_relay(resources.relay, stop, settings.relay_idle_seconds, Heartbeat("relay")))
        consumer = asyncio.create_task(resources.consumer_loop.run(stop))
        loops = {relay, consumer}
        stopper = asyncio.create_task(stop.wait())
        await asyncio.wait({stopper, *loops}, return_when=asyncio.FIRST_COMPLETED)
        stop.set()                                   # SIGTERM, or a loop ended first: stop the other one too
        stopper.cancel()
        done, pending = await asyncio.wait(loops, timeout=settings.drain_seconds)
        for task in pending:
            task.cancel()                            # idle consumer waiting for a record: nothing in flight
        await asyncio.gather(*pending, return_exceptions=True)
        for task in done:
            task.result()                            # a loop that crashed re-raises: the process exits non-zero

def main() -> None:
    asyncio.run(run_worker(AppSettings()))
```

- Waiting on the loops as well as on `stop` is what makes a crash visible: `await stop.wait()` alone never notices a
  loop task that died, so the pod would sit idle, still beating the other loop's heartbeat, until someone restarts
  it. When a loop ends first the other one drains, `task.result()` re-raises, `asyncio.run` exits non-zero and the
  kubelet restarts the container.
- `start_http_server(settings.metrics_port)` serves the worker's `prometheus_client` registry (consumer and relay
  lag, DLT count, `python-observability` §4) on a plain port the PodMonitor scrapes; it needs no ASGI app.
- The consumer loop polls with `getmany(timeout_ms=1000, max_records=1)` and checks `stop` after each record is
  processed and committed (`python-messaging` §5), so it never stops between the side effect and the offset commit,
  and an idle worker exits within one poll instead of waiting out `drain_seconds`. Only a handler still running
  after `drain_seconds` is cancelled; its record rolls back and is redelivered, which the idempotent consumer absorbs.
- `worker_resources` is an `asynccontextmanager` over an `AsyncExitStack`: closing the aiokafka consumer leaves
  the group, so its partitions move to another replica at once instead of after the session timeout.
- Worker budget: `terminationGracePeriodSeconds > drain_seconds + resource close`. A worker has no Service, so
  no readiness probe and no `preStop`.
- Liveness without an HTTP server: each loop (consumer, relay) calls `Heartbeat(<loop>).beat()` once per iteration
  (`run_relay` takes the `Heartbeat` as its fourth argument, `python-messaging` §3),
  which touches `/tmp/heartbeat/<loop>` (an `emptyDir`, so it works with a read-only root filesystem). A stdlib-only
  module checks the ages; an exec probe runs it, so a hung or deadlocked loop restarts the pod:

```python
HEARTBEAT_DIR = Path(os.environ.get("HEARTBEAT_DIR", "/tmp/heartbeat"))  # noqa: S108  (an emptyDir mount)
MAX_AGE_SECONDS = float(os.environ.get("HEARTBEAT_MAX_AGE_SECONDS", "60"))

class Heartbeat:                                     # my_service/liveness.py: imports nothing heavy
    def __init__(self, loop_name: str) -> None:
        self._path = HEARTBEAT_DIR / loop_name

    def beat(self) -> None:
        self._path.parent.mkdir(parents=True, exist_ok=True)
        self._path.touch()

def main() -> None:                                  # livenessProbe: exec ["python", "-m", "my_service.liveness"]
    now = time.time()
    stale = [p.name for p in HEARTBEAT_DIR.glob("*") if now - p.stat().st_mtime > MAX_AGE_SECONDS]
    sys.exit(f"stale loops: {stale}" if stale else 0)

if __name__ == "__main__":
    main()
```

  `MAX_AGE_SECONDS` must exceed the slowest record's handling with all its retries, plus the poll timeout; set the
  probe's `timeoutSeconds` and `failureThreshold` so one slow record does not restart the pod.

## 6. Testing
- Unit: the lifespan run through `LifespanManager` (`asgi-lifespan`) with fakes recording the close order —
  relay, then clients, then engine; the consumer loop with `stop` already set returns after one committed record.
- Unit: `run_worker`'s drain with fake loops — the in-flight record finishes and is committed, an idle consumer
  returns within one poll (nothing is cancelled), and a loop that raises makes `run_worker` raise after the other
  loop has stopped; `liveness.main` exits non-zero for a stale heartbeat file.
- Smoke, once per service: start uvicorn with the production flags, send a slow request, send `SIGTERM`; the
  request completes with `200`, a new connection is refused, the lifespan shutdown logs after the request.

## Do / Don't
- ✅ Exec-form `CMD`; `--timeout-graceful-shutdown` below the grace period minus `preStop` and lifespan shutdown.
- ✅ `preStop` sleep on every pod behind a Service; the budget written down next to the Deployment.
- ✅ One `AsyncExitStack` in the lifespan; background tasks stopped through an event and awaited.
- ✅ Workers install `SIGTERM`/`SIGINT` handlers and stop between records, after the commit.
- ✅ `run_worker` waits on its loops as well as on `stop`, so a crashed loop fails the process.
- ✅ Worker loops beat a heartbeat file each iteration; an exec liveness probe checks its age.
- ❌ Shell-form `CMD`, or a wrapper script that does not `exec` the server.
- ❌ uvicorn without `--timeout-graceful-shutdown`: the lifespan shutdown never runs on a stuck request.
- ❌ Failing liveness during shutdown; restarting a pod that is draining.
- ❌ Consumers in the API process: every API deploy or scale-out then rebalances the consumer group.
- ❌ `os._exit`, `sys.exit` from a signal handler, or cancelling a consumer task between side effect and commit.

## Cross-references
- [`python-ci`](../python-ci/SKILL.md) — the Dockerfile and its exec-form `CMD`.
- [`python-cd`](../python-cd/SKILL.md) — the Helm chart that carries this budget, the probes and the worker Deployment.
- [`python-observability`](../python-observability/SKILL.md) — logs and metrics around shutdown.
- `python-fastapi-conventions` — the lifespan and the health endpoints.
- `python-messaging` — the outbox relay and consumer loop that take the `stop` event.
- `python-code-structure` — the buildable package and its `[project.scripts]` entry.
