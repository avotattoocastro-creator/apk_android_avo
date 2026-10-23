/* MSVC shim so the firmware's avo_core (POSIX) builds unchanged on Windows. Only what avo_raw.cpp uses. */
#pragma once
#include <io.h>
#include <stdio.h>
#define fsync _commit
#define fileno _fileno
