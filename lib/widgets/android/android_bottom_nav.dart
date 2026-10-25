import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/theme/android_tokens.dart';
import '../../core/theme/app_colors.dart';
import '../../models/song.dart';
import '../../providers/player_provider.dart';
import '../cover_art.dart';
import 'android_bounded_chrome.dart';
import 'android_glass_surface.dart';
import 'android_ring_progress.dart';

/// Android 主框架的悬浮胶囊导航：首页与我的分列两侧，中间是正在播放的唱片。
///
/// 歌单入口收进「我的」，胶囊中间换成唱片，点它直接进播放页；
/// 选中态不垫常驻色块，靠描边→实心的图标形变和主题色文字区分，
/// 只在切过来的瞬间于新选中那格闪一块淡色切面；
/// 每次切换只触发一次轻触反馈，避免长按或重复点击产生连续震动。
class AndroidBottomNav extends StatelessWidget {
  const AndroidBottomNav({
    super.key,
    required this.selectedIndex,
    required this.onSelect,
    required this.onOpenPlayer,
  });

  final int selectedIndex;
  final ValueChanged<int> onSelect;
  final VoidCallback onOpenPlayer;

  static const _homeItem = _AndroidNavItem(
    icon: Icons.home_outlined,
    activeIcon: Icons.home_rounded,
    label: '首页',
  );
  static const _mineItem = _AndroidNavItem(
    icon: Icons.person_outline_rounded,
    activeIcon: Icons.person_rounded,
    label: '我的',
  );

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerProvider>();
    final palette = context.palette;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final panel = AndroidGlassSurface(
      borderRadius: const BorderRadius.all(Radius.circular(AndroidRadius.pill)),
      blurSigma: 24,
      tint: palette.surfaceHigh.withValues(alpha: isDark ? 0.82 : 0.9),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      child: Material(
        type: MaterialType.transparency,
        child: SizedBox(
          height: AndroidSizes.bottomBarHeight - 6,
          child: Row(
            children: [
              Expanded(
                child: _NavButton(
                  item: _homeItem,
                  selected: selectedIndex == 0,
                  onTap: () => _select(0),
                ),
              ),
              _NavDisc(player: player, onTap: onOpenPlayer),
              Expanded(
                child: _NavButton(
                  item: _mineItem,
                  selected: selectedIndex == 1,
                  onTap: () => _select(1),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    return AndroidBoundedChrome(child: panel);
  }

  void _select(int tab) {
    if (selectedIndex == tab) return;
    unawaited(HapticFeedback.selectionClick());
    onSelect(tab);
  }
}

class _AndroidNavItem {
  const _AndroidNavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
  });

  final IconData icon;
  final IconData activeIcon;
  final String label;
}

class _NavButton extends StatefulWidget {
  const _NavButton({required this.item, required this.selected, required this.onTap});

  final _AndroidNavItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_NavButton> createState() => _NavButtonState();
}

/// 导航格子：图标形变 + 文字变色表示选中，切过来时背后闪一块淡色切面，
/// 按住时垫一层同形状的按下底色。
class _NavButtonState extends State<_NavButton> with TickerProviderStateMixin {
  /// 图标槽定高：选中态只换图标形状和颜色，不再垫一块常驻底色，
  /// 槽位不变才不会让下面的文字在切换时上下跳。
  static const double _iconSlot = 26;
  static const double _iconSize = 24;

  /// 切面铺满整格，圆角跟胶囊同一档（999 会被夹到格子高度的一半），
  /// 两端都是半圆，读起来就是「胶囊里的一颗小胶囊」。用圆角矩形时外侧那两端
  /// 会被胶囊自己的弧线切平，内侧那端又是一条直边杵在唱片旁边。
  static const double _facetRadius = AndroidRadius.pill;

  /// 节奏照参考端量出来的：瞬间亮到峰值、定住 100ms、再用 400ms 淡干净。
  /// 淡的这段是线性的，实测浓度几乎匀速下降，换成减速曲线开头会掉得太急。
  static const Duration _facetHold = Duration(milliseconds: 100);
  static const Duration _facetFade = Duration(milliseconds: 400);

  /// 峰值浓度：浅色档叠在胶囊白底上正好还原参考端那块淡蓝。深色档不是简单
  /// 照搬——同样的 alpha 压在深色胶囊上偏色更重，实测比浅色高一档，往回收到
  /// 和浅色相当的色度差才不会看着像一块常驻底色。
  static const double _facetPeakLight = 0.13;
  static const double _facetPeakDark = 0.16;

  /// 按下底色比切面峰值淡一档：它是按住不放时的持续状态，不该盖过切换那一下。
  static const double _pressPeakLight = 0.09;
  static const double _pressPeakDark = 0.11;

  /// 静止位停在 1.0，也就是「淡完了」：不闪的时候切面完全透明，
  /// 再点一次才从头演，省掉一个「有没有在闪」的额外状态。
  late final AnimationController _facet = AnimationController(
    vsync: this,
    duration: _facetHold + _facetFade,
    value: 1,
  );

  static final double _holdFraction =
      _facetHold.inMilliseconds / (_facetHold + _facetFade).inMilliseconds;

  late final Animation<double> _facetOpacity = Tween<double>(
    begin: 1,
    end: 0,
  ).animate(CurvedAnimation(parent: _facet, curve: Interval(_holdFraction, 1)));

  /// 水波纹整个关掉了，按住不放时得有东西亮着，不然长按看着像没响应。
  /// 单独一个控制器，只负责这层底色淡入淡出。
  late final AnimationController _press = AnimationController(
    vsync: this,
    duration: AndroidMotion.fast,
    reverseDuration: AndroidMotion.fast,
  );

  late final Listenable _visual = Listenable.merge([_facetOpacity, _press]);

  bool _reduceMotion = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
  }

  @override
  void didUpdateWidget(covariant _NavButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 只闪新选中那格，被离开的那格不闪。
    if (!oldWidget.selected && widget.selected && !_reduceMotion) {
      _facet.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _press.dispose();
    _facet.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final peakAlpha = isDark ? _facetPeakDark : _facetPeakLight;
    final pressAlpha = isDark ? _pressPeakDark : _pressPeakLight;
    return Semantics(
      button: true,
      selected: widget.selected,
      label: widget.item.label,
      excludeSemantics: true,
      child: InkWell(
        onTap: widget.onTap,
        borderRadius: BorderRadius.circular(_facetRadius),
        // 切面本身就是这格的按下反馈，再叠一层从触点扩出去的圆形水波纹会跟
        // 胶囊形对不上，峰值那一瞬看着像两个形状叠在一起。
        splashFactory: NoSplash.splashFactory,
        onHighlightChanged: (down) => down ? _press.forward() : _press.reverse(),
        child: AnimatedBuilder(
          animation: _visual,
          builder: (context, child) => DecoratedBox(
            // 按下底色和切面共用同一层，取两者更浓的那个：松手那瞬切面刚到峰值、
            // 按下底色正在淡出，各画一层会叠得比峰值还重。
            decoration: BoxDecoration(
              color: palette.accent.withValues(
                alpha: math.max(
                  peakAlpha * _facetOpacity.value,
                  pressAlpha * _press.value,
                ),
              ),
              borderRadius: const BorderRadius.all(Radius.circular(_facetRadius)),
            ),
            child: child,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                height: _iconSlot,
                child: _IconMorph(
                  item: widget.item,
                  selected: widget.selected,
                  selectedColor: palette.accent,
                  idleColor: palette.textMuted,
                  size: _iconSize,
                ),
              ),
              const SizedBox(height: 2),
              AnimatedDefaultTextStyle(
                duration: AndroidMotion.base,
                curve: AndroidMotion.standard,
                style: TextStyle(
                  fontSize: 11.5,
                  height: 1.1,
                  fontWeight: widget.selected ? FontWeight.w700 : FontWeight.w500,
                  color: widget.selected ? palette.accent : palette.textSecondary,
                ),
                child: Text(
                  widget.item.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 描边图标淡出、实心图标淡入并轻微放大，让选中切换看起来是形变而不是硬切。
class _IconMorph extends StatelessWidget {
  const _IconMorph({
    required this.item,
    required this.selected,
    required this.selectedColor,
    required this.idleColor,
    required this.size,
  });

  final _AndroidNavItem item;
  final bool selected;
  final Color selectedColor;
  final Color idleColor;
  final double size;

  @override
  Widget build(BuildContext context) {
    // begin 只在首帧生效：让它跟着 selected 起算，App 冷启动时图标不会
    // 先演一遍形变；之后 begin 会被组件改写成当前值，切换才有动画。
    final target = selected ? 1.0 : 0.0;
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: target, end: target),
      duration: AndroidMotion.base,
      curve: AndroidMotion.emphasized,
      builder: (context, value, _) {
        return Stack(
          alignment: Alignment.center,
          children: [
            Opacity(
              opacity: (1 - value).clamp(0.0, 1.0),
              child: Transform.scale(
                scale: 1 + value * 0.18,
                child: Icon(item.icon, size: size, color: idleColor),
              ),
            ),
            Opacity(
              opacity: value.clamp(0.0, 1.0),
              child: Transform.scale(
                scale: 0.82 + value * 0.18,
                child: Icon(item.activeIcon, size: size, color: selectedColor),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// 胶囊中间的唱片：封面旋转、外圈走进度，点击进播放页。
class _NavDisc extends StatelessWidget {
  const _NavDisc({required this.player, required this.onTap});

  final PlayerProvider player;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final song = player.currentSong;
    return Semantics(
      button: true,
      label: '播放页',
      excludeSemantics: true,
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: () {
            unawaited(HapticFeedback.selectionClick());
            onTap();
          },
          child: SizedBox(
            width: AndroidSizes.navDiscSize,
            height: AndroidSizes.navDiscSize,
            child: _DiscProgress(player: player, song: song, palette: palette),
          ),
        ),
      ),
    );
  }
}

class _DiscProgress extends StatelessWidget {
  const _DiscProgress({
    required this.player,
    required this.song,
    required this.palette,
  });

  final PlayerProvider player;
  final Song? song;
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    final current = song;
    if (current == null) {
      return AndroidRingProgress(
        value: 0,
        color: palette.accent,
        track: palette.fillStrong,
        child: _IdleDisc(palette: palette),
      );
    }
    return StreamBuilder<Duration?>(
      stream: player.durationStream,
      builder: (context, durationSnapshot) {
        final duration = durationSnapshot.data ?? current.duration;
        return StreamBuilder<Duration>(
          stream: player.positionStream,
          builder: (context, positionSnapshot) {
            final position = positionSnapshot.data ?? Duration.zero;
            final progress = duration.inMilliseconds <= 0
                ? 0.0
                : (position.inMilliseconds / duration.inMilliseconds)
                      .clamp(0.0, 1.0)
                      .toDouble();
            return AndroidRingProgress(
              value: progress,
              color: palette.accent,
              track: palette.fillStrong,
              child: _SpinningCover(player: player, song: current),
            );
          },
        );
      },
    );
  }
}

class _SpinningCover extends StatefulWidget {
  const _SpinningCover({required this.player, required this.song});

  final PlayerProvider player;
  final Song song;

  @override
  State<_SpinningCover> createState() => _SpinningCoverState();
}

class _SpinningCoverState extends State<_SpinningCover>
    with SingleTickerProviderStateMixin {
  late final AnimationController _spin = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 16),
  );

  @override
  void initState() {
    super.initState();
    if (widget.player.isPlaying) _spin.repeat();
  }

  @override
  void didUpdateWidget(covariant _SpinningCover oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.player.isPlaying) {
      if (!_spin.isAnimating) _spin.repeat();
    } else if (_spin.isAnimating) {
      // 暂停时停在当前角度，回到列表再进来不会突然跳回原点。
      _spin.stop();
    }
  }

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: AnimatedBuilder(
        animation: _spin,
        builder: (context, child) =>
            Transform.rotate(angle: _spin.value * math.pi * 2, child: child),
        child: CoverArt(
          imageUrl: widget.song.coverUrl,
          seed: widget.song.name,
          size: AndroidSizes.navDiscSize - 7,
          borderRadius: BorderRadius.circular(AndroidSizes.navDiscSize),
          iconSize: 19,
        ),
      ),
    );
  }
}

class _IdleDisc extends StatelessWidget {
  const _IdleDisc({required this.palette});

  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: AndroidSizes.navDiscSize - 10,
        height: AndroidSizes.navDiscSize - 10,
        decoration: BoxDecoration(
          color: palette.fill,
          shape: BoxShape.circle,
          border: Border.all(color: palette.line),
        ),
        child: Icon(Icons.music_note_rounded, size: 19, color: palette.textMuted),
      ),
    );
  }
}
