import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../core/constants/app_constants.dart';
import '../core/navigation/app_shell_controller.dart';
import '../core/theme/android_system_ui.dart';
import '../core/theme/android_tokens.dart';
import '../core/theme/app_colors.dart';
import '../core/utils/platform_kind.dart';
import '../pages/about_page.dart';
import '../pages/home_page.dart';
import '../pages/mine_page.dart';
import '../pages/player_page.dart';
import '../pages/playlist_hub_page.dart';
import '../pages/search_page.dart';
import '../pages/settings_page.dart';
import '../providers/search_provider.dart';
import 'account_center.dart';
import 'ambient_background.dart';
import 'android/android_bottom_nav.dart';
import 'android/android_shell_inset.dart';
import 'app_window_caption.dart';
import 'brand_badge.dart';
import 'mini_player.dart';
import 'secondary_page_frame.dart';

/// 主框架：桌面端使用左侧导航，Android 使用「首页 / 唱片 / 我的」悬浮胶囊。
///
/// Windows 窄窗仍走原来的三栏底部导航，保持桌面端观感不变。
class AppShell extends StatelessWidget {
  const AppShell({super.key});

  static const int _mineIndex = 5;

  void _openPlayer(BuildContext context) {
    unawaited(openPlayerPage(context));
  }

  /// Android 只有首页与我的两个标签，歌单内容并进了「我的」。
  int _androidTab(int index) => index == 0 ? 0 : 1;

  int _androidIndex(int tab) => tab == 0 ? 0 : _mineIndex;

  int _mobileTab(int index) {
    if (index == 0) return 0;
    if (index == 2) return 1;
    return 2;
  }

  int _mobileIndex(int tab) {
    return switch (tab) {
      0 => 0,
      1 => 2,
      _ => _mineIndex,
    };
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.sizeOf(context).width >= 960;
    final selectedIndex = context.watch<AppShellController>().index;

    void select(int index) {
      context.read<AppShellController>().select(index);
    }

    if (isAndroidPlatform) {
      return _buildAndroidShell(context, selectedIndex, select);
    }

    if (isDesktop) {
      final desktopIndex = selectedIndex <= 4 ? selectedIndex : 0;
      final pages = <Widget>[
        HomePage(
          isDesktopShell: true,
          onOpenPlaylists: () => select(2),
          onOpenAbout: () => select(4),
        ),
        const SearchPage(),
        const PlaylistHubPage(),
        const SettingsPage(),
        const AboutPage(),
      ];
      return Scaffold(
        body: AmbientBackground(
          child: Column(
            children: [
              const AppWindowCaption(),
              Expanded(
                child: SafeArea(
                  top: !AppWindowCaption.managed,
                  child: Row(
                    children: [
                      _SideBar(selectedIndex: desktopIndex, onSelect: select),
                      Expanded(
                        child: Column(
                          children: [
                            Expanded(
                              child: IndexedStack(index: desktopIndex, children: pages),
                            ),
                            MiniPlayer(onOpen: () => _openPlayer(context)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    final tab = _mobileTab(selectedIndex);
    final pages = <Widget>[
      HomePage(
        isDesktopShell: false,
        onOpenPlaylists: () => select(2),
        onOpenAbout: () => openAboutPage(context),
      ),
      const PlaylistHubPage(),
      const MinePage(),
    ];
    return Scaffold(
      body: AmbientBackground(
        child: Column(
          children: [
            const AppWindowCaption(),
            Expanded(
              child: SafeArea(
                top: !AppWindowCaption.managed,
                child: Column(
                  children: [
                    Expanded(
                      child: IndexedStack(index: tab, children: pages),
                    ),
                    MiniPlayer(onOpen: () => _openPlayer(context)),
                    _BottomNav(
                      selectedIndex: tab,
                      onSelect: (value) => select(_mobileIndex(value)),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Android 专属壳层：页面铺满整屏，底部只悬浮一条导航胶囊。
  ///
  /// 播放状态由导航中间的唱片承担，不再叠一条迷你播放条；页面通过
  /// [AndroidShellInset] 获得滚动末端留白，键盘弹出时收起底栏，
  /// 避免搜索建议或输入框被悬浮层挡住。
  Widget _buildAndroidShell(
    BuildContext context,
    int selectedIndex,
    ValueChanged<int> select,
  ) {
    final tab = _androidTab(selectedIndex);
    final searchActive = context.select<SearchProvider, bool>(
      (search) => search.query.isNotEmpty,
    );
    final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;
    final systemBottom = MediaQuery.viewPaddingOf(context).bottom;
    // 与下面导航胶囊的边距保持同一组数字：底部留白 + 胶囊本体 + 顶部呼吸位。
    final barsHeight = keyboardOpen
        ? 0.0
        : AndroidSpacing.md + AndroidSizes.bottomBarHeight + AndroidSpacing.xs;
    final pages = <Widget>[
      HomePage(
        isDesktopShell: false,
        onOpenPlaylists: () => select(_mineIndex),
        onOpenAbout: () => openAboutPage(context),
      ),
      const MinePage(),
    ];
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: androidSystemUiStyle(
        statusIconBrightness: isDark ? Brightness.light : Brightness.dark,
        navigationIconBrightness: isDark ? Brightness.light : Brightness.dark,
        navigationBarColor: Colors.transparent,
      ),
      child: PopScope(
        canPop: tab == 0 && !searchActive,
        onPopInvokedWithResult: (didPop, _) {
          if (didPop) return;
          // 搜索态下返回键先清空关键词，和常见的安卓搜索页一致。
          if (searchActive) {
            FocusManager.instance.primaryFocus?.unfocus();
            context.read<SearchProvider>().clear();
            return;
          }
          if (tab != 0) select(0);
        },
        child: Scaffold(
          backgroundColor: Colors.transparent,
          body: AmbientBackground(
            child: Stack(
              fit: StackFit.expand,
              children: [
                SafeArea(
                  bottom: false,
                  child: AndroidShellInset(
                    bottom: systemBottom + barsHeight,
                    child: _AndroidPageSwiper(index: tab, children: pages),
                  ),
                ),
                if (!keyboardOpen)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: SafeArea(
                      top: false,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(
                          AndroidSpacing.sm,
                          0,
                          AndroidSpacing.sm,
                          // 底部留白比顶部宽一档：胶囊的投影要落在屏幕下沿之内，
                          // 压得太低只会剩下贴边那截最浓的灰。
                          AndroidSpacing.md,
                        ),
                        child: Center(
                          heightFactor: 1,
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(
                              maxWidth: AndroidSizes.sheetMaxWidth,
                            ),
                            child: AndroidBottomNav(
                              selectedIndex: tab,
                              onSelect: (value) => select(_androidIndex(value)),
                              onOpenPlayer: () => _openPlayer(context),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 首页与我的之间切换时给一段方向性的滑入淡入。
///
/// 页面本体仍由 [IndexedStack] 常驻，这里只动画最外层：切换不会重建页面，
/// 滚动位置和已加载的数据都保留，方向按索引增减判断。
class _AndroidPageSwiper extends StatefulWidget {
  const _AndroidPageSwiper({required this.index, required this.children});

  final int index;
  final List<Widget> children;

  @override
  State<_AndroidPageSwiper> createState() => _AndroidPageSwiperState();
}

class _AndroidPageSwiperState extends State<_AndroidPageSwiper>
    with SingleTickerProviderStateMixin {
  /// 位移按屏宽比例算，横屏和窄窗下的滑动幅度才一致。
  static const double _slideDistance = 0.055;

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: AndroidMotion.base,
    value: 1,
  );
  late final CurvedAnimation _curved = CurvedAnimation(
    parent: _controller,
    curve: AndroidMotion.standard,
  );
  final Tween<Offset> _slideTween = Tween<Offset>(begin: Offset.zero, end: Offset.zero);
  late final Animation<double> _fade = Tween<double>(
    begin: 0.45,
    end: 1,
  ).animate(_curved);
  late final Animation<Offset> _slide = _slideTween.animate(_curved);

  @override
  void didUpdateWidget(covariant _AndroidPageSwiper oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.index == widget.index) return;
    _slideTween.begin = widget.index > oldWidget.index
        ? const Offset(_slideDistance, 0)
        : const Offset(-_slideDistance, 0);
    _controller.forward(from: 0);
  }

  @override
  void dispose() {
    _curved.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fade,
      child: SlideTransition(
        position: _slide,
        child: IndexedStack(index: widget.index, children: widget.children),
      ),
    );
  }
}

class _SideBar extends StatelessWidget {
  const _SideBar({required this.selectedIndex, required this.onSelect});

  final int selectedIndex;
  final ValueChanged<int> onSelect;
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 248,
      decoration: BoxDecoration(
        border: Border(right: BorderSide(color: context.palette.line)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _Logo(),
            const SizedBox(height: 38),
            Padding(
              padding: const EdgeInsets.only(left: 12, bottom: 10),
              child: Text(
                '浏览',
                style: Theme.of(context).textTheme.labelMedium
                    ?.copyWith(color: context.palette.textMuted, letterSpacing: 1.4),
              ),
            ),
            _NavItem(
              icon: Icons.home_outlined,
              activeIcon: Icons.home_rounded,
              label: '首页',
              selected: selectedIndex == 0,
              onTap: () => onSelect(0),
            ),
            _NavItem(
              icon: Icons.search_rounded,
              activeIcon: Icons.manage_search_rounded,
              label: '搜索',
              selected: selectedIndex == 1,
              onTap: () => onSelect(1),
            ),
            _NavItem(
              icon: Icons.queue_music,
              activeIcon: Icons.queue_music,
              label: '歌单',
              selected: selectedIndex == 2,
              onTap: () => onSelect(2),
            ),
            _NavItem(
              icon: Icons.tune_rounded,
              activeIcon: Icons.tune_rounded,
              label: '设置',
              selected: selectedIndex == 3,
              onTap: () => onSelect(3),
            ),
            _NavItem(
              icon: Icons.info_outline_rounded,
              activeIcon: Icons.info_rounded,
              label: '关于',
              selected: selectedIndex == 4,
              onTap: () => onSelect(4),
            ),
            const Spacer(),
            const AccountSummaryCard(),
          ],
        ),
      ),
    );
  }
}

class _Logo extends StatelessWidget {
  const _Logo();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        BrandBadge(
          size: 48,
          radius: 16,
          shadow: [
            BoxShadow(
              color: context.palette.accent.withValues(alpha: 0.22),
              blurRadius: 14,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        const SizedBox(width: 14),
        Text(
          AppConstants.appName,
          style: Theme.of(context).textTheme.titleLarge
              ?.copyWith(fontSize: 20, letterSpacing: 0.2),
        ),
      ],
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final IconData activeIcon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Material(
        color: selected ? context.palette.accentSoft : Colors.transparent,
        borderRadius: BorderRadius.circular(13),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(13),
          hoverColor: context.palette.hover,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
            child: Row(
              children: [
                Icon(
                  selected ? activeIcon : icon,
                  size: 21,
                  color: selected
                      ? context.palette.accent
                      : context.palette.textSecondary,
                ),
                const SizedBox(width: 12),
                Text(
                  label,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: selected
                        ? context.palette.textPrimary
                        : context.palette.textSecondary,
                    fontSize: 13.5,
                  ),
                ),
                const Spacer(),
                if (selected)
                  Container(
                    width: 5,
                    height: 5,
                    decoration: BoxDecoration(
                      color: context.palette.accent,
                      shape: BoxShape.circle,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _BottomNav extends StatelessWidget {
  const _BottomNav({required this.selectedIndex, required this.onSelect});

  final int selectedIndex;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
      child: Material(
        color: context.palette.surfaceHigh.withValues(alpha: 0.96),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: context.palette.line),
        ),
        clipBehavior: Clip.antiAlias,
        child: SizedBox(
          height: 60,
          child: Row(
            children: [
              _BottomNavItem(
                icon: Icons.home_outlined,
                activeIcon: Icons.home_rounded,
                label: '首页',
                selected: selectedIndex == 0,
                onTap: () => onSelect(0),
              ),
              _BottomNavItem(
                icon: Icons.queue_music,
                activeIcon: Icons.queue_music,
                label: '歌单',
                selected: selectedIndex == 1,
                onTap: () => onSelect(1),
              ),
              _BottomNavItem(
                icon: Icons.person_outline_rounded,
                activeIcon: Icons.person_rounded,
                label: '我的',
                selected: selectedIndex == 2,
                onTap: () => onSelect(2),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BottomNavItem extends StatelessWidget {
  const _BottomNavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final IconData activeIcon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        child: Center(
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
            decoration: BoxDecoration(
              color: selected ? context.palette.accentSoft : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  selected ? activeIcon : icon,
                  size: 20,
                  color: selected ? context.palette.accent : context.palette.textMuted,
                ),
                AnimatedSize(
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOutCubic,
                  child: selected
                      ? Padding(
                          padding: const EdgeInsets.only(left: 6),
                          child: Text(
                            label,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: context.palette.accent,
                            ),
                          ),
                        )
                      : const SizedBox.shrink(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
