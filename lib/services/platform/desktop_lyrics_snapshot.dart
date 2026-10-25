import '../../core/utils/lyric_parser.dart';
import '../../models/lyric_line.dart';

/// 一次原生桌面歌词浮层的重绘载荷。
class DesktopLyricsSnapshot {
  const DesktopLyricsSnapshot({
    required this.lines,
    required this.status,
    required this.progress,
    required this.fontPt,
    required this.colorArgb,
    required this.unplayedArgb,
    required this.strokeArgb,
    required this.panelAlpha,
    required this.doubleLine,
    required this.topmost,
    required this.locked,
    required this.playing,
    this.lineDurationMs = 0,
    this.position,
  });

  /// 浮层显示的歌词行，第一行为当前句。
  final List<String> lines;

  /// 没有歌词时显示的占位文案。
  final String status;

  /// 当前句已播放的比例，用于逐字推进的高亮。
  final double progress;

  /// 当前句的总时长；原生浮层用它在自己的时钟上继续推进高亮，
  /// 这样颜色跟随不再受 Dart 侧推送频率和进度取整的限制。0 表示未知。
  final int lineDurationMs;

  final int fontPt;

  /// 已播放部分的颜色。
  final int colorArgb;

  /// 未播放部分与下一句的颜色。
  final int unplayedArgb;

  /// 描边颜色；alpha 为 0 表示不描边。
  final int strokeArgb;
  final int panelAlpha;
  final bool doubleLine;
  final bool topmost;
  final bool locked;
  final bool playing;

  /// 浮层左上角的物理像素坐标；为空时由原生窗口自行定位。
  final List<int>? position;

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'lines': lines,
      'status': status,
      'progress': progress,
      'lineDurationMs': lineDurationMs,
      'fontPt': fontPt,
      'color': colorArgb,
      'unplayedColor': unplayedArgb,
      'strokeColor': strokeArgb,
      'backgroundAlpha': panelAlpha,
      'doubleLine': doubleLine,
      'topmost': topmost,
      'locked': locked,
      'playing': playing,
      'x': position == null ? -1 : position![0],
      'y': position == null ? -1 : position![1],
    };
  }

  /// 用于跳过无变化的重绘；位置不参与，因为拖动不会改变内容。
  String get signature {
    return <Object>[
      lines.join(' | '),
      status,
      (progress * 40).round(),
      fontPt,
      colorArgb,
      unplayedArgb,
      strokeArgb,
      panelAlpha,
      doubleLine,
      topmost,
      locked,
      playing,
    ].join('#');
  }
}

/// 由歌词与播放进度拼出浮层载荷。
///
/// 一行内可能带翻译（解析时用 \n 合并），此时优先把译文当作第二行。
DesktopLyricsSnapshot buildDesktopLyricsSnapshot({
  required List<LyricLine> lines,
  required Duration position,
  required String status,
  required int fontPt,
  required int colorArgb,
  required int unplayedArgb,
  required int strokeArgb,
  required int panelAlpha,
  required bool doubleLine,
  required bool topmost,
  required bool locked,
  required bool playing,
  List<int>? windowPosition,
}) {
  final index = LyricParser.activeIndex(lines, position);
  if (index < 0) {
    return DesktopLyricsSnapshot(
      lines: const [],
      status: status,
      progress: 0,
      fontPt: fontPt,
      colorArgb: colorArgb,
      unplayedArgb: unplayedArgb,
      strokeArgb: strokeArgb,
      panelAlpha: panelAlpha,
      doubleLine: doubleLine,
      topmost: topmost,
      locked: locked,
      playing: playing,
      position: windowPosition,
    );
  }

  final parts = lines[index].text.split('\n');
  final display = <String>[parts.first];
  if (doubleLine) {
    if (parts.length > 1) {
      display.add(parts[1]);
    } else if (index + 1 < lines.length) {
      display.add(lines[index + 1].text.split('\n').first);
    }
  }

  return DesktopLyricsSnapshot(
    lines: display,
    status: status,
    progress: _lineProgress(lines, index, position),
    lineDurationMs: _lineDuration(lines, index),
    fontPt: fontPt,
    colorArgb: colorArgb,
    unplayedArgb: unplayedArgb,
    strokeArgb: strokeArgb,
    panelAlpha: panelAlpha,
    doubleLine: doubleLine,
    topmost: topmost,
    locked: locked,
    playing: playing,
    position: windowPosition,
  );
}

double _lineProgress(List<LyricLine> lines, int index, Duration position) {
  final duration = _lineDuration(lines, index);
  if (duration <= 0) return 0;
  final value =
      (position.inMilliseconds - lines[index].start.inMilliseconds) / duration;
  if (value <= 0) return 0;
  if (value >= 1) return 1;
  return value;
}

/// 当前句到下一句的间隔；最后一句没有边界，返回 0 让原生停止插值。
int _lineDuration(List<LyricLine> lines, int index) {
  if (index + 1 >= lines.length) return 0;
  return lines[index + 1].start.inMilliseconds - lines[index].start.inMilliseconds;
}
