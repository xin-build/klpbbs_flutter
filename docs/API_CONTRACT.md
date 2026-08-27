# klpbbs Flutter 客户端 —— API 解析契约

> 面向客户端开发的解析规则。所有数据来源于 comiis_app 手机模板 HTML（`mobile=2`），
> 无官方 JSON API。解析器针对下述稳定结构编写，样本见 `mock-server/samples/`。

## 0. 通用规则

- **Base URL**：真实 `https://klpbbs.com/`；开发 `http://localhost:3000/`（mock）。
- **UA 要求**：必须携带浏览器 UA，否则偶发空响应。建议：
  `Mozilla/5.0 (Linux; Android 13; Pixel 7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36`
- **编码**：UTF-8；解析时容错（`errors='replace'`），个别插件模板内嵌 JS 有 GBK 字节。
- **只读约束**：客户端只允许 GET 浏览接口；写操作 URL（见 REVERSE_ENGINEERING.md §4）一律不实现。

## 1. 模型（Model）

```dart
// 版块
class Forum {
  int fid;
  String name;          // 版块名
  String? description;  // 简介
  int? threadCount;
}

// 帖子条目（列表）
class ThreadSummary {
  int tid;
  int fid;
  int? uid;             // 作者 uid
  String author;        // 可能打码，如 "Cin***"
  String title;         // 含前缀标签（原创/转载 等）
  String? excerpt;      // 摘要
  String? coverUrl;     // 封面图（forum.php?mod=image... 或图床 URL）
  String? typeName;     // 主题分类，如 "文章"
  String? timeText;     // 相对时间文本，如 "4 天前"
  bool isHot;           // 是否热门（标题颜色为热门色）
}

// 楼层（帖子详情）
class PostFloor {
  int pid;              // 楼层 pid（如无则用 uid+索引）
  int? uid;
  String author;
  String timeText;
  String contentHtml;   // 正文 HTML（含 img/引用/代码块）
  List<String> images;  // 提取的图片 URL
}

// 签到排行条目
class SignEntry {
  int uid;
  String name;
  String timeText;      // 签到时间
  int totalDays;        // 总天数
  int monthDays;        // 月天数
  String rewardText;    // 上次奖励文本，如 "9 粒铁粒"
}
```

## 2. URL 构造

```dart
// 首页
GET {base}/forum.php?mobile=2

// 版块列表（fid=111 为例）
GET {base}/forum.php?mod=forumdisplay&fid=111&mobile=2
// 分类过滤
GET {base}/forum.php?mod=forumdisplay&fid=111&filter=typeid&typeid=101&mobile=2
// 分页（伪静态或参数）
GET {base}/forum-111-2.html
GET {base}/forum.php?mod=forumdisplay&fid=111&page=2&mobile=2

// 帖子详情
GET {base}/forum.php?mod=viewthread&tid=24419&mobile=2
GET {base}/thread-24419-1-1.html
// 分页/排序/只看作者
GET {base}/forum.php?mod=viewthread&tid=24419&page=2&mobile=2
GET {base}/forum.php?mod=viewthread&tid=24419&ordertype=2&mobile=2   // 2=倒序
GET {base}/forum.php?mod=viewthread&tid=24419&authorid=1&mobile=2    // 只看作者

// 导读
GET {base}/forum.php?mod=guide&view=hot&mobile=2      // 热门
GET {base}/forum.php?mod=guide&view=new&mobile=2      // 最新
GET {base}/forum.php?mod=guide&view=newthread&index=1&mobile=2

// 签到排行（k_misign）
GET {base}/plugin.php?id=k_misign:sign&operation=list&op=today     // 今日
GET {base}/plugin.php?id=k_misign:sign&operation=list&op=month    // 本月
GET {base}/plugin.php?id=k_misign:sign&operation=list&op=zong     // 总榜
GET {base}/plugin.php?id=k_misign:sign&operation=list&op=calendar // 日历

// 头像（公开）
GET https://user.klpbbs.com/avatar.php?uid={uid}&size=middle|small
```

## 3. HTML 解析点（comiis_app 模板）

### 3.1 帖子列表（forumdisplay/首页/导读）

```html
<li class="forumlist_li comiis_znalist bg_f b_t b_b comiis_list_readimgs">
  <div class="forumlist_li_top cl">
    <a href="home.php?mod=space&uid={uid}&do=profile&mobile=2" class="wblist_tximg"><img ...></a>
    <a href="...space&uid={uid}..." class="top_user">{作者}</a>
    <span class="f_d">{时间文本}</span>
    <a href="...filter=typeid&typeid={tid}..." class="f_d">来自 {分类}</a>
  </div>
  <div class="mmlist_li_box cl">
    <h2><a href="thread-{tid}-1-1.html" style="color:{颜色}">{标题}</a></h2>
    <div class="list_body cl"><a href="..." class="f_b">{摘要}</a></div>
    <div class="comiis_pyqlist_imgs">...
      <img comiis_loadimages="{图片URL(相对)}" ...>
```

解析规则：
- 条目：`li.forumlist_li.comiis_znalist`
- tid：从 `thread-{tid}-1-1.html` 正则提取；`img` 内 `comiis_loadimages` 属性为懒加载图
- 图片 URL 以 `forum.php?mod=image...` 开头时按相对路径拼接 base；`http` 开头原样使用
- 标题前缀标签：`h2 a` 内 `<span class="comiis_xifont f_g">{标签}</span>` 可选

### 3.2 帖子详情（viewthread）

```html
<div class="comiis_view_lcrate mt10 mb5">
  <!-- 作者区 -->
  <img src="https://user.klpbbs.com/avatar.php?uid={uid}&size=middle">
  <a href="home.php?mod=space&uid={uid}&do=profile&mobile=2">{作者}</a>
  <!-- 内容 -->
  <div class="comiis_message bg_f view_all cl message">{正文HTML}</div>
  <div class="comiis_messages comiis_aimg_show cl">...</div>
</div>
```

解析规则：
- 楼层：`div.comiis_view_lcrate`
- 正文：楼层内 `div.message`（正文 HTML 原样保留，Flutter 端用富文本/WebView 渲染）
- 图片：正文内 `<img src=...>` 提取；图床域 `img.klpz.net`
- 分页：页面内 `forum.php?mod=viewthread&tid={tid}&page={n}&mobile=2` 链接集合

### 3.3 签到排行（k_misign）

```html
<div class="k_misign_wp"><div class="k_misign_list">
<table id="misign_list" class="bg_f">
  <tbody id="autolist_{uid}"><tr>
    <td class="k_misign_lu"><a href="home.php?mod=space&uid={uid}"><img src="...avatar...size=small" /></a></td>
    <td class="k_misign_ll"><span></span></td>
    <td class="k_misign_lc b_b">
      <h4 class="f_c"><a href="...space&uid={uid}">{用户名}</a><span>{时间}</span>
          <span class="y">总天数 {N}天</span></h4>
      <p class="f_0">月天数 {N} 天，上次奖励 {N} 粒铁粒</p>
    </td>
  </tr></tbody>
</table></div></div>
```

解析规则：
- 条目：`tbody[id^="autolist_"]`，uid 从 id 提取
- 用户名/时间/总天数/月天数/奖励 按上述 class 提取

### 3.4 首页版块导航

- 版块链接：`forum-{fid}-1.html` 或 `forum.php?mod=forumdisplay&fid={fid}&mobile=2`
- 版块名：链接文本或 `alt` 属性
- 首页推荐帖：`thread-{tid}-1-1.html` 链接

## 4. 写操作与安全策略（环境感知）

### 4.1 写操作接口（本地测试环境实测）

| 操作 | 接口 | 关键参数 | 成功标志 |
|---|---|---|---|
| 登录 | `POST member.php?mod=logging&action=login&loginsubmit=yes&loginhash={hash}` | `formhash, referer, fastloginfield, cookietime, username, password` | 响应含 `pre*_auth` cookie |
| 发帖 | `POST forum.php?mod=post&action=newthread&fid={fid}&topicsubmit=yes` | `formhash, posttime(时间戳), subject, message[, typeid]` | 301 跳转 |
| 回复 | `POST forum.php?mod=post&action=reply&tid={tid}&replysubmit=yes` | `formhash, posttime, message` | 301 跳转 |
| 私信 | `POST home.php?mod=spacecp&ac=pm&op=send&touid={uid}&pmid=0&pmsubmit=yes` | `formhash, message` | 301 跳转 |
| 签到 | `GET plugin.php?id=k_misign:sign&operation=qiandao&formhash={hash}&format=empty` | 会话内 formhash | `<root><![CDATA[]]></root>` |

**会话机制**：
1. 登录后保存 `{cookiepre}_auth` cookie（前缀随 cookiepre，如 `pre0122_2132_auth`）。
2. 所有写操作需携带会话 cookie + 页面 formhash（登录后从目标页提取）。
3. 提交成功多返回 301 重定向（到帖子页/私信列表），客户端按 2xx/3xx 视为成功。

### 4.2 环境安全策略（ReadWritePolicy）

- **本地测试环境**（127.0.0.1）：允许 GET 浏览 + POST 写操作（登录/发帖/回复/私信/签到）。
- **真实论坛**（klpbbs.com）：**仅 GET 浏览**，写操作一律拦截（防账号禁言/警告风险）。
- **host 白名单**：仅允许当前 baseUrl 的域名；拒绝任意域/子域伪装/userinfo 技巧/非 http(s)。
- **重定向**：3xx 手动跟随且转 GET，目标再次过策略校验。
- **编码**：响应按 bytes + 容错 UTF-8 解码（个别模板内嵌 GBK 字节）。

### 4.3 解析器兼容（本地 vs klpbbs）

- 帖子链接：兼容伪静态 `thread-{tid}-1-1.html` 与参数 `forum.php?mod=viewthread&tid={tid}`。
- 签到排行：兼容 `tbody#autolist_{uid}`（klpbbs）与 `table#J_list_detail`（本地 v4.3.0）。
- 排行 op：本地 `month/zong/空`，klpbbs 另有 `today/calendar` → 客户端用 `month/zong`。
- 小黑屋：`forum.php?mod=misc&action=showdarkroom&mobile=no`（PC 模板含 `tr#darkroomuid_{uid}`）。
- 首页/导读内容空（本地 comiis 未配置数据区）→ fallback 到版块列表。
