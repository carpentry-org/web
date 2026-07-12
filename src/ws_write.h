#include <unistd.h>
#include <errno.h>
#include <poll.h>
#include <sys/socket.h>

/* How long to wait for the socket to become writable again before giving
 * up on the connection. A healthy client drains its receive buffer in
 * milliseconds; a stall this long means the peer is gone or wedged. */
#define WS_WRITE_POLL_TIMEOUT_MS 30000

/* Write a complete frame to a (possibly non-blocking) socket.
 *
 * A frame must never be partially written: the remainder of a torn frame
 * desynchronizes the WebSocket stream and the client kills the connection.
 * On EAGAIN we poll for writability and resume, which gives handlers that
 * stream via send-now natural backpressure. Returns the total bytes sent,
 * or -1 on error/timeout (the frame may then be torn and the connection
 * should be abandoned by the caller).
 */
int ws_write_fd(int fd, Array *data) {
    uint8_t *buf = (uint8_t *)data->data;
    int len = data->len;
    int sent = 0;
#ifdef MSG_NOSIGNAL
    int flags = MSG_NOSIGNAL;
#else
    int flags = 0;
#endif
#ifdef SO_NOSIGPIPE
    int one = 1;
    setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, sizeof(one));
#endif
    while (sent < len) {
        ssize_t n = send(fd, buf + sent, (size_t)(len - sent), flags);
        if (n > 0) {
            sent += (int)n;
            continue;
        }
        if (n < 0 && errno == EINTR) continue;
        if (n < 0 && (errno == EAGAIN || errno == EWOULDBLOCK)) {
            struct pollfd pfd = { .fd = fd, .events = POLLOUT };
            int p;
            do {
                p = poll(&pfd, 1, WS_WRITE_POLL_TIMEOUT_MS);
            } while (p < 0 && errno == EINTR);
            if (p <= 0) return -1;
            continue;
        }
        return -1;
    }
    return sent;
}
