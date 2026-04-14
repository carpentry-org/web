# WebSocket Design (issue #11)

## Overview

Add WebSocket support to the web framework. A handler upgrades an HTTP
connection to WebSocket, then sends and receives frames over the existing
non-blocking event loop.

## User API (as implemented)

The implementation uses an event-based handler instead of per-connection
callbacks (see open question #3 below). Storing `Fn` values per-connection
requires `copy`/`prn` derivations that `Map` entries need, which closures
don't satisfy. The event-based approach avoids this by keeping the handler
in the route array (which already works for `Route`).

```carp
(defn chat [event params ws]
  (match-ref event
    (WSEvent.Connect) (WebSocket.send ws @"connected")
    (WSEvent.Message msg) (WebSocket.send ws (fmt "echo: %s" msg))
    (WSEvent.Close) ()))

(defserver "0.0.0.0" 3000
  (GET "/api/data" api-handler)
  (WS  "/ws/chat"  chat))
```

`WS` registers a WebSocket route. The handler receives `&WSEvent`,
`&(Map String String)` (params), and `&WebSocket` (for sending). It is
called once per event: `Connect`, `(Message String)`, or `Close`.

## Protocol

WebSocket upgrade (RFC 6455):

1. Client sends `GET /ws/chat` with headers:
   - `Upgrade: websocket`
   - `Connection: Upgrade`
   - `Sec-WebSocket-Key: <base64 nonce>`
   - `Sec-WebSocket-Version: 13`

2. Server responds `101 Switching Protocols` with:
   - `Upgrade: websocket`
   - `Connection: Upgrade`
   - `Sec-WebSocket-Accept: <SHA-1 hash of key + magic GUID>`

3. Connection switches from HTTP to WebSocket framing.

## Frame codec

WebSocket frames:

```
 0                   1                   2                   3
 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1
+-+-+-+-+-------+-+-------------+-------------------------------+
|F|R|R|R| opcode|M| Payload len |    Extended payload length    |
|I|S|S|S|  (4)  |A|     (7)     |             (16/64)           |
|N|V|V|V|       |S|             |   (if payload len==126/127)   |
| |1|2|3|       |K|             |                               |
+-+-+-+-+-------+-+-------------+-------------------------------+
|     Masking-key (0 or 4 bytes)      |
+-------------------------------------+
|          Payload Data               |
+-------------------------------------+
```

Opcodes: 0x1 = text, 0x2 = binary, 0x8 = close, 0x9 = ping, 0xA = pong.

Client-to-server frames are always masked (XOR with 4-byte key).
Server-to-client frames are never masked.

## Implementation plan

### Socket library (0.1.5)

Nothing new needed. WebSocket runs over the existing TcpStream. Frame
encoding/decoding is pure Carp (byte manipulation on Arrays).

### Crypto dependency

`Sec-WebSocket-Accept` requires SHA-1 + base64. Options:
- Use the existing `base64.carp` library for encoding
- SHA-1 in pure Carp (~80 lines, bitwise ops on byte arrays). Not
  used for security here, just as a protocol handshake token.

### Web framework changes

#### 1. WebSocket type

```carp
(deftype WebSocket [fd Int
                    on-message (Fn [String] ())
                    on-close (Fn [] ())])
```

Stored in a new ConnState field:
```carp
ws-conns (Map Int WebSocket)
```

A connection is in WebSocket mode when it has an entry in `ws-conns`.

#### 2. Upgrade detection

In `handle-readable`, after parsing the HTTP request, check for
WebSocket upgrade headers before routing:

```
if Upgrade: websocket AND Sec-WebSocket-Key present:
  compute accept hash
  send 101 response (via write-bufs, same as normal response)
  after headers drain, mark connection as WebSocket (add to ws-conns)
  call the WS handler with &WebSocket to set up callbacks
```

#### 3. WebSocket read path

When a WebSocket connection becomes readable:
- Read bytes into read-buf (same as HTTP)
- Parse WebSocket frame(s) from the buffer
- Unmask payload
- Dispatch by opcode:
  - text/binary: call `on-message` callback
  - ping: queue pong response
  - close: queue close response, mark for cleanup

#### 4. WebSocket write path

`WebSocket.send` encodes a text frame and appends to the connection's
write-buf. The existing writable event handler drains it.

For streaming LLM tokens: each token is a separate text frame. The
event loop interleaves sends across connections naturally.

#### 5. Route registration

`(WS pattern handler)` in defserver registers a route with method
`"WS"`. The readable handler checks if the matched route is a WS route
and triggers the upgrade instead of building an HTTP response.

#### 6. Frame codec (pure Carp)

```carp
(defmodule WebSocket
  (defn encode-text [msg] ...)   ; -> (Array Byte)
  (defn decode-frame [buf] ...)  ; -> (Maybe Frame)
  (defn send [ws msg] ...)       ; encodes + queues for write
)
```

Encode: FIN=1, opcode=0x1, no mask, payload length, payload bytes.
Decode: read header, extract mask + length, unmask payload.

## Open questions

1. **Binary frames**: support text-only initially, or both?
   Recommendation: text-only for 0.4.0. Binary in 0.5.0.

2. **Fragmentation**: large messages split across frames.
   Recommendation: reassemble in the read path. Cap at
   `App.max-request-size` to prevent memory exhaustion.

3. **Per-message callbacks vs channel model**: the callback model
   (`on-message`) is simple but each WebSocket connection needs its
   own callback. Storing `Fn` values per-connection has the
   copy/prn derivation issues we hit with ConnState.
   Recommendation: store callbacks in a parallel map keyed by fd,
   similar to how we store sendfile state. Avoid putting Fn in a
   deftype.

4. **Backpressure**: if the server generates tokens faster than the
   client reads, the write buffer grows. Need a high-water mark
   that pauses the generator.
   Recommendation: defer to 0.5.0. For LLM token streaming, the
   token rate is slow enough that backpressure isn't a concern.

## Estimated scope

- SHA-1 + base64: ~100 lines pure Carp
- Frame codec: ~100 lines Carp
- Upgrade handshake: ~50 lines
- Event loop integration: ~80 lines
- Route/defserver support: ~20 lines
- Tests: ~50 lines

Total: ~400 lines across socket, web, and a small crypto helper.
