/// 时长与播放量的展示格式化。
String formatDuration(Duration? duration) {
  if (duration == null || duration <= Duration.zero) return '--:--';
  final totalSeconds = duration.inSeconds;
  final minutes = totalSeconds ~/ 60;
  final seconds = totalSeconds % 60;
  return '$minutes:${seconds.toString().padLeft(2, '0')}';
}

String formatSeconds(num? seconds) {
  if (seconds == null || seconds <= 0) return '--:--';
  return formatDuration(Duration(seconds: seconds.round()));
}

String compactNumber(String? raw) {
  final value = int.tryParse((raw ?? '').replaceAll(RegExp(r'\D'), ''));
  return value == null ? '--' : formatCount(value);
}

String formatCount(int value) {
  if (value >= 100000000) {
    return '${_trimZero(value / 100000000)}亿';
  }
  if (value >= 10000) {
    return '${_trimZero(value / 10000)}万';
  }
  return '$value';
}

String formatDate(DateTime? value) {
  if (value == null) return '';
  final local = value.toLocal();
  final month = local.month.toString().padLeft(2, '0');
  final day = local.day.toString().padLeft(2, '0');
  return '${local.year}.$month.$day';
}

String _trimZero(double value) {
  final fixed = value.toStringAsFixed(1);
  return fixed.endsWith('.0') ? fixed.substring(0, fixed.length - 2) : fixed;
}
