import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../core/navigation/app_page_route.dart';
import '../core/theme/app_colors.dart';
import '../pages/official_login_page.dart';
import '../providers/account_provider.dart';
import '../services/auth/migu_passport_api.dart';
import 'login_feedback.dart';

/// 咪咕原生登录表单：短信验证码与账号密码两种方式，由账号弹窗内嵌。
///
/// 表单里没有任何网页：手机号、验证码与密码只在登录请求中加密发给咪咕通行证，
/// 本机既不落盘也不写日志。被风控要求图形验证码时，这里显示咪咕下发的图片，
/// 由用户本人识别后回填；应用不自动作答。咪咕改要滑块等形式时，交给
/// [OfficialLoginPage]。
class NativeLoginPanel extends StatefulWidget {
  const NativeLoginPanel({super.key, this.onSignedIn});

  /// 登录成功后回调，携带咪咕下发的打码手机号；由宿主决定要不要关闭容器。
  final void Function(String? maskedPhone)? onSignedIn;

  @override
  State<NativeLoginPanel> createState() => _NativeLoginPanelState();
}

enum _LoginMode { sms, password }

class _NativeLoginPanelState extends State<NativeLoginPanel> {
  static final RegExp _cnMobile = RegExp(r'^1[3-9]\d{9}$');

  final _phone = TextEditingController();
  final _code = TextEditingController();
  final _account = TextEditingController();
  final _password = TextEditingController();
  final _captcha = TextEditingController();

  _LoginMode _mode = _LoginMode.sms;
  bool _obscure = true;
  bool _sending = false;
  bool _submitting = false;
  int _countdown = 0;
  String? _error;
  String? _captchaHint;
  Timer? _timer;

  /// 咪咕要求图形验证码时才展开的那一行：图片、输入框与「换一张」。
  bool _captchaRequired = false;
  bool _captchaLoading = false;
  Uint8List? _captchaImage;
  String? _captchaImageError;

  @override
  void initState() {
    super.initState();
    // 不监听控制器就没人触发重建，按钮可用态会一直停在初始值。
    for (final controller in [_phone, _code, _account, _password, _captcha]) {
      controller.addListener(_onInputChanged);
    }
  }

  void _onInputChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _timer?.cancel();
    _phone.dispose();
    _code.dispose();
    _account.dispose();
    _password.dispose();
    _captcha.dispose();
    super.dispose();
  }

  bool get _phoneReady => _cnMobile.hasMatch(_phone.text.trim());
  bool get _codeReady => RegExp(r'^\d{4,8}$').hasMatch(_code.text.trim());
  bool get _passwordReady =>
      _account.text.trim().isNotEmpty && _password.text.isNotEmpty;
  bool get _captchaReady => _captcha.text.trim().isNotEmpty;
  bool get _busy => _sending || _submitting || _captchaLoading;
  bool get _inputsReady =>
      _mode == _LoginMode.sms ? _phoneReady && _codeReady : _passwordReady;
  bool get _canSubmit => !_busy && _inputsReady && (!_captchaRequired || _captchaReady);

  /// 图形验证码分属两种登录方式，取值与官方页面一致。
  MiguImgcodeType get _imgcodeType =>
      _mode == _LoginMode.sms ? MiguImgcodeType.sms : MiguImgcodeType.password;

  void _setMode(_LoginMode mode) {
    if (_mode == mode || _busy) return;
    // 换方式等于换 imgcodeType，旧的验证码图片必然不再适用。
    _captcha.clear();
    setState(() {
      _mode = mode;
      _error = null;
      _captchaHint = null;
      _captchaRequired = false;
      _captchaImage = null;
      _captchaImageError = null;
    });
  }

  void _fail(Object error) {
    if (!mounted) return;
    setState(() {
      _submitting = false;
      _sending = false;
      _captchaLoading = false;
      if (error is MiguLoginException && error.officialOnly) {
        // 咪咕这次要的是滑块等我们呈现不出来的形式，只能交给官方页面。
        _captchaHint = error.message;
        _captchaRequired = false;
        _captchaImage = null;
        _error = null;
      } else if (error is MiguLoginException && error.captchaRequired) {
        _error = error.message;
        _captchaHint = null;
        _captchaRequired = true;
        _captcha.clear();
        _captchaImage = null;
        _captchaImageError = null;
      } else {
        _error = error is MiguLoginException ? error.message : '登录失败，请稍后重试。';
        _captchaHint = null;
      }
    });
    if (_captchaRequired && _captchaImage == null) {
      unawaited(_loadCaptcha());
    }
  }

  /// 向咪咕取一张图形验证码；失败只记在本行里，不打断整个表单。
  Future<void> _loadCaptcha({bool refresh = false}) async {
    if (_captchaLoading) return;
    setState(() {
      _captchaLoading = true;
      _captchaImageError = null;
    });
    try {
      final captcha = await context.read<AccountProvider>().requestLoginCaptcha(
        type: _imgcodeType,
        refresh: refresh,
      );
      if (!mounted) return;
      setState(() {
        _captchaLoading = false;
        _captchaImage = captcha.image;
      });
    } on Object catch (error) {
      if (!mounted) return;
      if (error is MiguLoginException && error.officialOnly) {
        // 咪咕这次要的验证形式我们呈现不了，收起这一行并交给官方页面。
        _fail(error);
        return;
      }
      setState(() {
        _captchaLoading = false;
        _captchaImage = null;
        _captchaImageError = error is MiguLoginException
            ? error.message
            : '验证码图片取不到，请点击重试。';
      });
    }
  }

  /// 已经填了图形验证码时，先让咪咕认一次；认不过就不必再提交登录。
  Future<bool> _passCaptcha() async {
    if (!_captchaRequired) return true;
    await context.read<AccountProvider>().verifyLoginCaptcha(
      type: _imgcodeType,
      captcha: _captcha.text,
    );
    return true;
  }

  Future<void> _sendCode() async {
    if (!_phoneReady) {
      setState(() => _error = '请输入 11 位手机号。');
      return;
    }
    final account = context.read<AccountProvider>();
    final captcha = _captcha.text.trim();
    setState(() {
      _sending = true;
      _error = null;
      _captchaHint = null;
    });
    try {
      await _passCaptcha();
      await account.requestLoginCode(_phone.text, captcha: captcha);
      if (!mounted) return;
      setState(() {
        _sending = false;
        _countdown = 60;
      });
      _startCountdown();
      showLoginSnack(context, '验证码已发送，请查看手机短信。');
    } on Object catch (error) {
      _fail(error);
    }
  }

  void _startCountdown() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        _countdown--;
        if (_countdown <= 0) timer.cancel();
      });
    });
  }

  Future<void> _submit() async {
    final account = context.read<AccountProvider>();
    final captcha = _captcha.text.trim();
    setState(() {
      _submitting = true;
      _error = null;
      _captchaHint = null;
    });
    try {
      await _passCaptcha();
      final maskedPhone = _mode == _LoginMode.sms
          ? await account.signInWithSmsCode(
              phone: _phone.text,
              code: _code.text,
              captcha: captcha,
            )
          : await account.signInWithPassword(
              username: _account.text,
              password: _password.text,
              captcha: captcha,
            );
      if (!mounted) return;
      _timer?.cancel();
      // 密码与验证码只留在输入框的内存里，登录成功立刻清掉。
      _code.clear();
      _password.clear();
      _captcha.clear();
      setState(() {
        _captchaRequired = false;
        _captchaImage = null;
        _captchaImageError = null;
      });
      widget.onSignedIn?.call(maskedPhone);
    } on Object catch (error) {
      _fail(error);
    }
  }

  Future<void> _openOfficialLogin() async {
    await Navigator.of(context)
        .push(AppPageRoute<void>(builder: (_) => const OfficialLoginPage()));
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ModeTabs(mode: _mode, enabled: !_busy, onChanged: _setMode),
        const SizedBox(height: 16),
        if (_mode == _LoginMode.sms)
          ..._buildSmsFields(context)
        else
          ..._buildPasswordFields(context),
        if (_captchaRequired) ..._buildCaptchaField(context),
        const SizedBox(height: 16),
        if (_error != null) ...[
          LoginStatusBanner(message: _error!, isError: true),
          const SizedBox(height: 10),
        ],
        if (_captchaHint != null) ...[
          LoginInfoBanner(
            icon: Icons.shield_outlined,
            tone: palette.gold,
            title: '需要官方页面协助',
            message: _captchaHint!,
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: _busy ? null : () => unawaited(_openOfficialLogin()),
            icon: const Icon(Icons.login_rounded, size: 16),
            label: const Text('打开咪咕官方登录页'),
          ),
          const SizedBox(height: 14),
        ],
        OutlinedButton(
          onPressed: _canSubmit ? () => unawaited(_submit()) : null,
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 15),
            side: BorderSide(color: _canSubmit ? palette.lineStrong : palette.line),
            foregroundColor: palette.textPrimary,
            textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(11)),
          ),
          child: _submitting
              ? SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: palette.textPrimary,
                  ),
                )
              : const Text('登录'),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: _busy ? null : () => unawaited(_openOfficialLogin()),
            icon: const Icon(Icons.verified_user_outlined, size: 15),
            label: const Text('改用咪咕官方页面登录'),
            style: TextButton.styleFrom(
              visualDensity: VisualDensity.compact,
              textStyle: const TextStyle(fontSize: 11.5),
              foregroundColor: palette.textMuted,
            ),
          ),
        ),
      ],
    );
  }

  List<Widget> _buildSmsFields(BuildContext context) {
    return [
      TextField(
        controller: _phone,
        enabled: !_busy,
        keyboardType: TextInputType.phone,
        maxLength: 11,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        decoration: _input(context, hint: '手机号'),
      ),
      const SizedBox(height: 12),
      Row(
        children: [
          Expanded(
            child: TextField(
              controller: _code,
              enabled: !_busy,
              keyboardType: TextInputType.number,
              maxLength: 8,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              onSubmitted: _phoneReady && _codeReady && !_busy
                  ? (_) => unawaited(_submit())
                  : null,
              decoration: _input(context, hint: '验证码'),
            ),
          ),
          const SizedBox(width: 4),
          TextButton(
            onPressed: !_phoneReady || _sending || _countdown > 0 || _submitting
                ? null
                : () => unawaited(_sendCode()),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              foregroundColor: context.palette.accent,
              textStyle: const TextStyle(fontSize: 13),
            ),
            child: Text(
              _sending
                  ? '发送中…'
                  : _countdown > 0
                  ? '${_countdown}s 后重发'
                  : '发送验证码',
            ),
          ),
        ],
      ),
    ];
  }

  List<Widget> _buildPasswordFields(BuildContext context) {
    final palette = context.palette;
    return [
      TextField(
        controller: _account,
        enabled: !_busy,
        autocorrect: false,
        enableSuggestions: false,
        keyboardType: TextInputType.phone,
        decoration: _input(context, hint: '手机号或通行证账号'),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: _password,
        enabled: !_busy,
        obscureText: _obscure,
        autocorrect: false,
        enableSuggestions: false,
        maxLines: 1,
        onSubmitted: _passwordReady && !_busy ? (_) => unawaited(_submit()) : null,
        decoration: _input(
          context,
          hint: '登录密码',
          suffix: IconButton(
            onPressed: () => setState(() => _obscure = !_obscure),
            tooltip: _obscure ? '显示密码' : '隐藏密码',
            icon: Icon(
              _obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined,
              size: 18,
              color: palette.textMuted,
            ),
          ),
        ),
      ),
    ];
  }

  /// 咪咕要求图形验证码时才展开的一行：图片由用户本人识别，应用只负责透传。
  List<Widget> _buildCaptchaField(BuildContext context) {
    final palette = context.palette;
    return [
      const SizedBox(height: 12),
      Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: TextField(
              controller: _captcha,
              enabled: !_busy,
              maxLength: 6,
              autocorrect: false,
              enableSuggestions: false,
              textCapitalization: TextCapitalization.none,
              onSubmitted: _canSubmit ? (_) => unawaited(_submit()) : null,
              decoration: _input(context, hint: '图形验证码'),
            ),
          ),
          const SizedBox(width: 10),
          GestureDetector(
            // 图片本身不吃命中测试，整块都要能点，所以声明为 opaque。
            behavior: HitTestBehavior.opaque,
            onTap: _busy ? null : () => unawaited(_loadCaptcha(refresh: true)),
            child: Container(
              width: 104,
              height: 46,
              alignment: Alignment.center,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: palette.fill,
                border: Border.all(color: palette.lineStrong),
                borderRadius: BorderRadius.circular(11),
              ),
              child: _captchaLoading
                  ? SizedBox(
                      width: 15,
                      height: 15,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: palette.textMuted,
                      ),
                    )
                  : _captchaImage != null
                  ? Image.memory(
                      _captchaImage!,
                      width: 104,
                      height: 46,
                      fit: BoxFit.contain,
                    )
                  : Text(
                      _captchaImageError ?? '点击取图',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 11, color: palette.textMuted),
                    ),
            ),
          ),
        ],
      ),
      const SizedBox(height: 6),
      Text(
        '图片由你本人识别后输入，应用不会代答。看不清就点图片换一张。',
        style: TextStyle(fontSize: 11, color: palette.textMuted),
      ),
    ];
  }

  /// 紧凑描边输入框：提示词即字段名，不再另起一行标题。
  InputDecoration _input(BuildContext context, {required String hint, Widget? suffix}) {
    final palette = context.palette;
    OutlineInputBorder frame(Color color, [double width = 1]) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(11),
      borderSide: BorderSide(color: color, width: width),
    );
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(fontSize: 13.5, color: palette.textMuted),
      counterText: '',
      isDense: true,
      filled: false,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
      suffixIcon: suffix,
      suffixIconConstraints: const BoxConstraints(minWidth: 40, minHeight: 40),
      border: frame(palette.line),
      enabledBorder: frame(palette.line),
      focusedBorder: frame(palette.accent, 1.4),
      errorBorder: frame(palette.danger),
      disabledBorder: frame(palette.line),
    );
  }
}

/// 登录方式切换：两种都是咪咕官方页面上的原生表单方式。
class _ModeTabs extends StatelessWidget {
  const _ModeTabs({required this.mode, required this.enabled, required this.onChanged});

  final _LoginMode mode;
  final bool enabled;
  final ValueChanged<_LoginMode> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _ModeTab(
          label: '短信验证码',
          selected: mode == _LoginMode.sms,
          enabled: enabled,
          onTap: () => onChanged(_LoginMode.sms),
        ),
        const SizedBox(width: 8),
        _ModeTab(
          label: '账号密码',
          selected: mode == _LoginMode.password,
          enabled: enabled,
          onTap: () => onChanged(_LoginMode.password),
        ),
      ],
    );
  }
}

class _ModeTab extends StatelessWidget {
  const _ModeTab({
    required this.label,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Material(
      color: selected ? palette.accentSoft : Colors.transparent,
      borderRadius: BorderRadius.circular(9),
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(9),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              color: selected
                  ? palette.accent
                  : (enabled ? palette.textSecondary : palette.textMuted),
            ),
          ),
        ),
      ),
    );
  }
}
