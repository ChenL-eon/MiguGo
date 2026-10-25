#include "flutter_window.h"

#include <dwmapi.h>
#include <shobjidl.h>
#include <wtypes.h>

#include <optional>
#include <string>

#include "flutter/generated_plugin_registrant.h"
#include "utils.h"

#ifndef DWMWA_USE_IMMERSIVE_DARK_MODE
#define DWMWA_USE_IMMERSIVE_DARK_MODE 20
#endif
#ifndef DWMWA_CAPTION_COLOR
#define DWMWA_CAPTION_COLOR 35
#endif
#ifndef DWMWA_TEXT_COLOR
#define DWMWA_TEXT_COLOR 36
#endif
#ifndef DWMWA_BORDER_COLOR
#define DWMWA_BORDER_COLOR 34
#endif

namespace {

// 标题栏文字与底色同色即视觉隐藏，任务栏仍然保留窗口标题。
COLORREF ArgbToColorRef(int value) {
  return RGB((value >> 16) & 0xFF, (value >> 8) & 0xFF, value & 0xFF);
}

std::wstring Utf16FromUtf8(const std::string& text) {
  if (text.empty()) {
    return std::wstring();
  }
  const int length = MultiByteToWideChar(CP_UTF8, 0, text.c_str(),
                                         static_cast<int>(text.size()),
                                         nullptr, 0);
  std::wstring result(length, L'\0');
  MultiByteToWideChar(CP_UTF8, 0, text.c_str(), static_cast<int>(text.size()),
                      &result[0], length);
  return result;
}

// Flutter 3.47 的 Windows 无障碍桥在语义树重排时会解引用已经失效的节点
// （accessibility_bridge.cc 的 CreateRemoveReparentedNodesUpdate，0xc0000005），
// 表现为启动后随机闪退。引擎没有关闭无障碍的接口，只能在 UIA 请求到达之前挡掉：
// WM_GETOBJECT 不回应，桥就不会建立，也就不会再更新语义树。
// 代价是屏幕阅读器等辅助技术读不到本应用窗口。
WNDPROC OriginalViewProc = nullptr;
HWND BlockedViewWindow = nullptr;

LRESULT CALLBACK SuppressUiaViewProc(HWND hwnd, UINT message, WPARAM wparam,
                                     LPARAM lparam) {
  if (message == WM_GETOBJECT) {
    return 0;
  }
  return CallWindowProc(OriginalViewProc, hwnd, message, wparam, lparam);
}

void SuppressViewUiAutomation(HWND view_window) {
  if (view_window == nullptr || OriginalViewProc != nullptr) {
    return;
  }
  const auto previous = reinterpret_cast<WNDPROC>(SetWindowLongPtr(
      view_window, GWLP_WNDPROC,
      reinterpret_cast<LONG_PTR>(SuppressUiaViewProc)));
  if (previous == nullptr) {
    return;
  }
  OriginalViewProc = previous;
  BlockedViewWindow = view_window;
}

void RestoreViewUiAutomation() {
  if (BlockedViewWindow != nullptr && OriginalViewProc != nullptr) {
    SetWindowLongPtr(BlockedViewWindow, GWLP_WNDPROC,
                     reinterpret_cast<LONG_PTR>(OriginalViewProc));
  }
  BlockedViewWindow = nullptr;
  OriginalViewProc = nullptr;
}

}  // namespace

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

void FlutterWindow::ApplyTitleBarTheme(bool dark, COLORREF caption) {
  const HWND window = GetHandle();
  if (!window) {
    return;
  }

  const BOOL use_dark = dark ? TRUE : FALSE;
  DwmSetWindowAttribute(window, DWMWA_USE_IMMERSIVE_DARK_MODE, &use_dark,
                        sizeof(use_dark));
  DwmSetWindowAttribute(window, DWMWA_CAPTION_COLOR, &caption,
                        sizeof(caption));
  // 与底色一致，标题文字不再和界面抢视线。
  DwmSetWindowAttribute(window, DWMWA_TEXT_COLOR, &caption, sizeof(caption));
  const COLORREF border_color =
      dark ? RGB(0x1C, 0x20, 0x29) : RGB(0xD3, 0xDC, 0xEA);
  DwmSetWindowAttribute(window, DWMWA_BORDER_COLOR, &border_color,
                        sizeof(border_color));
}

void FlutterWindow::HideCaptionIcon() {
  const HWND window = GetHandle();
  if (!window) {
    return;
  }

  // WS_EX_DLGMODALFRAME 是让系统不再绘制标题栏图标的标准做法，
  // 单靠 WM_SETICON 传空只会退回默认图标。
  const LONG_PTR ex_style =
      GetWindowLongPtr(window, GWL_EXSTYLE) | WS_EX_DLGMODALFRAME;
  SetWindowLongPtr(window, GWL_EXSTYLE, ex_style);
  SendMessageW(window, WM_SETICON, static_cast<WPARAM>(ICON_SMALL), 0);
  SendMessageW(window, WM_SETICON, static_cast<WPARAM>(ICON_BIG), 0);
  SendMessageW(window, WM_SETICON, static_cast<WPARAM>(ICON_SMALL2), 0);
  SetWindowPos(window, nullptr, 0, 0, 0, 0,
               SWP_FRAMECHANGED | SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER |
                   SWP_NOOWNERZORDER);
}

std::string FlutterWindow::PickImageFile(
    const std::string& initial_directory) {
  const HRESULT initialized = CoInitializeEx(
      nullptr, COINIT_APARTMENTTHREADED | COINIT_DISABLE_OLE1DDE);

  std::string picked;
  IFileOpenDialog* dialog = nullptr;
  if (SUCCEEDED(CoCreateInstance(CLSID_FileOpenDialog, nullptr,
                                 CLSCTX_INPROC_SERVER, IID_PPV_ARGS(&dialog)))) {
    static const COMDLG_FILTERSPEC kFilters[] = {
        {L"图片", L"*.jpg;*.jpeg;*.png;*.webp;*.bmp;*.gif"},
        {L"所有文件", L"*.*"},
    };
    dialog->SetFileTypes(
        static_cast<UINT>(sizeof(kFilters) / sizeof(kFilters[0])), kFilters);
    dialog->SetOptions(FOS_PATHMUSTEXIST | FOS_FILEMUSTEXIST |
                       FOS_FORCEFILESYSTEM);

    if (!initial_directory.empty()) {
      IShellItem* folder = nullptr;
      if (SUCCEEDED(SHCreateItemFromParsingName(
              Utf16FromUtf8(initial_directory).c_str(), nullptr,
              IID_PPV_ARGS(&folder)))) {
        dialog->SetFolder(folder);
        folder->Release();
      }
    }

    if (SUCCEEDED(dialog->Show(GetHandle()))) {
      IShellItem* item = nullptr;
      if (SUCCEEDED(dialog->GetResult(&item))) {
        PWSTR path = nullptr;
        if (SUCCEEDED(item->GetDisplayName(SIGDN_FILESYSPATH, &path))) {
          picked = Utf8FromUtf16(path);
          CoTaskMemFree(path);
        }
        item->Release();
      }
    }
    dialog->Release();
  }

  if (initialized == S_OK || initialized == S_FALSE) {
    CoUninitialize();
  }
  return picked;
}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  // The app defaults to the light theme; Flutter reports theme changes through
  // the channel below so the native caption always matches the UI.
  ApplyTitleBarTheme(false, RGB(0xF4, 0xF7, 0xFC));
  HideCaptionIcon();

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

  theme_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(), "migu_lele/window_theme",
          &flutter::StandardMethodCodec::GetInstance());
  theme_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                 result) {
        const std::string& method = call.method_name();
        if (method == "hideCaptionIcon") {
          HideCaptionIcon();
          result->Success();
          return;
        }
        if (method != "setTitleBarTheme") {
          result->NotImplemented();
          return;
        }

        bool dark = false;
        COLORREF caption = RGB(0xF4, 0xF7, 0xFC);
        const auto* arguments =
            std::get_if<flutter::EncodableMap>(call.arguments());
        if (arguments != nullptr) {
          const auto brightness =
              arguments->find(flutter::EncodableValue("brightness"));
          if (brightness != arguments->end()) {
            const auto* value = std::get_if<std::string>(&brightness->second);
            dark = value != nullptr && *value == "dark";
          }
          const auto color = arguments->find(flutter::EncodableValue("caption"));
          if (color != arguments->end()) {
            const auto* as_int = std::get_if<int32_t>(&color->second);
            const auto* as_long = std::get_if<int64_t>(&color->second);
            if (as_int != nullptr) {
              caption = ArgbToColorRef(*as_int);
            } else if (as_long != nullptr) {
              caption = ArgbToColorRef(static_cast<int>(*as_long));
            }
          }
        }
        ApplyTitleBarTheme(dark, caption);
        result->Success();
      });

  picker_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(), "migu_lele/file_picker",
          &flutter::StandardMethodCodec::GetInstance());
  picker_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                 result) {
        if (call.method_name() != "pickImage") {
          result->NotImplemented();
          return;
        }
        std::string initial_directory;
        const auto* arguments =
            std::get_if<flutter::EncodableMap>(call.arguments());
        if (arguments != nullptr) {
          const auto directory =
              arguments->find(flutter::EncodableValue("initialDirectory"));
          if (directory != arguments->end()) {
            const auto* value = std::get_if<std::string>(&directory->second);
            if (value != nullptr) {
              initial_directory = *value;
            }
          }
        }
        const std::string picked = PickImageFile(initial_directory);
        if (picked.empty()) {
          result->Success();
        } else {
          result->Success(flutter::EncodableValue(picked));
        }
      });

  lyrics_window_ = std::make_unique<DesktopLyricsWindow>();
  lyrics_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(),
          "migu_lele/desktop_lyrics",
          &flutter::StandardMethodCodec::GetInstance());
  lyrics_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                 result) { HandleLyricsCall(call, std::move(result)); });
  lyrics_window_->SetEventSender(
      [this](const std::string& method,
             const flutter::EncodableMap& arguments) {
        if (lyrics_channel_ == nullptr) {
          return;
        }
        lyrics_channel_->InvokeMethod(
            method, std::make_unique<flutter::EncodableValue>(arguments));
      });

  HWND view_window = flutter_controller_->view()->GetNativeWindow();
  SuppressViewUiAutomation(view_window);
  SetChildContent(view_window);

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  RestoreViewUiAutomation();
  if (lyrics_window_ != nullptr) {
    lyrics_window_->Hide();
  }
  lyrics_window_.reset();
  lyrics_channel_.reset();
  theme_channel_.reset();
  picker_channel_.reset();
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

void FlutterWindow::HandleLyricsCall(
    const flutter::MethodCall<flutter::EncodableValue>& call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  const std::string& method = call.method_name();
  const auto* payload =
      call.arguments() == nullptr ? nullptr
                                  : std::get_if<flutter::EncodableMap>(
                                        call.arguments());
  static const flutter::EncodableMap kEmpty;
  const flutter::EncodableMap& arguments = payload == nullptr ? kEmpty : *payload;

  if (method == "show") {
    result->Success(flutter::EncodableValue(lyrics_window_->Show(arguments)));
    return;
  }
  if (method == "update") {
    result->Success(flutter::EncodableValue(lyrics_window_->Update(arguments)));
    return;
  }
  if (method == "hide") {
    lyrics_window_->Hide();
    result->Success(flutter::EncodableValue(true));
    return;
  }
  result->NotImplemented();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // 见文件顶部说明：主窗口同样不回应 UIA 请求，避免引擎建立无障碍树。
  if (message == WM_GETOBJECT) {
    return 0;
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
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
