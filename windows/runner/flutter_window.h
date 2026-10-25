#ifndef RUNNER_FLUTTER_WINDOW_H_
#define RUNNER_FLUTTER_WINDOW_H_

#include <flutter/dart_project.h>
#include <flutter/encodable_value.h>
#include <flutter/flutter_view_controller.h>
#include <flutter/method_channel.h>
#include <flutter/method_result.h>
#include <flutter/standard_method_codec.h>

#include <memory>
#include <optional>

#include "desktop_lyrics_window.h"
#include "win32_window.h"

// A window that does nothing but host a Flutter view.
class FlutterWindow : public Win32Window {
 public:
  // Creates a new FlutterWindow hosting a Flutter view running |project|.
  explicit FlutterWindow(const flutter::DartProject& project);
  virtual ~FlutterWindow();

 protected:
  // Win32Window:
  bool OnCreate() override;
  void OnDestroy() override;
  LRESULT MessageHandler(HWND window, UINT const message, WPARAM const wparam,
                         LPARAM const lparam) noexcept override;

 private:
  // Applies the DWM title bar colors for the active Flutter theme.
  // |caption| is the page background color so the caption blends into the UI.
  void ApplyTitleBarTheme(bool dark, COLORREF caption);

  // Drops the caption icon so the title bar reads as part of the window body.
  void HideCaptionIcon();

  // Opens the system picker for a local background image. Returns "" on
  // cancel.
  std::string PickImageFile(const std::string& initial_directory);

  // Bridges show / update / hide calls for the desktop lyric overlay.
  void HandleLyricsCall(
      const flutter::MethodCall<flutter::EncodableValue>& call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

  // The project to run project_ hosts.
  flutter::DartProject project_;

  // The Flutter instance hosted by this window.
  std::unique_ptr<flutter::FlutterViewController> flutter_controller_;

  // Receives light/dark changes from the Flutter settings page.
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
      theme_channel_;

  // Serves the custom player background image picker.
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
      picker_channel_;

  // Chrome-free lyric overlay plus the channel that drives it.
  std::unique_ptr<DesktopLyricsWindow> lyrics_window_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
      lyrics_channel_;
};

#endif  // RUNNER_FLUTTER_WINDOW_H_
