#pragma once

#include <windows.h>

void InstallCrashDumpHandlers(HINSTANCE instance);
LONG WINAPI WriteCrashDump(EXCEPTION_POINTERS* exception_pointers);
