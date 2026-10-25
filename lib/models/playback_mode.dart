/// 播放模式：列表循环、单曲循环、随机播放。
enum PlaybackMode {
  listLoop,
  singleLoop,
  shuffle;

  String get label => switch (this) {
    PlaybackMode.listLoop => '列表循环',
    PlaybackMode.singleLoop => '单曲循环',
    PlaybackMode.shuffle => '随机播放',
  };

  PlaybackMode get next => switch (this) {
    PlaybackMode.listLoop => PlaybackMode.singleLoop,
    PlaybackMode.singleLoop => PlaybackMode.shuffle,
    PlaybackMode.shuffle => PlaybackMode.listLoop,
  };
}
