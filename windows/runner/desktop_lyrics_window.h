#ifndef RUNNER_DESKTOP_LYRICS_WINDOW_H_
#define RUNNER_DESKTOP_LYRICS_WINDOW_H_

#include <flutter/encodable_value.h>

#include <functional>
#include <memory>
#include <string>
#include <vector>

#include <windows.h>
#include <gdiplus.h>

// Chrome-free, click-through-capable desktop lyric overlay.
//
// Rendered with GDI+ into a per-pixel alpha layered window so the desktop
// stays visible behind the panel; Flutter only feeds it text and style.
//
// The colour sweep is driven by this window's own timer: Flutter pushes the
// line, its duration and a progress anchor, and the overlay interpolates the
// anchor on its clock. That keeps the highlight moving at display rate
// instead of stepping whenever Flutter happens to send a tick.
class DesktopLyricsWindow {
 public:
  using EventSender = std::function<void(
      const std::string& method, const flutter::EncodableMap& arguments)>;

  DesktopLyricsWindow();
  ~DesktopLyricsWindow();

  DesktopLyricsWindow(const DesktopLyricsWindow&) = delete;
  DesktopLyricsWindow& operator=(const DesktopLyricsWindow&) = delete;

  void SetEventSender(EventSender sender);
  bool Show(const flutter::EncodableMap& payload);
  bool Update(const flutter::EncodableMap& payload);
  void Hide();
  bool IsVisible() const { return hwnd_ != nullptr; }

 private:
  struct Control {
    std::wstring label;
    bool glyph = false;
    RECT bounds{};
    std::string event;
  };

  struct State {
    std::vector<std::wstring> lines;
    std::wstring status;
    double progress = 0.0;
    long long line_duration_ms = 0;
    int font_pt = 22;
    unsigned int color = 0xFFFFFFFF;
    unsigned int unplayed_color = 0xFFB9BEC9;
    unsigned int stroke_color = 0;
    int background_alpha = 0;
    bool double_line = true;
    bool topmost = true;
    bool locked = false;
    bool playing = false;
  };

  struct Layout {
    float scale = 1.0f;
    float width = 0.0f;
    float height = 0.0f;
    float pad = 0.0f;
    float toolbar_height = 0.0f;
    float primary_size = 0.0f;
    float secondary_size = 0.0f;
    std::vector<Control> controls;
  };

  // Text already turned into a GDI+ path. Rebuilding a path costs a
  // MeasureString/AddString round trip, so it happens only when the scene
  // key changes, never on a progress tick.
  struct CachedText {
    std::unique_ptr<Gdiplus::GraphicsPath> path;
    Gdiplus::RectF bounds{};  // tight path bounds, used for the sweep clip
  };

  static LRESULT CALLBACK WndProc(HWND hwnd, UINT message, WPARAM wparam,
                                  LPARAM lparam);
  LRESULT HandleMessage(HWND hwnd, UINT message, WPARAM wparam, LPARAM lparam);

  bool EnsureWindow();
  void ApplyFlags();
  // Returns true when the incoming payload moved the lyric anchor.
  bool ApplyPayload(const flutter::EncodableMap& payload);
  Layout ComputeLayout(Gdiplus::Graphics& graphics) const;
  std::wstring SceneKey() const;
  void RebuildScene(const std::wstring& key);
  void ReleaseScene();
  void Paint();
  void EnsureSurface(int width, int height);
  void ReleaseSurface();
  void ClampPosition();
  void DrawScene(Gdiplus::Graphics& graphics, const Layout& layout);
  void DrawControl(Gdiplus::Graphics& graphics, const Control& control,
                   const CachedText& cached, float scale, bool hovered) const;
  void Emit(const std::string& event);
  void EmitMoved();
  int HitTest(const POINT& point) const;
  bool InToolbarBand(const POINT& point) const;
  bool ToolbarVisible() const { return pointer_inside_ || dragging_; }
  float DpiScale() const;
  double LiveProgress() const;

  static constexpr UINT_PTR kProgressTimerId = 0x4C79;
  static constexpr UINT kProgressIntervalMs = 33;

  HWND hwnd_ = nullptr;
  State state_;
  int x_ = -1;
  int y_ = -1;
  int width_ = 0;
  int height_ = 0;
  int hovered_ = -1;
  bool positioned_ = false;
  bool dragging_ = false;
  bool pointer_inside_ = false;
  bool leave_armed_ = false;
  LONG drag_dx_ = 0;
  LONG drag_dy_ = 0;
  EventSender sender_;
  std::vector<Control> controls_;

  // Cached scene, valid while scene_key_ matches SceneKey().
  std::wstring scene_key_;
  Layout scene_layout_;
  CachedText primary_;
  CachedText secondary_;
  CachedText status_text_;
  CachedText font_label_;
  std::vector<CachedText> control_texts_;

  // Progress interpolation anchored to this window's own clock.
  double anchor_progress_ = 0.0;
  ULONGLONG anchor_tick_ = 0;
  double painted_progress_ = -1.0;

  // Persistent layered-window surface, recreated only when the size changes.
  HDC surface_ = nullptr;
  HBITMAP surface_bitmap_ = nullptr;
  HGDIOBJ surface_previous_ = nullptr;
  void* surface_bits_ = nullptr;
  int surface_width_ = 0;
  int surface_height_ = 0;
};

#endif  // RUNNER_DESKTOP_LYRICS_WINDOW_H_
