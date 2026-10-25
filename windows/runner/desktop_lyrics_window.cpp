#include "desktop_lyrics_window.h"

#include <windowsx.h>

#include <algorithm>
#include <cmath>
#include <string>

namespace {

const wchar_t kWindowClass[] = L"MiguGoDesktopLyricsWindow";
const wchar_t kTextFont[] = L"Microsoft YaHei UI";
const wchar_t kGlyphFont[] = L"Segoe MDL2 Assets";

const wchar_t kGlyphPrevious[] = L"\uE892";
const wchar_t kGlyphNext[] = L"\uE893";
const wchar_t kGlyphPlay[] = L"\uE768";
const wchar_t kGlyphPause[] = L"\uE769";
const wchar_t kGlyphClose[] = L"\uE8BB";
const wchar_t kGlyphLock[] = L"\uE72E";
const wchar_t kGlyphUnlock[] = L"\uE785";
const wchar_t kGlyphSettings[] = L"\uE713";

constexpr float kPad = 12.0f;
constexpr float kToolbarHeight = 30.0f;
constexpr float kItemSize = 28.0f;
constexpr float kItemGap = 4.0f;
constexpr float kBaseWidth = 720.0f;
constexpr float kMinWidth = 420.0f;
constexpr int kMinFontPt = 12;
constexpr int kMaxFontPt = 40;
// 拖动时至少要让这么多像素留在屏幕内，否则浮层再也抓不回来。
constexpr int kEdgeGrab = 60;
// Flutter 的进度是按歌词时间取整后推过来的，本身滞后于音频。只要偏差没超过
// 这个比例就继续用浮层自己的时钟走，避免每次推送都把高亮往回拽一下。
constexpr double kResyncThreshold = 0.25;
constexpr double kPausedResyncThreshold = 0.01;
// 高亮推进不足一个像素级别时不值得重画整张分层窗口。
constexpr double kRepaintEpsilon = 0.0005;

constexpr size_t kControlCount = 9;
constexpr size_t kPinIndex = 0;
constexpr size_t kFontMinusIndex = 1;
constexpr size_t kFontPlusIndex = 2;
constexpr size_t kSettingsIndex = 3;
constexpr size_t kLockIndex = 4;
constexpr size_t kPreviousIndex = 5;
constexpr size_t kPlayPauseIndex = 6;
constexpr size_t kNextIndex = 7;
constexpr size_t kCloseIndex = 8;

ULONG_PTR gdiplus_token = 0;

bool EnsureGdiplus() {
  if (gdiplus_token != 0) {
    return true;
  }
  Gdiplus::GdiplusStartupInput input;
  return Gdiplus::GdiplusStartup(&gdiplus_token, &input, nullptr) ==
         Gdiplus::Ok;
}

float ClampF(float value, float low, float high) {
  return value < low ? low : (value > high ? high : value);
}

int ClampI(int value, int low, int high) {
  return value < low ? low : (value > high ? high : value);
}

std::wstring ToWide(const std::string& text) {
  if (text.empty()) {
    return std::wstring();
  }
  const int size = ::MultiByteToWideChar(
      CP_UTF8, 0, text.data(), static_cast<int>(text.size()), nullptr, 0);
  if (size <= 0) {
    return std::wstring();
  }
  std::wstring wide(static_cast<size_t>(size), L'\0');
  ::MultiByteToWideChar(CP_UTF8, 0, text.data(), static_cast<int>(text.size()),
                        &wide[0], size);
  return wide;
}

const flutter::EncodableValue* Find(const flutter::EncodableMap& map,
                                    const char* key) {
  const auto it = map.find(flutter::EncodableValue(key));
  return it == map.end() ? nullptr : &it->second;
}

bool ReadBool(const flutter::EncodableMap& map, const char* key,
              bool fallback) {
  const auto* value = Find(map, key);
  const auto* parsed = value == nullptr ? nullptr : std::get_if<bool>(value);
  return parsed == nullptr ? fallback : *parsed;
}

double ReadDouble(const flutter::EncodableMap& map, const char* key,
                  double fallback) {
  const auto* value = Find(map, key);
  if (value == nullptr) {
    return fallback;
  }
  if (const auto* parsed = std::get_if<double>(value)) {
    return *parsed;
  }
  if (const auto* parsed = std::get_if<int32_t>(value)) {
    return static_cast<double>(*parsed);
  }
  if (const auto* parsed = std::get_if<int64_t>(value)) {
    return static_cast<double>(*parsed);
  }
  return fallback;
}

int ReadInt(const flutter::EncodableMap& map, const char* key, int fallback) {
  return static_cast<int>(ReadDouble(map, key, static_cast<double>(fallback)));
}

std::wstring ReadString(const flutter::EncodableMap& map, const char* key,
                        const std::wstring& fallback) {
  const auto* value = Find(map, key);
  const auto* parsed =
      value == nullptr ? nullptr : std::get_if<std::string>(value);
  return parsed == nullptr ? fallback : ToWide(*parsed);
}

std::vector<std::wstring> ReadStrings(const flutter::EncodableMap& map,
                                      const char* key) {
  std::vector<std::wstring> lines;
  const auto* value = Find(map, key);
  const auto* list = value == nullptr
                         ? nullptr
                         : std::get_if<std::vector<flutter::EncodableValue>>(
                               value);
  if (list == nullptr) {
    return lines;
  }
  for (const auto& item : *list) {
    const auto* text = std::get_if<std::string>(&item);
    if (text != nullptr && !text->empty()) {
      lines.push_back(ToWide(*text));
    }
  }
  return lines;
}

void AddRoundedRect(Gdiplus::GraphicsPath& path, const Gdiplus::RectF& rect,
                    float radius) {
  const float diameter = radius * 2.0f;
  path.Reset();
  path.AddArc(rect.X, rect.Y, diameter, diameter, 180.0f, 90.0f);
  path.AddArc(rect.X + rect.Width - diameter, rect.Y, diameter, diameter,
              270.0f, 90.0f);
  path.AddArc(rect.X + rect.Width - diameter, rect.Y + rect.Height - diameter,
              diameter, diameter, 0.0f, 90.0f);
  path.AddArc(rect.X, rect.Y + rect.Height - diameter, diameter, diameter,
              90.0f, 90.0f);
  path.CloseFigure();
}

// Turns text into a fill path once so every repaint is just two FillPath
// calls. Returns null when the font or the text is unusable.
std::unique_ptr<Gdiplus::GraphicsPath> BuildPath(const std::wstring& text,
                                                 const wchar_t* family_name,
                                                 float em_size,
                                                 Gdiplus::FontStyle style,
                                                 const Gdiplus::RectF& box,
                                                 bool no_wrap,
                                                 Gdiplus::RectF* bounds) {
  if (text.empty() || em_size <= 0.0f) {
    return nullptr;
  }
  Gdiplus::FontFamily family(family_name);
  if (!family.IsAvailable()) {
    return nullptr;
  }
  Gdiplus::StringFormat format;
  format.SetAlignment(Gdiplus::StringAlignmentCenter);
  format.SetLineAlignment(Gdiplus::StringAlignmentCenter);
  if (no_wrap) {
    format.SetFormatFlags(Gdiplus::StringFormatFlagsNoWrap);
  }
  auto path = std::make_unique<Gdiplus::GraphicsPath>();
  if (path->AddString(text.c_str(), static_cast<int>(text.size()), &family,
                      style, em_size, box, &format) != Gdiplus::Ok) {
    return nullptr;
  }
  path->GetBounds(bounds);
  return path;
}

Gdiplus::Color Argb(unsigned int value) {
  return Gdiplus::Color(static_cast<BYTE>((value >> 24) & 0xFFu),
                        static_cast<BYTE>((value >> 16) & 0xFFu),
                        static_cast<BYTE>((value >> 8) & 0xFFu),
                        static_cast<BYTE>(value & 0xFFu));
}

RECT ToBounds(float x, float y, float width, float height) {
  RECT bounds{};
  bounds.left = static_cast<LONG>(std::floor(x));
  bounds.top = static_cast<LONG>(std::floor(y));
  bounds.right = static_cast<LONG>(std::ceil(x + width));
  bounds.bottom = static_cast<LONG>(std::ceil(y + height));
  return bounds;
}

Gdiplus::RectF ToRect(const RECT& rect) {
  return Gdiplus::RectF(static_cast<float>(rect.left),
                        static_cast<float>(rect.top),
                        static_cast<float>(rect.right - rect.left),
                        static_cast<float>(rect.bottom - rect.top));
}

RECT VirtualScreen() {
  RECT area{};
  area.left = ::GetSystemMetrics(SM_XVIRTUALSCREEN);
  area.top = ::GetSystemMetrics(SM_YVIRTUALSCREEN);
  area.right = area.left + ::GetSystemMetrics(SM_CXVIRTUALSCREEN);
  area.bottom = area.top + ::GetSystemMetrics(SM_CYVIRTUALSCREEN);
  return area;
}

}  // namespace

DesktopLyricsWindow::DesktopLyricsWindow() = default;

DesktopLyricsWindow::~DesktopLyricsWindow() {
  Hide();
}

void DesktopLyricsWindow::SetEventSender(EventSender sender) {
  sender_ = std::move(sender);
}

float DesktopLyricsWindow::DpiScale() const {
  if (hwnd_ == nullptr) {
    return 1.0f;
  }
  const UINT dpi = ::GetDpiForWindow(hwnd_);
  return dpi == 0 ? 1.0f : static_cast<float>(dpi) / 96.0f;
}

double DesktopLyricsWindow::LiveProgress() const {
  if (!state_.playing || state_.line_duration_ms <= 0) {
    return state_.progress;
  }
  const ULONGLONG now = ::GetTickCount64();
  const double elapsed = static_cast<double>(now - anchor_tick_) /
                         static_cast<double>(state_.line_duration_ms);
  return ClampF(static_cast<float>(anchor_progress_ + elapsed), 0.0f, 1.0f);
}

bool DesktopLyricsWindow::EnsureWindow() {
  static bool registered = false;
  if (!registered) {
    if (!EnsureGdiplus()) {
      return false;
    }
    WNDCLASSEXW window_class{};
    window_class.cbSize = sizeof(window_class);
    window_class.style = CS_HREDRAW | CS_VREDRAW;
    window_class.lpfnWndProc = &DesktopLyricsWindow::WndProc;
    window_class.hInstance = ::GetModuleHandleW(nullptr);
    window_class.hCursor = ::LoadCursorW(nullptr, IDC_ARROW);
    window_class.lpszClassName = kWindowClass;
    if (::RegisterClassExW(&window_class) == 0) {
      return false;
    }
    registered = true;
  }
  if (hwnd_ != nullptr) {
    return true;
  }
  // WS_EX_NOACTIVATE：浮层只负责显示，点控制条不能把主窗口的键盘焦点抢走。
  hwnd_ = ::CreateWindowExW(
      WS_EX_LAYERED | WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE |
          (state_.topmost ? WS_EX_TOPMOST : 0),
      kWindowClass, L"MiguGo Desktop Lyrics", WS_POPUP, 0, 0,
      static_cast<int>(kBaseWidth), 120, nullptr, nullptr,
      ::GetModuleHandleW(nullptr), this);
  return hwnd_ != nullptr;
}

bool DesktopLyricsWindow::ApplyPayload(
    const flutter::EncodableMap& payload) {
  std::vector<std::wstring> lines = ReadStrings(payload, "lines");
  if (lines.size() > 2) {
    lines.resize(2);
  }
  const double incoming = ClampF(
      static_cast<float>(ReadDouble(payload, "progress", state_.progress)),
      0.0f, 1.0f);
  const long long duration = static_cast<long long>(ReadDouble(
      payload, "lineDurationMs", static_cast<double>(state_.line_duration_ms)));
  const bool playing = ReadBool(payload, "playing", state_.playing);

  // 换句、换曲（时长变了）或明显跳变（拖动进度条）都要重新对表；其余情况让
  // 浮层自己的时钟继续推进，Dart 的推送只作为校准。
  const bool line_switched = lines != state_.lines ||
                             duration != state_.line_duration_ms ||
                             playing != state_.playing;
  const double live = LiveProgress();
  const double threshold =
      playing || state_.playing ? kResyncThreshold : kPausedResyncThreshold;
  const bool resynced =
      line_switched || std::fabs(incoming - live) > threshold;

  if (!lines.empty()) {
    state_.lines = lines;
    state_.status.clear();
  } else {
    state_.lines.clear();
    state_.status = ReadString(payload, "status", L"MiguGo 桌面歌词");
  }
  if (resynced) {
    anchor_progress_ = incoming;
    anchor_tick_ = ::GetTickCount64();
    state_.progress = incoming;
  } else {
    state_.progress = live;
  }
  state_.line_duration_ms = duration;
  state_.font_pt =
      ClampI(ReadInt(payload, "fontPt", state_.font_pt), kMinFontPt,
             kMaxFontPt);
  state_.color = static_cast<unsigned int>(
      ReadDouble(payload, "color", static_cast<double>(state_.color)));
  state_.unplayed_color = static_cast<unsigned int>(ReadDouble(
      payload, "unplayedColor", static_cast<double>(state_.unplayed_color)));
  state_.stroke_color = static_cast<unsigned int>(
      ReadDouble(payload, "strokeColor",
                 static_cast<double>(state_.stroke_color)));
  state_.background_alpha =
      ClampI(ReadInt(payload, "backgroundAlpha", state_.background_alpha), 0,
             200);
  state_.double_line = ReadBool(payload, "doubleLine", state_.double_line);
  state_.topmost = ReadBool(payload, "topmost", state_.topmost);
  state_.locked = ReadBool(payload, "locked", state_.locked);
  state_.playing = playing;
  const int stored_x = ReadInt(payload, "x", -1);
  const int stored_y = ReadInt(payload, "y", -1);
  // Only the first show honours the stored position; afterwards the window is
  // owned by the user's drags, so progress ticks must not snap it backwards.
  if (!positioned_ && stored_x >= 0 && stored_y >= 0) {
    x_ = stored_x;
    y_ = stored_y;
  }
  return resynced;
}

DesktopLyricsWindow::Layout DesktopLyricsWindow::ComputeLayout(
    Gdiplus::Graphics& graphics) const {
  Layout layout;
  const float scale = DpiScale();
  layout.scale = scale;
  layout.pad = kPad * scale;
  layout.toolbar_height = kToolbarHeight * scale;
  layout.primary_size = static_cast<float>(state_.font_pt) * scale / 0.75f;
  layout.secondary_size = layout.primary_size * 0.66f;

  const float item = kItemSize * scale;
  const float gap = kItemGap * scale;
  const Gdiplus::StringFormat format;

  auto measure = [&graphics, &format](const std::wstring& text,
                                      const Gdiplus::Font& font) {
    if (text.empty()) {
      return Gdiplus::SizeF(0.0f, 0.0f);
    }
    Gdiplus::RectF box(0.0f, 0.0f, 6000.0f, 2000.0f);
    Gdiplus::RectF bounds(0.0f, 0.0f, 0.0f, 0.0f);
    graphics.MeasureString(text.c_str(), static_cast<int>(text.size()), &font,
                           box, &format, &bounds);
    return Gdiplus::SizeF(bounds.Width, bounds.Height);
  };

  const Gdiplus::Font text_font(kTextFont, 12.5f * scale,
                                Gdiplus::FontStyleRegular,
                                Gdiplus::UnitPixel);
  const std::wstring pin_label = state_.topmost ? L"置顶" : L"置下";
  const std::wstring size_label = std::to_wstring(state_.font_pt) + L"pt";
  const float pin_width = measure(pin_label, text_font).Width + 16.0f * scale;
  const float label_width = measure(size_label, text_font).Width +
                            8.0f * scale;
  const float step_width = item * 0.92f;

  const Gdiplus::Font lyric_font(kTextFont, layout.primary_size,
                                 Gdiplus::FontStyleBold, Gdiplus::UnitPixel);
  float text_width = 0.0f;
  for (const auto& line : state_.lines) {
    text_width = std::max(text_width, measure(line, lyric_font).Width);
  }
  const float status_width =
      state_.lines.empty() ? measure(state_.status, text_font).Width : 0.0f;

  const float left_group = pin_width + gap + step_width + gap + label_width +
                           gap + step_width + gap + item;
  const float right_group = item * 5.0f + gap * 4.0f;
  const float needed = layout.pad * 2.0f + std::max(
                         text_width + 40.0f * scale,
                         std::max(status_width + 40.0f * scale,
                                  std::max(left_group + right_group +
                                               24.0f * scale,
                                           kMinWidth * scale)));

  const int virtual_width = GetSystemMetrics(SM_CXVIRTUALSCREEN);
  const float limit = std::max(
      kMinWidth * scale,
      static_cast<float>(std::max(640, virtual_width - 80)));
  layout.width = ClampF(std::max(needed, kBaseWidth * scale),
                        kMinWidth * scale, limit);

  const float available = layout.width - layout.pad * 2.0f - 12.0f * scale;
  if (text_width > available && text_width > 0.0f) {
    layout.primary_size = layout.primary_size * available / text_width;
    layout.secondary_size = layout.primary_size * 0.66f;
  }

  const float primary_height = layout.primary_size * 1.5f;
  const float secondary_height =
      state_.double_line ? layout.secondary_size * 1.45f : 0.0f;
  layout.height = layout.pad + layout.toolbar_height + 6.0f * scale +
                  primary_height +
                  (secondary_height > 0.0f ? gap + secondary_height : 0.0f) +
                  layout.pad;

  layout.controls.resize(kControlCount);
  const float top = layout.pad + (layout.toolbar_height - item) / 2.0f;
  auto place = [&layout, top, item](size_t index, const std::wstring& label,
                                    bool glyph, float x, float width,
                                    const char* event) {
    Control& control = layout.controls[index];
    control.label = label;
    control.glyph = glyph;
    control.event = event;
    control.bounds = ToBounds(x, top, width, item);
  };

  float x = layout.pad;
  place(kPinIndex, pin_label, false, x, pin_width, "togglePin");
  x += pin_width + gap;
  place(kFontMinusIndex, L"A-", false, x, step_width, "fontMinus");
  x += step_width + gap + label_width + gap;
  place(kFontPlusIndex, L"A+", false, x, step_width, "fontPlus");
  x += step_width + gap;
  place(kSettingsIndex, kGlyphSettings, true, x, item, "openSettings");

  x = layout.width - layout.pad - right_group;
  const std::wstring lock_label = state_.locked ? kGlyphLock : kGlyphUnlock;
  place(kLockIndex, lock_label, true, x, item, "toggleLock");
  x += item + gap;
  place(kPreviousIndex, kGlyphPrevious, true, x, item, "previous");
  x += item + gap;
  place(kPlayPauseIndex, state_.playing ? kGlyphPause : kGlyphPlay, true, x,
        item, "playPause");
  x += item + gap;
  place(kNextIndex, kGlyphNext, true, x, item, "next");
  x += item + gap;
  place(kCloseIndex, kGlyphClose, true, x, item, "close");
  return layout;
}

std::wstring DesktopLyricsWindow::SceneKey() const {
  std::wstring key;
  for (const auto& line : state_.lines) {
    key += line;
    key += L'\n';
  }
  key += L'|';
  key += state_.status;
  // 颜色不进几何布局，但必须让换色触发一次重画。
  key += L'|';
  key += std::to_wstring(state_.color);
  key += L'|';
  key += std::to_wstring(state_.unplayed_color);
  key += L'|';
  key += std::to_wstring(state_.stroke_color);
  key += L'|';
  key += std::to_wstring(state_.background_alpha);
  key += L'|';
  key += std::to_wstring(state_.font_pt);
  key += L'|';
  key += std::to_wstring(state_.double_line ? 1 : 0);
  key += L'|';
  key += std::to_wstring(state_.topmost ? 1 : 0);
  key += L'|';
  key += std::to_wstring(state_.locked ? 1 : 0);
  key += L'|';
  key += std::to_wstring(state_.playing ? 1 : 0);
  key += L'|';
  key += std::to_wstring(static_cast<long long>(DpiScale() * 100.0));
  key += L'|';
  key += std::to_wstring(::GetSystemMetrics(SM_CXVIRTUALSCREEN));
  return key;
}

void DesktopLyricsWindow::RebuildScene(const std::wstring& key) {
  HDC screen = ::GetDC(nullptr);
  HDC probe = ::CreateCompatibleDC(screen);
  HBITMAP stock = ::CreateCompatibleBitmap(screen, 1, 1);
  HGDIOBJ previous = ::SelectObject(probe, stock);
  {
    Gdiplus::Graphics graphics(probe);
    graphics.SetTextRenderingHint(Gdiplus::TextRenderingHintAntiAlias);
    const Layout layout = ComputeLayout(graphics);
    scene_layout_ = layout;
    controls_ = layout.controls;
    width_ = static_cast<int>(std::ceil(layout.width));
    height_ = static_cast<int>(std::ceil(layout.height));

    const Gdiplus::RectF primary_box(
        layout.pad, layout.pad + layout.toolbar_height + 6.0f * layout.scale,
        layout.width - layout.pad * 2.0f, layout.primary_size * 1.5f);

    primary_ = CachedText();
    if (!state_.lines.empty()) {
      primary_.path = BuildPath(state_.lines[0], kTextFont,
                                layout.primary_size, Gdiplus::FontStyleBold,
                                primary_box, true, &primary_.bounds);
    }

    secondary_ = CachedText();
    if (!state_.lines.empty() && state_.double_line &&
        state_.lines.size() > 1) {
      const Gdiplus::RectF box(
          primary_box.X, primary_box.Y + primary_box.Height + 4.0f * layout.scale,
          primary_box.Width, layout.secondary_size * 1.45f);
      secondary_.path = BuildPath(state_.lines[1], kTextFont,
                                  layout.secondary_size,
                                  Gdiplus::FontStyleBold, box, true,
                                  &secondary_.bounds);
    }

    status_text_ = CachedText();
    if (state_.lines.empty()) {
      status_text_.path = BuildPath(state_.status, kTextFont,
                                    12.5f * layout.scale,
                                    Gdiplus::FontStyleRegular, primary_box,
                                    false, &status_text_.bounds);
    }

    font_label_ = CachedText();
    control_texts_.clear();
    control_texts_.resize(layout.controls.size());
    if (!layout.controls.empty()) {
      const RECT minus = layout.controls[kFontMinusIndex].bounds;
      const RECT plus = layout.controls[kFontPlusIndex].bounds;
      const Gdiplus::RectF label_box(
          static_cast<float>(minus.right), static_cast<float>(minus.top),
          static_cast<float>(plus.left - minus.right),
          static_cast<float>(minus.bottom - minus.top));
      font_label_.path = BuildPath(std::to_wstring(state_.font_pt) + L"pt",
                                   kTextFont, 12.5f * layout.scale,
                                   Gdiplus::FontStyleRegular, label_box, false,
                                   &font_label_.bounds);
      for (size_t i = 0; i < layout.controls.size(); ++i) {
        const Control& control = layout.controls[i];
        const Gdiplus::RectF box = ToRect(control.bounds);
        control_texts_[i].path = BuildPath(
            control.label, control.glyph ? kGlyphFont : kTextFont,
            (control.glyph ? 15.0f : 12.5f) * layout.scale,
            Gdiplus::FontStyleRegular, box, false, &control_texts_[i].bounds);
      }
    }
  }
  ::SelectObject(probe, previous);
  ::DeleteObject(stock);
  ::DeleteDC(probe);
  ::ReleaseDC(nullptr, screen);

  scene_key_ = key;
  painted_progress_ = -1.0;
}

void DesktopLyricsWindow::ReleaseScene() {
  scene_key_.clear();
  scene_layout_ = Layout();
  primary_ = CachedText();
  secondary_ = CachedText();
  status_text_ = CachedText();
  font_label_ = CachedText();
  control_texts_.clear();
}

bool DesktopLyricsWindow::Show(const flutter::EncodableMap& payload) {
  ApplyPayload(payload);
  if (!EnsureWindow()) {
    return false;
  }
  if (x_ < 0 || y_ < 0) {
    RECT work{};
    ::SystemParametersInfoW(SPI_GETWORKAREA, 0, &work, 0);
    const float scale = DpiScale();
    x_ = static_cast<int>((static_cast<float>(work.left + work.right) -
                           kBaseWidth * scale) /
                          2.0f);
    y_ = static_cast<int>(static_cast<float>(work.bottom) - 150.0f * scale);
  }
  positioned_ = true;
  ApplyFlags();
  ::ShowWindow(hwnd_, SW_SHOWNOACTIVATE);
  // 高亮由浮层自己的时钟推进，不再依赖 Dart 的推送节奏。
  ::SetTimer(hwnd_, kProgressTimerId, kProgressIntervalMs, nullptr);
  Update(payload);
  return true;
}

void DesktopLyricsWindow::ApplyFlags() {
  if (hwnd_ == nullptr) {
    return;
  }
  // 锁定不再用 WS_EX_TRANSPARENT 整窗穿透：那会把控制条一起封死，
  // 用户再也点不到解锁按钮。穿透改由 WM_NCHITTEST 按区域决定。
  // 层级直接读窗口真实样式而不是记缓存：缓存一旦和 HWND 不同步（例如重建
  // 窗口时置顶带没跟过来），浮层会永远被主窗口压住且再也没有机会纠正。
  const bool is_topmost =
      (::GetWindowLongPtrW(hwnd_, GWL_EXSTYLE) & WS_EX_TOPMOST) != 0;
  if (is_topmost == state_.topmost) {
    return;
  }
  ::SetWindowPos(hwnd_, state_.topmost ? HWND_TOPMOST : HWND_NOTOPMOST, 0, 0,
                 0, 0, SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE);
}

bool DesktopLyricsWindow::Update(const flutter::EncodableMap& payload) {
  if (hwnd_ == nullptr) {
    return Show(payload);
  }
  if (!::IsWindow(hwnd_)) {
    hwnd_ = nullptr;
    return Show(payload);
  }
  const bool resynced = ApplyPayload(payload);
  ApplyFlags();
  const std::wstring key = SceneKey();
  if (key != scene_key_) {
    RebuildScene(key);
    Paint();
  } else if (resynced) {
    // 只有进度真的对表过才重画；纯推送交给定时器，避免一秒画几十遍。
    Paint();
  }
  return true;
}

void DesktopLyricsWindow::Hide() {
  if (hwnd_ != nullptr) {
    ::KillTimer(hwnd_, kProgressTimerId);
    ::DestroyWindow(hwnd_);
    hwnd_ = nullptr;
  }
  positioned_ = false;
  hovered_ = -1;
  dragging_ = false;
  pointer_inside_ = false;
  leave_armed_ = false;
  controls_.clear();
  ReleaseScene();
  ReleaseSurface();
}

void DesktopLyricsWindow::EnsureSurface(int width, int height) {
  if (surface_ != nullptr && surface_width_ == width &&
      surface_height_ == height) {
    return;
  }
  ReleaseSurface();
  HDC screen = ::GetDC(nullptr);
  BITMAPINFO info{};
  info.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
  info.bmiHeader.biWidth = width;
  info.bmiHeader.biHeight = -height;
  info.bmiHeader.biPlanes = 1;
  info.bmiHeader.biBitCount = 32;
  info.bmiHeader.biCompression = BI_RGB;
  void* bits = nullptr;
  HBITMAP bitmap =
      ::CreateDIBSection(screen, &info, DIB_RGB_COLORS, &bits, nullptr, 0);
  ::ReleaseDC(nullptr, screen);
  if (bitmap == nullptr) {
    return;
  }
  HDC memory = ::CreateCompatibleDC(nullptr);
  if (memory == nullptr) {
    ::DeleteObject(bitmap);
    return;
  }
  surface_previous_ = ::SelectObject(memory, bitmap);
  surface_ = memory;
  surface_bitmap_ = bitmap;
  surface_bits_ = bits;
  surface_width_ = width;
  surface_height_ = height;
}

void DesktopLyricsWindow::ReleaseSurface() {
  if (surface_ != nullptr) {
    if (surface_previous_ != nullptr) {
      ::SelectObject(surface_, surface_previous_);
    }
    ::DeleteDC(surface_);
  }
  if (surface_bitmap_ != nullptr) {
    ::DeleteObject(surface_bitmap_);
  }
  surface_ = nullptr;
  surface_bitmap_ = nullptr;
  surface_previous_ = nullptr;
  surface_bits_ = nullptr;
  surface_width_ = 0;
  surface_height_ = 0;
}

void DesktopLyricsWindow::ClampPosition() {
  if (width_ <= 0 || height_ <= 0) {
    return;
  }
  const RECT area = VirtualScreen();
  const int left = static_cast<int>(area.left);
  const int top = static_cast<int>(area.top);
  const int right = static_cast<int>(area.right);
  const int bottom = static_cast<int>(area.bottom);
  if (right <= left || bottom <= top) {
    return;
  }
  const bool on_screen =
      x_ + width_ > left && x_ < right && y_ + height_ > top && y_ < bottom;
  if (!on_screen) {
    // 记住的坐标可能属于一块已经拔掉的外接屏，直接用会让浮层彻底看不见，
    // 而且再也拖不回来，只能退回工作区底部居中。
    RECT work{};
    ::SystemParametersInfoW(SPI_GETWORKAREA, 0, &work, 0);
    x_ = (static_cast<int>(work.left) + static_cast<int>(work.right) - width_) /
         2;
    y_ = static_cast<int>(work.bottom) - height_ -
         static_cast<int>(24.0f * DpiScale());
    return;
  }
  const int grab = std::min(kEdgeGrab, std::min(width_, height_));
  x_ = std::max(left - width_ + grab, std::min(x_, right - grab));
  y_ = std::max(top - height_ + grab, std::min(y_, bottom - grab));
}

void DesktopLyricsWindow::Paint() {
  if (hwnd_ == nullptr || width_ <= 0 || height_ <= 0) {
    return;
  }
  ClampPosition();
  EnsureSurface(width_, height_);
  if (surface_ == nullptr || surface_bits_ == nullptr) {
    return;
  }
  {
    Gdiplus::Graphics graphics(surface_);
    graphics.SetSmoothingMode(Gdiplus::SmoothingModeAntiAlias);
    graphics.SetTextRenderingHint(Gdiplus::TextRenderingHintAntiAlias);
    graphics.SetPixelOffsetMode(Gdiplus::PixelOffsetModeHalf);
    graphics.Clear(Gdiplus::Color(0, 0, 0, 0));
    DrawScene(graphics, scene_layout_);
  }
  painted_progress_ = LiveProgress();
  // 关掉底板后整窗几乎全是 alpha=0 像素，而分层窗口把完全透明的像素当成
  // "这里没有窗口"直接穿透到桌面——歌词拖不动、控制条点不到都是这个原因。
  // 把 alpha 抬到 1 仍然肉眼不可见，但命中测试会回到本窗口。
  BYTE* pixels = static_cast<BYTE*>(surface_bits_);
  const size_t count =
      static_cast<size_t>(width_) * static_cast<size_t>(height_);
  for (size_t i = 0; i < count; ++i) {
    if (pixels[i * 4 + 3] == 0) {
      pixels[i * 4 + 3] = 1;
    }
  }
  HDC screen = ::GetDC(nullptr);
  POINT source{0, 0};
  SIZE size{width_, height_};
  POINT target{x_, y_};
  BLENDFUNCTION blend{};
  blend.BlendOp = AC_SRC_OVER;
  blend.SourceConstantAlpha = 255;
  blend.AlphaFormat = AC_SRC_ALPHA;
  // UpdateLayeredWindow reads the bitmap through the source DC, so the DIB has
  // to stay selected until it returns; tearing the DC down first fails the call
  // with ERROR_GEN_FAILURE and leaves the window permanently invisible.
  ::UpdateLayeredWindow(hwnd_, screen, &target, &size, surface_, &source,
                        RGB(0, 0, 0), &blend, ULW_ALPHA);
  ::ReleaseDC(nullptr, screen);
}

void DesktopLyricsWindow::DrawScene(Gdiplus::Graphics& graphics,
                                    const Layout& layout) {
  if (state_.background_alpha > 0) {
    Gdiplus::GraphicsPath panel;
    AddRoundedRect(
        panel, Gdiplus::RectF(0.0f, 0.0f, layout.width, layout.height),
        14.0f * layout.scale);
    Gdiplus::SolidBrush backdrop(
        Gdiplus::Color(static_cast<BYTE>(state_.background_alpha), 10, 12,
                       20));
    graphics.FillPath(&backdrop, &panel);
    Gdiplus::Pen edge(Gdiplus::Color(0x2E, 255, 255, 255), 1.0f);
    graphics.DrawPath(&edge, &panel);
  }

  // 工具栏只在鼠标停在浮层上时出现，移开即隐藏，歌词区保持干净。
  if (ToolbarVisible()) {
    for (size_t i = 0; i < layout.controls.size(); ++i) {
      if (i >= control_texts_.size()) {
        break;
      }
      DrawControl(graphics, layout.controls[i], control_texts_[i], layout.scale,
                  static_cast<int>(i) == hovered_);
    }
    if (font_label_.path != nullptr) {
      Gdiplus::SolidBrush label(Gdiplus::Color(0xE0, 255, 255, 255));
      Gdiplus::Pen outline(Gdiplus::Color(0xBF, 0, 0, 0),
                           1.4f * layout.scale);
      outline.SetLineJoin(Gdiplus::LineJoinRound);
      outline.SetStartCap(Gdiplus::LineCapRound);
      outline.SetEndCap(Gdiplus::LineCapRound);
      graphics.DrawPath(&outline, font_label_.path.get());
      graphics.FillPath(&label, font_label_.path.get());
    }
  }

  if (state_.lines.empty()) {
    if (status_text_.path != nullptr) {
      Gdiplus::SolidBrush brush(Gdiplus::Color(0xE0, 255, 255, 255));
      Gdiplus::Pen outline(Gdiplus::Color(0xBF, 0, 0, 0), 1.4f * layout.scale);
      outline.SetLineJoin(Gdiplus::LineJoinRound);
      outline.SetStartCap(Gdiplus::LineCapRound);
      outline.SetEndCap(Gdiplus::LineCapRound);
      graphics.DrawPath(&outline, status_text_.path.get());
      graphics.FillPath(&brush, status_text_.path.get());
    }
    return;
  }

  const Gdiplus::Color active = Argb(state_.color);
  const Gdiplus::Color waiting = Argb(state_.unplayed_color);
  const BYTE stroke_alpha =
      static_cast<BYTE>((state_.stroke_color >> 24) & 0xFFu);

  // 主句：整句描边一次，再铺未播放色，最后按进度裁出已播放的部分。
  if (primary_.path != nullptr) {
    if (stroke_alpha > 0) {
      Gdiplus::Pen outline(
          Argb(state_.stroke_color),
          std::max(2.0f, layout.primary_size * 0.08f));
      outline.SetLineJoin(Gdiplus::LineJoinRound);
      outline.SetStartCap(Gdiplus::LineCapRound);
      outline.SetEndCap(Gdiplus::LineCapRound);
      graphics.DrawPath(&outline, primary_.path.get());
    }
    Gdiplus::SolidBrush waiting_brush(waiting);
    graphics.FillPath(&waiting_brush, primary_.path.get());
    const double progress = LiveProgress();
    if (progress > 0.0 && primary_.bounds.Width > 1.0f) {
      const float played_width =
          ClampF(static_cast<float>(progress), 0.0f, 1.0f) *
          primary_.bounds.Width;
      graphics.SetClip(Gdiplus::RectF(primary_.bounds.X - 1.0f,
                                      primary_.bounds.Y - 1.0f,
                                      played_width + 1.0f,
                                      primary_.bounds.Height + 2.0f));
      Gdiplus::SolidBrush played_brush(active);
      graphics.FillPath(&played_brush, primary_.path.get());
      graphics.ResetClip();
    }
  }
  if (state_.double_line && secondary_.path != nullptr) {
    Gdiplus::SolidBrush brush(waiting);
    if (stroke_alpha > 0) {
      Gdiplus::Pen outline(
          Argb(state_.stroke_color),
          std::max(2.0f, layout.secondary_size * 0.08f));
      outline.SetLineJoin(Gdiplus::LineJoinRound);
      outline.SetStartCap(Gdiplus::LineCapRound);
      outline.SetEndCap(Gdiplus::LineCapRound);
      graphics.DrawPath(&outline, secondary_.path.get());
    }
    graphics.FillPath(&brush, secondary_.path.get());
  }
}

void DesktopLyricsWindow::DrawControl(Gdiplus::Graphics& graphics,
                                      const Control& control,
                                      const CachedText& cached, float scale,
                                      bool hovered) const {
  const Gdiplus::RectF box = ToRect(control.bounds);
  if (hovered) {
    Gdiplus::GraphicsPath path;
    AddRoundedRect(path, box, 8.0f * scale);
    // 没有底板时白色高亮在浅色桌面上看不见，改用深色底。
    const bool bare = state_.background_alpha == 0;
    Gdiplus::SolidBrush highlight(
        bare ? Gdiplus::Color(0x66, 0, 0, 0)
             : Gdiplus::Color(0x2D, 255, 255, 255));
    graphics.FillPath(&highlight, &path);
  }
  if (cached.path == nullptr) {
    return;
  }
  Gdiplus::SolidBrush brush(Gdiplus::Color(0xF2, 255, 255, 255));
  Gdiplus::Pen outline(Gdiplus::Color(0xBF, 0, 0, 0),
                       (control.glyph ? 1.6f : 1.4f) * scale);
  outline.SetLineJoin(Gdiplus::LineJoinRound);
  outline.SetStartCap(Gdiplus::LineCapRound);
  outline.SetEndCap(Gdiplus::LineCapRound);
  graphics.DrawPath(&outline, cached.path.get());
  graphics.FillPath(&brush, cached.path.get());
}

int DesktopLyricsWindow::HitTest(const POINT& point) const {
  // 工具栏隐藏时那些位置没有按钮，落点应当回到歌词区用于拖动。
  if (!ToolbarVisible()) {
    return -1;
  }
  for (size_t i = 0; i < controls_.size(); ++i) {
    const RECT& bounds = controls_[i].bounds;
    if (point.x >= bounds.left && point.x < bounds.right && point.y >= bounds.top &&
        point.y < bounds.bottom) {
      return static_cast<int>(i);
    }
  }
  return -1;
}

bool DesktopLyricsWindow::InToolbarBand(const POINT& point) const {
  if (controls_.empty()) {
    return false;
  }
  const RECT& first = controls_.front().bounds;
  return point.y >= first.top && point.y < first.bottom;
}

void DesktopLyricsWindow::Emit(const std::string& event) {
  if (sender_) {
    sender_(event, flutter::EncodableMap());
  }
}

void DesktopLyricsWindow::EmitMoved() {
  if (!sender_) {
    return;
  }
  flutter::EncodableMap arguments;
  arguments[flutter::EncodableValue("x")] = flutter::EncodableValue(x_);
  arguments[flutter::EncodableValue("y")] = flutter::EncodableValue(y_);
  sender_("moved", arguments);
}

LRESULT CALLBACK DesktopLyricsWindow::WndProc(HWND hwnd, UINT message,
                                              WPARAM wparam, LPARAM lparam) {
  DesktopLyricsWindow* self = nullptr;
  if (message == WM_NCCREATE) {
    const auto* create = reinterpret_cast<CREATESTRUCTW*>(lparam);
    self = static_cast<DesktopLyricsWindow*>(create->lpCreateParams);
    ::SetWindowLongPtrW(hwnd, GWLP_USERDATA,
                        reinterpret_cast<LONG_PTR>(self));
  } else {
    self = reinterpret_cast<DesktopLyricsWindow*>(
        ::GetWindowLongPtrW(hwnd, GWLP_USERDATA));
  }
  if (self == nullptr) {
    return ::DefWindowProcW(hwnd, message, wparam, lparam);
  }
  return self->HandleMessage(hwnd, message, wparam, lparam);
}

LRESULT DesktopLyricsWindow::HandleMessage(HWND hwnd, UINT message,
                                           WPARAM wparam, LPARAM lparam) {
  switch (message) {
    case WM_ERASEBKGND:
      return 1;
    // 逐字高亮靠这个节拍推进，Dart 只在换句或跳变时重新对表。
    case WM_TIMER:
      if (wparam == kProgressTimerId) {
        if (std::fabs(LiveProgress() - painted_progress_) >=
            kRepaintEpsilon) {
          Paint();
        }
        return 0;
      }
      break;
    // 只靠 WS_EX_NOACTIVATE 还不够：点击浮层仍会把它顶成前台窗口，
    // 主窗口的快捷键会因此失效，这里显式拒绝激活。
    case WM_MOUSEACTIVATE:
      return MA_NOACTIVATE;
    case WM_LBUTTONDOWN: {
      POINT point{GET_X_LPARAM(lparam), GET_Y_LPARAM(lparam)};
      const int hit = HitTest(point);
      if (hit >= 0) {
        Emit(controls_[static_cast<size_t>(hit)].event);
        return 0;
      }
      if (!state_.locked) {
        dragging_ = true;
        ::SetCapture(hwnd);
        // 记下抓取点相对窗口左上角的偏移，之后让这一点一直贴着光标。
        drag_dx_ = point.x;
        drag_dy_ = point.y;
      }
      return 0;
    }
    case WM_LBUTTONDBLCLK: {
      POINT point{GET_X_LPARAM(lparam), GET_Y_LPARAM(lparam)};
      if (!state_.locked && HitTest(point) < 0) {
        Emit("playPause");
      }
      return 0;
    }
    case WM_MOUSEMOVE: {
      POINT point{GET_X_LPARAM(lparam), GET_Y_LPARAM(lparam)};
      if (dragging_) {
        POINT cursor{};
        ::GetCursorPos(&cursor);
        x_ = cursor.x - drag_dx_;
        y_ = cursor.y - drag_dy_;
        ClampPosition();
        ::SetWindowPos(hwnd, nullptr, x_, y_, 0, 0,
                       SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE);
        return 0;
      }
      if (!leave_armed_) {
        TRACKMOUSEEVENT track{};
        track.cbSize = sizeof(track);
        track.dwFlags = TME_LEAVE;
        track.hwndTrack = hwnd;
        ::TrackMouseEvent(&track);
        leave_armed_ = true;
      }
      const bool was_inside = pointer_inside_;
      const int hit = HitTest(point);
      pointer_inside_ = true;
      if (hit != hovered_ || !was_inside) {
        hovered_ = hit;
        Paint();
      }
      return 0;
    }
    case WM_MOUSELEAVE:
      leave_armed_ = false;
      if (pointer_inside_ || hovered_ != -1) {
        pointer_inside_ = false;
        hovered_ = -1;
        Paint();
      }
      return 0;
    case WM_LBUTTONUP:
      if (dragging_) {
        dragging_ = false;
        ::ReleaseCapture();
        EmitMoved();
      }
      return 0;
    case WM_CAPTURECHANGED:
      dragging_ = false;
      return 0;
    case WM_NCHITTEST: {
      if (!state_.locked) {
        break;
      }
      POINT point{GET_X_LPARAM(lparam), GET_Y_LPARAM(lparam)};
      ::ScreenToClient(hwnd, &point);
      // 锁定只让歌词区域穿透到下面的窗口；顶部那条工具栏必须留得住鼠标，
      // 否则悬浮显示的工具栏永远出不来，锁上之后就再也解不开。
      if (InToolbarBand(point)) {
        break;
      }
      return HTTRANSPARENT;
    }
    case WM_DESTROY:
      hwnd_ = nullptr;
      controls_.clear();
      return 0;
    default:
      break;
  }
  return ::DefWindowProcW(hwnd, message, wparam, lparam);
}
