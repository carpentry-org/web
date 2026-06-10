"""WebSocket echo server stress test.

Each client runs separate send and receive tasks to pipeline messages
and keep the server saturated. Measures server-side throughput, not
client RTT.
"""
import asyncio
import sys
import time

import websockets

CLIENTS = 50
MESSAGES = 10000
PAYLOAD = "hello"
URI = "ws://127.0.0.1:3001/ws"


async def client(results, idx):
    async with websockets.connect(URI, ping_interval=None) as ws:
        # Drain connect message if any
        try:
            await asyncio.wait_for(ws.recv(), timeout=0.1)
        except asyncio.TimeoutError:
            pass

        recv_count = 0

        async def sender():
            for _ in range(MESSAGES):
                await ws.send(PAYLOAD)

        async def receiver():
            nonlocal recv_count
            for _ in range(MESSAGES):
                await ws.recv()
                recv_count += 1

        t0 = time.monotonic()
        await asyncio.gather(sender(), receiver())
        t1 = time.monotonic()
        results[idx] = (recv_count, t1 - t0)


async def main():
    results = [None] * CLIENTS
    tasks = [asyncio.create_task(client(results, i)) for i in range(CLIENTS)]
    t_start = time.monotonic()
    await asyncio.gather(*tasks)
    t_total = time.monotonic() - t_start

    total_msgs = sum(r[0] for r in results)
    slowest = max(r[1] for r in results)

    print(f"Clients:         {CLIENTS}")
    print(f"Messages/client: {MESSAGES}")
    print(f"Total echoed:    {total_msgs}")
    print(f"Wall clock:      {t_total:.3f}s")
    print(f"Throughput:      {total_msgs / t_total:.0f} msg/s")


if __name__ == "__main__":
    asyncio.run(main())
