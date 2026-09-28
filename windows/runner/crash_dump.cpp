#include "crash_dump.h"

#include <dbghelp.h>

#include <chrono>
#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <sstream>
#include <string>

namespace {

std::wstring DumpDirectory() {
  std::filesystem::path dir = std::filesystem::current_path() / "crash_dumps";
  std::error_code ignored;
  std::filesystem::create_directories(dir, ignored);
  return dir.wstring();
}

std::wstring Timestamp() {
  SYSTEMTIME t;
  GetLocalTime(&t);
  wchar_t buffer[64] = {};
  swprintf_s(buffer, L"%04u%02u%02u-%02u%02u%02u-%03u",
             t.wYear, t.wMonth, t.wDay, t.wHour, t.wMinute, t.wSecond,
             t.wMilliseconds);
  return buffer;
}

void WriteCrashNote(const std::wstring& dump_path, DWORD code) {
  std::ofstream note(std::filesystem::path(dump_path).replace_extension(L".txt"));
  note << "exception=0x" << std::hex << code << "\n";
  note << "process=" << GetCurrentProcessId() << "\n";
  note << "thread=" << GetCurrentThreadId() << "\n";
}

void TerminateHandler() {
  RaiseException(0xE0000001, EXCEPTION_NONCONTINUABLE, 0, nullptr);
}

void PurecallHandler() {
  RaiseException(0xE0000002, EXCEPTION_NONCONTINUABLE, 0, nullptr);
}

void InvalidParameterHandler(const wchar_t*, const wchar_t*, const wchar_t*,
                             unsigned int, uintptr_t) {
  RaiseException(0xE0000003, EXCEPTION_NONCONTINUABLE, 0, nullptr);
}

}  // namespace

LONG WINAPI WriteCrashDump(EXCEPTION_POINTERS* exception_pointers) {
  const DWORD code = exception_pointers && exception_pointers->ExceptionRecord
                         ? exception_pointers->ExceptionRecord->ExceptionCode
                         : 0;
  const std::wstring path = DumpDirectory() + L"\\webview_cef_app-" +
                            Timestamp() + L"-" +
                            std::to_wstring(GetCurrentProcessId()) + L".dmp";
  HANDLE file = CreateFileW(path.c_str(), GENERIC_WRITE, 0, nullptr,
                            CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
  if (file != INVALID_HANDLE_VALUE) {
    MINIDUMP_EXCEPTION_INFORMATION exception_info = {};
    exception_info.ThreadId = GetCurrentThreadId();
    exception_info.ExceptionPointers = exception_pointers;
    exception_info.ClientPointers = FALSE;
    const MINIDUMP_TYPE type = static_cast<MINIDUMP_TYPE>(
        MiniDumpWithFullMemory | MiniDumpWithHandleData | MiniDumpWithThreadInfo |
        MiniDumpWithUnloadedModules | MiniDumpWithIndirectlyReferencedMemory);
    MiniDumpWriteDump(GetCurrentProcess(), GetCurrentProcessId(), file, type,
                      exception_pointers ? &exception_info : nullptr, nullptr,
                      nullptr);
    CloseHandle(file);
    WriteCrashNote(path, code);
  }
  return EXCEPTION_EXECUTE_HANDLER;
}

void InstallCrashDumpHandlers(HINSTANCE) {
  SetUnhandledExceptionFilter(WriteCrashDump);
  std::set_terminate(TerminateHandler);
  _set_purecall_handler(PurecallHandler);
  _set_invalid_parameter_handler(InvalidParameterHandler);
}
