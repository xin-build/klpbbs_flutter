# 苦力怕论坛客户端 接手文档

> 生成时间：2026-08-18。本文档供后续接手者快速了解项目状态、架构、已做/未做事宜。

---

## 1. 项目概况

- 目标：Flutter 桌面/移动客户端，100% 复刻 klpbbs.com 移动端模板（克米 comiis_app）+ PC 专属功能。
- 工作目录：`F:\klpbbs`；Flutter 工程：`F:\klpbbs\klpbbs_app`。
- Flutter：`D:\fullter\flutter\bin\flutter.bat`（3.32.5 / Dart 3.8.1），**不在 PATH，必须用绝对路径**。
- 本地测试论坛（真实 Discuz X3.4 + comiis）：`http://127.0.0.1:8000/`；账号 `admin/Admin@123456`、`testuser/Test@123456`。

---

## 2. 架构分层

| 目录 | 职责 |
|---|---|
| `lib/core/` | `app_config.dart`（全局配置/主题/UA/写开关）、`dio_client.dart`（网络 + ReadWritePolicy 访问策略）、`bbcode.dart`（BBCode→HTML）、`write_confirm.dart`（写操作二次确认） |
| `lib/api/` | `klpbbs_api.dart`（所有 GET/POST 接口）、`comiis_parser.dart`（HTML→模型，核心解析器） |
| `lib/models/` | `thread_summary.dart`、`post_floor.dart`、`post_block.dart`、`forum.dart`、`user_space.dart`、`horn_message.dart`、`smiley.dart`、`pm_models.dart` 等 |
| `lib/widgets/` | `thread_card.dart`（帖子卡片 + `UserAvatarWidget` 头像）、`discuz_post_renderer.dart`（帖子正文富媒体渲染）、`horn_banner_widget.dart`、`responsive_layout.dart`（自适应主框架）、`retry_image.dart`（图片自动重试）、`skeleton_list.dart` |
| `lib/pages/` | 各页面：首页/帖子详情/帖子列表/用户空间/私信/好友/签到/小黑屋/搜索/发帖/小喇叭/登录/设置/通知等 |
| `docs/` | `PLAN.md`（计划+进度记录）、`REVERSE_ENGINEERING.md`（逆向结论）、`HANDOFF.md`（本文） |
| `mock-server/samples/` | 真实抓取的 HTML 样本（解析器单测用） |
| `tools/` | 抓包辅助工具（见 §7） |
| `refs/` | 外部参考（DiscuzSign 等） |

---

## 3. 关键机制

### 3.1 网络与安全
- `KlpbbsApi._get/_post`：Dio + `validateStatus code<400` + bytes 响应 + GBK 容错 `_decode`。
- **GET 缓存**：内存缓存 30s TTL，POST 后清空。
- **ReadWritePolicy**（`dio_client.dart`）：`_allowedPathPatterns` 白名单 + `_writePatterns` 写操作白名单（rate/replyfloor/ahome_horn/qiandao/magic/recommend/comment/spacecp/logout 等）。
- **写操作**：`AppConfig.allowWrite` 已改**恒 true**（用户可用）；真实论坛写操作经 `needRealWriteConfirm` 二次确认。
- **安全红线（仅对 AI 开发期）**：真实 klpbbs.com 上，AI 代理只做 GET 只读 + 登录；**绝不**发帖/回复/打赏/签到/小喇叭等写操作。写操作只在 127.0.0.1:8000 测试。

### 3.2 逆向方法
- 真实论坛只读抓取（用 `mock-server/samples/cookies.txt` 的登录 cookie），存 HTML 样本到 `mock-server/samples/`。
- 用 `package:html` 解析，对照 comiis 模板结构写 `comiis_parser.dart` 静态方法。
- 每个新解析都加单测（`test/comiis_parser_test.dart`），断言真实样本字段。
- **Flash 模型（Antigravity）** 用于 UI 渲染核验：
  - 环境变量：`ANTIGRAVITY_LS_ADDRESS='127.0.0.1:1759'`、`ANTIGRAVITY_CSRF_TOKEN='dcdaf8e4-...'`、`ANTIGRAVITY_PROJECT_ID='785a8d40-...'`。
  - 命令：`language_server.exe agentapi new-conversation --model=flash "提示词"`，读 `~/.gemini/antigravity/brain/{conversationId}/.system_generated/logs/transcript.jsonl`（PLANNER_RESPONSE，GBK/936 解码）。

### 3.3 构建/测试命令（必须 cd 到 klpbbs_app）
```powershell
D:\fullter\flutter\bin\flutter.bat analyze
D:\fullter\flutter\bin\flutter.bat test
D:\fullter\flutter\bin\flutter.bat build windows --release
# 若 exe 被占用：Get-Process klpbbs_app | Stop-Process -Force
```

---

## 4. 已完成（本会话累计约 58 项，摘重要）

- 写操作开放（allowWrite=true + writePatterns 补全）
- formhash 提取多模式（JS/hidden input/URL）→ 修点赞/收藏/打赏失败
- 打赏 score2=铁粒、楼中楼 replyfloor、签到 k_misign(DiscuzSign)、小喇叭 ahome_horn、道具 magic 全部对齐
- 头像挂件 sunju_facemall（faceUrl 叠加）
- 分区版块名（img.alt 优先）、今日/总贴数分离、发帖选版块（真实分区扁平化）
- 嵌套表格正文（layout table 扁平化 + clone 避免 parseFragment 破坏 table）
- 标题零宽字符/图标字体剥离（荐/红包贴/热徽章）
- 通知 div.ntc_body 解析、首页推荐改导读热门（含作者）
- 帖子详情显示所属板块 forumName
- 移动端导航菜单（scaffoldKey 挂载 + 汉堡按钮）、分页跳页输入、图片自动重试、高级搜索、自定义 UA（PC/手机）
- 编辑器 BBCode 工具栏 + Discuz smilies + 预览（贴吧/B站/抖音/QQ）
- 附件卡片（文件类型徽章）、折叠 spoiler 行高、图片满宽 fitWidth、豆腐块字体回退
- 用户空间（签名/勋章/等级/积分/别人空间去个人入口）

---

## 5. 剩余待办

### 高优先级
1. **编辑器增强**：用户要求「专业、不准塞 emoji、原站全部表情」。当前已接入 Discuz smilies（贴吧/B站/抖音/QQ），需增强工具栏（更多 BBCode 按钮、字号/颜色/对齐等）+ 确认无系统 emoji。
2. **资源贴信息**：资源贴（地图/模组/材质等）有分类字段（版本/依赖/授权等），需抓几个热门资源贴样本，按不同类型提取字段。
3. **导航菜单全局**：抽屉只在主 shell，pushed 页面（帖子详情等）只有返回键、无全局菜单；需确认是否要全局抽屉入口。

### 中优先级
4. **首页热门信息**：已改导读热门优先（含作者），但「图文推荐」twlist 无作者，需进一步确认首页各区块。
5. **附件卡片**：已加文件类型徽章，可继续加「下载次数/积分价格/购买状态」等字段（需解析附件详情）。
6. **折叠 spoiler**：已修行高；内容里的嵌套表格/图片用 `_htmlToSpans` 渲染不完整，可考虑用完整渲染器。

### 低优先级
7. 图片查看器 PC 端已加 minScale/视口宽，可继续做「自然尺寸 + 双击缩放 + 边缘拖」。
8. 移动端导航菜单的「进页面退不出」需逐个页面核对 back 按钮。

---

## 6. 已知问题 / 陷阱

- **`package:html` 会把 `<main>` 内的 `<table>` 移到 main 外**：解析楼层正文时不能用 `parseFragment`，要 `message.clone(true)`，且 coreBody 无 table 时回退父级 td。
- **JS 模板字面量反斜杠陷阱**：`\[` 在 JS 字符串里会变 `[`，写 Dart 正则要用 `\\[`；写 Dart 文件用数组 `join("\n")`。
- **`_cleanTitle`**：剥离零宽空格（U+200B/E/F/FEFF）、NBSP、私有区图标字体（U+E000-F8FF，comiis_font 图标码）、回复/阅读/日期后缀。
- **`_extractFormhash`**：多模式（JS 单双引号/hidden input/URL）。
- **头像**：一律用 `UserAvatarWidget`（CachedNetworkImage + 字母 fallback），不要 `CircleAvatar(backgroundImage + child)`（会字母叠头像）。
- **图片 URL**：优先 `comiis_loadimages`（原图），不要 `src`（one.klp.api.mutool.top 预览图/none.png 占位）。
- **写操作测试**：本地插件不全（replyfloor/ahome_horn 本地无），这些写操作「暂时不测」，真实论坛禁写。

---

## 7. 抓包辅助工具

- `tools/capture-server.js`：本地接收服务端，监听 `127.0.0.1:8765`，写 `F:\klpbbs\capture\requests.jsonl`。启动：`node F:\klpbbs\tools\capture-server.js`（后台）。
- `tools/klpbbs-capture.user.js`：油猴脚本 v5，hook fetch/XHR/表单提交，只抓 klpbbs 域名，sendBeacon 上报（防页面跳转丢失）。
- `tools/summarize-captures.js`：流式汇总抓包记录。
- `tools/README.md`：使用说明。

---

## 8. 下一步建议（接手者）

1. 先跑一遍 `analyze` + `test`（65 测）+ `build` 确认基线。
2. 从 §5「高优先级」第 1 项（编辑器）或第 2 项（资源贴）入手。
3. 资源贴：让用户给 2-3 个不同类型的资源贴链接，抓样本 → 看 HTML 字段 → 写 parser + 单测 → 渲染。
4. 渲染问题：截图 → flash 核验 → 改 → 复验。
5. 每轮改完更新 `docs/PLAN.md` 进度记录（reverse-chron `[x]` 条目）。

---

## 9. 当前目标状态

- 目标（goal）**active**：klpbbs 完整功能 + 拓展。
- 会话累计约 58 项修复，核心写操作/解析器/渲染已基本收敛。
