/* MSVC shim so the firmware's avo_core (POSIX) builds unchanged on Windows. Only what avo_raw.cpp uses. */
#pragma once
#include <io.h>
#include <stdio.h>
#define fsync _commit
#define fileno _fileno
#include <fcntl.h>
#include <sys/stat.h>
static inline int truncate(const char* path, long long len) {
  int fd = -1;
  if (_sopen_s(&fd, path, _O_RDWR | _O_BINARY, _SH_DENYNO, _S_IREAD | _S_IWRITE) != 0) return -1;
  int r = _chsize_s(fd, len) == 0 ? 0 : -1;
  _close(fd);
  return r;
}
