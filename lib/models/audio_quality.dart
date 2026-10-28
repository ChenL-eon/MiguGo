/// 咪咕网页播放器使用的音质档位：PQ / HQ / SQ，以及按账号权益发放的至臻 ZQ24。
enum AudioQuality {
  pq('PQ', '标准音质', '标准', '约 128 kbps'),
  hq('HQ', '高品质', '高品质', '约 320 kbps'),
  sq('SQ', '无损音质', '无损', 'FLAC 无损'),
  zq24('ZQ24', '至臻音质', '至臻', 'FLAC 24bit');

  const AudioQuality(this.toneFlag, this.label, this.shortLabel, this.detail);

  /// 取链接口使用的 toneFlag。
  final String toneFlag;
  final String label;
  final String shortLabel;
  final String detail;

  /// 从高到低列出不高于 [preferred] 的档位，用于按账号权益逐级回退。
  static List<AudioQuality> fallbackChain(AudioQuality preferred) {
    return [
      for (final quality in values.reversed)
        if (quality.index <= preferred.index) quality,
    ];
  }

  static AudioQuality fromName(String? name) {
    return values.firstWhere(
      (quality) => quality.name == name,
      orElse: () => AudioQuality.hq,
    );
  }
}
