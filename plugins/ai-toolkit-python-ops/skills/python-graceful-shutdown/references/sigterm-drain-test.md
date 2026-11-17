# python-graceful-shutdown — SIGTERM drain test under load

Back to [`SKILL.md`](../SKILL.md) §6. Starts the real service with uvicorn and the production flags in a subprocess,
keeps 20 clients sending 1-second requests, sends `SIGTERM` mid-load and asserts that no request that was sent
before the signal fails, that the process exits, and that new connections are refused. Run against PostgreSQL
(testcontainers). The negative control (`SIGKILL` instead of `SIGTERM`) fails the same assertions.

Findings from running it:
- uvicorn finishes in-flight requests and then **re-raises the signal**. A subprocess of the test is not PID 1, so
  it ends with status `-15` (shell `143`), which is what the test asserts. As PID 1 in a container the same drain
  exits `0` (the kernel ignores a signal PID 1 has no handler for): do not assert `0` for a subprocess or `-15` for
  a container, and do not treat either as a failed container in smoke scripts.
- A request sent in the same instant as the signal may hit the closing listener. In a cluster the `preStop` sleep
  (§3) covers that window; the test therefore only judges requests sent `UNAMBIGUOUS_MARGIN` before the signal.

A test-only app adds one slow route to the real `create_app()`, so the request is in flight when the signal arrives:

### `tests/integration/slow_app.py`

```python
import asyncio
from typing import Annotated

from fastapi import Depends, FastAPI
from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncEngine

from my_service.api.dependencies import get_engine
from my_service.main import create_app


def create() -> FastAPI:
    app = create_app()

    @app.get("/slow")
    async def slow(
        engine: Annotated[AsyncEngine, Depends(get_engine)], seconds: float = 1.0
    ) -> dict[str, str]:
        await asyncio.sleep(seconds)
        async with engine.connect() as conn:
            await conn.execute(text("SELECT 1"))
        return {"status": "done"}

    return app
```

### `tests/integration/test_graceful_shutdown.py`

```python
import asyncio
import os
import signal
import socket
import subprocess
import sys
import time
from collections.abc import Iterator
from dataclasses import dataclass
from pathlib import Path

import httpx
import pytest
from sqlalchemy.engine import make_url
from sqlalchemy.ext.asyncio import AsyncEngine

GRACE_SECONDS = 15
SLOW_SECONDS = 1.0
UNAMBIGUOUS_MARGIN = 0.3


def _free_port() -> int:
    with socket.socket() as s:
        s.bind(("127.0.0.1", 0))
        port: int = s.getsockname()[1]
    return port


@dataclass
class Outcome:
    started: float
    status: int | None
    error: str | None


@dataclass
class Server:
    process: subprocess.Popen[bytes]
    port: int

    @property
    def base_url(self) -> str:
        return f"http://127.0.0.1:{self.port}"


@pytest.fixture
def server(engine: AsyncEngine, postgres_url: str, tmp_path: Path) -> Iterator[Server]:
    url = make_url(postgres_url)
    port = _free_port()
    env = {
        **os.environ,
        "DB_URL": url.set(password=None).render_as_string(),
        "DB_PASSWORD": url.password or "",
        "PYTHONUNBUFFERED": "1",
    }
    process = subprocess.Popen(  # noqa: S603
        [
            sys.executable,
            "-m",
            "uvicorn",
            "tests.integration.slow_app:create",
            "--factory",
            "--port",
            str(port),
            "--proxy-headers",
            "--timeout-graceful-shutdown",
            str(GRACE_SECONDS),
        ],
        env=env,
    )
    yield Server(process, port)
    if process.poll() is None:
        process.kill()
        process.wait()


async def _wait_ready(base_url: str) -> None:
    async with httpx.AsyncClient(base_url=base_url) as client:
        async with asyncio.timeout(30):
            while True:
                try:
                    if (await client.get("/health/ready")).status_code == 200:
                        return
                except httpx.TransportError:
                    pass
                await asyncio.sleep(0.2)


async def _load(base_url: str, stop_sending: asyncio.Event, outcomes: list[Outcome]) -> None:
    async with httpx.AsyncClient(base_url=base_url, timeout=GRACE_SECONDS + 5) as client:
        while not stop_sending.is_set():
            started = time.monotonic()
            try:
                response = await client.get("/slow", params={"seconds": SLOW_SECONDS})
            except httpx.TransportError as exc:
                outcomes.append(Outcome(started, None, type(exc).__name__))
            else:
                outcomes.append(Outcome(started, response.status_code, None))


async def test_sigterm_underLoad_inFlightRequestsCompleteAndProcessEndsBySigterm(
    server: Server,
) -> None:
    await _wait_ready(server.base_url)
    outcomes: list[Outcome] = []
    stop_sending = asyncio.Event()
    clients = [
        asyncio.create_task(_load(server.base_url, stop_sending, outcomes)) for _ in range(20)
    ]
    await asyncio.sleep(3 * SLOW_SECONDS)
    terminated_at = time.monotonic()
    server.process.send_signal(signal.SIGTERM)
    await asyncio.sleep(0.1)
    stop_sending.set()
    await asyncio.gather(*clients)
    exit_code = await asyncio.to_thread(server.process.wait, GRACE_SECONDS + 5)

    before = [o for o in outcomes if o.started < terminated_at - UNAMBIGUOUS_MARGIN]
    in_flight = [o for o in before if o.started > terminated_at - SLOW_SECONDS]
    assert len(before) >= 40
    assert len(in_flight) >= 10
    failed = [o for o in before if o.status != 200]
    assert failed == []
    assert exit_code == -signal.SIGTERM
    with pytest.raises(httpx.ConnectError):
        async with httpx.AsyncClient(base_url=server.base_url) as client:
            await client.get("/health/live")
```

