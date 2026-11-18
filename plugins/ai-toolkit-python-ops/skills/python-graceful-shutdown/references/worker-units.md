# python-graceful-shutdown — heartbeat module and worker unit tests

Back to [`SKILL.md`](../SKILL.md) §5 and §6. `worker.py` itself is in `python-messaging`'s `kafka-worker.md`. These
unit tests need no broker or database: `worker_resources` is replaced by an async context manager yielding fake
loops, and a real `SIGTERM` is sent to the test process (`run_worker` installs the handler on the running loop and
removes it in `finally`, so it does not outlive the test).

## Heartbeat and liveness probe

### `src/my_service/liveness.py`

```python
import os
import sys
import time
from pathlib import Path

HEARTBEAT_DIR = Path(os.environ.get("HEARTBEAT_DIR", "/tmp/heartbeat"))  # noqa: S108 (emptyDir)
MAX_AGE_SECONDS = float(os.environ.get("HEARTBEAT_MAX_AGE_SECONDS", "60"))


class Heartbeat:
    def __init__(self, loop_name: str) -> None:
        self._path = HEARTBEAT_DIR / loop_name

    def beat(self) -> None:
        self._path.parent.mkdir(parents=True, exist_ok=True)
        self._path.touch()


def main() -> None:
    now = time.time()
    stale = [p.name for p in HEARTBEAT_DIR.glob("*") if now - p.stat().st_mtime > MAX_AGE_SECONDS]
    sys.exit(f"stale loops: {stale}" if stale else 0)


if __name__ == "__main__":
    main()
```

## Worker drain tests

### `tests/unit/test_worker.py`

```python
import asyncio
import os
import signal
import time
from collections.abc import AsyncIterator
from contextlib import asynccontextmanager
from pathlib import Path

import pytest
from pydantic import SecretStr

from my_service import liveness, worker
from my_service.config.settings import AppSettings, DatabaseSettings
from my_service.worker import WorkerResources, run_worker

SETTINGS = AppSettings(
    db=DatabaseSettings(url="postgresql+asyncpg://t@127.0.0.1:1/t", password=SecretStr("x")),
    drain_seconds=2.0,
    relay_idle_seconds=0.01,
)


class FakeRelay:
    def __init__(self, fail: bool = False) -> None:
        self.batches = 0
        self._fail = fail

    async def publish_batch(self) -> int:
        self.batches += 1
        if self._fail:
            raise RuntimeError("batch failed")
        return 0


class FakeConsumerLoop:
    def __init__(self, crash: bool = False, busy_seconds: float = 0.0) -> None:
        self.started = asyncio.Event()
        self.finished = False
        self._crash = crash
        self._busy_seconds = busy_seconds

    async def run(self, stop: asyncio.Event) -> None:
        self.started.set()
        if self._crash:
            raise RuntimeError("consumer crashed")
        await stop.wait()
        await asyncio.sleep(self._busy_seconds)
        self.finished = True


@pytest.fixture(autouse=True)
def isolated_worker(monkeypatch: pytest.MonkeyPatch, tmp_path: Path) -> None:
    monkeypatch.setattr(liveness, "HEARTBEAT_DIR", tmp_path)
    monkeypatch.setattr(worker, "start_http_server", lambda port: None)


def _install(monkeypatch: pytest.MonkeyPatch, relay: FakeRelay, consumer: FakeConsumerLoop) -> None:
    @asynccontextmanager
    async def fake_resources(settings: AppSettings) -> AsyncIterator[WorkerResources]:
        yield WorkerResources(relay=relay, consumer_loop=consumer)

    monkeypatch.setattr(worker, "worker_resources", fake_resources)


async def test_runWorker_sigterm_inFlightRecordFinishesAndWorkerReturns(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    relay, consumer = FakeRelay(), FakeConsumerLoop(busy_seconds=0.2)
    _install(monkeypatch, relay, consumer)
    task = asyncio.create_task(run_worker(SETTINGS))
    await asyncio.wait_for(consumer.started.wait(), 1)
    os.kill(os.getpid(), signal.SIGTERM)
    await asyncio.wait_for(task, 3)
    assert consumer.finished
    assert relay.batches >= 1


async def test_runWorker_idleConsumer_returnsWithinOnePollNotTheDrainBudget(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    _install(monkeypatch, FakeRelay(), FakeConsumerLoop())
    task = asyncio.create_task(run_worker(SETTINGS))
    await asyncio.sleep(0.1)
    started = time.monotonic()
    os.kill(os.getpid(), signal.SIGTERM)
    await asyncio.wait_for(task, 3)
    assert time.monotonic() - started < SETTINGS.drain_seconds / 2


async def test_runWorker_loopCrashes_workerRaisesAfterTheOtherLoopStopped(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    relay, consumer = FakeRelay(), FakeConsumerLoop(crash=True)
    _install(monkeypatch, relay, consumer)
    with pytest.raises(RuntimeError, match="consumer crashed"):
        await asyncio.wait_for(run_worker(SETTINGS), 3)


async def test_runWorker_handlerOutlivesDrainBudget_isCancelledNotAwaitedForever(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    consumer = FakeConsumerLoop(busy_seconds=30)
    _install(monkeypatch, FakeRelay(), consumer)
    settings = SETTINGS.model_copy(update={"drain_seconds": 0.2})
    task = asyncio.create_task(run_worker(settings))
    await asyncio.wait_for(consumer.started.wait(), 1)
    os.kill(os.getpid(), signal.SIGTERM)
    await asyncio.wait_for(task, 3)
    assert not consumer.finished


def test_livenessMain_staleHeartbeat_exitsNonZero(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    monkeypatch.setattr(liveness, "HEARTBEAT_DIR", tmp_path)
    stale = tmp_path / "consumer"
    stale.touch()
    old = time.time() - liveness.MAX_AGE_SECONDS - 5
    os.utime(stale, (old, old))
    with pytest.raises(SystemExit) as exited:
        liveness.main()
    assert "consumer" in str(exited.value.code)


def test_livenessMain_freshHeartbeat_exitsZero(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    monkeypatch.setattr(liveness, "HEARTBEAT_DIR", tmp_path)
    liveness.Heartbeat("relay").beat()
    with pytest.raises(SystemExit) as exited:
        liveness.main()
    assert exited.value.code == 0
```
