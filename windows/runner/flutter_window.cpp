#include "flutter_window.h"

#include <optional>

#include "flutter/generated_plugin_registrant.h"
#include "gpu_preferences.h"

FlutterWindow::FlutterWindow(const flutter::DartProject& project,
                             bool background_preview)
    : project_(project),
      background_preview_(background_preview) {}

FlutterWindow::~FlutterWindow() {
  // Channels must release their messenger before the engine is destroyed,
  // including a partially failed window creation.
  gpu_preferences_.reset();
  flutter_controller_.reset();
}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }
  // Win32Window::Create first calls Destroy(), which virtually dispatches to
  // OnDestroy even for a new window. Allocate only after that cleanup, while
  // still applying the preference before Flutter constructs its engine.
  gpu_preferences_ = std::make_unique<GpuPreferences>(background_preview_);
  project_.set_gpu_preference(gpu_preferences_->startup_preference());
  if (background_preview_) {
    const auto style = ::GetWindowLongPtr(GetHandle(), GWL_EXSTYLE);
    ::SetWindowLongPtr(GetHandle(), GWL_EXSTYLE,
                       style | WS_EX_NOACTIVATE | WS_EX_TOOLWINDOW);
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  gpu_preferences_->Register(flutter_controller_->engine());
  SetChildContent(flutter_controller_->view()->GetNativeWindow(),
                  !background_preview_);

  if (!background_preview_) {
    flutter_controller_->engine()->SetNextFrameCallback([&]() {
      this->Show();
    });
  }

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  gpu_preferences_.reset();
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  if (background_preview_) {
    if (message == WM_MOUSEACTIVATE) {
      return MA_NOACTIVATE;
    }
    if (message == WM_ACTIVATE) {
      return 0;
    }
  }
  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      if (flutter_controller_ && flutter_controller_->engine()) {
        flutter_controller_->engine()->ReloadSystemFonts();
      }
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
