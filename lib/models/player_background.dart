/// 播放页整屏背景的图片来源。
enum PlayerBackground {
  cover('歌曲封面'),
  custom('自定义图片');

  const PlayerBackground(this.label);

  final String label;

  static PlayerBackground fromName(String? name) {
    return values.firstWhere(
      (value) => value.name == name,
      orElse: () => PlayerBackground.cover,
    );
  }
}
