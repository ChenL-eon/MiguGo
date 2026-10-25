import 'package:flutter/material.dart';

/// Android 手机布局的间距阶梯，桌面端仍使用原有主题尺寸。
class AndroidSpacing {
  const AndroidSpacing._();

  static const double xxs = 4;
  static const double xs = 8;
  static const double sm = 12;
  static const double md = 16;
  static const double lg = 20;
  static const double xl = 24;
  static const double xxl = 32;
}

/// 统一的圆角规格，避免页面之间出现 12/14/16 混用。
class AndroidRadius {
  const AndroidRadius._();

  static const double xs = 10;
  static const double sm = 14;
  static const double md = 18;
  static const double lg = 22;
  static const double xl = 28;
  static const double pill = 999;

  static const BorderRadius card = BorderRadius.all(Radius.circular(md));
  static const BorderRadius cover = BorderRadius.all(Radius.circular(sm));
  static const BorderRadius sheetTop = BorderRadius.vertical(top: Radius.circular(xl));
  static const BorderRadius pillAll = BorderRadius.all(Radius.circular(pill));
}

/// 手机端字号阶梯：页面 26、次级标题 22、分组标题 17、列表标题 15.5。
class AndroidTypeScale {
  const AndroidTypeScale._();

  static const double pageTitle = 26;
  static const double headline = 22;
  static const double section = 17;
  static const double listTitle = 15.5;
  static const double body = 13.5;
  static const double caption = 12;
  static const double micro = 11;
}

/// 与 [AndroidTypeScale] 配套的字重、行高与字距。
class AndroidTextStyles {
  const AndroidTextStyles._();

  static TextStyle pageTitle(Color color) => TextStyle(
    fontSize: AndroidTypeScale.pageTitle,
    height: 1.22,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.6,
    color: color,
  );

  static TextStyle headline(Color color) => TextStyle(
    fontSize: AndroidTypeScale.headline,
    height: 1.25,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.3,
    color: color,
  );

  static TextStyle sectionTitle(Color color) => TextStyle(
    fontSize: AndroidTypeScale.section,
    height: 1.3,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.2,
    color: color,
  );

  static TextStyle listTitle(Color color) => TextStyle(
    fontSize: AndroidTypeScale.listTitle,
    height: 1.35,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.1,
    color: color,
  );

  static TextStyle body(Color color) =>
      TextStyle(fontSize: AndroidTypeScale.body, height: 1.5, color: color);

  static TextStyle caption(Color color) =>
      TextStyle(fontSize: AndroidTypeScale.caption, height: 1.4, color: color);

  static TextStyle label(Color color) => TextStyle(
    fontSize: AndroidTypeScale.micro,
    height: 1.3,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.4,
    color: color,
  );

  static TextStyle action(Color color) => TextStyle(
    fontSize: AndroidTypeScale.body,
    height: 1.3,
    fontWeight: FontWeight.w600,
    color: color,
  );
}

/// 手机端的固定尺寸，触控区域不小于 48dp。
class AndroidSizes {
  const AndroidSizes._();

  static const double touch = 48;
  static const double icon = 22;
  static const double smallIcon = 18;
  static const double largeIcon = 26;
  static const double bottomBarHeight = 62;

  /// 底部胶囊中间的正在播放唱片直径，需要小于 bottomBarHeight - 6。
  static const double navDiscSize = 54;
  static const double miniPlayerHeight = 60;
  static const double miniPlayerCover = 46;
  static const double listCover = 56;
  static const double sheetMaxWidth = 560;

  /// 播放页整屏封面的最大边长。
  ///
  /// 咪咕最大档是 800px，在 3x 屏上 264dp 刚好一像素对一像素；再放大只是把
  /// 原图插值拉糊，不如留出呼吸空间。
  static const double playerCoverMaxSide = 264;

  /// 迷你条与底部导航是定高壳层，字号放大到这里为止仍能容纳。
  static const double chromeMaxTextScale = 1.4;
}

/// 手机端动效时长；列表反馈要快，页面转场留一点缓冲。
class AndroidMotion {
  const AndroidMotion._();

  static const Duration fast = Duration(milliseconds: 160);
  static const Duration base = Duration(milliseconds: 240);
  static const Duration slow = Duration(milliseconds: 320);
  static const Curve standard = Curves.easeOutCubic;
  static const Curve emphasized = Curves.easeOutQuint;
}
