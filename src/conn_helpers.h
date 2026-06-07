#ifndef WEB_CONN_HELPERS_H
#define WEB_CONN_HELPERS_H

/* Extract the file descriptor from a TcpStream and set it to -1,
   preventing the stream from closing the socket on drop.  Used when
   handing the fd to TlsStream.accept which takes ownership. */
static int web_detach_fd(TcpStream *s) {
    int fd = s->fd;
    s->fd = -1;
    return fd;
}

#endif
