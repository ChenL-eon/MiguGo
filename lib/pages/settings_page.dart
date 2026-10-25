import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/navigation/app_shell_controller.dart';
import '../core/theme/android_tokens.dart';
import '../core/theme/app_colors.dart';
import '../core/utils/platform_kind.dart';
import '../models/audio_quality.dart';
import '../models/lyrics_style.dart';
import '../models/playback_mode.dart';
import '../models/player_background.dart';
import '../models/theme_accent.dart';
import '../providers/desktop_lyrics_provider.dart';
import '../providers/player_provider.dart';
import '../providers/settings_provider.dart';
import '../services/platform/global_hotkeys.dart';
import '../services/platform/native_file_picker.dart';
import '../widgets/android/android_choice.dart';
import '../widgets/android/android_feedback.dart';
import '../widgets/secondary_page_frame.dart';

/// 设置页：外观、播放、搜索与快捷键。
///
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
  final GlobalKey _lyricsSectionKey = GlobalKey();
  int _seenLyricsFocusTick = 0;

  void _revealLyricsSection() {
    final target = _lyricsSectionKey.currentContext;
    if (target == null || !target.mounted) return;
    Scrollable.ensureVisible(
      target,
      alignment: 0.06,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
  }

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

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    final player = context.watch<PlayerProvider>();
    final lyricsMode = context.watch<DesktopLyricsProvider>();
    final isWindows = Platform.isWindows;

    // 浮层控制条的"设置"按钮靠这个自增计数把页面定位到桌面歌词分组。
    final lyricsFocusTick = context.select<AppShellController, int>(
      (controller) => controller.desktopLyricsFocusTick,
    );
    if (lyricsFocusTick != _seenLyricsFocusTick) {
      _seenLyricsFocusTick = lyricsFocusTick;
      WidgetsBinding.instance.addPostFrameCallback((_) => _revealLyricsSection());
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final android = isAndroidPlatform;
        final padding = android
            ? AndroidSpacing.md
            : (constraints.maxWidth >= 700 ? 40.0 : 20.0);
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
                constraints: const BoxConstraints(maxWidth: 920),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 手机端的标题与副标题已经在二级页顶栏里，不再重复一遍。
                    if (!android) ...[
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            '设置',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.headlineMedium,
                          ),
                          const SizedBox(width: 12),
                          Flexible(
                            child: Padding(
                              padding: const EdgeInsets.only(bottom: 4),
                              child: Text(
                                '所有改动即时生效并保存在本机',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                  color: context.palette.textMuted,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                    ],
                    _SettingsSection(
                      icon: Icons.palette_outlined,
                      title: '外观',
                      subtitle: '应用默认跟随系统明暗，主题色默认为玫粉。',
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
                              onChanged: (mode) =>
                                  unawaited(settings.setThemeMode(mode)),
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
                                    swatch: accent.accentFor(
                                      Theme.of(context).brightness,
                                    ),
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
                    const SizedBox(height: 14),
                    _SettingsSection(
                      icon: Icons.graphic_eq_rounded,
                      title: '播放',
                      subtitle: '播放模式、音质、音量记忆、歌词跟随与睡眠定时。',
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
                              onChanged: (mode) =>
                                  unawaited(player.setPlaybackMode(mode)),
                            ),
                          ),
                          const _SettingsDivider(),
                          _SettingsRow(
                            title: '播放音质',
                            description:
                                '优先请求所选音质（${settings.audioQuality.detail}），'
                                '账号没有该音质权益时自动回退到可用档位；实际音质由咪咕按账号权益发放。',
                            control: _OptionDropdown<AudioQuality>(
                              sheetTitle: '播放音质',
                              value: settings.audioQuality,
                              width: 132,
                              entries: const [
                                _OptionEntry(AudioQuality.pq, '标准'),
                                _OptionEntry(AudioQuality.hq, '高品质'),
                                _OptionEntry(AudioQuality.sq, '无损'),
                              ],
                              onChanged: (quality) {
                                unawaited(settings.setAudioQuality(quality));
                                _showMessage(
                                  '播放音质已设为${quality.label}，'
                                  '下一首开始按新音质请求。',
                                );
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
                                for (final speed
                                    in SettingsProvider.playbackSpeedOptions)
                                  _OptionEntry(speed, _formatSpeed(speed)),
                              ],
                              onChanged: (speed) => unawaited(player.setSpeed(speed)),
                            ),
                          ),
                          const _SettingsDivider(),
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
                            title: '歌词自动滚动',
                            description: '关闭后歌词停在当前位置，点按任意歌词仍可跳转播放。',
                            control: Switch.adaptive(
                              value: settings.lyricsAutoScrollEnabled,
                              onChanged: (value) =>
                                  unawaited(settings.setLyricsAutoScrollEnabled(value)),
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
                    const SizedBox(height: 14),
                    _SettingsSection(
                      icon: Icons.play_circle_outline_rounded,
                      title: '播放页',
                      subtitle: '播放页整屏背景只在本机显示，不会上传或保存音频文件。',
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
                                        unawaited(
                                          settings.setPlayerBackgroundImage(null),
                                        );
                                        _showMessage('已清除自定义背景。');
                                      },
                                      child: const Text('清除'),
                                    ),
                                  if (NativeFilePicker.supportsImagePicker)
                                    FilledButton.icon(
                                      onPressed: _pickingBackground
                                          ? null
                                          : () => unawaited(
                                              _pickBackgroundImage(settings),
                                            ),
                                      style: FilledButton.styleFrom(
                                        visualDensity: VisualDensity.compact,
                                      ),
                                      icon: const Icon(Icons.image_outlined, size: 16),
                                      label: const Text('选择图片'),
                                    ),
                                ],
                              ),
                            ),
                            if (settings.playerBackgroundImage != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 14, bottom: 2),
                                child: _BackgroundPreview(
                                  path: settings.playerBackgroundImage!,
                                ),
                              ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    _SettingsSection(
                      icon: Icons.search_rounded,
                      title: '搜索',
                      subtitle: '搜索历史只保存在本机。',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _SettingsRow(
                            title: '记录搜索历史',
                            description: '在搜索页显示最近 10 条关键词，便于再次搜索。',
                            control: Switch.adaptive(
                              value: settings.recordSearchHistoryEnabled,
                              onChanged: (value) => unawaited(
                                settings.setRecordSearchHistoryEnabled(value),
                              ),
                            ),
                          ),
                          if (settings.searchHistory.isNotEmpty) ...[
                            const _SettingsDivider(),
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    '已记录 ${settings.searchHistory.length} 条搜索历史',
                                    style: Theme.of(context).textTheme.bodyMedium
                                        ?.copyWith(
                                          color: context.palette.textSecondary,
                                          fontSize: 12,
                                        ),
                                  ),
                                ),
                                TextButton.icon(
                                  onPressed: () {
                                    unawaited(settings.clearSearchHistory());
                                    _showMessage('已清空搜索历史。');
                                  },
                                  icon: const Icon(
                                    Icons.delete_outline_rounded,
                                    size: 16,
                                  ),
                                  label: const Text('清空历史'),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (isWindows) ...[
                      const SizedBox(height: 14),
                      _SettingsSection(
                        icon: Icons.keyboard_outlined,
                        title: '快捷键',
                        subtitle: 'Windows 桌面端全局与窗口内控制。',
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _SettingsRow(
                              title: '应用内空格播放 / 暂停',
                              description: '仅在应用窗口内生效；输入框聚焦时会自动让位。',
                              control: Switch.adaptive(
                                value: settings.inAppSpaceShortcutEnabled,
                                onChanged: (value) => unawaited(
                                  settings.setInAppSpaceShortcutEnabled(value),
                                ),
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
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      ),
                                    )
                                  : Switch.adaptive(
                                      value: settings.globalSpaceHotkeyEnabled,
                                      onChanged: (value) =>
                                          unawaited(_toggleGlobalHotkey(value)),
                                    ),
                            ),
                            const _SettingsDivider(),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: const [
                                _ShortcutHint(label: '上一首', keys: 'Ctrl + Alt + ←'),
                                _ShortcutHint(
                                  label: '播放 / 暂停',
                                  keys: 'Ctrl + Alt + 空格',
                                ),
                                _ShortcutHint(label: '下一首', keys: 'Ctrl + Alt + →'),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                    if (isWindows) ...[
                      const SizedBox(height: 14),
                      _SettingsSection(
                        key: _lyricsSectionKey,
                        icon: Icons.lyrics_outlined,
                        title: '桌面歌词',
                        subtitle: '独立置顶浮层，不占用主窗口；改动即时生效。',
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
                                  _OptionEntry(
                                    true,
                                    '双行',
                                    icon: Icons.view_stream_rounded,
                                  ),
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
                                    _OptionEntry(
                                      color,
                                      color.label,
                                      swatch: color.color,
                                    ),
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
                                    _OptionEntry(
                                      color,
                                      color.label,
                                      swatch: color.color,
                                    ),
                                ],
                                onChanged: (color) => unawaited(
                                  settings.setDesktopLyricsUnplayedColor(color),
                                ),
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
                                onChanged: (value) => unawaited(
                                  settings.setDesktopLyricsPanelAlpha(value),
                                ),
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
                                onChanged: (topmost) => unawaited(
                                  settings.setDesktopLyricsTopmost(topmost),
                                ),
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
                              description: '独立于主窗口的置顶歌词条：拖动移动，双击切换播放 / 暂停，鼠标悬停时浮出控制条，可切层级、字号、锁定与播放。',
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
                    const SizedBox(height: 14),
                    _SettingsSection(
                      icon: Icons.restart_alt_rounded,
                      title: '重置',
                      subtitle: '恢复默认设置不会影响登录状态与搜索历史。',
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              '主题恢复为跟随系统、主题色恢复为玫粉，播放模式、音量记忆、歌词跟随与快捷键开关恢复默认。',
                              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: context.palette.textSecondary,
                                fontSize: 12,
                                height: 1.65,
                              ),
                            ),
                          ),
                          const SizedBox(width: 14),
                          OutlinedButton.icon(
                            onPressed: _resetting
                                ? null
                                : () => unawaited(_resetToDefaults()),
                            icon: _resetting
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  )
                                : const Icon(Icons.restart_alt_rounded, size: 17),
                            label: const Text('恢复默认设置'),
                          ),
                        ],
                      ),
                    ),
                    // 手机端的「关于」从「我的」挪到这里，桌面端仍走原来的入口。
                    if (android) ...[
                      const SizedBox(height: 14),
                      _SettingsSection(
                        icon: Icons.info_outline_rounded,
                        title: '关于',
                        subtitle: '用途声明、合规边界与实现说明。',
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: OutlinedButton.icon(
                            onPressed: () => openAboutPage(context),
                            icon: const Icon(Icons.info_outline_rounded, size: 17),
                            label: const Text('查看关于页'),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        );
      },
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

class _SettingsSection extends StatelessWidget {
  const _SettingsSection({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.child,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: context.palette.surface.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: context.palette.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: context.palette.accent),
              const SizedBox(width: 9),
              Text(
                title,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(fontSize: 14),
              ),
            ],
          ),
          const SizedBox(height: 5),
          Text(
            subtitle,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: context.palette.textMuted,
              fontSize: 10.5,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
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
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            color: context.palette.textPrimary,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          description,
          style: TextStyle(
            fontSize: 10.5,
            height: 1.6,
            color: context.palette.textMuted,
          ),
        ),
      ],
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 520) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              textBlock,
              const SizedBox(height: 12),
              SingleChildScrollView(scrollDirection: Axis.horizontal, child: control),
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(child: textBlock),
            const SizedBox(width: 16),
            control,
          ],
        );
      },
    );
  }
}

class _SettingsDivider extends StatelessWidget {
  const _SettingsDivider();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 13),
      child: Divider(height: 1),
    );
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
