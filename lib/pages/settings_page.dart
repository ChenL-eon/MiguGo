import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../core/constants/app_constants.dart';
import '../core/navigation/app_shell_controller.dart';
import '../core/theme/android_tokens.dart';
import '../core/theme/app_colors.dart';
import '../core/utils/platform_kind.dart';
import '../models/audio_quality.dart';
import '../models/lyrics_style.dart';
import '../models/playback_mode.dart';
import '../models/player_background.dart';
import '../models/theme_accent.dart';
import '../providers/account_provider.dart';
import '../providers/desktop_lyrics_provider.dart';
import '../providers/player_provider.dart';
import '../providers/settings_provider.dart';
import '../services/platform/global_hotkeys.dart';
import '../services/platform/native_file_picker.dart';
import '../services/auth/session_probe_diagnostics.dart';
import '../widgets/account_center.dart';
import '../widgets/android/android_choice.dart';
import '../widgets/android/android_feedback.dart';
import '../widgets/secondary_page_frame.dart';

/// 设置页的分组导航：左侧一列，点开只渲染该组的设置。
enum _SettingsGroup {
  appearance(
    label: '外观',
    subtitle: '主题、强调色与背景光晕',
    icon: Icons.palette_outlined,
  ),
  playback(
    label: '播放与音效',
    subtitle: '模式、音质、倍速与睡眠定时',
    icon: Icons.graphic_eq_rounded,
  ),
  lyrics(
    label: '歌词与播放画面',
    subtitle: '歌词跟随、播放页画面与桌面歌词',
    icon: Icons.lyrics_outlined,
  ),
  shortcuts(
    label: '快捷键',
    subtitle: 'Windows 全局与窗口内控制',
    icon: Icons.keyboard_outlined,
  ),
  general(label: '通用', subtitle: '搜索历史与恢复默认设置', icon: Icons.tune_rounded),
  updates(label: '关于', subtitle: '版本信息与检查更新', icon: Icons.info_outline_rounded),
  account(
    label: '账户',
    subtitle: '登录状态与账号权益',
    icon: Icons.account_circle_outlined,
  );

  const _SettingsGroup({
    required this.label,
    required this.subtitle,
    required this.icon,
  });

  final String label;
  final String subtitle;
  final IconData icon;
}

/// 设置页：左栏分组导航 + 右侧设置卡片。
///
/// 宽窗口下是两栏；窄窗口与手机先显示分组菜单，点进去再显示该组设置。
/// 所有设置项都会立即生效并持久化到本机；不涉及任何音频下载或权限绕过。
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool _updatingGlobalHotkey = false;
  bool _resetting = false;
  bool _pickingBackground = false;
  int _seenLyricsFocusTick = 0;
  _SettingsGroup _group = _SettingsGroup.appearance;
  bool _narrowMenuOpen = true;

  void _showMessage(String message, {bool isError = false}) {
    if (!mounted) return;
    if (isAndroidPlatform) {
      showAndroidSnack(context, message, isError: isError);
      return;
    }
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(
                isError
                    ? Icons.error_outline_rounded
                    : Icons.check_circle_outline_rounded,
                size: 17,
                color: isError ? context.palette.danger : context.palette.mint,
              ),
              const SizedBox(width: 9),
              Expanded(child: Text(message)),
            ],
          ),
        ),
      );
  }

  String _fileName(String path) {
    final normalized = path.replaceAll(r'\', '/');
    final index = normalized.lastIndexOf('/');
    return index >= 0 && index < normalized.length - 1
        ? normalized.substring(index + 1)
        : path;
  }

  Future<void> _pickBackgroundImage(SettingsProvider settings) async {
    if (_pickingBackground) return;
    setState(() => _pickingBackground = true);
    try {
      final current = settings.playerBackgroundImage;
      final path = await NativeFilePicker.pickImage(
        initialDirectory: current == null ? null : File(current).parent.path,
      );
      if (path == null || !mounted) return;
      if (!File(path).existsSync()) {
        _showMessage('图片已不可访问，请重新选择。', isError: true);
        return;
      }
      await settings.setPlayerBackgroundImage(path);
      if (!mounted) return;
      _showMessage('已更新播放页背景。');
    } finally {
      if (mounted) setState(() => _pickingBackground = false);
    }
  }

  String _formatRemaining(Duration duration) {
    final seconds = duration.inSeconds.clamp(0, 24 * 3600);
    final minutes = (seconds ~/ 60).toString().padLeft(2, '0');
    final rest = (seconds % 60).toString().padLeft(2, '0');
    return '$minutes:$rest';
  }

  String _formatSpeed(double speed) {
    final text = speed == speed.roundToDouble()
        ? speed.toStringAsFixed(0)
        : speed.toString();
    return '$text×';
  }

  Future<void> _toggleGlobalHotkey(bool enabled) async {
    final hotkeys = context.read<GlobalHotkeyService>();
    setState(() => _updatingGlobalHotkey = true);
    try {
      await hotkeys.setBareSpaceEnabled(enabled);
      if (!mounted) return;
      _showMessage(enabled ? '已启用空格键全局播放 / 暂停。它会拦截其他应用的空格输入。' : '已关闭空格键全局快捷键。');
    } catch (error) {
      if (!mounted) return;
      final message = error is StateError
          ? error.message.toString()
          : '快捷键注册失败，可能已被其他程序占用。';
      _showMessage(message, isError: true);
    } finally {
      if (mounted) setState(() => _updatingGlobalHotkey = false);
    }
  }

  Future<void> _resetToDefaults() async {
    const resetHint =
        '将把主题、播放、歌词、快捷键与搜索记录开关恢复到默认值。'
        '已导入的登录 Cookie 与搜索历史会保留。';
    final confirmed = isAndroidPlatform
        ? await showAndroidConfirm(
            context,
            title: '恢复默认设置？',
            message: resetHint,
            confirmLabel: '恢复默认',
            icon: Icons.tune_rounded,
          )
        : await showDialog<bool>(
            context: context,
            builder: (dialogContext) {
              return AlertDialog(
                backgroundColor: context.palette.surfaceHigh,
                surfaceTintColor: Colors.transparent,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(22),
                  side: BorderSide(color: context.palette.line),
                ),
                title: const Text('恢复默认设置？'),
                content: Text(
                  resetHint,
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.7,
                    color: context.palette.textSecondary,
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(dialogContext).pop(false),
                    child: const Text('取消'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.of(dialogContext).pop(true),
                    child: const Text('恢复默认'),
                  ),
                ],
              );
            },
          );
    if (confirmed != true || !mounted) return;

    setState(() => _resetting = true);
    try {
      final settings = context.read<SettingsProvider>();
      final player = context.read<PlayerProvider>();
      final hotkeys = context.read<GlobalHotkeyService>();

      player.setSleepTimer(null);
      if (Platform.isWindows) {
        await hotkeys.setBareSpaceEnabled(false);
      }
      await settings.resetToDefaults();
      await player.setPlaybackMode(PlaybackMode.listLoop);
      await player.setSpeed(1);
      if ((player.volume - 1).abs() > 0.001) {
        await player.setVolume(1);
      }
      if (!mounted) return;
      _showMessage('已恢复默认设置，登录 Cookie 与搜索历史保持不变。');
    } catch (error) {
      if (!mounted) return;
      _showMessage('恢复默认设置失败：$error', isError: true);
    } finally {
      if (mounted) setState(() => _resetting = false);
    }
  }

  Future<void> _toggleDesktopLyrics() async {
    final lyrics = context.read<DesktopLyricsProvider>();
    await lyrics.toggle();
    if (!mounted) return;
    final error = lyrics.error;
    if (error != null) {
      _showMessage(error, isError: true);
    }
  }

  Future<void> _copyProbeLog() async {
    final text = await SessionProbeDiagnostics.instance.exportText();
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    _showMessage('登录探测记录已复制，可直接粘贴发送。');
  }

  /// 当场用留存票据再换一次。自动续期已经摘掉（票据在登录那一次就被消耗，
  /// 换不来第二份会话），这里是唯一的复测入口：刚登录完点一下，能把它一次性钉死。
  void _debugRenewNow() {
    final result = context.read<AccountProvider>().debugRenewNow();
    _showMessage('$result，稍等再点「复制记录」看 renewal 那行。');
  }

  Future<void> _clearProbeLog() async {
    await SessionProbeDiagnostics.instance.clear();
    if (!mounted) return;
    _showMessage('登录探测记录已清空。');
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    final player = context.watch<PlayerProvider>();
    final lyricsMode = context.watch<DesktopLyricsProvider>();
    final isWindows = Platform.isWindows;

    // 浮层控制条的"设置"按钮靠这个自增计数直接切到桌面歌词分组。
    final lyricsFocusTick = context.select<AppShellController, int>(
      (controller) => controller.desktopLyricsFocusTick,
    );
    if (lyricsFocusTick != _seenLyricsFocusTick) {
      _seenLyricsFocusTick = lyricsFocusTick;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() {
          _group = _SettingsGroup.lyrics;
          _narrowMenuOpen = false;
        });
      });
    }

    // 桌面端左栏已经有专门的「关于」页，设置里不再重复一个分组；
    // 手机端没有那个入口，设置里的「关于」保持原样。
    final groups = [
      for (final group in _SettingsGroup.values)
        if (group != _SettingsGroup.shortcuts || isWindows)
          if (group != _SettingsGroup.updates || isAndroidPlatform) group,
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final android = isAndroidPlatform;
        final wide = !android && constraints.maxWidth >= 880;
        if (wide) {
          // 整页收进一张圆角大卡：左栏导航与右栏内容共用同一层底板，
          // 卡片的边线和中缝的分割线都不画，靠左右两块的底色差分层。
          final palette = context.palette;
          final radius = BorderRadius.circular(26);
          return Padding(
            padding: const EdgeInsets.fromLTRB(20, 2, 20, 20),
            child: Container(
              decoration: BoxDecoration(
                color: palette.surface,
                borderRadius: radius,
              ),
              child: ClipRRect(
                borderRadius: radius,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(width: 268, child: _buildRail(context, groups)),
                    Expanded(
                      child: _buildGroupContent(
                        context,
                        settings,
                        player,
                        lyricsMode,
                        android: false,
                        withBack: false,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }
        if (!_narrowMenuOpen) {
          return PopScope(
            canPop: false,
            onPopInvokedWithResult: (didPop, _) {
              if (didPop) return;
              setState(() => _narrowMenuOpen = true);
            },
            child: _buildGroupContent(
              context,
              settings,
              player,
              lyricsMode,
              android: android,
              withBack: true,
            ),
          );
        }
        return _buildMenu(context, groups, android: android);
      },
    );
  }

  Widget _buildRail(BuildContext context, List<_SettingsGroup> groups) {
    final palette = context.palette;
    return Container(
      color: palette.surfaceSoft.withValues(alpha: 0.45),
      padding: const EdgeInsets.fromLTRB(20, 26, 16, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '设置',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 24,
                    height: 1.16,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.5,
                    color: palette.textPrimary,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '个性化你的播放器',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12.5, color: palette.textMuted),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Expanded(
            child: Scrollbar(
              child: SingleChildScrollView(
                child: _SettingsNavList(
                  groups: groups,
                  selected: _group,
                  onSelect: (group) => setState(() => _group = group),
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.only(left: 8),
            child: Text(
              '所有改动即时生效并保存在本机',
              style: TextStyle(fontSize: 10.5, color: palette.textMuted),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMenu(
    BuildContext context,
    List<_SettingsGroup> groups, {
    required bool android,
  }) {
    final padding = android ? AndroidSpacing.md : 24.0;
    return Scrollbar(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          padding,
          android ? AndroidSpacing.xs : 26,
          padding,
          android ? AndroidSpacing.xl : 36,
        ),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 手机端的标题与副标题已经在二级页顶栏里，不再重复一遍。
                if (!android) ...[
                  Text(
                    '设置',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 26,
                      height: 1.16,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.6,
                      color: context.palette.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '个性化你的播放器',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12.5,
                      color: context.palette.textMuted,
                    ),
                  ),
                  const SizedBox(height: 22),
                ],
                for (final group in groups)
                  _SettingsNavTile(
                    group: group,
                    selected: false,
                    onTap: () => setState(() {
                      _group = group;
                      _narrowMenuOpen = false;
                    }),
                  ),
                const SizedBox(height: 12),
                Text(
                  '所有改动即时生效并保存在本机',
                  style: TextStyle(
                    fontSize: 10.5,
                    color: context.palette.textMuted,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildGroupContent(
    BuildContext context,
    SettingsProvider settings,
    PlayerProvider player,
    DesktopLyricsProvider lyricsMode, {
    required bool android,
    required bool withBack,
  }) {
    final group = _group;
    final padding = android ? AndroidSpacing.md : (withBack ? 24.0 : 34.0);
    return Scrollbar(
      child: SingleChildScrollView(
        key: ValueKey(group),
        padding: EdgeInsets.fromLTRB(
          padding,
          android ? AndroidSpacing.xs : (withBack ? 10 : 26),
          padding,
          android ? AndroidSpacing.xl : 36,
        ),
        child: Align(
          // 宽屏右栏靠左上排布，窗口再宽也只是留白变多，内容不会飘到中间。
          alignment: withBack ? Alignment.topCenter : Alignment.topLeft,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (withBack)
                  _buildDrillHeader(context, group)
                else
                  _buildGroupHeader(context, group),
                const SizedBox(height: 18),
                ..._buildGroupSections(context, settings, player, lyricsMode),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildGroupHeader(BuildContext context, _SettingsGroup group) {
    final palette = context.palette;
    return Row(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: palette.accentSoft,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(group.icon, size: 22, color: palette.accent),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                group.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 22,
                  height: 1.18,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.4,
                  color: palette.textPrimary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                group.subtitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12.5,
                  height: 1.45,
                  color: palette.textMuted,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDrillHeader(BuildContext context, _SettingsGroup group) {
    final palette = context.palette;
    return Row(
      children: [
        IconButton(
          onPressed: () => setState(() => _narrowMenuOpen = true),
          tooltip: '返回设置',
          style: IconButton.styleFrom(
            backgroundColor: palette.fill,
            foregroundColor: palette.textPrimary,
            fixedSize: const Size(40, 40),
            side: BorderSide(color: palette.line),
          ),
          icon: const Icon(Icons.arrow_back_rounded, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                group.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 20,
                  height: 1.2,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.3,
                  color: palette.textPrimary,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                group.subtitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11.5,
                  height: 1.45,
                  color: palette.textMuted,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  List<Widget> _buildGroupSections(
    BuildContext context,
    SettingsProvider settings,
    PlayerProvider player,
    DesktopLyricsProvider lyricsMode,
  ) {
    return switch (_group) {
      _SettingsGroup.appearance => _buildAppearance(settings),
      _SettingsGroup.playback => _buildPlayback(settings, player),
      _SettingsGroup.lyrics => _buildLyrics(settings, lyricsMode),
      _SettingsGroup.shortcuts => _buildShortcuts(settings),
      _SettingsGroup.general => _buildGeneral(context, settings),
      _SettingsGroup.updates => _buildUpdates(context),
      _SettingsGroup.account => _buildAccount(context, settings),
    };
  }

  List<Widget> _buildAppearance(SettingsProvider settings) {
    return [
      _SettingsCard(
        label: '主题与强调色',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SettingsRow(
              title: '主题模式',
              description: '浅色、深色或跟随 Windows / Android 系统设置。',
              control: _OptionDropdown<ThemeMode>(
                sheetTitle: '主题模式',
                value: settings.themeMode,
                entries: const [
                  _OptionEntry(
                    ThemeMode.light,
                    '浅色',
                    icon: Icons.light_mode_outlined,
                  ),
                  _OptionEntry(
                    ThemeMode.dark,
                    '深色',
                    icon: Icons.dark_mode_outlined,
                  ),
                  _OptionEntry(
                    ThemeMode.system,
                    '跟随系统',
                    icon: Icons.brightness_auto_rounded,
                  ),
                ],
                onChanged: (mode) => unawaited(settings.setThemeMode(mode)),
              ),
            ),
            const _SettingsDivider(),
            _SettingsRow(
              title: '主题色',
              description: '选择界面的强调色，默认玫粉；只改颜色，不动明暗模式。',
              control: _OptionDropdown<ThemeAccent>(
                sheetTitle: '主题色',
                value: settings.themeAccent,
                entries: [
                  for (final accent in ThemeAccent.values)
                    _OptionEntry(
                      accent,
                      accent.label,
                      swatch: accent.accentFor(Theme.of(context).brightness),
                    ),
                ],
                onChanged: (accent) =>
                    unawaited(settings.setThemeAccent(accent)),
              ),
            ),
            const _SettingsDivider(),
            _SettingsRow(
              title: '环境光晕',
              description: '在背景中显示柔和的品牌色光晕，关闭后界面更纯净。',
              control: Switch.adaptive(
                value: settings.ambientGlowEnabled,
                onChanged: (value) =>
                    unawaited(settings.setAmbientGlowEnabled(value)),
              ),
            ),
          ],
        ),
      ),
    ];
  }

  List<Widget> _buildPlayback(
    SettingsProvider settings,
    PlayerProvider player,
  ) {
    return [
      _SettingsCard(
        label: '播放',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SettingsRow(
              title: '播放模式',
              description: '打开应用时使用的默认模式，也会同步到播放页。',
              control: _OptionDropdown<PlaybackMode>(
                sheetTitle: '播放模式',
                value: player.mode,
                entries: const [
                  _OptionEntry(
                    PlaybackMode.listLoop,
                    '列表循环',
                    icon: Icons.repeat_rounded,
                  ),
                  _OptionEntry(
                    PlaybackMode.singleLoop,
                    '单曲循环',
                    icon: Icons.repeat_one_rounded,
                  ),
                  _OptionEntry(
                    PlaybackMode.shuffle,
                    '随机',
                    icon: Icons.shuffle_rounded,
                  ),
                ],
                onChanged: (mode) => unawaited(player.setPlaybackMode(mode)),
              ),
            ),
            const _SettingsDivider(),
            _SettingsRow(
              title: '播放音质',
              description:
                  '优先请求所选音质（${settings.audioQuality.detail}），'
                  '至臻 24bit 需曲目提供且账号有对应权益；'
                  '账号没有该音质权益时自动回退到可用档位，实际音质由咪咕发放。',
              control: _OptionDropdown<AudioQuality>(
                sheetTitle: '播放音质',
                value: settings.audioQuality,
                width: 132,
                entries: const [
                  _OptionEntry(AudioQuality.pq, '标准'),
                  _OptionEntry(AudioQuality.hq, '高品质'),
                  _OptionEntry(AudioQuality.sq, '无损'),
                  _OptionEntry(AudioQuality.zq24, '至臻'),
                ],
                onChanged: (quality) {
                  unawaited(settings.setAudioQuality(quality));
                  _showMessage('播放音质已设为${quality.label}，下一首开始按新音质请求。');
                },
              ),
            ),
            const _SettingsDivider(),
            _SettingsRow(
              title: '播放倍速',
              description: '默认 1.0×；变速只影响本机播放，不改变音质。',
              control: _OptionDropdown<double>(
                sheetTitle: '播放倍速',
                value: player.speed,
                width: 120,
                entries: [
                  for (final speed in SettingsProvider.playbackSpeedOptions)
                    _OptionEntry(speed, _formatSpeed(speed)),
                ],
                onChanged: (speed) => unawaited(player.setSpeed(speed)),
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 18),
      _SettingsCard(
        label: '音量与定时',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SettingsRow(
              title: '记住上次音量',
              description: '关闭后不再保存音量，下次启动恢复为 100%。',
              control: Switch.adaptive(
                value: settings.rememberVolume,
                onChanged: (value) =>
                    unawaited(settings.setRememberVolume(value)),
              ),
            ),
            const _SettingsDivider(),
            _SettingsRow(
              title: '睡眠定时',
              description: player.hasSleepTimer
                  ? '将在 ${_formatRemaining(player.sleepRemaining ?? Duration.zero)} 后暂停播放。'
                  : '到时间后自动暂停，适合睡前听歌。',
              control: _OptionDropdown<Duration?>(
                sheetTitle: '睡眠定时',
                value: player.hasSleepTimer ? player.sleepDuration : null,
                width: 132,
                entries: [
                  for (final option in PlayerProvider.sleepTimerOptions)
                    _OptionEntry(option.delay, option.label),
                ],
                onChanged: (delay) {
                  player.setSleepTimer(delay);
                  if (delay == null) {
                    _showMessage('已关闭睡眠定时。');
                  } else {
                    final label = PlayerProvider.sleepTimerOptions
                        .firstWhere((option) => option.delay == delay)
                        .label;
                    _showMessage('已设置 $label 睡眠定时，到时将自动暂停。');
                  }
                },
              ),
            ),
          ],
        ),
      ),
    ];
  }

  List<Widget> _buildLyrics(
    SettingsProvider settings,
    DesktopLyricsProvider lyricsMode,
  ) {
    final isWindows = Platform.isWindows;
    return [
      _SettingsCard(
        label: '歌词',
        child: _SettingsRow(
          title: '歌词自动滚动',
          description: '关闭后歌词停在当前位置，点按任意歌词仍可跳转播放。',
          control: Switch.adaptive(
            value: settings.lyricsAutoScrollEnabled,
            onChanged: (value) =>
                unawaited(settings.setLyricsAutoScrollEnabled(value)),
          ),
        ),
      ),
      const SizedBox(height: 18),
      _SettingsCard(
        label: '播放页画面',
        description: '播放页整屏背景只在本机显示，不会上传或保存音频文件。',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SettingsRow(
              title: '播放页背景',
              description: '打开播放页时显示的背景来源。',
              control: _OptionDropdown<PlayerBackground>(
                sheetTitle: '播放页背景',
                value: settings.playerBackground,
                width: 138,
                entries: [
                  for (final option in PlayerBackground.values)
                    _OptionEntry(option, option.label),
                ],
                onChanged: (value) =>
                    unawaited(settings.setPlayerBackground(value)),
              ),
            ),
            const _SettingsDivider(),
            _SettingsRow(
              title: '背景模糊',
              description: '数值越大越柔和，0 为不模糊。',
              control: _LyricsSlider(
                value: settings.playerBackgroundBlur,
                min: SettingsProvider.minPlayerBackgroundBlur,
                max: SettingsProvider.maxPlayerBackgroundBlur,
                suffix: 'px',
                onChanged: (value) =>
                    unawaited(settings.setPlayerBackgroundBlur(value)),
              ),
            ),
            if (settings.playerBackground == PlayerBackground.custom) ...[
              const _SettingsDivider(),
              _SettingsRow(
                title: '自定义图片',
                description: settings.playerBackgroundImage == null
                    ? '还没有选择图片，播放页暂时继续显示歌曲封面。'
                    : _fileName(settings.playerBackgroundImage!),
                control: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (settings.playerBackgroundImage != null)
                      TextButton(
                        onPressed: () {
                          unawaited(settings.setPlayerBackgroundImage(null));
                          _showMessage('已清除自定义背景。');
                        },
                        child: const Text('清除'),
                      ),
                    if (NativeFilePicker.supportsImagePicker)
                      TextButton.icon(
                        onPressed: _pickingBackground
                            ? null
                            : () => unawaited(_pickBackgroundImage(settings)),
                        icon: const Icon(Icons.image_outlined, size: 16),
                        label: const Text('选择图片'),
                      ),
                  ],
                ),
              ),
              if (settings.playerBackgroundImage != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 18),
                  child: _BackgroundPreview(
                    path: settings.playerBackgroundImage!,
                  ),
                ),
            ],
          ],
        ),
      ),
      if (isWindows) ...[
        const SizedBox(height: 18),
        _SettingsCard(
          label: '桌面歌词',
          description: '独立置顶浮层，不占用主窗口。',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _SettingsRow(
                title: '歌词行数',
                description: '双行显示当前句与下一句；单行只显示当前句。',
                control: _OptionDropdown<bool>(
                  value: settings.desktopLyricsDoubleLine,
                  width: 120,
                  entries: const [
                    _OptionEntry(false, '单行', icon: Icons.notes_rounded),
                    _OptionEntry(true, '双行', icon: Icons.view_stream_rounded),
                  ],
                  onChanged: (doubleLine) => unawaited(
                    settings.setDesktopLyricsDoubleLine(doubleLine),
                  ),
                ),
              ),
              const _SettingsDivider(),
              _SettingsRow(
                title: '已播放颜色',
                description: '当前句逐字推进时，读过的部分用这个颜色。',
                control: _OptionDropdown<DesktopLyricsColor>(
                  value: settings.desktopLyricsColor,
                  width: 132,
                  entries: [
                    for (final color in DesktopLyricsColor.values)
                      _OptionEntry(color, color.label, swatch: color.color),
                  ],
                  onChanged: (color) =>
                      unawaited(settings.setDesktopLyricsColor(color)),
                ),
              ),
              const _SettingsDivider(),
              _SettingsRow(
                title: '未播放颜色',
                description: '当前句还没唱到的部分与第二行歌词用这个颜色。',
                control: _OptionDropdown<DesktopLyricsColor>(
                  value: settings.desktopLyricsUnplayedColor,
                  width: 132,
                  entries: [
                    for (final color in DesktopLyricsColor.values)
                      _OptionEntry(color, color.label, swatch: color.color),
                  ],
                  onChanged: (color) =>
                      unawaited(settings.setDesktopLyricsUnplayedColor(color)),
                ),
              ),
              const _SettingsDivider(),
              _SettingsRow(
                title: '描边颜色',
                description: '默认不描边；桌面偏浅、歌词看不清时再选一个描边色。',
                control: _OptionDropdown<DesktopLyricsStroke>(
                  value: settings.desktopLyricsStroke,
                  width: 132,
                  entries: [
                    for (final stroke in DesktopLyricsStroke.values)
                      _OptionEntry(
                        stroke,
                        stroke.label,
                        swatch: stroke.color,
                        icon: Icons.block_rounded,
                      ),
                  ],
                  onChanged: (stroke) =>
                      unawaited(settings.setDesktopLyricsStroke(stroke)),
                ),
              ),
              const _SettingsDivider(),
              _SettingsRow(
                title: '歌词字号',
                description: '单位 pt，浮层控制条上的 A- / A+ 会同步调整这里。',
                control: _LyricsSlider(
                  value: settings.desktopLyricsFontPt,
                  min: SettingsProvider.minDesktopLyricsFontPt,
                  max: SettingsProvider.maxDesktopLyricsFontPt,
                  step: 2,
                  suffix: 'pt',
                  onChanged: (value) =>
                      unawaited(settings.setDesktopLyricsFontPt(value)),
                ),
              ),
              const _SettingsDivider(),
              _SettingsRow(
                title: '底板浓度',
                description: '浮层自带半透明底板，调到 0 即为纯描边文字，桌面完全透出。',
                control: _LyricsSlider(
                  value: settings.desktopLyricsPanelAlpha,
                  min: 0,
                  max: SettingsProvider.maxDesktopLyricsPanelAlpha,
                  step: 10,
                  onChanged: (value) =>
                      unawaited(settings.setDesktopLyricsPanelAlpha(value)),
                ),
              ),
              const _SettingsDivider(),
              _SettingsRow(
                title: '窗口层级',
                description: '置顶始终盖住其他窗口；置下贴到桌面层，只在最前面保留歌词。',
                control: _OptionDropdown<bool>(
                  value: settings.desktopLyricsTopmost,
                  width: 120,
                  entries: const [
                    _OptionEntry(true, '置顶'),
                    _OptionEntry(false, '置下'),
                  ],
                  onChanged: (topmost) =>
                      unawaited(settings.setDesktopLyricsTopmost(topmost)),
                ),
              ),
              const _SettingsDivider(),
              _SettingsRow(
                title: '锁定浮层',
                description:
                    '锁定后不能拖动，歌词区域的点击会穿透到下面的窗口；把鼠标移到歌词那一行上方会浮出控制条，随时能解锁。',
                control: Switch(
                  value: settings.desktopLyricsLocked,
                  onChanged: (value) =>
                      unawaited(settings.setDesktopLyricsLocked(value)),
                ),
              ),
              const _SettingsDivider(),
              _SettingsRow(
                title: '桌面歌词浮层',
                description:
                    '独立于主窗口的置顶歌词条：拖动移动，双击切换播放 / 暂停，鼠标悬停时浮出控制条，可切层级、字号、锁定与播放。',
                control: FilledButton.icon(
                  onPressed: lyricsMode.busy
                      ? null
                      : () => unawaited(_toggleDesktopLyrics()),
                  icon: Icon(
                    lyricsMode.enabled
                        ? Icons.close_fullscreen_rounded
                        : Icons.open_in_full_rounded,
                    size: 17,
                  ),
                  label: Text(lyricsMode.enabled ? '退出桌面歌词' : '开启桌面歌词'),
                ),
              ),
            ],
          ),
        ),
      ],
    ];
  }

  List<Widget> _buildShortcuts(SettingsProvider settings) {
    return [
      _SettingsCard(
        label: '空格键',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SettingsRow(
              title: '应用内空格播放 / 暂停',
              description: '仅在应用窗口内生效；输入框聚焦时会自动让位。',
              control: Switch.adaptive(
                value: settings.inAppSpaceShortcutEnabled,
                onChanged: (value) =>
                    unawaited(settings.setInAppSpaceShortcutEnabled(value)),
              ),
            ),
            const _SettingsDivider(),
            _SettingsRow(
              title: '空格键全局播放 / 暂停',
              description:
                  '默认关闭。开启后会拦截所有应用的裸空格，'
                  '仅在把本应用当作后台播放器时使用。',
              control: _updatingGlobalHotkey
                  ? const Padding(
                      padding: EdgeInsets.only(right: 12),
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : Switch.adaptive(
                      value: settings.globalSpaceHotkeyEnabled,
                      onChanged: (value) =>
                          unawaited(_toggleGlobalHotkey(value)),
                    ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 18),
      _SettingsCard(
        label: '组合键',
        child: const _SettingsCardPad(
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _ShortcutHint(label: '上一首', keys: 'Ctrl + Alt + ←'),
              _ShortcutHint(label: '播放 / 暂停', keys: 'Ctrl + Alt + 空格'),
              _ShortcutHint(label: '下一首', keys: 'Ctrl + Alt + →'),
            ],
          ),
        ),
      ),
    ];
  }

  List<Widget> _buildGeneral(BuildContext context, SettingsProvider settings) {
    return [
      _SettingsCard(
        label: '搜索',
        description: '搜索历史只保存在本机。',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SettingsRow(
              title: '记录搜索历史',
              description: '在搜索页显示最近 10 条关键词，便于再次搜索。',
              control: Switch.adaptive(
                value: settings.recordSearchHistoryEnabled,
                onChanged: (value) =>
                    unawaited(settings.setRecordSearchHistoryEnabled(value)),
              ),
            ),
            if (settings.searchHistory.isNotEmpty) ...[
              const _SettingsDivider(),
              _SettingsRow(
                title: '已记录 ${settings.searchHistory.length} 条搜索历史',
                description: '清空只删除本机关键词，不影响登录与歌单。',
                control: TextButton.icon(
                  onPressed: () {
                    unawaited(settings.clearSearchHistory());
                    _showMessage('已清空搜索历史。');
                  },
                  icon: const Icon(Icons.delete_outline_rounded, size: 16),
                  label: const Text('清空历史'),
                ),
              ),
            ],
          ],
        ),
      ),
      const SizedBox(height: 18),
      _SettingsCard(
        label: '重置',
        child: _SettingsRow(
          title: '恢复默认设置',
          description:
              '主题、播放、歌词、快捷键与搜索记录开关回到默认值；'
              '已导入的登录凭据与搜索历史保留。',
          control: OutlinedButton.icon(
            onPressed: _resetting ? null : () => unawaited(_resetToDefaults()),
            icon: _resetting
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.restart_alt_rounded, size: 17),
            label: const Text('恢复默认'),
          ),
        ),
      ),
    ];
  }

  List<Widget> _buildUpdates(BuildContext context) {
    return [
      _SettingsCard(
        label: '版本',
        child: _SettingsRow(
          title: '当前版本',
          description: '${AppConstants.appName} · v${AppConstants.appVersion}',
          control: OutlinedButton.icon(
            onPressed: () => openAboutPage(context),
            icon: const Icon(Icons.info_outline_rounded, size: 17),
            label: const Text('查看关于页'),
          ),
        ),
      ),
    ];
  }

  List<Widget> _buildAccount(BuildContext context, SettingsProvider settings) {
    return [
      const AccountSummaryCard(),
      const SizedBox(height: 18),
      _SettingsCard(
        label: '登录与权益',
        child: _SettingsCardPad(
          child: Text(
            '登录凭据只保存在本机；退出登录会清除凭据与账号快照，'
            '不改动设置与歌单。',
            style: TextStyle(
              fontSize: 12.5,
              height: 1.7,
              color: context.palette.textSecondary,
            ),
          ),
        ),
      ),
      // 只有 Windows 做：安卓没有托盘，后台进程随时被系统回收，
      // 等价能力要另做前台服务，不能靠这个开关顺手承诺。
      if (Platform.isWindows) ...[
        const SizedBox(height: 18),
        _SettingsCard(
          label: '后台保持登录',
          description: '咪咕给每份登录凭据的有效期只有约两小时，'
              '要靠应用按时问一次服务端来续。应用一退，就没人再问了。',
          child: _SettingsRow(
            title: '关闭主窗口后常驻托盘',
            description:
                '开启后点窗口上的关闭只是把窗口藏起来，进程留着，'
                '每 45–75 分钟带本机凭据向咪咕查一次登录状态；收起窗口时会顺手暂停播放。'
                '双击托盘图标回到主界面，托盘菜单里的「退出」才停止保活并结束进程。',
            control: Switch.adaptive(
              value: settings.backgroundKeepAliveEnabled,
              onChanged: (value) =>
                  unawaited(settings.setBackgroundKeepAliveEnabled(value)),
            ),
          ),
        ),
      ],
      if (kDebugMode) ...[
        const SizedBox(height: 18),
        _SettingsCard(
          label: '登录探测记录（调试）',
          description:
              '看 checkPacMtoken 轮换有没有把会话一直续住：启动与保活每次探测记一条，'
              '开了常驻托盘后藏在后台的那几次也照样记（trigger 都是 keep-alive，'
              '分不出前台还是后台，只能对着时间看），'
              '保留最近 ${SessionProbeDiagnostics.instance.maxEntries} 条，'
              '只记返回码、是否轮换与 Cookie 过期时间，不含凭据内容；正式版不记录。'
              '「试一次续期」当场用留存票据再换一次：这张票登录时已经被咪咕消耗，'
              '自动续期因此摘掉了，按钮留着复测这个结论，一次会写两行（发起与结果）。',
          child: _SettingsCardPad(
            child: Wrap(
              spacing: 10,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: _debugRenewNow,
                  icon: const Icon(Icons.sync_rounded, size: 17),
                  label: const Text('试一次续期'),
                ),
                OutlinedButton.icon(
                  onPressed: () => unawaited(_copyProbeLog()),
                  icon: const Icon(Icons.copy_all_outlined, size: 17),
                  label: const Text('复制记录'),
                ),
                TextButton.icon(
                  onPressed: () => unawaited(_clearProbeLog()),
                  icon: const Icon(Icons.delete_outline_rounded, size: 17),
                  label: const Text('清空记录'),
                ),
              ],
            ),
          ),
        ),
      ],
    ];
  }
}

/// 左栏导航列表：选中底色只有一枚，直接落在当前项上。
///
/// 不做位移动画：滑块在列表上跑一趟，跑过的每一行都像多出一块亮底，
/// 而鼠标正悬停着要点的那一行本身也有按下前的亮底，两块叠在一起最明显。
/// 逐项各自淡入淡出也不行，旧项没退干净、新项已亮起，连点时同样两块同亮。
class _SettingsNavList extends StatelessWidget {
  const _SettingsNavList({
    required this.groups,
    required this.selected,
    required this.onSelect,
  });

  static const double _tileHeight = 46;
  static const double _tileGap = 6;
  static const double _stride = _tileHeight + _tileGap;

  final List<_SettingsGroup> groups;
  final _SettingsGroup selected;
  final ValueChanged<_SettingsGroup> onSelect;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final index = groups.indexOf(selected);
    return Stack(
      children: [
        if (index >= 0)
          Positioned(
            key: const ValueKey('settings-nav-selection'),
            left: 0,
            right: 0,
            top: index * _stride,
            height: _tileHeight,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: palette.surfaceHigh,
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final group in groups)
              _SettingsNavTile(
                group: group,
                selected: group == selected,
                onTap: () => onSelect(group),
              ),
          ],
        ),
      ],
    );
  }
}

/// 分组导航的一项：选中与否只看这枚底色、图标强调色与字重，自身不画底色。
class _SettingsNavTile extends StatelessWidget {
  const _SettingsNavTile({
    required this.group,
    required this.selected,
    required this.onTap,
  });

  final _SettingsGroup group;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final radius = BorderRadius.circular(14);
    final android = isAndroidPlatform;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: Colors.transparent,
        borderRadius: radius,
        child: InkWell(
          onTap: onTap,
          borderRadius: radius,
          // 选中项已经有底色了，再叠一层悬停亮底就成了两块。
          hoverColor: selected ? Colors.transparent : palette.hover,
          // 桌面端不铺水波纹：一圈灰色涟漪绽在选中底色上，看着就是第二块亮底，
          // 淡出的那半秒还像拖影。手机端保留 Material 的按下反馈。
          splashFactory: android ? null : NoSplash.splashFactory,
          highlightColor: android ? null : Colors.transparent,
          child: SizedBox(
            height: 46,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 13),
              child: Row(
                children: [
                  SizedBox(
                    width: 22,
                    child: Icon(
                      group.icon,
                      size: 19,
                      color: selected ? palette.accent : palette.textMuted,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      group.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: selected
                            ? FontWeight.w700
                            : FontWeight.w500,
                        color: selected
                            ? palette.textPrimary
                            : palette.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 设置页的离散选项选择器：外框显示当前档位，点开菜单换档。
///
/// Android 上不弹桌面式悬浮菜单，改为打开手机习惯的单选底部面板。
class _OptionDropdown<T> extends StatelessWidget {
  const _OptionDropdown({
    required this.value,
    required this.entries,
    required this.onChanged,
    this.width = 158,
    this.sheetTitle,
  });

  final T value;
  final List<_OptionEntry<T>> entries;
  final ValueChanged<T> onChanged;
  final double width;

  /// Android 单选面板的标题；缺省用「请选择」。
  final String? sheetTitle;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    // 存档里的值可能因版本升级而不在候选内，退回第一项避免断言。
    final current = entries.any((entry) => entry.value == value)
        ? value
        : entries.first.value;
    final currentEntry = entries.firstWhere((entry) => entry.value == current);
    if (isAndroidPlatform) {
      final radius = BorderRadius.circular(AndroidRadius.sm);
      return SizedBox(
        width: width,
        child: Material(
          color: palette.surfaceHigh,
          borderRadius: radius,
          child: InkWell(
            onTap: () => unawaited(_openAndroidSheet(context, current)),
            borderRadius: radius,
            child: Container(
              constraints: const BoxConstraints(minHeight: AndroidSizes.touch),
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                borderRadius: radius,
                border: Border.all(color: palette.line),
              ),
              child: _label(currentEntry, palette: palette, chevron: true),
            ),
          ),
        ),
      );
    }
    return Container(
      width: width,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: palette.surfaceHigh,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: palette.line),
      ),
      child: DropdownButton<T>(
        value: current,
        isExpanded: true,
        isDense: true,
        underline: const SizedBox.shrink(),
        borderRadius: BorderRadius.circular(14),
        dropdownColor: palette.surfaceHigh,
        menuMaxHeight: 320,
        // 箭头画进按钮本体，整块区域都还能点开。
        icon: const SizedBox.shrink(),
        style: TextStyle(fontSize: 12, color: palette.textPrimary),
        selectedItemBuilder: (context) => [
          for (final entry in entries) _label(entry, palette: palette, chevron: true),
        ],
        items: [
          for (final entry in entries)
            DropdownMenuItem<T>(
              value: entry.value,
              child: _label(entry, palette: palette),
            ),
        ],
        onChanged: (next) {
          if (next != null) onChanged(next);
        },
      ),
    );
  }

  Future<void> _openAndroidSheet(BuildContext context, T current) {
    return showAndroidChoiceSheet<T>(
      context,
      title: sheetTitle ?? '请选择',
      options: [
        for (final entry in entries)
          AndroidChoiceOption(
            value: entry.value,
            label: entry.label,
            icon: entry.icon,
            swatch: entry.swatch,
          ),
      ],
      selected: current,
      onSelected: onChanged,
    );
  }

  Widget _label(
    _OptionEntry<T> entry, {
    required AppPalette palette,
    bool chevron = false,
  }) {
    return Row(
      children: [
        if (entry.swatch != null || entry.icon != null)
          Padding(
            padding: const EdgeInsets.only(right: 7),
            child: SizedBox(
              width: 14,
              height: 14,
              child: entry.swatch == null
                  ? Icon(entry.icon, size: 14, color: palette.textSecondary)
                  : DecoratedBox(
                      decoration: BoxDecoration(
                        color: entry.swatch,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.black26),
                      ),
                    ),
            ),
          ),
        Expanded(child: Text(entry.label, overflow: TextOverflow.ellipsis)),
        if (chevron)
          Icon(Icons.unfold_more_rounded, size: 16, color: palette.textMuted),
      ],
    );
  }
}

class _OptionEntry<T> {
  const _OptionEntry(this.value, this.label, {this.icon, this.swatch});

  final T value;
  final String label;
  final IconData? icon;
  final Color? swatch;
}

/// 桌面歌词的整数取值滑杆，带右侧当前值。
class _LyricsSlider extends StatelessWidget {
  const _LyricsSlider({
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.step = 1,
    this.suffix = '',
  });

  final int value;
  final int min;
  final int max;
  final int step;
  final String suffix;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final clamped = value.clamp(min, max).toDouble();
    final text = '$value$suffix';
    return SizedBox(
      width: 230,
      child: Row(
        children: [
          Expanded(
            child: Slider(
              value: clamped,
              min: min.toDouble(),
              max: max.toDouble(),
              divisions: ((max - min) / step).round().clamp(1, 200),
              label: text,
              onChanged: (next) =>
                  onChanged(((next - min) / step).round() * step + min),
            ),
          ),
          SizedBox(
            width: 46,
            child: Text(
              text,
              textAlign: TextAlign.end,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: context.palette.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingsCard extends StatelessWidget {
  const _SettingsCard({
    required this.label,
    required this.child,
    this.description,
  });

  final String label;
  final String? description;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: palette.textSecondary,
          ),
        ),
        if (description != null) ...[
          const SizedBox(height: 5),
          Text(
            description!,
            style: TextStyle(
              fontSize: 11.5,
              height: 1.6,
              color: palette.textMuted,
            ),
          ),
        ],
        const SizedBox(height: 10),
        Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: palette.surfaceHigh,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: palette.line),
          ),
          child: child,
        ),
      ],
    );
  }
}

/// 卡片里的非设置行内容（说明文字、按钮组、预览图）自己补回行的内边距。
class _SettingsCardPad extends StatelessWidget {
  const _SettingsCardPad({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 17, 20, 17),
      child: child,
    );
  }
}

class _SettingsRow extends StatelessWidget {
  const _SettingsRow({
    required this.title,
    required this.description,
    required this.control,
  });

  final String title;
  final String description;
  final Widget control;

  @override
  Widget build(BuildContext context) {
    final textBlock = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 14.5,
            height: 1.35,
            fontWeight: FontWeight.w600,
            color: context.palette.textPrimary,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          description,
          style: TextStyle(
            fontSize: 12,
            height: 1.6,
            color: context.palette.textMuted,
          ),
        ),
      ],
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < 520) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                textBlock,
                const SizedBox(height: 12),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: control,
                ),
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(child: textBlock),
              const SizedBox(width: 20),
              control,
            ],
          );
        },
      ),
    );
  }
}

/// 卡片内两行设置之间的通栏分隔线：行自己带内边距，这里不再留白。
class _SettingsDivider extends StatelessWidget {
  const _SettingsDivider();

  @override
  Widget build(BuildContext context) {
    return Divider(height: 1, thickness: 1, color: context.palette.line);
  }
}

class _BackgroundPreview extends StatelessWidget {
  const _BackgroundPreview({required this.path});

  final String path;

  @override
  Widget build(BuildContext context) {
    final blur = context.watch<SettingsProvider>().playerBackgroundBlur;
    final image = Image.file(
      File(path),
      fit: BoxFit.cover,
      errorBuilder: (context, error, stack) => ColoredBox(
        color: context.palette.fill,
        child: const Center(child: Icon(Icons.broken_image_outlined, size: 18)),
      ),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        height: 74,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (blur > 0)
              ImageFiltered(
                imageFilter: ui.ImageFilter.blur(
                  sigmaX: blur.toDouble(),
                  sigmaY: blur.toDouble(),
                ),
                child: Transform.scale(scale: 1.25, child: image),
              )
            else
              image,
            Align(
              alignment: Alignment.bottomLeft,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 0, 0, 7),
                child: Text(
                  '模糊 $blur px',
                  style: const TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                    shadows: [Shadow(color: Colors.black54, blurRadius: 6)],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ShortcutHint extends StatelessWidget {
  const _ShortcutHint({required this.label, required this.keys});

  final String label;
  final String keys;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: context.palette.fillSubtle,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: context.palette.line),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(fontSize: 10.5, color: context.palette.textMuted),
          ),
          const SizedBox(width: 7),
          Text(
            keys,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
              color: context.palette.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
