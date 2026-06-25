#include <sys/stat.h>

bool web_is_directory(String *path) {
#ifdef _WIN32
    struct _stat64 st;
    if (_stat64(*path, &st) == -1) return false;
    return (st.st_mode & _S_IFDIR) != 0;
#else
    struct stat st;
    if (stat(*path, &st) == -1) return false;
    return S_ISDIR(st.st_mode);
#endif
}
