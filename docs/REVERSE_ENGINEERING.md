# klpbbs（苦力怕论坛）逆向分析文档

> 逆向时间：2026-08（以实际会话为准）
> 目标：弄清楚 klpbbs 的前端-后端接口契约，为 Flutter 重写客户端提供依据。
> 原则：**本阶段所有分析仅使用只读 GET 请求，绝不执行任何写操作**（签到/发帖/回复/私信/删帖等一律禁止）。

---

## 1. 论坛概况

| 项目 | 值 |
|---|---|
| 主站 | https://klpbbs.com/ |
| 程序 | Discuz! X3.4（`<meta name="generator" content="Discuz! X3.4">`） |
| 编码 | UTF-8（注意：个别插件模板内嵌 JS 注释为 GBK 字节，解析时需容错） |
| PC 模板 | `template/the_c_style`（克米设计风格模板） |
| 手机模板 | `template/comiis_app` + `source/plugin/comiis_app`（**克米设计 comiis_app**） |
| 伪静态 | 开启：`thread-{tid}-{page}-1.html`、`forum-{fid}-1.html`、`k_misign-sign.html` |
| 头像域 | `https://user.klpbbs.com/avatar.php?uid={uid}&size=middle` |
| 图片域 | `https://img.klpz.net/...`（图床） |

### 1.1 为什么 discuz_flutter 不兼容 klpbbs —— 根因

discuz_flutter（kidozh）依赖 Discuz 官方移动 API：

```
GET /api/mobile/index.php?version=4&module={check|forumlist|newthread|hotthread|...}
```

在 klpbbs 上**全部返回**：

```json
{"error":"module_not_exists"}
```

所有 `version`（1~5）均被禁用。该论坛用**手机网页模板**（`forum.php?...&mobile=2`，comiis_app）替代了官方移动 API。
因此任何依赖官方 mobile API 的通用客户端都无法工作；重写必须基于 HTML 解析或找到论坛自身提供的其他数据通道。

---

## 2. 插件清单（已逆向确认）

插件标识通过页面 HTML 中的 `source/plugin/{name}/` 引用与 `plugin.php?id={name}` 入口确认。

| 插件标识 | 名称/类型 | 入口 | 状态 |
|---|---|---|---|
| `comiis_app` | 克米手机版模板（主） | `forum.php?...&mobile=2` | ✅ 全站手机端 |
| `comiis_app_homestyle` | comiis 首页风格子插件 | 内嵌于 comiis_app | ✅ |
| `comiis_app_portal` | comiis 门户子插件 | `plugin.php?id=comiis_app_portal&pid={id}` | ✅ 可用 |
| `k_misign` | **克米每日签到** | `plugin.php?id=k_misign:sign` | ✅ 可用 |
| `saya_frontjs` | 前端 JS 库（jQuery 3.3.1 改） | `source/plugin/saya_frontjs/sayaquery.js` | ✅ 静态资源 |
| `sunju_facemall` | 表情商城 | `plugin.php?id=sunju_facemall` | ✅ 可用 |
| `ahome_horn` | 公告喇叭 | `plugin.php?id=ahome_horn:index` | ✅ 可用 |
| `pn_qrcode` | 二维码 | - | 静态 |
| `x520_loading` | 加载动画 | - | 静态 |

> 说明：`k_misign`、`comiis_app` 为克米设计（KmDesign/Comiis）商业插件，**闭源**，无法获得本地源码；
> 本地复现只能按接口契约模拟。

---

## 3. 接口契约（只读浏览类，全部 GET）

> 以下接口已用真实请求验证（HTTP 200）。`mobile=2` 返回 comiis_app 手机模板 HTML。

### 3.1 首页 / 版块导航

```
GET https://klpbbs.com/forum.php?mobile=2
```

- 返回：手机版首页（版块导航 + 首页推荐帖）
- 版块链接：`forum-{fid}-1.html`
- 帖子链接：`thread-{tid}-1-1.html`
- 特殊功能：勋章 `home.php?mod=medal`、道具 `home.php?mod=magic`、任务 `home.php?mod=task`、标签 `misc.php?mod=tag`、搜索 `search.php?mod=forum`

### 3.2 版块帖子列表

```
GET https://klpbbs.com/forum.php?mod=forumdisplay&fid={fid}&mobile=2
GET https://klpbbs.com/forum.php?mod=forumdisplay&fid={fid}&filter=typeid&typeid={typeid}&mobile=2   # 按主题分类过滤
GET https://klpbbs.com/forum-{fid}-{page}.html                                                        # 伪静态分页
```

**帖子条目结构**（`<li class="forumlist_li comiis_znalist bg_f b_t b_b comiis_list_readimgs">`）：

```html
<div class="forumlist_li_top cl">
  <a href="home.php?mod=space&uid={uid}&do=profile&mobile=2" class="wblist_tximg">
    <img src="https://user.klpbbs.com/avatar.php?uid={uid}&size=middle">
  <a href="...space&uid={uid}..." class="top_user">{作者，部分打码如 Cin***}</a>
  <span class="f_d">{相对时间，如 "4 天前"}</span>
  <a href="forum.php?mod=forumdisplay&fid={fid}&filter=typeid&typeid={typeid}&mobile=2" class="f_d">来自 {主题分类}</a>
</div>
<div class="mmlist_li_box cl">
  <h2><a href="thread-{tid}-1-1.html" style="color:{颜色}"><span class="comiis_xifont f_g">{前缀如 原创}</span>{标题}</a></h2>
  <div class="list_body cl"><a href="thread-{tid}-1-1.html" class="f_b">{摘要}</a></div>
  <a href="thread-{tid}-1-1.html"><div class="comiis_pyqlist_imgs">...
    <img comiis_loadimages="forum.php?mod=image&aid={aid}&size=220x200&key={key}">
</div>
```

### 3.3 帖子详情

```
GET https://klpbbs.com/forum.php?mod=viewthread&tid={tid}&mobile=2
GET https://klpbbs.com/thread-{tid}-1-1.html                       # 伪静态
GET https://klpbbs.com/forum.php?mod=viewthread&tid={tid}&page={n}&mobile=2   # 分页
GET https://klpbbs.com/forum.php?mod=viewthread&tid={tid}&ordertype=2&mobile=2  # 倒序
GET ...&authorid={uid}                                            # 只看作者
```

**楼层结构**：

```html
<div class="comiis_view_lcrate mt10 mb5">           <!-- 每个楼层一个 -->
  <!-- 作者区 -->
  <img src="https://user.klpbbs.com/avatar.php?uid={uid}&size=middle">
  <a href="home.php?mod=space&uid={uid}&do=profile&mobile=2">{用户名}</a>
  <!-- 内容区 -->
  <div class="comiis_message bg_f view_all cl message">…帖子正文 HTML…</div>
  <div class="comiis_messages comiis_aimg_show cl">…图片…</div>
</div>
```

### 3.4 导读（hot/new）

```
GET https://klpbbs.com/forum.php?mod=guide&view=hot&mobile=2
GET https://klpbbs.com/forum.php?mod=guide&view=new&mobile=2
GET https://klpbbs.com/forum.php?mod=guide&view=newthread&index=1&mobile=2
```

> **导读列表结构**（真实抓取 `guide_hot.html`）：导读热门帖子条目为
> `<a href="thread-{tid}-1-1.html" title="{标题}"><img comiis_loadimages="..."></a>`，
> **标题在 `title` 属性、封面在 `img[comiis_loadimages]`，不在 `<a>` 文本内**；页内另有导航短链接
> （`thread-228-1-1.html` 文本「打赏」等）。解析器需优先取 `a[title]` 并跳过无 title 的短链接。

### 3.5 用户空间

```
GET https://klpbbs.com/home.php?mod=space&uid={uid}&mobile=2
GET https://klpbbs.com/home.php?mod=space&uid={uid}&do=thread&view=me&type=thread&mobile=2   # 主题
GET https://klpbbs.com/home.php?mod=space&uid={uid}&do=thread&view=me&type=reply&mobile=2    # 回复
GET https://klpbbs.com/home.php?mod=space&uid={uid}&do=profile&view=me&from=space&mobile=2   # 资料
```

### 3.6 签到排行（k_misign 只读部分）

```
GET https://klpbbs.com/plugin.php?id=k_misign:sign&operation=list&op=today     # 今日排行
GET https://klpbbs.com/plugin.php?id=k_misign:sign&operation=list&op=month    # 本月排行
GET https://klpbbs.com/plugin.php?id=k_misign:sign&operation=list&op=zong     # 总排行
GET https://klpbbs.com/plugin.php?id=k_misign:sign&operation=list&op=calendar # 签到日历
```

**排行结构**：`<table id="misign_list"><tbody id="autolist_{uid}">…<tr>` 每行一个用户
（头像、用户名、签到数据），JS 通过 `ajaxlist('today'|'month'|'zong'|'calendar')` 切换。
页面导航 tabs：今日排行 / 本月排行 / 总排行 / 签到日历。

### 3.7 帖子图片（防盗链）

```
GET https://klpbbs.com/forum.php?mod=image&aid={aid}&size={w}x{h}&key={md5key}
```

- key 由服务端下发（在 HTML 的 `comiis_loadimages` 属性中），客户端需原样携带。

### 3.8 其他可用页面

```
GET https://klpbbs.com/home.php?mod=medal&mobile=2     # 勋章中心
GET https://klpbbs.com/home.php?mod=magic&mobile=2     # 道具中心
GET https://klpbbs.com/home.php?mod=task&mobile=2      # 任务中心
GET https://klpbbs.com/misc.php?mod=tag&mobile=2       # 标签
GET https://klpbbs.com/search.php?mod=forum&mobile=2   # 搜索页（GET 打开；搜索提交为 POST）
GET https://klpbbs.com/plugin.php?id=comiis_app_portal&pid={pid}&page={n}&comiis_list=yes&inajax=1  # portal 列表 AJAX
```

---

## 4. 写操作接口（本地环境实测验证）

> 以下写操作**已在本地 Discuz X3.4 测试环境（127.0.0.1:8000）完整实测成功**。
> ⚠️ **真实论坛（klpbbs.com）仍属高风险操作**：管理机制严格，随意测试可能导致账号禁言/警告。
> 客户端在真实论坛模式下应保持只读，写操作仅限本地测试环境。

### 4.1 会话机制（formhash + cookie）

Discuz 所有写操作都需要：
1. **登录会话**：`POST member.php?mod=logging&action=login&loginsubmit=yes&loginhash={hash}`，表单字段 `formhash, referer, fastloginfield, cookietime, username, password, answer(安全提问), agreebbrule`。成功后响应设置 `{cookiepre}_auth` cookie（身份凭证）。
2. **formhash**：登录后从目标页面 HTML 提取（`formhash={32位hex}`），每个页面会话内有效。
3. 提交写操作时携带 cookie + formhash，缺任一都会被拒（"来路不正确"/"未登录"）。

### 4.2 接口清单（本地实测成功）

| 接口 | 操作 | 实测参数 |
|---|---|---|
| `POST member.php?mod=logging&action=login&loginsubmit=yes&loginhash={hash}` | 登录 | `formhash, referer, fastloginfield=username, cookietime=2592000, username, password` |
| `GET plugin.php?id=k_misign:sign&operation=qiandao&formhash={hash}&format=empty` | **签到** | 响应 `<root><![CDATA[]]></root>` 成功；数据写入 `pre_plugin_k_misign` |
| `GET plugin.php?id=k_misign:sign&operation=list&op={month\|zong\|空}` | 签到排行（只读） | 排行表格 `J_list_detail` / `misign_list`（版本差异） |
| `POST forum.php?mod=post&action=newthread&fid={fid}&extra=&topicsubmit=yes` | 发帖 | `formhash, posttime(时间戳), subject, message`；成功 301 跳转 |
| `POST forum.php?mod=post&action=reply&tid={tid}&extra=&replysubmit=yes` | 回复 | `formhash, posttime, message` |
| `POST home.php?mod=spacecp&ac=pm&op=send&touid={uid}&pmid=0&pmsubmit=yes` | 私信 | `formhash, message`；数据写入 `uc_pm_messages_{0-9}` 分表 |
| `GET forum.php?mod=misc&action=showdarkroom` | 小黑屋（只读） | 违规用户公示列表（`pre_common_member_crime` action 4/5 + 用户组 4/5） |

### 4.3 本地环境插件差异（与 klpbbs 对比）

| 项 | klpbbs | 本地环境 |
|---|---|---|
| Discuz 版本 | X3.4（较新） | X3.4（20180101） |
| k_misign | 较新版（支持 `op=today/calendar`） | v4.3.0（支持 `op=空/month/zong`） |
| 手机模板 | comiis_app v3.5.1（完整） | comiis_app v3.5.1 + 自写列表模板 |
| 签到排行 id | `misign_list`/`autolist_{uid}` | `J_list_detail`（PC 模板）/`misign_list`（需配置） |

> 客户端适配：排行接口用两端都支持的 `op=month/zong`；`op=today` 仅在 klpbbs 有效。

---

## 5. 关键逆向结论

1. **无官方 JSON API**：只能解析 HTML（comiis_app 手机模板结构稳定，适合写解析器）。
2. **伪静态 URL 规则**：`forum-{fid}-{page}.html`、`thread-{tid}-{page}-1.html` 可解析出结构化数据。
3. **图片链路**：列表缩略图走 `forum.php?mod=image&aid=&size=&key=`（带防盗链 key）；正文图走 `img.klpz.net` 图床。
4. **作者信息打码**：列表中部分用户名显示为 `Cin***` 形式，详情页有完整用户名（可能需要登录态或访问权限）。
5. **分页/排序参数**：`page`、`ordertype`（1 正序 2 倒序）、`authorid`、`filter=typeid&typeid=` 均为标准 Discuz 参数，comiis 模板透传。
6. **反爬特征**：无 UA 时偶发空响应（`curl` 需带浏览器 UA）；首页 `forum.php?mobile=2` 偶发 0 字节，需带完整 UA + Accept-Language。
7. **编码陷阱**：comiis/k_misign 模板内嵌 JS 存在 GBK 注释字节，HTML 解析需容错（`errors='replace'`）。

---

## 6. 本地测试环境（真实 Discuz + 克米插件）

> 原「mock 方案」已升级为**真实 Discuz X3.4 + 克米插件完整环境**（用户提供插件资源）。

### 6.1 环境信息

| 项 | 值 |
|---|---|
| 访问地址 | http://127.0.0.1:8000/ |
| 程序 | Discuz X3.4（20180101，简体 UTF-8） |
| PHP | 7.4.33（内置服务器，`local-env/php`） |
| 数据库 | MariaDB 10.4.32（`local-env/mariadb-data`，root 无密码） |
| 站点目录 | `F:\klpbbs\local-env\www` |
| 插件 | comiis_app 系列 17 个 + k_misign v4.3.0（克米设计） |
| 手机模板 | comiis_app v3.5.1（默认，STYLEID=2） |

### 6.2 测试账号

| 账号 | 密码 | 角色 |
|---|---|---|
| `admin` | `Admin@123456` | 管理员（uid=1） |
| `testuser` | `Test@123456` | 普通用户（uid=2） |
| `baduser` | `Bad@123456` | 违规示例（uid=3，小黑屋 groupid=4） |

### 6.3 启动/维护

```bash
# 数据库
cd F:\klpbbs\local-env\mariadb-10.4.32-winx64 && ./bin/mysqld.exe --datadir="F:\klpbbs\local-env\mariadb-data" --port=3306 --bind-address=127.0.0.1
# 站点
cd F:\klpbbs\local-env\www && F:\klpbbs\local-env\php\php.exe -S 127.0.0.1:8000 -t "F:\klpbbs\local-env\www"
# 缓存/初始化脚本（位于 www/install/）
#   build_cache.php 系统缓存 | install_plugins.php 插件注册 | import_style.php 风格
#   init_comiis_manual.php comiis 配置 | create_users.php 账号
```

### 6.4 本地与 klpbbs 差异（客户端适配要点）

- 签到排行 op：本地 `month/zong/空`，klpbbs 额外支持 `today/calendar` → 客户端用 `month/zong`
- 排行表格 id：本地 PC 模板 `J_list_detail`，klpbbs `misign_list` → 解析器同时兼容
- 手机版列表：本地 comiis 列表结构（`forumlist_li`）与 klpbbs 一致（自写模板保证）
- 伪静态：本地默认关闭（用 `forum.php?mod=` 参数形式），klpbbs 开启（`thread-{tid}-1-1.html`）→ 客户端用参数形式

---

## 7. 编辑器 / 表情 / 小喇叭（2026-08 补充逆向，登录态只读）

### 7.1 登录（真实论坛，只读会话）
- 登录页 `member.php?mod=logging&action=login&mobile=no`：无图形验证码（首试），有 `formhash`、`loginhash`（在 form action 内）。
- 密码经前端 `pwmd5()` MD5 后提交；UCenter `onlogin`：`$passwordmd5 = /^\w{32}$/ ? 直接用 : md5($password)`，再 `md5($passwordmd5.$salt)` 比对。明文或 MD5 均可提交。
- 成功后返回 auth cookie（`{cookiepre}_auth`），curl 用 `-b/-c` 保存即可取得只读登录态。

### 7.2 发帖/回复编辑器（`forum.php?mod=post&action=newthread|reply&fid=…&mobile=2`）
- 表单字段：`posttime`(时间戳)、`subject`、`message`、`typeid`(主题分类 select)、`readperm`(阅读权限)、`allownoticeauthor`、`usesig`、`tags`。
- 附件上传：`attachnew[aid][description]`、`attachnew[aid][readperm]`；插入码 `[attach]aid[/attach]`、`[attachimg]aid[/attachimg]`、`[audio]attach://aid.mp3[/audio]`、`[media=x,500,375]attach://aid.mp4[/media]`。
- BBCode 工具栏：`[img][url][audio][media][flash][quote][code][free][hide=d天数,积分]`。
- 悬赏问答版块 `fid=68`。
- 附件类型图标：`static/image/filetype/{ext}.gif`。

### 7.3 表情目录（`data/cache/common_smilies_var.js`，GBK 编码）
- `smilies_type['_ID'] = ['名称','目录']`；`smilies_array[ID][页] = [['id','code','file','w','h','order'], ...]`。
- 分类（目录名 → 中文名）：`tieba`=贴吧、`bilibili`=B站、`dy`=抖音、`qq`=QQ。
- 图片 URL：`static/image/smiley/{目录}/{file}`；帖子内渲染为 `<img src="static/image/smiley/bilibili/67.png" smilieid="417">`（smilieid 即 smiley id）。
- 注意：JS 内中文 code 为论坛 DB 的 mojibake（GBK 字节被当 UTF-8），客户端按 ASCII 的目录/文件名解析，中文名硬编码映射。

### 7.4 小喇叭（`plugin.php?id=ahome_horn`）
- 读取：社区页内嵌 `#hornbox`，结构 `table.tsmini_horn_content > tr#horn_{id}`，含头像、用户链接、内容（可含 `<img>` 表情、`thread-` 链接）、时间。
- 表情：`source/plugin/ahome_horn/image/smiles/{n}.png`（独立表情集）。
- 发布入口：`plugin.php?id=ahome_horn:add&fid=&tid=0&fromurl=…`（写操作，仅本地测试）。

#### 7.4.1 发布表单（真实抓取 horn_add.html，登录态）

`<form action="plugin.php?id=ahome_horn:add" method="post" enctype="multipart/form-data">`：

| 字段 | 说明 |
|---|---|
| `formhash` | 会话凭证 |
| `fid`/`tid`/`fromurl` | 隐藏字段（空） |
| `ifsystem` | 消息类型：`0` 个人消息 |
| `hidename` | `0` 公开身份 |
| `color` | 文本颜色 select（默认色 + 14 色：#000000/#FF0000/#f37b1d/#fbbd08/#8dc63f/#39b54a/#1cbbb4/#0081ff/#6739b6/#9c26b0/#e03997/#f691b2/#a5673f/#8799a3） |
| `boss` | 土豪霸屏 checkbox（额外 1000 铁粒/天） |
| `message` | 消息内容 textarea（maxlength=240） |
| `addsubmit` | 提交按钮 value=true |

- 发布费用：15 铁粒/条。
- 内置表情 24 个：`source/plugin/ahome_horn/image/smiles/{0-23}.png`，点击插入码 `[s:{n}]`（如 `[s:0]`）。
- 客户端：`parseHornPostInfo`（formhash+颜色）、`getHornPostInfo`/`postHorn`（仅本地可写）、`HornPostPage` 发布页（内容+颜色+表情+霸屏）；读取侧 `parseHornMessages` 保留 `<img>` 表情 + `_HornCard` 用 `InlineHtmlText` 渲染。

### 7.5 签名编辑（`home.php?mod=spacecp&ac=profile&op=info`）
- PC 模板含签名输入框（Discuz 代码），字段随 `ac=profile` 提交（`signature` 等）。

### 7.6 客户端已完成（对应实现）
- `parseSmilies` 解析表情目录（`SmileyCategory`/`Smiley` 模型 + `getSmilies`）。
- 帖子渲染：`ImageBlock.isEmoji` 标记表情按原始比例（~20px）渲染；`_htmlToSpans` 处理行内 `<img>`（此前被丢弃）。
- `parseForumGroups` 解析社区版块树；`parseThreadList` 匹配真实 `comiis_milist` 结构 + 精/荐/热度/置顶标签。
- 编辑器（`post_page.dart`）已加：Discuz 代码（BBCode）工具栏（`[b]/[i]/[u]/[color]/[img]/[url]/[quote]/[code]/[hide]/[spoiler]`，`_insertTag` 包裹选中文本/`_insertText` 光标处插入）；全站表情面板（`getSmilies` 4 分类贴吧/B站/抖音/QQ，点击插入表情 `code`，如 `[贴吧_呵呵]`/`[QQ_119]`）；`core/bbcode.dart` 提供 BBCode→HTML 本地转换 + 编辑器「预览」按钮（`DiscuzPostRenderer` 渲染预览）。

---

## 8. 楼中楼（replyfloor 插件）逆向

> 来源：`mock-server/samples/viewthread.html`（tid=124867，真实抓取）。插件目录 `source/plugin/replyfloor/`，本地环境未安装。

### 8.1 结构

replyfloor 是**克米/第三方「楼中楼」插件**，在每条楼层正文（`div.comiis_message`）之后、签名档之前插入：

```html
<div class="replyfloor_box" id="replyfloor_box_{pid}" onclick="event.stopPropagation();">
  <div class="replyfloor_hd">
    <span class="replyfloor_tail_floor"><em>{楼层号}</em><sup>#</sup></span>
    <span class="replyfloor_tail_time">{时间}<code class="comiis_iplocality f_d">  IP:{省}</code></span>
    <span class="replyfloor_link_unfold">回复<span class="replyfloor_count">(<span id="replyfloor_count_{pid}">{N}</span>)</span></span>
    <span class="replyfloor_link_fold">收起回复</span>
  </div>
  <div class="replyfloor_bd bg_e" id="replyfloor_bd_{pid}">
    <div class="replyfloor_content" id="replyfloor_content_{pid}">
      <div class="replyfloor_content_ul bg_e">
        <div class="replyfloor_content_li" id="replyfloor_content_li_{msgid}">
          <div class="replyfloor_content_avatar"><a href="...space&uid={uid}..."><img src="...avatar...&size=small" /></a></div>
          <div class="replyfloor_content_cnt">
            <div class="replyfloor_content_head">
              <span class="replyfloor_content_user"><a href="...">{用户名}</a></span>
              <span class="replyfloor_content_location">IP：{归属地}</span>
            </div>
            <div class="replyfloor_content_main">
              <div class="replyfloor_content_text">{正文，可含行内表情 <img smilieid="...">}</div>
            </div>
            <div class="replyfloor_content_foot">
              <span class="replyfloor_content_time">{时间}</span>
              <span class="replyfloor_content_rpbtn" onclick="replyfloor_editor('{pid}', {msgid}, '回复 {名} :');">回复</span>
              <span class="replyfloor_content_reportbtn" onclick="replyfloor_report('{pid}', {msgid});">举报</span>
            </div>
          </div>
        </div>
      </div>
    </div>
  </div>
</div>
```

### 8.2 关键结论

1. **定位**：`div.replyfloor_box` 是 `div.comiis_postli`（楼层）的子元素，`id="replyfloor_box_{pid}"` 与楼层 pid 对应；但正文容器 `div.message` 的 id 也等于 pid。
2. **每条回复**：`.replyfloor_content_li`（`id=replyfloor_content_li_{msgid}`），msgid 为楼中楼回复 id。
3. **正文**：`.replyfloor_content_text` 的 innerHTML（保留 `<img smilieid>` 行内表情，走 `static/image/smiley/` 目录）。
4. **元数据**：用户名+uid 在 `.replyfloor_content_user a[href*=mod=space]`；IP 在 `.replyfloor_content_location`；时间在 `.replyfloor_content_time`；头像在 `.replyfloor_content_avatar img`（size=small）。
5. **总数**：`#replyfloor_count_{pid}` 为楼中楼回复总数（可能大于当前页已渲染条数，插件支持分页）。
6. **写操作**：`plugin.php?id=replyfloor:index&ac=post`（formhash + pid + msgid + message），举报 `ac=report`；本地环境无此插件，仅实现只读渲染。
7. **与 Discuz 原生「点评 postcomment」区分**：点评结构（`.rate_comment li` / `.postcomment li`）与 replyfloor 是两套机制；客户端分别解析为 `PostFloor.comments` 与 `PostFloor.replyFloors`。

### 8.3 客户端实现

- `ReplyFloorComment` 模型（msgid/uid/author/avatar/contentHtml/timeText/location）。
- `PostFloor` 新增 `replyFloors` / `replyFloorCount` / `floorNumber`。
- `ComiisParser._parseReplyFloor` 解析 `div.replyfloor_box`；`parseThreadDetail` 正文剔除 `.replyfloor_box` 与签名档，楼中楼单独渲染。
- `InlineHtmlText` 组件渲染楼中楼正文（行内表情/链接/加粗/颜色）。
- 打赏记录 `ratelog` 解析重写：按 `li[id^=rate_]` 结构提取 `a.f_c`(用户) / `span.f_a`(金额) / `p`(理由)，并在楼层底部渲染。

---

## 9. 用户徽章（top_lev 用户组 / comiis_verify 认证）

> 逆向来源：`mock-server/samples/viewthread.html`（真实抓取，含管理员/版主/普通会员）
> + 本地插件源码 `source/plugin/comiis_app/function/function_comiis_load.php`。

### 9.1 结构

楼层作者名后紧跟两个徽章元素（在 `div.comiis_postli_top h2` 内）：

```html
<h2>
  <a href="...space&uid={uid}..." class="top_user f_b">{用户名}</a>
  <a href="home.php?mod=spacecp&ac=usergroup&gid={gid}&mobile=2"
     class="top_lev bg_a f_f" style="background:#FF0000 !important"> 管理员</a>
  <span class="comiis_verify"></span>
</h2>
```

1. **top_lev（用户组徽章）**：`<a class="top_lev bg_a f_f">`
   - 文本 = 用户组标题：`Lv.1 新手上路` / `Lv.2 注册会员` / `Lv.3 中级会员` / `Lv.4 高级会员` / `管理员` / `版主` 等。
   - `gid` 从 href `ac=usergroup&gid={gid}` 提取：1=管理员、3=版主、10/11/12/13…=普通会员等级。
   - 特殊用户组带内联 `style="background:#XXX !important"`：管理员 `#FF0000`（红）、版主 `#FF00FF`（品红）；普通会员无内联色（用主题色浅底）。
   - 另有一枚 `top_lev bg_c f_f` 文本为「楼主」的徽章（`isThreadAuthor`）。
2. **comiis_verify（认证徽章）**：`<span class="comiis_verify">`，无认证时为空。有认证时内部为：
   ```html
   <a href="home.php?mod=spacecp&ac=profile&op=verify&vid={vid}" target="_blank">
     <img src="{icon}" class="vm" alt="{title}" title="{title}" />
   </a>
   ```
   （来源：`comiis_forumdisplay_verify_author()` 遍历 `common_member_verify`，`verify{vvid}==1` 且 `showicon` 时输出 `<a><img alt=title title=title></a>`，vid 为认证类型 id。）

### 9.2 关键结论

1. 「VIP/SVIP」在 comiis_app 中并非独立插件，而是由 **用户组（top_lev）+ 认证（comiis_verify）** 两类徽章共同表达：特殊用户组（管理员/版主/VIP 组）用内联背景色，认证用图标。
2. `top_lev` 的 `style` 内联背景色是区分「管理员/版主/特殊组」与「普通 Lv 会员」的唯一视觉依据；普通会员无内联色。
3. `comiis_verify` 图标高度 14px（`.comiis_postli_top .comiis_verify img {height:14px}`）。
4. 客户端需同时渲染：等级徽章（带正确背景色）+ 认证图标，才能 100% 还原。

### 9.3 客户端实现

- `PostFloor` 新增 `levelGid`(int?) / `levelColor`(String) / `verifies`(List<{img,title,vid}>)。
- `ComiisParser.parseThreadDetail` 提取 `top_lev` 的 gid + 内联背景色，`comiis_verify` 的 `<a><img alt/title>` + vid。
- `thread_detail_page` 的 `_badgeColor` 按内联色渲染等级徽章（红/品红/主题色浅底），认证徽章以 14px 图标渲染。

---

## 10. 勋章（medal）逆向

> 来源：`mock-server/samples/user_check.html`（PC 用户空间真实抓取，含 10 枚勋章）
> + 本地插件模板 `template/comiis_app/touch/home/space_profile.php`（手机模板）。

### 10.1 结构

勋章出现在**用户空间资料页**（`home.php?mod=space&uid={uid}&do=profile`），不在楼层头。两套模板：

1. **手机模板**（`mobile=2`，`#comiis_medal`）：
   ```html
   <div id="comiis_medal" class="profile_r comiis_medal">
     <li class="swiper-slide">
       <a href="javascript:;" onclick="popup.open('...<img>...<em>名称</em>...<em>描述</em>...', 'alerts');">
         <img src="{STATICURL}/image/common/{file}" alt="{名称}" id="md_{medalid}" class="vm" />
       </a>
     </li>
   </div>
   ```
2. **PC 模板**（`p.md_ctrl` + tooltip 菜单）：
   ```html
   <h2>勋章</h2>
   <p class="md_ctrl"><a href="home.php?mod=medal">
     <img src="static//image/common/medal/{file}" alt="{名称}" id="md_{id}" />
   </a></p>
   <div id="md_{id}_menu" class="tip tip_4" style="display:none;">
     <div class="tip_c"><h4>{名称}</h4><p>{描述}</p></div>
   </div>
   ```

### 10.2 关键结论

1. 勋章 id 前缀 `md_`（`img[id="md_{id}"]`），名称在 `alt`，图片在 `src`（`static/image/common/medal/{file}`，PC 模板双斜杠 `static//image` 需折叠）。
2. 描述：PC 模板在 `div[id="md_{id}_menu"] .tip_c p`；手机模板嵌在 onclick 弹窗 JS 字符串里（未单独解析，名称足够）。
3. 勋章中心（`home.php?mod=medal`）用 `id=medal_{id}`（前缀 `medal_`），与用户空间的 `md_` 前缀不同，两者分别解析。

### 10.3 客户端实现

- `UserSpace` 新增 `medals`(List<{id,name,desc,img}>)。
- `ComiisParser.parseUserSpace` 从 `#comiis_medal img[id^=md_]` / `p.md_ctrl img[id^=md_]` 提取勋章，desc 从 `md_{id}_menu` 提示框提取；`_medalUrl` 折叠路径双斜杠。
- `user_space_page` 在资料卡片下方渲染勋章（Wrap 图标 + Tooltip 显示名称/描述）。

---

## 11. 使用道具（mgc_post_{pid} 菜单）与分享框（comiis_share_box）

> 来源：`mock-server/samples/viewthread.html`（真实抓取）。

### 11.1 道具菜单（mgc_post_{pid}）

每条楼层后有一个道具菜单容器（`comiis_pltit` 之后、正文之前/之后）：

```html
<div id="mgc_post_{pid}" popup="true" class="comiis_bodybg comiis_popup comiis_mgcshow"
     style="display:none">
  <ul class="cl">
    <li class="bg_f f_b">
      <a href="home.php?mod=magic&mid={mid}&idtype={idtype}&id={id}&mobile=2"
         id="a_{mid}" class="dialog">
        <img src="static/image/magic/{mid}.gif" />{道具名}
      </a>
    </li>
  </ul>
  <div class="kmall bg_f b_t f_g cl"><a href="javascript:;" class="comiis_glclose">取消</a></div>
</div>
```

- 楼层底部的「道具」按钮 `<a href="#mgc_post_{pid}" class="comiis_openrebox">` 打开该菜单。
- 道具项：`mid`（道具标识，如 `bump` 提升卡 / `namepost` 观察者）、`idtype`（`tid` 作用于主题 / `pid` 作用于本楼）、`id`（`pid:tid` 或 `tid`）、图标 `static/image/magic/{mid}.gif`。
- 使用道具（写操作）：`home.php?mod=magic&mid={mid}&idtype={idtype}&id={id}` 打开使用表单，POST `usesubmit=yes` + `formhash` 提交（`home_magic.php` 的 `submitcheck('usesubmit')`）。**仅本地测试环境执行**。

### 11.2 分享框（comiis_share_box）

```html
<div id="comiis_foot_more" class="comiis_share_box comiis_bodybg">
  <div id="comiis_foot_fxbtn"><ul id="comiis_share">…（JS 注入的原生分享图标）…</ul></div>
  <div id="comiis_foot_gobtn" class="b_t cl">
    <ul class="comiis_shareul swiper-wrapper">
      <li class="kmfanhui"><a href="forum-{fid}-1.html">返回本版</a></li>
      <li class="kmfuzhi"><a onclick="comiis_mob_copyurl_key()" data-clipboard-text="【标题】https://.../thread-{tid}-1-1.html">复制链接</a></li>
      <li class="kmdaoju"><a href="#mgc_post_{pid}">道具</a></li>
      <li class="kmjubao"><a onclick="popup.open(...)">举报</a></li>
    </ul>
  </div>
  <h2 class="comiis_share_box_close"><a>取消</a></h2>
</div>
```

- 分享框由头部/底部 `comiis_share_key` 按钮触发，含：原生分享、返回本版、复制链接（标题+URL）、道具、举报、取消。

### 11.3 客户端实现

- `PostFloor` 新增 `magicItems`(List<{mid,name,img,idtype,id}>)。
- `ComiisParser._parseMagicItems` 解析 `div[id^=mgc_post_] > a[href*=mod=magic]`。
- `KlpbbsApi.useMagic` 先取 formhash 再 POST `usesubmit`（仅本地可写）。
- `thread_detail_page` 楼层底部新增「道具」按钮 → 底部弹出道具菜单；分享改为复制「标题+链接」（对应 comiis_share_box 的复制链接）。
