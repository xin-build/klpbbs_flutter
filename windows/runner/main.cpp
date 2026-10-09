#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>
#include <shobjidl.h>
#include <algorithm>
#include <string>

#include "flutter_window.h"
#include "utils.h"

namespace {
class ScopedComApartment {
 public:
  ScopedComApartment()
      : initialized_(SUCCEEDED(::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED))) {}
  ~ScopedComApartment() {
    if (initialized_) ::CoUninitialize();
  }
 private:
  bool initialized_;
};
}  // namespace

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  std::vector<std::string> command_line_arguments = GetCommandLineArguments();
#ifndef NDEBUG
  const bool background_preview =
      std::find(command_line_arguments.begin(), command_line_arguments.end(),
                "--background-preview") != command_line_arguments.end();
#else
  const bool background_preview = false;
#endif
  if (background_preview) {
    // Background acceptance keeps credentials in RAM. Do not let Windows Error
    // Reporting open a dialog or write a dump if a probe encounters a fault.
    ::SetErrorMode(SEM_FAILCRITICALERRORS | SEM_NOGPFAULTERRORBOX |
                   SEM_NOOPENFILEERRORBOX);
  }
  const std::wstring mutex_name = background_preview
      ? L"klpbbs_background_preview_" + std::to_wstring(::GetCurrentProcessId())
      : L"klpbbs_app_single_instance_mutex_id";
  HANDLE hMutex = ::CreateMutexW(nullptr, TRUE, mutex_name.c_str());
  if (hMutex != nullptr && ::GetLastError() == ERROR_ALREADY_EXISTS) {
    if (background_preview) {
      ::CloseHandle(hMutex);
      return EXIT_FAILURE;
    }
    HWND hwndExisting = ::FindWindowW(L"FLUTTER_RUNNER_WIN32_WINDOW", nullptr);
    if (!hwndExisting) {
      hwndExisting = ::FindWindowW(nullptr, L"klpbbs_app");
    }
    if (hwndExisting) {
      if (::IsIconic(hwndExisting)) {
        ::ShowWindow(hwndExisting, SW_RESTORE);
      } else {
        ::ShowWindow(hwndExisting, SW_SHOW);
      }
      ::SetForegroundWindow(hwndExisting);
    }
    ::CloseHandle(hMutex);
    return EXIT_SUCCESS;
  }

  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ScopedComApartment com_apartment;
  if (!background_preview) {
    // Match the notification shortcut identity from the first window frame.
    ::SetCurrentProcessExplicitAppUserModelID(L"\u82e6\u529b\u6015\u8bba\u575b");
  }

  flutter::DartProject project(L"data");

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project, background_preview);
  Win32Window::Point origin(10, 10);
  // The debug preview is created hidden at its final size. Resizing it through
  // window_manager would call SetWindowPos without SWP_NOACTIVATE.
  Win32Window::Size size(background_preview ? 1600 : 1280,
                        background_preview ? 1100 : 720);
  if (!window.Create(L"\u82e6\u529b\u6015\u8bba\u575b", origin, size)) {
    if (hMutex) ::CloseHandle(hMutex);
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  if (hMutex) ::CloseHandle(hMutex);
  return EXIT_SUCCESS;
}
