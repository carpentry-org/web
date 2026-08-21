#!/usr/bin/env python3
"""End-to-end WebSocket checks against test/smoke-server.carp.

Frames are built and parsed with the standard library alone: nothing here may
share code with the server under test.
"""

import base64
import hashlib
import os
import signal
import socket
import struct
import sys

HOST = "127.0.0.1"
PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 8437
GUID = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
TIMEOUT = 10.0
MAX_FRAME = 1 << 20
MAX_HEAD = 8192

OP_CONT, OP_TEXT, OP_BIN, OP_CLOSE, OP_PING, OP_PONG = 0x0, 0x1, 0x2, 0x8, 0x9, 0xA

failures = []


class Failure(Exception):
    pass


def want(label, expected, got):
    if expected != got:
        raise Failure("%s: expected %r, got %r" % (label, expected, got))


class Conn:
    def __init__(self):
        self.sock = socket.create_connection((HOST, PORT), timeout=TIMEOUT)
        self.sock.settimeout(TIMEOUT)
        self.buf = b""

    def _fill(self):
        chunk = self.sock.recv(4096)
        if not chunk:
            raise Failure("server closed the connection mid-read")
        self.buf += chunk

    def take(self, n):
        while len(self.buf) < n:
            self._fill()
        out, self.buf = self.buf[:n], self.buf[n:]
        return out

    def handshake(self, path, key=None, version="13", protocols=None):
        if key is None:
            key = base64.b64encode(os.urandom(16)).decode()
        lines = [
            "GET %s HTTP/1.1" % path,
            "Host: %s:%d" % (HOST, PORT),
            "Upgrade: websocket",
            "Connection: Upgrade",
        ]
        if key:
            lines.append("Sec-WebSocket-Key: %s" % key)
        if version:
            lines.append("Sec-WebSocket-Version: %s" % version)
        if protocols:
            lines.append("Sec-WebSocket-Protocol: %s" % protocols)
        self.sock.sendall(("\r\n".join(lines) + "\r\n\r\n").encode())
        return key, self.read_head()

    def read_head(self):
        while b"\r\n\r\n" not in self.buf:
            if len(self.buf) > MAX_HEAD:
                raise Failure("response head exceeded %d bytes" % MAX_HEAD)
            self._fill()
        head, self.buf = self.buf.split(b"\r\n\r\n", 1)
        lines = head.decode("latin-1").split("\r\n")
        headers = {}
        for line in lines[1:]:
            name, _, value = line.partition(":")
            headers[name.strip().lower()] = value.strip()
        return lines[0], headers

    def send_frame(self, opcode, payload=b"", fin=True, mask=True):
        head = bytes([(0x80 if fin else 0) | opcode])
        n = len(payload)
        flag = 0x80 if mask else 0
        if n < 126:
            head += bytes([flag | n])
        elif n < 65536:
            head += bytes([flag | 126]) + struct.pack("!H", n)
        else:
            head += bytes([flag | 127]) + struct.pack("!Q", n)
        if mask:
            key = os.urandom(4)
            payload = bytes(b ^ key[i % 4] for i, b in enumerate(payload))
            head += key
        self.sock.sendall(head + payload)

    def read_frame(self):
        b0, b1 = self.take(2)
        fin, rsv, opcode = bool(b0 & 0x80), (b0 >> 4) & 0x7, b0 & 0xF
        masked, n = bool(b1 & 0x80), b1 & 0x7F
        if n == 126:
            n = struct.unpack("!H", self.take(2))[0]
        elif n == 127:
            n = struct.unpack("!Q", self.take(8))[0]
        if n > MAX_FRAME:
            raise Failure("server declared a %d byte payload" % n)
        if masked:
            raise Failure("server frame is masked (RFC 6455 5.1)")
        want("frame RSV bits", 0, rsv)
        return fin, opcode, self.take(n)

    def expect_frame(self, label, opcode, payload=None, fin=True):
        got_fin, got_op, got_payload = self.read_frame()
        want("%s opcode" % label, opcode, got_op)
        want("%s FIN" % label, fin, got_fin)
        if payload is not None:
            want("%s payload" % label, payload, got_payload)
        return got_payload

    def expect_eof(self, label):
        if self.buf:
            raise Failure("%s: %d unread byte(s): %r"
                          % (label, len(self.buf), self.buf[:32]))
        try:
            rest = self.sock.recv(4096)
        except (ConnectionResetError, socket.timeout) as e:
            raise Failure("%s: %s" % (label, e.__class__.__name__))
        want(label, b"", rest)

    def close(self):
        try:
            self.sock.close()
        except OSError:
            pass


def accept_for(key):
    digest = hashlib.sha1((key + GUID).encode()).digest()
    return base64.b64encode(digest).decode()


def expect_upgrade(conn, path, protocols=None):
    key, (status, headers) = conn.handshake(path, protocols=protocols)
    want("status line", "HTTP/1.1 101 Switching Protocols", status)
    want("Upgrade header", "websocket", headers.get("upgrade", "").lower())
    want("Connection header", "upgrade", headers.get("connection", "").lower())
    want("Sec-WebSocket-Accept", accept_for(key), headers.get("sec-websocket-accept"))
    return headers


def run(name, fn):
    try:
        fn()
        print("ws: %s" % name)
    except Failure as e:
        failures.append("%s: %s" % (name, e))
        print("FAIL: ws %s: %s" % (name, e))
    except (OSError, struct.error) as e:
        failures.append("%s: %s: %s" % (name, e.__class__.__name__, e))
        print("FAIL: ws %s: %s: %s" % (name, e.__class__.__name__, e))


def check(name, fn):
    def connected():
        conn = Conn()
        try:
            fn(conn)
        finally:
            conn.close()
    run(name, connected)


def echo_session(conn):
    expect_upgrade(conn, "/ws/echo")
    conn.expect_frame("connect event", OP_TEXT, b"ready")

    text = "hello wörld ✓".encode()
    conn.send_frame(OP_TEXT, text)
    conn.expect_frame("text echo", OP_TEXT, text)

    binary = bytes(range(256)) + b"\x00\x00\xff"
    conn.send_frame(OP_BIN, binary)
    conn.expect_frame("binary echo", OP_BIN, binary)

    long_text = ("carp " * 120).encode()
    conn.send_frame(OP_TEXT, long_text)
    conn.expect_frame("extended-length echo", OP_TEXT, long_text)

    conn.send_frame(OP_PING, b"ping-payload")
    conn.expect_frame("pong", OP_PONG, b"ping-payload")

    conn.send_frame(OP_TEXT, b"frag", fin=False)
    conn.send_frame(OP_PING, b"mid")
    conn.send_frame(OP_CONT, b"ment", fin=True)
    conn.expect_frame("interleaved pong", OP_PONG, b"mid")
    conn.expect_frame("fragmented echo", OP_TEXT, b"fragment")

    conn.send_frame(OP_CLOSE, struct.pack("!H", 1000))
    payload = conn.expect_frame("close echo", OP_CLOSE)
    # RFC 6455 5.5.1: the answering close MAY carry a body, so empty is conformant too
    if payload not in (b"", struct.pack("!H", 1000)):
        raise Failure("close echo payload: want b'' or the echoed 1000, got %r"
                      % payload)
    conn.expect_eof("connection stayed open after close")


def subprotocol(conn):
    headers = expect_upgrade(conn, "/ws/proto", protocols="bogus, smoke-v1")
    want("negotiated protocol", "smoke-v1", headers.get("sec-websocket-protocol"))
    conn.expect_frame("protocol reported to the handler", OP_TEXT, b"smoke-v1")


def bad_version(conn):
    _, (status, headers) = conn.handshake("/ws/echo", version="8")
    want("status line", "HTTP/1.1 426 Upgrade Required", status)
    want("advertised version", "13", headers.get("sec-websocket-version"))


def missing_key(conn):
    _, (status, _) = conn.handshake("/ws/echo", key="")
    want("keyless status line", "HTTP/1.1 404 Not Found", status)
    # a keyless refusal is byte-identical to an unknown path, so prove the route is there
    control = Conn()
    try:
        _, (control_status, _) = control.handshake("/ws/echo")
        want("keyed control status line",
             "HTTP/1.1 101 Switching Protocols",
             control_status)
    finally:
        control.close()


def large_frame(conn):
    expect_upgrade(conn, "/ws/echo")
    conn.expect_frame("connect event", OP_TEXT, b"ready")
    # 70000 bytes puts both directions on the 64-bit length path (indicator 127)
    payload = b"".join(b"%06d." % i for i in range(10000))
    conn.send_frame(OP_TEXT, payload)
    conn.expect_frame("64-bit length echo", OP_TEXT, payload)


def unmasked_frame(conn):
    expect_upgrade(conn, "/ws/echo")
    conn.expect_frame("connect event", OP_TEXT, b"ready")
    conn.send_frame(OP_TEXT, b"unmasked", mask=False)
    payload = conn.expect_frame("close on unmasked frame", OP_CLOSE)
    want("close status", 1002, struct.unpack("!H", payload[:2])[0] if payload else None)
    conn.expect_eof("connection stayed open after an unmasked frame")


signal.alarm(120)
run("the client agrees with the RFC 6455 1.3 accept vector",
    lambda: want("accept vector",
                 "s3pPLMBiTxaQ9kYGzzhZRbK+xOo=",
                 accept_for("dGhlIHNhbXBsZSBub25jZQ==")))
check("handshake, echo, ping and close on /ws/echo", echo_session)
check("a 70000-byte frame round trips on the 64-bit length path", large_frame)
check("subprotocol negotiation on /ws/proto", subprotocol)
check("a bad Sec-WebSocket-Version is refused", bad_version)
check("a keyless upgrade is refused", missing_key)
check("an unmasked client frame fails the connection", unmasked_frame)

if failures:
    print("ws: %d check(s) failed" % len(failures))
    sys.exit(1)
print("ws: all WebSocket checks passed")
