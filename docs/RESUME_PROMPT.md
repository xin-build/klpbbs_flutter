# 苦力怕论坛客户端 —— 继续工作提示词

把下面整段作为提示词，交给新会话即可无缝接手：

---

你在开发一个 Flutter 客户端「苦力怕论坛客户端」，100% 复刻 klpbbs.com 移动端模板（克米 comiis_app）+ PC 专属功能。

## 环境（务必遵守）
- 工作目录：`F:\klpbbs`；Flutter 工程：`F:\klpbbs\klpbbs_app`。
- Flutter 二进制：`D:\fullter\flutter\bin\flutter.bat`（3.32.5/Dart 3.8.1），**不在 PATH，必须用绝对路径**。
- 本地测试论坛：`http://127.0.0.1:8000/`；账号 `admin/Admin@123456`、`testuser/Test@123456`。
- 构建/测试/编译命令必须先 `cd` 到 `klpbbs_app`：
  `D:\fullter\flutter\bin\flutter.bat analyze` / `... test` / `... build windows --release`。
- exe 被占用导致 LNK1104 时：`Get-Process klpbbs_app | Stop-Process -Force` 再重跑 build。

## 安全红线
- 真实论坛 klpbbs.com：AI 只做 GET 只读 + 登录；**绝不**发帖/回复/编辑/打赏/签到/小喇叭/道具等写操作。
- 写操作只在 127.0.0.1:8000 测试；本地缺插件（replyfloor/ahome_horn）的写操作「暂时不测」。
- 真实论坛只读登录 cookie 在 `mock-server/samples/cookies.txt`（cookiepre=8Mjv_2132_，含 auth+saltkey）。

## 工作流（每轮）
1. 从下方「剩余待办」挑一项，按「抓真实样本 → 写/改代码 → analyze+test → build → flash 核验渲染 → 更新 PLAN.md」推进。
2. 反向工程只读抓取 klpbbs.com，HTML 样本存 `mock-server/samples/`，每个新解析器都加单测到 `test/comiis_parser_test.dart`。
3. 渲染类问题用 flash 模型核验：
   环境变量 `ANTIGRAVITY_LS_ADDRESS='127.0.0.1:1759'`、`ANTIGRAVITY_CSRF_TOKEN='dcdaf8e4-eb37-447d-b5f5-8916d7030ac5'`、`ANTIGRAVITY_PROJECT_ID='785a8d40-1b4a-42b2-b6aa-b8099bc2309f'`；
   `language_server.exe agentapi new-conversation --model=flash "提示词"`，读 `~/.gemini/antigravity/brain/{id}/.system_generated/logs/transcript.jsonl`（PLANNER_RESPONSE，GBK/936）。
4. 每轮改完在 `docs/PLAN.md` 追加 reverse-chron `[x]` 进度条目。

## 架构速览
- 解析器：`lib/api/comiis_parser.dart`（HTML→模型）；接口：`lib/api/klpbbs_api.dart`（_get/_post，GET 30s 缓存）。
- 帖子正文渲染：`lib/widgets/discuz_post_renderer.dart`（结构化 blocks + `_htmlToSpans`）。
- 帖子卡片/头像：`lib/widgets/thread_card.dart`（`UserAvatarWidget`）。
- 网络策略：`lib/core/dio_client.dart`（ReadWritePolicy 白名单）。
- 全局配置：`lib/core/app_config.dart`（allowWrite 已恒 true；userAgent 可切 PC/手机）。

## 关键陷阱（已踩过，勿重蹈）
- `package:html` 会把 `<main>` 内 `<table>` 移到 main 外：解析楼层正文别用 `parseFragment`，用 `message.clone(true)`，coreBody 无 table 时回退父 td。
- 写 Dart 正则时 JS 模板字面量会剥反斜杠，`\[` 要写 `\\[`。
- `_cleanTitle` 剥零宽空格/私有区图标字体（U+E000-F8FF）/回复阅读日期后缀。
- `_extractFormhash` 多模式（JS 单双引号 / hidden input / URL）。
- 头像用 `UserAvatarWidget`，别用 `CircleAvatar(backgroundImage+child)`。
- 图片优先 `comiis_loadimages`（原图），别用 `src`（预览图/none.png）。
- 嵌套表格=布局表要扁平化（直接行判断 + 只解析直接 td）。

## 已完成（约 58 项，别重复做）
写操作开放、formhash 多模式、打赏 score2、楼中楼/签到/小喇叭/道具对齐、头像挂件、分区名/今日总贴数分离、发帖选版块、嵌套表格正文、标题徽章、通知解析、首页导读热门、帖子所属板块、导航菜单/分页跳页/图片重试/高级搜索/自定义UA、编辑器 BBCode+smilies、附件卡片、折叠行高、图片满宽、豆腐块字体。

## 剩余待办（优先做）
1.【高】编辑器增强：专业工具栏（更多 BBCode 按钮/字号/颜色/对齐），确认无系统 emoji，保留原站全部 Discuz smilies（贴吧/B站/抖音/QQ，已接入）。
2.【高】资源贴信息：地图/模组/材质等资源贴有分类字段（版本/依赖/授权等），让用户给 2-3 个不同类型资源贴链接，抓样本提取字段。
3.【中】导航菜单全局：抽屉只在主 shell，pushed 页面无全局菜单入口，需确认/补。
4.【中】首页热门/图文推荐信息、附件卡片加下载次数/积分价格/购买状态。
5.【低】图片查看器自然尺寸+双击缩放、折叠内容用完整渲染器。

## 接手第一步
先跑 `analyze` + `test`（当前 65 测）+ `build` 确认基线，然后从待办 1 或 2 开始。遇到结构未知就「找不到直接抓」真实页面；写操作「本地可测的测，不可测的暂缓」。

详细背景另见 `docs/HANDOFF.md`、`docs/PLAN.md`、`docs/REVERSE_ENGINEERING.md`。