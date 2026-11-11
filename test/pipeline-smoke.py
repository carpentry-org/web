#!/usr/bin/env python3
"""End-to-end HTTP/1.1 pipelining checks against test/smoke-server.carp.

Each case sends several requests in one write and expects every response, in
order, on the same connection.
"""

import os
import socket
import sys
import time

HOST = "127.0.0.1"
PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 8437
TIMEOUT = 5.0
HERE = os.path.dirname(os.path.abspath(__file__))

with open(os.path.join(HERE, "static-fixtures", "index.html"), "rb") as f:
    INDEX = f.read()

BIG = b"x" * 600000


class Failure(Exception):
    pass


def get(path):
    return ("GET %s HTTP/1.1\r\nHost: x\r\n\r\n" % path).encode()


def post(path, body):
    head = "POST %s HTTP/1.1\r\nHost: x\r\nContent-Length: %d\r\n\r\n"
    return (head % (path, len(body))).encode() + body


def chunked_post(path, body, trailer):
    head = "POST %s HTTP/1.1\r\nHost: x\r\nTransfer-Encoding: chunked\r\n\r\n"
    chunk = b"%x\r\n%s\r\n0\r\n%s\r\n" % (len(body), body, trailer)
    return (head % path).encode() + chunk


def take_response(buf):
    """(status, body, rest) for the first whole response in `buf`, or None."""
    end = buf.find(b"\r\n\r\n")
    if end < 0:
        return None
    lines = buf[:end].decode("latin-1").split("\r\n")
    length = 0
    for line in lines[1:]:
        name, _, value = line.partition(":")
        if name.strip().lower() == "content-length":
            length = int(value.strip())
    if len(buf) < end + 4 + length:
        return None
    status = int(lines[0].split(" ")[1])
    return status, buf[end + 4:end + 4 + length], buf[end + 4 + length:]


def exchange(payload, count):
    sock = socket.create_connection((HOST, PORT), timeout=TIMEOUT)
    deadline = time.monotonic() + TIMEOUT
    got = []
    buf = b""
    try:
        sock.sendall(payload)
        while len(got) < count:
            r = take_response(buf)
            if r is not None:
                got.append((r[0], r[1]))
                buf = r[2]
                continue
            left = deadline - time.monotonic()
            if left <= 0:
                raise Failure("timed out after %d of %d responses" % (len(got), count))
            sock.settimeout(left)
            try:
                chunk = sock.recv(65536)
            except socket.timeout:
                raise Failure("timed out after %d of %d responses" % (len(got), count))
            if not chunk:
                raise Failure("connection closed after %d of %d responses" % (len(got), count))
            buf += chunk
    finally:
        sock.close()
    return got


def short(responses):
    return [(s, b if len(b) <= 40 else b[:40] + b"...") for s, b in responses]


CASES = [
    ("two GETs in one write",
     get("/ok") + get("/static/index.html"),
     [(200, b"ok"), (200, INDEX)]),
    ("a Content-Length POST, then a GET",
     post("/echo", b"hello") + get("/ok"),
     [(200, b"hello"), (200, b"ok")]),
    ("a chunked POST, then a GET",
     chunked_post("/echo", b"hello", b"") + get("/ok"),
     [(200, b"hello"), (200, b"ok")]),
    ("a chunked POST with trailers, then a GET",
     chunked_post("/echo", b"hello", b"X-One: 1\r\nX-Two: 2\r\n") + get("/ok"),
     [(200, b"hello"), (200, b"ok")]),
    ("a large echo, then a file, then a GET",
     post("/echo", BIG) + get("/static/index.html") + get("/ok"),
     [(200, BIG), (200, INDEX), (200, b"ok")]),
]


def main():
    failed = 0
    for label, payload, want in CASES:
        try:
            got = exchange(payload, len(want))
            if got != want:
                raise Failure("expected %r, got %r" % (short(want), short(got)))
            print("pipeline: %s: ok" % label)
        except (Failure, OSError) as e:
            failed += 1
            print("pipeline: %s: FAIL: %s" % (label, e))
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
