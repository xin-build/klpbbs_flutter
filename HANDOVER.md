# 苦力怕论坛客户端（KLPBBS App）项目接手与协同开发文档

> **文档版本**：v1.0.0  
> **更新时间**：2026-08-17  
> **项目定位**：苦力怕论坛（[klpbbs.com](https://klpbbs.com)）全功能、现代化、自适应第三方跨平台客户端（Flutter/Dart），全面覆盖 Windows PC 桌面端与 Android/iOS 移动端。

---

## 目录
1. [项目概览与设计规范](#1-项目概览与设计规范)
2. [技术栈与核心依赖](#2-技术栈与核心依赖)
3. [项目目录结构与源码地图](#3-项目目录结构与源码地图)
4. [Discuz 逆向解析与关键业务机制](#4-discuz-逆向解析与关键业务机制)
5. [近期已完成的重构成果](#5-近期已完成的重构成果)
6. [后续待办事项与开发路线 (Roadmap)](#6-后续待办事项与开发路线-roadmap)
7. [本地运行、调试与测试指令](#7-本地运行调试与测试指令)
8. [核心避坑指南 (Gotchas)](#8-核心避坑指南-gotchas)

---

## 1. 项目概览与设计规范

- **核心目标**：100% 还原并超越官方网页版论坛体验，提供纯净、无广告、丝滑流畅、功能完备的论坛客户端。
- **排版与自适应**：
  - **PC 桌面端（宽屏 ≥ 600px）**：双栏/多栏自适应网格，横向图文卡片流，支持快速悬停、右侧缩略图、多列流式布局。
  - **移动端（竖屏 < 600px）**：紧凑单列 Feed，大图/多图瀑布流，单手微操手势支持。
- **设计风格**：Material 3 规范结合 PiliPlus 风格，提供动态色彩取色、高对比度暗色主题、字体大小自定义缩放。

---

## 2. 技术栈与核心依赖

| 模块 | 技术选型 | 说明 |
| :--- | :--- | :--- |
| **语言与框架** | Flutter 3.x / Dart 3.x | 跨平台 UI 渲染框架（Windows / Android / iOS） |
| **网络请求** | `dio` + `cookie_jar` | 保持 Discuz Session，自动管理 `saltkey`、`auth`、`cookiepre` |
| **HTML/DOM 解析** | `html` (dart package) | 逆向提取 Discuz Comiis 移动端与 PC 端的 DOM 节点 |
| **图片加载与缓存** | `cached_network_image` | 离线图片缓存、多级画质控制、占位骨架屏 |
| **状态与持久化** | `shared_preferences` | 本地存储主题配置、排版模式、黑名单、历史记录等 |
| **测试框架** | `flutter_test` | 单元测试、解析器测试与 Headless Widget 截图测试 |

---

## 3. 项目目录结构与源码地图

```
f:/klpbbs/klpbbs_app/
├── lib/
│   ├── api/                           # 网络层与 HTML 数据解析
│   │   ├── dio_client.dart            # Dio 基础单例与 CookieJar 配置
│   │   ├── klpbbs_api.dart            # 论坛 API 请求封装（登录/发帖/回帖/个人中心）
│   │   └── comiis_parser.dart         # Discuz DOM 逆向解析器（核心数据提取引擎）
│   ├── core/                          # 全局配置与状态
│   │   ├── app_config.dart            # 主题风格、排版模式、画质与全局设置
│   │   └── constants.dart             # API 路径常量、请求头等
│   ├── models/                        # 数据模型
│   │   ├── forum.dart                 # 版块与分类模型
│   │   ├── thread_summary.dart        # 帖子列表摘要模型
│   │   ├── horn_message.dart          # 小喇叭公告广播模型
│   │   ├── sign_info.dart             # 签到排行与状态模型
│   │   └── user_profile.dart          # 用户个人资料模型
│   ├── pages/                         # 业务页面
│   │   ├── home_page.dart             # 论坛首页（自适应 Feed、小喇叭、快捷入口、版块分类）
│   │   ├── thread_detail_page.dart    # 帖子详情页（楼层列表、作者卡片、底部快捷交互栏）
│   │   ├── login_page.dart            # 登录页（账号密码 + SecCode 验证码 + Cookie 快速导入）
│   │   ├── register_page.dart         # 注册页
│   │   ├── forum_page.dart            # 版块帖子列表页
│   │   ├── search_page.dart           # 搜索页（帖子/用户/版块）
│   │   ├── user_space_page.dart       # 用户个人空间主页
│   │   ├── notice_page.dart           # 系统通知与提醒页
│   │   ├── pm_inbox_page.dart         # 站内私信会话页
│   │   ├── post_page.dart             # 发帖/编辑帖子页
│   │   └── settings_page.dart         # 全局高级设置页
│   └── widgets/                       # 通用 UI 组件
│       ├── discuz_post_renderer.dart  # Discuz 结构化富媒体排版渲染引擎（11类Block）
│       ├── thread_card.dart           # 自适应帖子卡片（列表布局 & PC 网格布局）
│       ├── horn_banner_widget.dart    # 小喇叭公告跑马灯
│       ├── user_avatar_widget.dart    # 用户头像与挂件组件
│       └── rich_editor_widget.dart    # 富文本/BBCode 发帖编辑器
├── test/                              # 自动化测试用例
│   ├── comiis_parser_test.dart        # 解析引擎单元测试（全量覆盖）
│   ├── settings_test.dart             # 配置持久化与黑名单测试
│   └── render_screenshots_test.dart   # 界面渲染与截图测试
└── mock-server/                       # 本地 Mock 数据服务器与真实 HTML 样本
    └── samples/                       # viewthread.html, forumdisplay.html 等真实样本
```

---

## 4. Discuz 逆向解析与关键业务机制

### 4.1 会话管理与 FormHash
- 论坛所有写操作（登录、发帖、回复、签到、点赞）均依赖 `formhash`。
- `ComiisParser.extractFormHash(html)` 负责从页面隐藏 input `<input type="hidden" name="formhash" value="..."/>` 或 JS 变量 `var formhash = '...'` 中提取。

### 4.2 SecCode 验证码机制
- 登录和发帖需要通过 `misc.php?mod=seccode&action=update&idhash=...` 获取更新，并通过 `misc.php?mod=seccode&update=...&idhash=...` 获取图片。
- **必须保证请求携带相同的 Dio CookieJar 会话**（包含 `saltkey`），否则 Discuz 服务端无法校验 session，验证码将报失效。

### 4.3 结构化富媒体渲染引擎 (`DiscuzPostRenderer`)
Discuz 帖子正文通常包含复杂的 Comiis 标签和嵌套结构。`ComiisParser.parseStructuredBlocks` 将其解析为 11 种强类型 Block：
1. `TextBlock`：常规富文本与行内样式（粗体、斜体、下划线、字号、颜色、链接）
2. `SpoilerBlock`：Discuz 折叠块/展开隐藏内容
3. `CodeBlock`：语法高亮代码块
4. `QuoteBlock`：引用他人回复/系统引用
5. `VideoBlock`：Bilibili / HTML5 / 原生 MP4 视频播放卡片
6. `AudioBlock`：音频播放组件
7. `NetdiskBlock`：百度网盘 / 夸克网盘 / 123云盘提取码卡片
8. `AttachBlock`：论坛附件、压缩包、MC 附加包 (.mcpack / .mcaddon / .mcworld) 下载
9. `TableBlock`：多行多列数据表格
10. `ImageBlock`：高清大图、多图相册画廊
11. `DividerBlock`：分割线

---

## 5. 近期已完成的重构成果

1. **登录验证码重构**：
   - 彻底修复 `LoginPage` 验证码加载失败问题，增加 `KlpbbsApi.getSecCodeImageBytes` 二进制流直接加载与重试机制。
2. **PC 桌面自适应排版优化**：
   - 修复了 `home_page.dart` 中版块分类导航的 `2.8px OVERFLOWED` 溢出；
   - 重构 PC 端 `GridView` 为横向紧凑图文卡片 (`SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 440, mainAxisExtent: 142)`)，解决原本 400px 巨型空白方块问题；
   - 重构 `ThreadCard` 底部作者栏为弹性伸缩布局，彻底消除横向 Row 溢出。
3. **帖子排版与 Discuz 残留清理**：
   - 在 DOM 清洗阶段过滤掉 `.comiis_rate`, `div[id^="ratelog_"]`, `.comiis_dzhan_img`, `.pstatus`, `style`, `script` 等冗余原生插件噪音；
   - 递归解开 Discuz 用于排版的外层单格嵌套表格，使富媒体内容直接暴露并由 Flutter 原生组件高效渲染。
4. **测试与截图核验**：
   - 13/13 自动化单元测试 100% 通过；
   - 产出 Headless 渲染真实截图，核验通过。

---

## 6. 后续待办事项与开发路线 (Roadmap)

接手者可优先跟进以下功能与优化：

- [ ] **发帖与回复高级功能联调**：
  - 发帖页面表情包选择器（Discuz 经典小黄脸、苦力怕论坛自定义表情包）；
  - 上传图片/附件进度条与 Discuz 附件 hash 回填。
- [ ] **回帖可见 / 购买可见隐藏内容处理**：
  - 遇到 `*** 隐藏内容需要回复后查看 ***` 时，提供一键快捷回复并局部刷新当前楼层。
- [ ] **视频播放器桌面端原生强化**：
  - 增强 `discuz_post_renderer.dart` 对 B 站 `bilibili.com/video/BV...` 嵌入 iframe 的原生全屏播放支持。
- [ ] **离线缓存与深色模式打磨**：
  - 对离线浏览数据进行 SQLite / Hive 缓存；
  - 优化纯黑 OLED 模式与护眼绿色调的高对比度文字可读性。

---

## 7. 本地运行、调试与测试指令

### 7.1 获取依赖
```bash
cd f:\klpbbs\klpbbs_app
flutter pub get
```

### 7.2 运行测试
```bash
# 运行单元测试（解析器 + 设置项）
flutter test test/comiis_parser_test.dart test/settings_test.dart

# 静态代码检查（确保 0 错误）
flutter analyze
```

### 7.3 Windows 桌面端构建与运行
```bash
# Debug 模式运行
flutter run -d windows

# Debug 模式编译 exe
flutter build windows --debug

# 编译输出路径：
# build\windows\x64\runner\Debug\klpbbs_app.exe
```

### 7.4 启动本地 Mock 服务器（可选，用于无网离线开发）
```bash
cd f:\klpbbs\mock-server
node server.js
# 本地服务将在 http://127.0.0.1:3000 运行
```

---

## 8. 核心避坑指南 (Gotchas)

1. **单格排版表格解包**：
   - Discuz Comiis 移动端页面通常将整篇帖子内容套在一个 `<table style="width:100%"><tr><td><main>...</main></td></tr></table>` 内。
   - **切勿直接把所有 `<table>` 当做数据表渲染**，解析器中已内置 `_unwrapSingleCellTable` 递归解包逻辑，修改解析器时请勿破坏该逻辑。
2. **Flutter 异步生命周期**：
   - 在 async 方法中使用 `BuildContext` 时，务必先判断 `if (!mounted) return;`，防止页面销毁后的 context 悬挂崩溃。
3. **Timer 与测试环境**：
   - 如在 Widget 中使用了 `Timer.periodic`（例如跑马灯、倒计时），在编写 widget test 时必须使用固定 `pump(Duration)` 或在测试结束时 unmount，避免 `timersPending` 异常。
4. **Cookie 隔离**：
   - 苦力怕论坛主站与头像站域名不同（`klpbbs.com` 与 `user.klpbbs.com`），头像请求为静态只读，无需携带敏感 Cookie。

---
*祝开发顺利！如有任何架构或接口疑问，请查阅 `mock-server/samples/` 中的真实 HTML 样例。*
