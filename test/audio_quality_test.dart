import 'package:flutter_test/flutter_test.dart';
import 'package:migu_lele/models/audio_quality.dart';

void main() {
  test('音质回退链按从高到低排列且不超过所选档位', () {
    expect(AudioQuality.fallbackChain(AudioQuality.sq), [
      AudioQuality.sq,
      AudioQuality.hq,
      AudioQuality.pq,
    ]);
    expect(AudioQuality.fallbackChain(AudioQuality.hq), [
      AudioQuality.hq,
      AudioQuality.pq,
    ]);
    expect(AudioQuality.fallbackChain(AudioQuality.pq), [AudioQuality.pq]);
  });

  test('未知或缺失的持久化值回退到高品质', () {
    expect(AudioQuality.fromName(null), AudioQuality.hq);
    expect(AudioQuality.fromName('unknown'), AudioQuality.hq);
    expect(AudioQuality.fromName('sq'), AudioQuality.sq);
  });

  test('与咪咕官方一致的三档音质标识', () {
    expect(AudioQuality.values.map((item) => item.toneFlag), ['PQ', 'HQ', 'SQ']);
    expect(AudioQuality.sq.label, '无损音质');
  });
}
