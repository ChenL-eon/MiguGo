/// 隐私政策的一条：一个小标题配一段说明，「关于」页按列表顺序原样渲染。
typedef PrivacyNotice = ({String title, String body});

/// 全局常量：接口来自咪咕网页端与官方通行证；原生登录只提交用户当场输入的
/// 手机号、验证码或密码，代码里不含任何账号密钥，也不生成官方风控签名。
class AppConstants {
  const AppConstants._();

  static const String appName = 'MiguGo';
  static const String appVersion = '1.0.0';

  /// 关于页的代码仓库与更新入口，地址确定前先留占位。
  static const String githubRepoUrl = '#';
  static const String updatePageUrl = '#';

  /// 咪咕接口要求携带的固定来源页。
  static const String miguReferer = 'https://music.migu.cn';
  static const String miguImageBase = 'https://d.musicapp.migu.cn';

  /// 通行证登录用的来源标识，与网页登录页 `sourceid=220029` 一致。
  static const String passportSourceId = '220029';

  /// 音乐站会话标识，换票时随来源一起上报。
  static const String passportActivityId = 'MUSIC-WWW';

  static const String passportReferer = 'https://passport.migu.cn/login';

  /// 下发 RSA 公钥（modulus / publicExponent，均为 16 进制字符串）。
  static const String passportPublicKeyUrl =
      'https://passport.migu.cn/password/publickey';

  /// 账号密码登录。
  static const String passportPasswordAuthnUrl = 'https://passport.migu.cn/authn';

  /// 短信验证码下发与校验。
  static const String passportSmsSendUrl =
      'https://passport.migu.cn/login/dynamicpassword';
  static const String passportSmsAuthnUrl =
      'https://passport.migu.cn/authn/dynamicpassword';

  /// 图形验证码：取图与校验。答案与 `mgnd_session_id` 这份会话 Cookie 绑定，
  /// 所以取图、校验和随后的登录必须共用同一份 Cookie。
  static const String passportCaptchaRiskUrl =
      'https://passport.migu.cn/captcha/graph/risk';
  static const String passportCaptchaCheckUrl =
      'https://passport.migu.cn/captcha/graph/check';

  /// 用登录票据换音乐站会话（登录与静默续期共用；响应里的
  /// `Set-Cookie: pacmtoken` 即取链凭据）。
  static const String passportTokenValidateUrl =
      'https://c.musicapp.migu.cn/user/h5/token-validate/v3.0';

  // 当前可用的公开 PC 接口（v3 接口现已 301 重定向至 v5）。
  static const String songSearchUrl =
      'https://app.u.nf.migu.cn/pc/resource/song/item/search/v1.0';
  static const String playlistSearchUrl =
      'https://app.u.nf.migu.cn/pc/v1.0/content/search_all.do';
  static const String playlistInfoUrl =
      'https://app.c.nf.migu.cn/resource/playlist/v2.0';
  static const String playlistSongsUrl =
      'https://app.c.nf.migu.cn/MIGUM3.0/resource/playlist/song/v2.0';
  static const String listenSongUrl =
      'https://app.pd.nf.migu.cn/MIGUM2.0/v1.0/content/sub/listenSong.do';

  /// 网页首页的每日推荐与栏目配置，用于原生推送页。
  static const String dailyRecommendUrl =
      'https://app.c.nf.migu.cn/pc/v1.0/template/todayRecommendList/release';
  static const String homeIndexUrl =
      'https://app.c.nf.migu.cn/pc/bmw/page-data/music-index-show/v2.0';

  /// 网页播放器使用的取链接口：按账号权益发放地址，响应体是站点自己的编码。
  static const String vipListenUrl = 'https://app.c.nf.migu.cn/strategy/pc/listen/v2.0';

  /// 当前登录账号的公开资料；需要 pacmtoken / uid 请求头。
  static const String userProfileUrl =
      'https://app.c.nf.migu.cn/user/h5/user-info/v1.0';

  /// 账号主页：我喜欢、自建歌单与收藏歌单；需要登录凭据。
  static const String userHomePageUrl =
      'https://app.c.nf.migu.cn/pc/user/home-page/v2.0';

  /// 会员身份标识接口，失败时只影响 VIP 徽标显示。
  static const String userBadgeUrl =
      'https://app.c.nf.migu.cn/pc/open/api/member/icon/v1.0';

  static const String userAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36';

  static const String aboutNotice =
      '本应用为第三方咪咕音乐流式播放客户端，仅作个人学习、技术研究使用。'
      '本项目无破解会员、绕过权限等功能，不会保存、下载、传播任何音频文件，不用于商业用途。'
      '所有版权内容归属原平台及著作权方。';

  // 使用边界声明，统一在“关于”页原样展示。
  static const String accountPolicy =
      '账号权限完全跟随咪咕官方：只有登录咪咕账号、且该账号拥有对应曲目权益时，才可能拿到播放地址。'
      '禁止实现歌曲下载、音频文件解密、本地持久保存音频文件，仅在线流式播放。';

  static const String webViewPolicy =
      '原生登录只调用咪咕通行证与音乐站的会话接口，代码里不含任何账号密钥，也不生成官方风控签名；'
      '只有你主动点「改用咪咕官方页面登录」时才临时打开一个加载通行证页面的登录窗口，'
      '读到凭证后该窗口立即关闭；播放页只为 VIP 曲目内嵌咪咕官方网页播放器；'
      '两处 WebView 都只显示咪咕自己的页面，其余界面全部为原生 Flutter。'
      '不读取内嵌播放器页面里的音频地址；只在这些页面与自己之间同步本机账号的登录会话，'
      '其余 Cookie 一概不取。';

  /// 登录弹窗底部的一句提示；完整说明在点「隐私政策」后弹出的详情里。
  static const String loginPrivacyHint =
      '手机号、验证码与密码只在登录请求中提交给咪咕通行证，本机不保存；'
      '登录换来的会话凭据只写入系统安全存储。';

  /// 隐私政策正文前的一句导语，详情窗口与「关于」页共用。
  static const String privacyPolicyIntro =
      '下面每一条都对应 MiguGo 当前的实现，不写做不到的承诺；'
      '咪咕官方如何处理你提交的账号信息，以它的官方隐私政策为准。';

  /// 隐私政策正文：只写实现里真实发生过的事，「关于」页原样展示。
  ///
  /// 新增条目时必须先确认代码里确实如此，不能用理想描述代替实现。
  static const List<PrivacyNotice> privacyPolicy = [
    (
      title: '政策范围',
      body:
          'MiguGo 没有自己的服务器，也没有独立账号体系：数据只在你这台设备与咪咕官方接口之间来回，'
          '本应用不转发给任何中间方、不在自己的服务端留副本。本文只说明 MiguGo 做了什么；'
          '咪咕官方如何处理你提交的手机号、密码与账号信息，以咪咕官方隐私政策为准。'
          '原生登录走的是咪咕网页端自用协议，接口随时可能调整，数据流改变时本文同步更新。',
    ),
    (
      title: '登录时提交出去的信息',
      body:
          '手机号、短信验证码、账号与密码，都用咪咕当场下发的 RSA 公钥加密后直接提交给咪咕通行证，'
          '只存在于那一次请求里：本机不保存、不写日志，界面与错误提示也不回显内容。'
          '代码里不含任何账号密钥，也不生成官方风控签名。',
    ),
    (
      title: '登录之后保存在本机的是什么',
      body:
          '登录换来的会话凭据写入系统安全存储：Android 由 Keystore 派生密钥加密，'
          'Windows 是以当前 Windows 账户加密的密文，放在该用户的应用数据目录里，'
          '换个账户读出来解不开。原生登录保存取链用的 pacmtoken，'
          '以及通行证签发的那张登录票据（token）：票据不随普通请求发送，'
          '只在账号接口回绝本机凭据时用来再换一次新 pacmtoken，换不到就按登录失效处理。'
          '改用官方页面登录时，保存的是那个页面写下的咪咕音乐登录 Cookie，'
          '其中可能包含 uid、手机号标识 msisdn 与网页会话 id；'
          '这条路径没有登录票据，不会主动续期。'
          '之后咪咕接口通过 Set-Cookie 轮换的会话值也只更新进这一份加密存储，'
          '用途是取播放地址、读取本账号资料与账号里的歌单。',
    ),
    (
      title: '图形验证码',
      body:
          '被官方风控要求图形验证码时，应用向咪咕取那张图片显示在登录框里，由你本人照着输入：'
          '不识别图片、不自动作答，答案只可能来自输入框。取图与校验都只发给咪咕通行证，'
          '验证码会话只留在内存、随本次登录结束丢弃，不落盘。'
          '咪咕改要滑块这类本应用无法呈现的验证形式时，只能改用官方页面登录。',
    ),
    (
      title: '设备标识与固定请求头',
      body:
          '每次音乐接口请求都带上咪咕网页端要求的固定来源头（Referer、来源标识、版本号等）、'
          '一个设备标识和登录后的账号凭据。设备标识在 Android 取系统的 ANDROID_ID，'
          '其余平台在首次启动时生成随机 UUID 存在本机；它只发给咪咕，不发给任何第三方，'
          '只用于把同一账号的多端会话区分开。登录表单里的 fingerPrint 在每次启动时生成一次、'
          '本次运行内复用，不代表真实硬件；名为 imei、imsi 的请求头固定填字符串 h5page，'
          '应用不读取真实 IMEI 或 IMSI。',
    ),
    (
      title: '本机保存的其余内容',
      body:
          '除凭据外只有：界面与播放设置（主题、音质、倍速、音量、桌面歌词的位置与配色、'
          '播放页背景图的文件路径）、搜索历史（你输入过的原始关键词，最多 10 条，'
          '可在设置页关闭或清空）、以及你主动导入的歌单（歌单名、来源链接和咪咕侧匹配到的'
          '曲目名、歌手、专辑、封面与歌词地址）；另有一条「最近一次账号接口回绝本机凭据」的'
          '取证记录，只写接口地址、HTTP 状态码、业务编码与服务端那句文案，用来在登录状态说明'
          '里讲清为什么提示失效，里面不会有凭据内容。'
          '这些写在应用的普通偏好文件里，不含凭据，也不上传。'
          '没有播放历史，没有收听统计。',
    ),
    (
      title: '数据流向的网络地址',
      body:
          '除咪咕自有域名外，本应用不会主动连别的地址：passport.migu.cn 负责登录，'
          'app.c.nf.migu.cn、app.u.nf.migu.cn、app.pd.nf.migu.cn 负责曲库、取链、歌词与封面，'
          'c.musicapp.migu.cn 负责登录换票与会话续期，'
          'music.migu.cn 与 d.musicapp.migu.cn 是官方页面与图片。'
          '两个例外不由本应用决定：播放地址是咪咕返回的跳转，会落到它自己的音频 CDN，域名不固定；'
          '导入外部歌单时，封面按来源平台给出的图片地址加载。'
          '只有在主动导入歌单时才访问网易云、QQ音乐、酷狗的公开歌单页，且只读曲目名与歌手。',
    ),
    (
      title: 'WebView 里产生的数据',
      body:
          '只有两处加载网页：你主动打开的咪咕官方登录窗口，和 VIP 曲目内嵌的咪咕官方播放器，'
          '两处都只显示咪咕自己的页面。Windows 上它们用彼此独立的用户数据目录：'
          '登录目录里的 Cookie 在离开登录页时清除，播放器目录里由咪咕页面自己写入的会话与网页缓存'
          '不会被本应用清除。Android 上网页数据跟随系统 WebView 的本应用存储。'
          '登录窗口主要通过 CookieManager 读取 Cookie；个别时机它读不到页面刚写入的条目，'
          '这时还会直接读页面自己的 document.cookie 作为兜底——只取名称与值、只用于把你用'
          '自己账号登录后的会话导入本机，不发起额外请求，也不交给任何第三方。'
          '本应用不读取内嵌播放器页面里的音频地址，只在本机凭据与这些页面之间同步同一账号的登录会话。',
    ),
    (
      title: '日志与第三方组件',
      body:
          '没有统计、广告、崩溃上报或自动更新组件，依赖里只有播放、界面与网络库。'
          '不写日志文件，调试输出只进系统调试日志，不外发。'
          '界面文案、错误提示和调试输出都不包含 Cookie 值、密码或验证码，'
          '涉及凭据的提示只说名称不说内容。',
    ),
    (
      title: '系统权限',
      body:
          'Android 清单只声明网络访问一项，不申请存储、通讯录、定位、麦克风或相机权限；'
          '安装包中出现的前台服务、通知与网络状态类权限来自后台播放和系统媒体控制插件。'
          'Windows 端没有权限申请，桌面歌词只是本机屏幕上的一个悬浮窗口，不采集任何内容。',
    ),
    (
      title: '如何清除本机数据',
      body:
          '数据全部在你本机。登录后的左下角卡片是个人中心，里面有「退出登录」与「切换账号」：'
          '两者都只清除本机保存的登录凭据、登录票据与账号快照，并停止播放、清空播放列表；'
          '设置、搜索历史与导入的歌单都不受这一步影响，搜索历史与设置也能在设置页单独清空。'
          '咪咕没有登出接口，退出只发生在你这台设备上，不会通知服务端。'
          '当要求登录的账号接口（用户资料、账号歌单）回绝本机凭据——HTTP 401 或返回'
          '“请先登录”——时，原生登录的账号会先用留存的登录票据静默换一次新会话，'
          '换到了就继续用，不算一次回绝；换不到时，应用第一次只把状态标成'
          '「登录可能已失效」并继续保留凭据；'
          '隔过 30 分钟后账号接口再次回绝，才认定这份凭据确实作废，按同样的方式'
          '自动退出一次，同时在状态说明里写出最近一次被拒的接口地址、HTTP 状态码'
          '与业务编码，这条记录不含 Cookie、手机号或任何凭据内容。'
          '歌词、封面、公开搜索这些不要求登录的接口回 401，以及 HTTP 403'
          '（很可能只是这首歌没有权益）都不参与失效判定，不会动你的登录。'
          '要彻底清除本机数据，Android 用系统的「清除应用数据」或卸载，'
          'Windows 删除 %APPDATA% 下本应用的用户数据目录，以及 %LOCALAPPDATA% 下的 migu_lele 目录'
          '（那是两个 WebView 的用户数据）。',
    ),
  ];

  static const String networkPolicy =
      '音乐数据来自咪咕网页公开接口；只有你主动导入歌单时，才会读取对应平台公开歌单的曲目名与歌手，'
      '用于匹配咪咕曲库。不登录第三方账号、不下载音频、不批量抓取。';

  /// 外部歌单导入的限制说明，统一在歌单页展示。
  static const String externalPlaylistNotice =
      '导入只读取公开歌单的曲目名与歌手，再逐首搜索咪咕曲库；匹配不到的歌曲会被跳过。'
      '不登录网易云、QQ音乐或酷狗账号，也不读取或保存这些平台的 Cookie。';

  /// 咪咕云盘无法通过公开接口读取，只在歌单页说明原因。
  static const String cloudDiskNotice =
      '咪咕云盘的曲目列表与播放地址由咪咕官方客户端通过私有签名下发。'
      '本软件只使用网页端公开接口，不模拟官方签名、不破解客户端，因此暂不读取云盘内容；'
      '如需使用云盘，请在咪咕音乐官方客户端中操作。';

  /// 免费曲目的兜底音质；更高音质由设置项与账号权益决定。
  static const String playbackToneFlag = 'PQ';
  static const int playbackResourceType = 2;
}
