"""Single-process shard of the WS benchmark. Runs CLIENTS connections,
prints msg count and elapsed time as "COUNT SECONDS" for aggregation."""
import asyncio
import sys
import time

import websockets

CLIENTS = 10
MESSAGES = 10000
PAYLOAD = "hello"
URI = "ws://127.0.0.1:3001/ws"


async def client(results, idx):
    async with websockets.connect(URI, ping_interval=None) as ws:
        try:
            await asyncio.wait_for(ws.recv(), timeout=0.1)
        except asyncio.TimeoutError:
            pass

        count = 0

        async def sender():
            for _ in range(MESSAGES):
                await ws.send(PAYLOAD)

        async def receiver():
            nonlocal count
            for _ in range(MESSAGES):
                await ws.recv()
                count += 1

        await asyncio.gather(sender(), receiver())
        results[idx] = count


async def main():
    results = [0] * CLIENTS
    t0 = time.monotonic()
    await asyncio.gather(*(asyncio.create_task(client(results, i)) for i in range(CLIENTS)))
    t1 = time.monotonic()
    print(f"{sum(results)} {t1-t0:.4f}")


if __name__ == "__main__":
    asyncio.run(main())
