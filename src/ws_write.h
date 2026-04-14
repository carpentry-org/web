#include <unistd.h>

int ws_write_fd(int fd, Array *data) {
    uint8_t *buf = (uint8_t *)data->data;
    int len = data->len;
    int sent = 0;
    while (sent < len) {
        int n = (int)write(fd, buf + sent, len - sent);
        if (n <= 0) break;
        sent += n;
    }
    return sent;
}
