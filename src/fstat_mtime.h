#include <sys/stat.h>

Long web_fstat_mtime(int fd) {
#ifdef _WIN32
    struct _stat64 st;
    if (_fstat64(fd, &st) == -1) return -1;
#else
    struct stat st;
    if (fstat(fd, &st) == -1) return -1;
#endif
    return (Long)st.st_mtime;
}
