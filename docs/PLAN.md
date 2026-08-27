# 苦力怕论坛客户端 —— 完整还原开发计划（Living Document）

> **定位**：本文件是「100% 还原 klpbbs 移动端（克米设计 comiis_app）+ 整合 PC 端独有功能」的
> 持续更新总计划。每完成一项勾选一项，逆向/测试中发现的遗漏问题持续追加到对应清单。
> 所有相关结论同步回 `docs/REVERSE_ENGINEERING.md` 与 `docs/API_CONTRACT.md`。

---

## 0. 文档版本与推进记录

- 版本：v0.2.0
- 最后更新：2026-08
- 推进记录（按时间倒序）：
  - [x] 修复真实论坛写操作安全红线（allowWrite 恒 true → 仅本地可写 + 登录放行）
  - [x] 建立 Flutter 工具链基线（3.32.5 / Dart 3.8.1），基线 analyze 23 项 lint
  - [x] 逆向真实列表/详情结构：`li.forumlist_li.comiis_milist`（h2 在 a 内）、标签（精/荐/热度/置顶/分类）、浏览回复数、楼层（pid/等级/IP/签名/图章/表情目录）
  - [x] 重写 parseThreadList 匹配真实结构 + ThreadSummary 增精/荐/热度/置顶字段 + ThreadCard 标签渲染
  - [x] 逆向社区版块树（分区→版块）+ ForumGroup 模型 + parseForumGroups + 首页分组渲染
  - [x] 抓取真实样本 home/forumdisplay/digest/viewthread/forumlist/login/editor×2/signature/smilies_var 共 11 份
  - [x] 修复 13 处字符串插值 bug（`\${` → `${`：收藏版块/私信草稿/发帖附件/私信计数/详情 URL）
  - [x] 登录真实论坛成功（只读会话，密码 qx114514）——逆向编辑器/签名/表情面板
  - [x] 逆向编辑器表单（typeid/readperm/附件/BBCode 工具栏）、表情目录（4 分类 tieba/bilibili/dy/qq）、小喇叭、签名编辑
  - [x] 表情系统：Smiley/SmileyCategory 模型 + parseSmilies + getSmilies + 帖子表情按原始比例渲染（含行内 img 修复）
  - [x] 解析器测试 11/11 通过（真实样本）；代码 0 error
  - [x] 启动本地测试论坛（MariaDB+PHP），修复 api_smoke_test（login 返回值 record）+ 解析器兼容 milist/znalist 双结构
  - [x] 修复 render_screenshots_test（path_provider mock + 登录页 Timer）
  - [x] 全量测试 38/38 通过（解析器 11 + 设置 + 响应式 + 本地写操作 17 + 截图 3）；analyze 0 error
  - [x] 打通反重力 agentapi（flash 模型）做 UI 截图视觉核验（new-conversation + 读 transcript.jsonl）
  - [x] 修复截图测试字体：加载 SimHei(CJK) + MaterialIcons，汉字/图标不再豆腐块
  - [x] 首页版块树改为可折叠（默认仅展开第一个分区），推荐帖子回到首屏
  - [x] 登录页按钮「立 即 登 录」硬编码空格修复
  - [x] 验证码适配：修复 seccode 取图流程（action=update 生成 + Referer 同源，否则 "Access Denied"）
  - [x] 注册页验证码：parseSecCodeInfo 提取 seccodemodid + getRegisterSecCodeInfo + register() 支持 SecCode + 注册页验证码 UI
  - [x] 全量测试 39/39 通过（新增注册验证码测试）；analyze 0 error
  - [x] 修复用户反馈：头像环境感知 + 首页用导读数据 + 登录uid + 去重 + 标签移到标题下方 + 小喇叭真实结构 + 删除假广播 + 网格溢出
  - [x] 楼主徽章按 uid 解析（isThreadAuthor）+ 详情页头像环境感知
  - [x] 图片放大（size=200x160→800x600）+ 小喇叭重写（头像+可进主页+可进帖子，删假广播）+ 链接跳转（Text.rich + 站内应用内跳转）
  - [x] IP 重复显示修复 + 摘要剥离「最后编辑」系统记录 + 详情页底部 padding 加大
  - [x] 首页 widget 块解析 parseHomeThreads（幻灯/图文推荐/最新主题，标题/封面/阅读/日期分离）
  - [x] flash 视觉核验三轮：CJK/图标字体加载、版块树折叠、小喇叭、IP/摘要/间距等问题定位
  - [x] 楼中楼（replyfloor）：逆向 .replyfloor_box/.replyfloor_content_li 结构（REVERSE §8），新增 ReplyFloorComment 模型 + _parseReplyFloor 解析 + InlineHtmlText 组件，楼层内渲染楼中楼；重写打赏记录解析并渲染点评/打赏记录；analyze 0 error、全量测试 41/41 通过、Windows release 构建成功、flash 视觉核验通过（头像/作者/IP/时间/正文/无豆腐块/无溢出）
  - [x] 用户徽章（top_lev 用户组 + comiis_verify 认证）：逆向 REVERSE §9，PostFloor 新增 levelGid/levelColor/verifies，解析 top_lev gid+内联背景色（管理员红/版主品红/普通 Lv）+ comiis_verify 认证图标，_badgeColor 渲染等级徽章；analyze 0 error、全量测试 43/43 通过、Windows release 构建成功、flash 视觉核验通过（管理员红+白字/版主品红+白字/Lv 浅绿底，无乱码无溢出）
  - [x] 勋章：逆向 REVERSE §10（手机 #comiis_medal + PC p.md_ctrl/md_{id} 结构），UserSpace 新增 medals，parseUserSpace 解析勋章（id/名称/描述/图片 URL，_medalUrl 折叠双斜杠），user_space_page 渲染勋章；analyze 0 error、全量测试 45/45 通过、Windows release 构建成功、flash 视觉核验通过（10 枚勋章名称齐全无乱码无溢出）
  - [x] 使用道具 + 分享：逆向 REVERSE §11（mgc_post_{pid} 道具菜单 + comiis_share_box 分享框），PostFloor 新增 magicItems，_parseMagicItems 解析道具（mid/名称/图标/idtype），KlpbbsApi.useMagic 本地写操作，楼层「道具」按钮弹出菜单 + 分享复制「标题+链接」；analyze 0 error、全量测试 47/47 通过、Windows release 构建成功、flash 视觉核验通过（提升卡/观察者/作用对象/无乱码溢出）
  - [x] 编辑器强化（部分）：post_page 新增 Discuz 代码（BBCode）工具栏（b/i/u/color/img/url/quote/code/hide/spoiler）+ 全站表情面板（getSmilies 4 分类贴吧/B站/抖音/QQ，插入表情 code），_insertTag/_insertText 光标处插入；analyze 0 error、全量测试 48/48 通过、Windows release 构建成功、flash 视觉核验通过（10 个 BBCode 按钮 + 4 分类 tabs 清晰无乱码溢出）
  - [x] 日期显示：parseThreadDetail 新增 publishDate（首楼时间）/lastReplyDate（末楼时间），getThread/thread_detail_page 透传，帖子详情标题下方渲染「发布 + 最近回复」；analyze 0 error、全量测试 49/49 通过、Windows release 构建成功、flash 视觉核验通过（发布 2024-1-9 02:50:46 / 最近回复 2026-2-18 17:24:39 清晰无乱码溢出）
  - [x] UI 重构（登录页卡片 + 首页网格）：登录页卡片黑边柔化（边框 alpha 50→24、elevation 3→1、圆角 16→20 + 柔和阴影）；首页网格卡片统一移除摘要保持高度/留白一致；analyze 0 error、全量测试 49/49 通过、Windows release 构建成功、flash 视觉核验通过（黑边已消除/网格高度与缩略图对齐）
  - [x] 编辑器 Discuz 预览：新增 core/bbcode.dart（BBCode→HTML 转换：b/i/u/color/url/img/quote/code/hide/spoiler/free/attach）+ post_page「预览」按钮切换编辑/预览（DiscuzPostRenderer 渲染）；analyze 0 error、全量测试 54/54 通过、Windows release 构建成功
  - [x] 用户反馈修复（第一批）：签到排行头像 + op=today 映射默认（本地 v4.3.0 不支持 today）；小黑屋头像 + 翻页（getDarkroom page 参数）；帖子楼层/用户空间/楼中楼头像改用 UserAvatarWidget 消除「头像内嵌字」+ 空间头像走 AppConfig.avatarUrl；analyze 0 error、全量测试 54/54 通过、Windows release 构建成功
  - [x] 用户反馈修复（第二批）：小喇叭由横向滚动卡片改为竖向列表（头像+作者+时间+内容）；首页 widget 块（幻灯/图文推荐）无作者时隐藏空头像/空名（_buildFooter 条件渲染）；导读热门标题修复（parseThreadList 兜底优先取 a[title] 属性、跳过导航短链接，抓 guide_hot.html 样本 + 单测）；analyze 0 error、全量测试 55/55 通过、Windows release 构建成功
  - [x] 小喇叭发布 + 内置表情：真实登录态抓取 horn_add.html 逆向发布表单（REVERSE §7.4.1：formhash/color/boss/message/addsubmit + 表情 [s:{0-23}]）；parseHornPostInfo + getHornPostInfo/postHorn（仅本地可写）+ HornPostPage 发布页（内容/颜色/24 表情/霸屏）；小喇叭读取保留 <img> 表情 + InlineHtmlText 渲染；analyze 0 error、全量测试 56/56 通过、Windows release 构建成功
  - [x] 道具页修复：真实登录态抓取 home.php?mod=magic 发现道具条目结构为 div[id^="magic_"]（mid 为字符串标识 + img alt=名称 + onclick kmtxt 描述），原 parseMagics 按 magicid= 解析为空导致道具页异常；重写 parseMagics + 抓 magic.html 样本 + 单测；analyze 0 error、全量测试 57/57 通过、Windows release 构建成功
  - [x] 用户空间修复 + 缓存优化：真实抓取 space_profile_mobile.html 发现手机版用户名在 meta description/ h2.fyy、等级在 span.kmlevs.kmlv、积分格式为「N 积分」（原解析用 title/积分[:：]/错 selector 导致个人中心/他人空间用户名/等级/积分异常）；重写 parseUserSpace 三处 + 样本单测；_get 加 30s 内存缓存（写操作后清空）缓解加载慢；analyze 0 error、全量测试 58/58 通过、Windows release 构建成功
  - [x] 帖子内勋章修复：真实抓取 viewthread_168986_medal.html 发现勋章 <img> 直接嵌在 a.top_user 内（src=static/image/common/medal/{file}），原解析只查 .comiis_medaltip/.medal 容器导致不显示；改为额外提取 a.top_user 内 img[src*=medal]；analyze 0 error、全量测试 59/59 通过、Windows release 构建成功
  - [x] 私信收件箱修复：真实抓取 pm_inbox.html 发现会话用户名在 a.xw1、uid 为伪静态 space-uid-{uid}.html（原解析用 a[href*=mod=space&uid=] 提取 touid=0、时间未提取）；_uidFromHref 支持伪静态 + 重写 parsePmList（用户名/uid/摘要/时间）；analyze 0 error、全量测试 60/60 通过、Windows release 构建成功
  - [x] 楼中楼使用（写）：postReplyFloor API（plugin.php?id=replyfloor:index&ac=post + formhash/savesubmit/pid/msgid/message，仅本地可写）+ 楼中楼区块「我要说一句」弹窗输入；analyze 0 error、全量测试 60/60 通过、Windows release 构建成功
  - [x] 全站公告 + 附件下载：getAnnouncements fid<=0 改为抓首页 forum.php?mobile=2（原抓 forumdisplay&fid=0 无效）；附件卡片新增「复制下载链接」按钮（可用外部下载工具多线程下载）；analyze 0 error、全量测试 60/60 通过、Windows release 构建成功
  - [x] UI 细节 + 标题修复：小喇叭改为限高 220px 可上下滑动翻阅；楼层头等级徽章紧贴名字右边、勋章移到等级之后（Expanded→Flexible + 交换块序）；标题抓取剥离「N回复/N阅读/N查看/日期」等尾随元数据（_cleanTitle 应用到 parseHomeThreads/_parseThreadListItem/导读兜底/幻灯）；analyze 0 error、全量测试 60/60 通过、Windows release 构建成功
  - [x] 头像内嵌字第二批：好友页/私信收件箱/私信详情/详情页积分头 4 处 CircleAvatar(backgroundImage+child 首字母) 全部改用 UserAvatarWidget（消除字母叠在头像上）；analyze 0 error、全量测试 60/60 通过、Windows release 构建成功
  - [x] 帖子排版（flash 核验后修复）：正文行高 1.75→1.55；详情标题从 <title> 标签取（原取 .comiis_viewtit 容器把「122回复 32289阅读 版块名」污染进标题）；parseStructuredBlocks 跳过空段落/<br>/空 div（Discuz 编辑器插入的空白节点，消除 80-120px 幽灵空白）；analyze 0 error、全量测试 60/60 通过、Windows release 构建成功
  - [x] 用户空间二批：别人空间不再显示「编辑资料/推广/道具/任务/好友/收藏」等个人专属入口（仅 _myUid==uid 时显示）；签名从 <li><span>个人签名</span> 的 .profile_face 提取（原正则匹配不到「这家伙很懒」模板）；analyze 0 error、全量测试 60/60 通过、Windows release 构建成功
  - [x] 图片太糊修复：图片 URL 优先取 comiis_loadimages（原图 ip.klpbbs.com/attach.php，实测 4212px 全尺寸），原取 src（one.klp.api.mutool.top 预览图/none.png 占位）；解析器 3 处图片提取顺序反转；analyze 0 error、全量测试 60/60 通过、Windows release 构建成功
  - [x] 勋章中心修复：真实抓取 medal.html 发现勋章名称/描述在 onclick 弹窗 JS 字符串（em.kmtit/em.kmtxt），原 querySelector('.kmtit/.kmtxt') 匹配不到 → desc 恒空；改从 onclick 正则提取 + 样本单测；analyze 0 error、全量测试 61/61 通过、Windows release 构建成功
  - [x] 任务中心修复：真实抓取 task_doing.html 发现任务条目为 a[href*=do=view&id=] > img[alt=任务名]（原按 itemid= 解析恒空）；重写 parseTasks + getTasks 默认抓「进行中」tab（新任务常为空）；analyze 0 error、全量测试 62/62 通过、Windows release 构建成功
  - [x] 推广中心修复：真实抓取 promotion.html 发现推广链接在 textarea#copy（原按 a[href*=fromuid=] 解析恒空）；重写 parsePromotion + 样本单测；analyze 0 error、全量测试 63/63 通过、Windows release 构建成功
  - [x] 头像挂件修复：sunju_facemall 头像 URL 带 ##SJ##data/attachment/... 后缀导致图片加载失败，新增 _avatarUrl 剥离 ##SJ## 后缀（小喇叭头像等）；analyze 0 error、全量测试 63/63 通过、Windows release 构建成功
  - [x] 代码块语言提取：从 class 的 language-xxx 提取语言名（原直接显示整个 class 字符串）；analyze 0 error、全量测试 63/63 通过、Windows release 构建成功
  - [x] 签到对齐 + 楼中楼确认：参考 DiscuzSign（IamGuangZe/DiscuzSign）确认签到接口 k_misign-sign.html?operation=qiandao&format=button&formhash={formhash}（format=empty→button + 成功文案判断 + allowWrite 守卫）；从 diskao.com 测试站 + klpbbs 样本确认楼中楼 POST 表单 plugin.php?id=replyfloor:index&ac=post（formhash/savesubmit/pid/msgid/handlekey/message）与 postReplyFloor 一致；抓包工具修复自捕获递归 bug（v5 只抓 klpbbs 域名 + 表单提交 sendBeacon）；analyze 0 error、全量测试 63/63 通过、Windows release 构建成功
  - [x] 头像挂件（sunju_facemall）适配：头像 URL 的 ##SJ##data/attachment/sunju_facemall/fm_{n}.png 后缀是挂件图；_faceUrlFromAvatar 提取 + PostFloor/UserSpace 增 faceUrl + UserAvatarWidget 增 faceUrl 参数并叠 1.75x 挂件（左上偏移 3/8，clip.none）；楼层头像 + 用户空间头像接入；analyze 0 error、全量测试 63/63 通过、Windows release 构建成功
  - [x] 打赏修复：真实抓取 rate_form.html 确认 klpbbs 评分表单字段 score2=铁粒（credit id 2，1~500，快捷 +49/+98/...）、score8=钻石、reason；原 ratePost 用 score1（不存在）导致打赏失败 → 改 score2 + 补 tid/pid + allowWrite 守卫；analyze 0 error、全量测试 63/63 通过、Windows release 构建成功
  - [x] 移动端侧边栏修复：Drawer 头部由静态「苦力怕论坛」改为用户信息（已登录显示头像+「已登录」，未登录显示「点击登录」）；新增登录/退出登录入口（KlpbbsApi.logout + LoginPage + getMyUid 刷新）；analyze 0 error、全量测试 63/63 通过、Windows release 构建成功
  - [x] 写操作对用户开放：按用户澄清「写操作限制是给我(AI)开发时的，不是给用户禁用的」，AppConfig.allowWrite 改恒 true（真实论坛写经 needRealWriteConfirm 二次确认）+ _writePatterns 补全 rate/replyfloor/ahome_horn/qiandao/magic/recommend/comment/spacecp/logout 等；删除全站公告入口按钮；修详情页「链接已复制：\$url」插值 bug；楼层勋章显示溢出→最多显示3枚+「+N」；analyze 0 error、全量测试 63/63 通过、Windows release 构建成功
  - [x] 图片自动重试 + 高级搜索：新增 RetryImage 组件（加载失败自动重试3次、延迟递增）并用于帖子正文图片；搜索 API 增高级参数（作者/标题全文/排序/版块/页码）+ 搜索页增「高级搜索」折叠面板（作者输入 + 范围/排序下拉）；analyze 0 error、全量测试 63/63 通过、Windows release 构建成功
  - [x] 移动端导航菜单修复（重定位根因）：_scaffoldKey 从未挂到 Scaffold 上导致 openDrawer 失效，且首页菜单按钮只在 side 布局显示；改 AdaptiveScaffold 增 scaffoldKey 参数并挂到移动端 Scaffold + 首页 always 显示汉堡按钮；分页跳转：新增 _jumpPage 输入页码对话框 + 「当前/总」指示可点击跳页；analyze 0 error、全量测试 63/63 通过、Windows release 构建成功
  - [x] 分区版块名显示数字修复：真实抓取 forumlist 发现 comiis_forum_three 布局里 <span> 是数字徽章、名字在 <p>，而 comiis_forum_two 里名字在 <span>；原 a.querySelector('span') 抓到数字 → 改优先取 img.alt（两种布局通用）；打赏记录居中显示；analyze 0 error、全量测试 63/63 通过、Windows release 构建成功
  - [x] 小喇叭删除 API：新增 KlpbbsApi.deleteHorn（ahome_horn:index&ac=del&id&formhash），供自己删除小喇叭；analyze 0 error、全量测试 63/63 通过、Windows release 构建成功
  - [x] 标题异常方块修复：_cleanTitle 剥离零宽空格(U+200B/U+200E/U+200F/U+FEFF)与 NBSP（红包贴等标题常带这些隐形字符导致渲染成异常方块）；analyze 0 error、全量测试 63/63 通过、Windows release 构建成功
  - [x] 首页帖子用户信息修复：parseHomeThreads 原来 author 恒空（'author: ''）导致首页卡片无头像用户名；改为从 twlist_info 的 em.kmx/span em 提取作者；analyze 0 error、全量测试 63/63 通过、Windows release 构建成功
  - [x] 「荐/红包贴/热」等徽章正常渲染：真实抓取 home 确认图文推荐 twlist 无作者、em.kmx 是分隔符「|」，改取版块名填充 author（去空）；_cleanTitle 与 badge 剥离私有区图标字体（U+E000-F8FF，comiis_font 图标码渲染成方块）；analyze 0 error、解析器 25 测通过、Windows release 构建成功
  - [x] 帖子图片比例修复：正文图片由无宽度约束（大图溢出卡片）改 width: double.infinity + BoxFit.fitWidth（满宽自适应高度，最高 520）；analyze 0 error、全量测试 63/63 通过、Windows release 构建成功
  - [x] 小喇叭删除 UI 接线 + 列表项渲染：_HornCard 增 canDelete/onDelete（自己发的显示删除图标，调 deleteHorn + 刷新）；_htmlToSpans 增 ul/li 列表项项目符号与换行；analyze 0 error、全量测试 63/63 通过、Windows release 构建成功
  - [x] flash 核验豆腐块修复：flash 指出代码块/正文 emoji 渲染成方块（缺中文字体/emoji 回退）；ThemeData 加 fontFamilyFallback（PingFang/微软雅黑/Noto Color Emoji/Apple/Segoe UI Emoji）+ 代码块 SelectableText 加 fontFamilyFallback；analyze 0 error、全量测试 63/63 通过、Windows release 构建成功
  - [x] 通知消息修复：真实抓取 do=notice&view=mypost 发现通知条目是 div.ntc_body 内 a[href*=ptid=]（作者 space-uid + 帖子标题 goto=findpost&ptid），原解析按 li.ntc + viewthread 匹配恒空 → 重写 parseNotices + 真实样本单测；analyze 0 error、全量测试 64/64 通过、Windows release 构建成功
  - [x] 点赞/收藏/打赏写操作失败根因修复：_extractFormhash 正则只匹配 formhash=xxx（URL 形式），但 viewthread 页是 var formhash='xxx'（JS）+ name="formhash" value="xxx"（hidden input）→ 取不到 formhash 致 recommend/favorite/rate 全返回 false；改多模式匹配（JS 单双引号/hidden input/URL）；analyze 0 error、全量测试 64/64 通过、Windows release 构建成功
  - [x] 通知 mobile 对齐 + 分页重做：getNotices 由 mobile=no 改 mobile=2（对齐真实移动模板的 div.ntc_body）；分区列表「加载更多」按钮重做为分页导航（上一页/下一页 +「第 N 页·点此跳页」输入对话框）；analyze 0 error、全量测试 64/64 通过、Windows release 构建成功
  - [x] 附件卡片美化（flash 讨论后）：灰条改为克米风卡片——按扩展名着色的文件类型徽章（zip/apk/pdf/doc/txt/图/mcpack 各配色）+ 文件名 + 大小/价格 + 下载按钮；analyze 0 error、全量测试 64/64 通过、Windows release 构建成功
  - [x] 布局表格扁平化：真实抓取 tid=172298 发现克米用多层嵌套 <table><tr><td> 排版（非数据表）；parseStructuredBlocks 增「无 th 且单列 → 递归解析 td 内容」扁平化，避免嵌套表格丢内容；样本已存 viewthread_172298_table.html；analyze 0 error、全量测试 64/64 通过、Windows release 构建成功（表格正文完全解析待下轮继续调试）
  - [x] 嵌套表格正文修复：定位 package:html 把 <main> 内的 <table> 移出 main 导致 coreBody 丢表内容；cleanMessage 由 parseFragment 改 message.clone(true)（避免 fragment 破坏 table）+ coreBody 无 table 时回退父级 td；正文现在能解析出内容（TableBlock）
  - [x] 自定义 UA（PC/手机）：AppConfig 增 mobileUserAgent/pcUserAgent + usePcUa 开关 + setUsePcUa 持久化 + 设置页「浏览器 UA」PC UA 开关（默认手机 UA）；analyze 0 error、全量测试 64/64 通过、Windows release 构建成功
  - [x] 嵌套表格正文完全修复：isSingleColumn 原用递归 querySelectorAll('td') 误判（嵌套表的多 td 让外层布局表被判成数据表）→ 改为收集直接行（处理 tbody）+ 只数直接 td；布局表只解析直接 td（避免重复），嵌套数据表仍走 TableBlock；tid=172298 正文「创意思海」测试通过；analyze 0 error、全量测试 65/65 通过、Windows release 构建成功
  - [x] 综合分区贴数修复（今日/总混淆）：Forum 增 todayCount；parseForumGroups 区分「今日:N」（今日帖数）与「帖数:N」（总帖数），三列布局数字徽章归为今日帖数；analyze 0 error、全量测试 65/65 通过、Windows release 构建成功
  - [x] 帖子详情显示所属板块：parseThreadDetail 从 <title>「标题 - 版块 - 论坛名」提取第二段为版块名 forumName（记录类型增字段）；getThread/详情页类型同步；详情页标题下显示「版块：xxx」；analyze 0 error、全量测试 65/65 通过、Windows release 构建成功
  - [x] 首页推荐/热门信息修复：getHome 由「首页 widget 块（图文推荐 twlist 无作者）优先」改为「导读热门 getGuide(hot) 优先（含作者/板块）」，空时再 fallback 首页块——首页卡片现在有正确作者头像用户名；analyze 0 error、全量测试 65/65 通过、Windows release 构建成功
  - [x] 发布选版块修复：getForums 原来用 parseForums 抓首页（抓不到克米分区结构）导致回退硬编码默认版块；改优先从 forum.php?forumlist=1 抓 parseForumGroups 完整分区并扁平化所有版块——发帖页版块下拉现在显示真实 klpbbs 版块；analyze 0 error、全量测试 65/65 通过、Windows release 构建成功
  - [x] 图片查看器 PC 端优化：灯箱 InteractiveViewer 加 minScale:0.5 + maxScale:6 + 图片宽取视口宽（BoxFit.contain），改善放大比例锁死/两侧空白；analyze 0 error、全量测试 65/65 通过、Windows release 构建成功
  - [x] 折叠 spoiler 渲染：正文行高 1.7→1.55 与正文一致，消除折叠内容留白/行距过松；analyze 0 error、Windows release 构建成功
  - [ ] 小喇叭发布（ahome_horn:add，本地写操作，本地无 ahome_horn 插件待定）
  - [x] 分享图/分享框（comiis_share_box，复制链接含标题，见 §11）
  - [x] 使用道具（magic：mgc_post_{pid} 菜单 + useMagic 本地写，见 §11）
  - [x] SVIP/VIP/管理员徽章显示（用户组 gid → group title + comiis_verify，见 §9）
  - [x] 编辑器增强（专业 BBCode 工具栏 + 无系统 emoji + 原站 Discuz smilies）：工具栏分两行——上行排版（B/I/U/S、字号 1~7 弹层、文字颜色/背景色调色盘、左中右对齐、字体），下行插入（引用/代码/回复可见/折叠/免费/图片/链接/列表/表格/分隔线，全部 Material 矢量图标）；移除 Unicode emoji 兜底网格（改为加载失败重试态，绝不塞系统 emoji）；smilies 面板改 MaxCrossAxisExtent 自适应网格 + mainAxisExtent:46 + 面板高 192 精确显示 3 行不露残边 + 单元格底框/占位图标；bbcodeToHtml 新增 size/font/backcolor/align/list/table/hr 并清理列表/表格内 <br>；DiscuzPostRenderer._htmlToSpans 新增 face/背景色/块级 text-align 支持；PostPage 增 initialSmileys 注入供截图测试；flash 核验通过（无溢出/无豆腐块/无系统 emoji/表情 3 行完整）；analyze 0 error、全量测试 67/67 通过、Windows release 构建成功
  - [x] 附件卡片重做 + 图片大小/预览图加载修复 + 帖子排版细化：AttachmentBlock 新增 iconUrl/uploadTime/downloadCount/priceText；解析器附件识别改为 classes.any(contains('attach'))（原只匹配 'attach' 会漏掉 comiis_attach 真实结构）并解析 .attach_tit/.attach_size（大小/下载次数/上传时间，时间补零）；渲染器附件卡改克米风卡片（46px 文件徽章 + 元数据胶囊 + 复制/下载按钮分层，flash 核验通过）；_htmlToSpans 与 InlineHtmlText 图片优先取 comiis_loadimages（原取 src 会拿到 none.png 占位图），非表情图从 24px 行内小图改为满宽块级渲染（修复 [img] 外部图变小/不显示）；ThreadCard 封面改用 RetryImage 自动重试；列表/首页封面提取新增 _coverFromScope（无 comiis_loadimages 时回退 img src，排除头像/版块图标）；新增附件解析单测 + 封面回退单测 + 附件卡渲染截图；analyze 0 error、全量测试 70/70 通过、Windows release 构建成功
  - [x] 登录状态持久化 + 注册本地 Discuz 适配：DioClient 新增 saveCookies/loadCookies/clearCookies（SharedPreferences 持久化 session_cookies_v1，启动 main 恢复；登录/导入 Cookie 自动保存，退出清空）；注册 API 重写——抓取 mobile=2 注册页并解析 Discuz reginput 随机字段名（parseRegisterForm），已登录时自动登出+清缓存重试（Discuz 注册页在登录态会 302 到首页/短信注册表）；getRegisterSecCodeInfo 改 mobile=2；本地真实注册+新账号登录实测通过；新增 parseRegisterForm 单测（本地/klpbbs 真实样本）与注册烟测；flash 给出首页/详情页 10 条 UI 改进清单（后续逐条推进）；analyze 0 error、全量测试 73/73 通过、Windows release 构建成功
  - [x] UI 收敛第二轮：ThreadCard 热帖标题不再整条红色（改中性色，热帖由「热」徽章表达，flash 确认已消除大面积红色）；卡片底部回复数与时间之间加「·」分隔；DiscuzPostRenderer 裸 URL 链接自动缩短显示（域名+路径，避免长串 URL 破坏版面）；flash 复检首页给出后续 5 条改进清单（网格占位统一/公告标签重复/社区分区宽屏多列等）；analyze 0 error、全量测试 73/73 通过、Windows release 构建成功
  - [x] UI 收敛第三轮：首页社区分区网格由固定 2/3/4 列改为 SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent:180)（修复宽屏下 4 个版块卡片被横向拉长、右侧大量留白）；桌面网格帖子卡片无封面时补统一文章占位图（108x76），保证网格结构一致；渲染测试移除「(PC 桌面布局)/(PC自适应网格)」调试后缀；analyze 0 error、全量测试 73/73 通过、Windows release 构建成功
  - [x] 发帖特殊主题支持（辩论/投票/普通 + 版块权限提示）：新增 ComiisParser.parseNewThreadInfo 解析发帖页 formhash、switchpost 暴露的可用特殊主题（0普通/1投票/5辩论）与权限错误；KlpbbsApi 新增 getNewThreadInfo + postThread 支持 special/affirmpoint/negapoint/endtime；PostPage 增加主题类型 ChoiceChip（按版块能力显示普通/投票/辩论）、发帖权限错误横幅、辩论正反方观点+结束时间输入；本地 fid=2 解析出普通+投票，真实 klpbbs 手机页解析出普通帖；新增 parseNewThreadInfo 单测（本地/klpbbs 真实样本）；analyze 0 error、全量测试 75/75 通过、Windows release 构建成功
  - [x] PC 主题分类 typeid + 签到失败修复 + 封神榜改名 + 全局导航初版：parseNewThreadInfo 新增解析 PC 发帖页 select[name=typeid] 分类选项（真实 klpbbs PC 样本：版本发布/游戏快讯等）；PostPage 显示主题分类下拉并随帖提交；signIn 兼容 k_misign:tdyq/signed/signsuccess（今日已签不再误报失败）；「小黑屋」全部 UI 文案改为「封神榜」；新增 lib/core/main_tab_controller.dart + lib/widgets/global_nav.dart，在帖子详情/列表/用户空间/私信/发帖页 AppBar 注入全局导航按钮（底部弹出全站导航，可切回首页 Tab 或跳排行榜/设置/登录）；新增 klpbbs PC 发帖页样本与 typeid 解析单测；analyze 0 error、全量测试 76/76 通过、Windows release 构建成功
  - [x] 长图/多图帖修复 + 编辑器全面增强：真实抓取 tid=171272 多图帖样本并新增解析单测；正文图片与行内图片移除 maxHeight 520 约束（改为 width 满宽 + fitWidth 保留自然比例，长图不再锁比例/被裁切，点击仍进灯箱看原图）；编辑器征求 flash 重设计建议后实施：PopScope 未保存内容防误触退出弹窗（保留草稿）、标题 maxLength 120 计数、正文输入/预览区改为圆角卡片容器、聚焦态去边框更简洁；新增 viewthread_171272 样本；analyze 0 error、全量测试 77/77 通过、Windows release 构建成功
  - [x] 作者头像兜底 + 通知兜底：ThreadCard 无作者/uid 时显示占位头像与「论坛帖子」；parseNotices 无 ntc_body 时兜底查找 goto=findpost/ptid= 链接；diskao 楼中楼登录需图形验证码（待人工验证码输入后测）；analyze 0 error、全量测试 77/77 通过、Windows release 构建成功
  - [x] 代码块/折叠块美化 + 全局导航覆盖扩展：代码块内容区增加纵向 maxHeight 360（长代码不再撑爆楼层，横纵双向滚动）；spoiler 折叠块增加圆角 shape/展开收起背景色；GlobalNavButton 扩展到通知/私信会话/私信发送/编辑资料/推广/道具/勋章/任务/好友/收藏版块/功能列表/小喇叭/排行榜/用户帖子等 pushed 页面；analyze 0 error、全量测试 77/77 通过、Windows release 构建成功
  - [x] diskao 登录验证码人工协作 + 标准 Discuz 兼容：通过 ask_user 拿到验证码并成功登录 diskao；发现 diskao 为普通 Discuz 点评（comment=pid）而非 klpbbs replyfloor 插件，回复仍要求 seccode；_tidFromHref 新增 `thread-{tid}.html` 兼容；_extractFormhash 新增 `name="formhash" id="formhash" value="..."` 兼容（diskao 回复页）；analyze 0 error、全量测试 77/77 通过、Windows release 构建成功
  - [x] 详情页留白：楼层卡片底部 margin 0→6，列表底部已有 48 安全区，楼层间距更透气；analyze 0 error、全量测试 77/77 通过、Windows release 构建成功
  - [x] diskao forum-52.html 标准 Discuz 手机版列表适配：parseThreadList 新增 `div.threadlist li.list` 解析（标题/作者/uid/时间/摘要/浏览/回复）；_fidFromHtml 兼容 `forum-{fid}.html`；新增 forumdisplay_diskao_52.html 样本与单测；全量单测因本机内存不足偶发 OOM，但 api_smoke+bbcode、comiis_parser(36项)、render_screenshots(10项)、responsive+settings 分别以 --concurrency=1 全部通过；Windows release 构建成功
  - [x] 折叠内图片可点击 + 首页作者信息修复：折叠块/正文行内图片现在可点击打开灯箱（此前只能看不能按）；klpbbs guide hot 实为首页 portal，getGuide 改为检测 twlist/comiis_mh_twlist 后走 parseHomeThreads，首页卡片不再全是「论坛帖子」；parseHomeThreads 增加作者提取（人才市场等 span.f_d/span.y/kmuser）；新增首页 portal 作者单测；全部测试分文件通过、Windows release 构建成功
  - [x] 首页 portal 作者再修复 + tid=172616 适配 + 行内表格渲染：parseHomeThreads 新增 _homeSectionTitle 向上查找板块标题（资讯/图文推荐等），twlist 作者/日期拆分为「版块名」+「yyyy-MM-dd」；真实 klpbbs 首页验证 author 不再为空（资讯/BE附加包/BE地图等）；新增 viewthread_172616 样本与解析单测（多图首楼 + replyfloor 楼层号）；_htmlToSpans 新增 table WidgetSpan 行内表格渲染（折叠/引用/正文内表格都能显示）；analyze 0 error、comiis_parser 38 项通过、render 10 项通过、Windows release 构建成功
  - [x] jt.png 桌面首页 flash 审阅后修复：快捷入口顶部 padding 8→14 防裁剪；推荐网格无封面时不再显示灰占位图，标题区自然撑满；首页 ListView 末尾预留 96px 给发帖 FAB，避免遮挡最后一张卡片；analyze 0 error、render 10 项通过、Windows release 构建成功
  - [x] 首页真实作者/头像修复：getGuide 改用 PC 模板（mobile=no），parseThreadList 新增 PC 导读列表解析（th.main.common/.titbox + .aor 作者 + space-uid 头像 uid + 回复/浏览/时间）；真实 klpbbs 首页验证每张卡片显示真实楼主昵称与头像；新增 guide_hot_pc.html 样本与单测；analyze 0 error、comiis_parser 39 项通过、render 10 项通过、Windows release 构建成功
  - [x] 刷新/加载更多修复 + 置顶/代码/编辑器预览：首页 _loadMore 不再硬编码 getThreadList(2)，改用 getGuide('hot', page: N) 保持真实作者；getGuide 增加 page 参数；置顶帖无作者时显示「版块置顶」；代码块 language 仅提取 language-xxx，空语言时标题改为「代码 · N 行」；编辑器预览改为 ComiisParser.parseStructuredBlocksFromHtml(bbcodeToHtml(...))，代码块/表格/引用/折叠等结构在预览中走完整渲染器；analyze 0 error、comiis_parser 39 项通过、render 10 项通过、Windows release 构建成功
  - [x] 哔哩哔哩视频解析 + 特殊主题选择器优化：parseStructuredBlocks 新增 iframe/video/embed 子节点拆分为 VideoBlock（tid=173158 首楼 BV1CT4y1X7Sd 现已解析）；新增 viewthread_173158 样本与单测；getNewThreadInfo 强制 mobile=no 获取 PC 发帖页；PostPage 普通/投票/辩论 ChoiceChip 始终显示，版块未开放时置灰并 Tooltip 说明；analyze 0 error、comiis_parser 40 项通过、render 10 项通过、Windows release 构建成功
  - [x] flash 复检编辑器/详情页 + 行内表格横向滚动：根据 flash 审阅建议，_buildInlineTable 包裹 SingleChildScrollView 横向滚动，窄屏表格不再溢出；flash 指出的豆腐块/字体回退、代码高亮/行号、PiliPlus 1080p 播放器移植等大项记录为后续专项；analyze 0 error、render 10 项通过、Windows release 构建成功
  - [x] 豆腐块清理 + 代码行号：DiscuzPostRenderer/InlineHtmlText 文本节点统一剔除私有区 U+E000-F8FF 与零宽字符（comiis 图标字体不再渲染成方块）；代码块增加行号列（等宽右对齐），代码复制仍可用；analyze 0 error、render 10 项通过、Windows release 构建成功
  - [x] 代码块字体修复 + 代码/B站卡渲染测试：代码块 fontFamily 改为 Consolas + fallback（monospace/Courier New/CJK），渲染测试加载 consola.ttf；新增 Code + Bilibili Video Card 渲染截图测试，flash 复检哔哩哔哩卡正常、代码块字体不再豆腐块；render 11 项通过、Windows release 构建成功
  - [x] 代码块轻量语法高亮：_highlightCode 对常见关键字（if/else/for/class/return/async/await 等）与数字着色，关键字蓝、数字浅绿；保留可选中复制与行号；analyze 0 error、render 11 项通过、Windows release 构建成功
  - [x] 桌面版心限宽：首页 ListView 外层加 Center + ConstrainedBox(maxWidth:1280)，帖子详情 ListView 外层加 Center + ConstrainedBox(maxWidth:980)，宽屏不再出现上千像素行长；analyze 0 error、render 11 项通过、Windows release 构建成功
  - [x] 楼层标识优化：楼层号从 `1#` 改为 `#1 楼` 并加粗，视觉权重更清晰；analyze 0 error、render 11 项通过、Windows release 构建成功
  - [x] PiliPlus 1080p 播放器 MCP 落盘：子代理分析 PiliPlus 源码后，klpbbs_app 新增 media_kit/media_kit_video/media_kit_libs_video 依赖；新增 lib/bilibili/bili_models.dart、bili_api.dart（bvid->cid、WBI 签名、try_look=1 免登录 1080p、DASH/EDL 音视频拼接）与 lib/widgets/bili_video_player.dart（懒加载播放器，点击播放）；DiscuzPostRenderer B站 VideoBlock 改为内嵌播放器卡片（保留浏览器打开）；main.dart 初始化 MediaKit；Windows release 构建成功（media_kit 自带 libmpv，有 CMake policy 警告但构建通过）
  - [x] B站播放器画质/预览图/错误态优化：BiliVideoPlayer 增加 autoFetchPreview 开关（widget 测试关闭避免网络 Timer）；封面图改用 CachedNetworkImage + Referer 防盗链头；未播放态有 BV 号占位标题与圆角容器；画质菜单带当前项对勾，1080P 标注「免登录」、720P「高清」、1080P60「高帧率」；播放失败显示重试 + 外部打开按钮；修复渲染测试结构；analyze 0 error、render 11 项通过、Windows release 构建成功
  - [x] B站卡设计中性化 + 画质精简 + 楼层信息右对齐 + 网易云识别：B站卡去掉大蓝框/蓝标题，改为 surfaceContainerLow + 主题色图标；画质菜单只保留 1080P/720P/480P/360P；楼层时间/IP 与楼层号改为右对齐两行布局（时间+IP 一行、#N 楼一行）；非 B站媒体检测网易云显示音乐卡（红色音符图标）并支持外部打开；analyze 0 error、render 11 项通过、Windows release 构建成功
  - [x] B站播放态布局修复 + 网易云内嵌播放：BiliVideoPlayer 播放后改为 ClipRRect + AspectRatio(16:9) + Stack(fit: expand)，Video fit contain，避免播放后下方渲染错误；新增 NetEaseMusicPlayer（网易云 outer/url 直链 + media_kit 内嵌播放/暂停，不再跳转）；DiscuzPostRenderer 检测网易云 iframe 的 id 参数并内嵌音乐卡；新增网易云卡渲染截图测试；flash 复检确认 B站卡已无雷霆大蓝框；analyze 0 error、render 12 项通过、Windows release 构建成功
  - [x] 播放持续/进度/全屏 + 楼层右对齐修复 + 打赏用户头像 + 自由选择复制：BiliVideoPlayer 静态保存 Player/VideoController，滚动出屏不销毁、回来复用；新增进度条（可拖拽 seek）、3 秒自动隐藏控制栏、全屏页；NetEaseMusicPlayer 同样保持播放并加进度条；楼层头部改为 Expanded 作者区（不再多个 Flexible+Spacer 导致右对齐失效）；打赏记录解析头像+uid，UI 显示头像并可点击进用户空间，新增「查看打赏详情」外部链接；长按楼层新增「选择复制正文」对话框（SelectableText 自由选择）；analyze 0 error、render 12 项通过、Windows release 构建成功
  - [x] 退出帖子停止播放 + 打赏模块完善：BiliVideoPlayer/NetEaseMusicPlayer 新增静态 stopAll()，ThreadDetailPage dispose 时统一停止播放器；打赏区按 flash 方案重构：暖金色容器、默认显示 3 条、可展开全部、金额正负分色、点击用户进空间、「查看详情」改为应用内 ModalBottomSheet 完整评分日志；移除无用 url_launcher import；analyze 0 error、render 12 项通过、Windows release 构建成功
  - [x] 截图对比修复 + 个人空间 PC 资料增强：打赏解析修正用户昵称选择器（a.f_c 优先，头像链接文本为空不再误取）、金额清洗（前导零/正负号/单位）；奖励头像不再传 faceUrl 防止重叠；帖子 AppBar 返回按钮加中文 tooltip；底部操作栏改为不透明防穿透；getUserSpace 改抓 PC 版资料页（mobile=no），UserSpace 模型新增 stats/creditsDetail/gameProfile，用户空间 UI 新增主题/回帖/好友统计行、积分明细彩色 Chip、游戏与社交资料卡片；analyze 0 error、comiis_parser 40 项、render 12 项通过、Windows release 构建成功
  - [x] 帖子分页修复 + 封神榜解析/UI + 全局导航补充 + 签名 BBCode：parseThreadDetail 总页数改为解析 thread-{tid}-{page}-1.html 与「共 N 页」（旧正则误命中表单导致总页数恒为 1）；封神榜解析修正 5 列（用户/行为/到期/操作时间/理由），UI 改为卡片：头像/昵称/行为彩色标签/理由框/封禁时间/到期时间，底部留白防遮挡；darkroom/search/guide/sign_rank 补 GlobalNavButton；用户空间签名改用 InlineHtmlText 渲染 Discuz 签名 HTML；comiis_parser 41 项、render 12 项通过、Windows release 构建成功
  - [x] 网易云封面/歌名 + 折叠图片渲染 + 勋章显示：NetEaseMusicPlayer 自动拉取歌曲封面/歌名/歌手并显示（autoFetchMeta 可关避免测试 Timer）；折叠块改用 Text.rich（SelectableText.rich 对 WidgetSpan 支持差导致折叠内容加载失败/图片不显示）；勋章行从 take(3) 改为 take(6)，超过 6 枚才显示 +N，加载失败显示勋章占位图标；analyze 0 error、comiis_parser 41 项、render 12 项通过、Windows release 构建成功
  - [x] 编辑权限修复 + tid=173104 样本：ThreadDetailPage 现在只有当前登录用户是楼主时才显示「编辑帖子/删除帖子」（非作者只显示举报）；新增 viewthread_173104 样本与解析单测（多图正文/文字+图片 URL）；comiis_parser 42 项、render 12 项通过、Windows release 构建成功
  - [x] flash 全面前端审阅 + 幽灵空白修复：3.7 flash 输出分页面 P0/P1/P2 优化清单；修复 P0 帖子正文大面积空白（_htmlToSpans 中 <div align> 分支移除多余 WidgetSpan 换行）；其余 P1/P2 已记录待后续（AppBar 精简、播放器手势、打赏卡片风格、勋章详情弹窗等）；render 12 项通过、Windows release 构建成功
  - [x] 回退最近两轮改动：按用户要求回退「接口一致性审计/登录态验证/点赞链接」三轮改动（getHome、signIn、recommendThread、getFavorites、getCreditRules、parseSubForums、parseRatings、parseThreadDetail、parseTasks、parsePromotion、parseUserThreads、parseSimpleThreadLinks 等恢复原样）；analyze 0 error、comiis_parser 47 项、api_smoke+bbcode 25 项通过、Windows release 构建成功




  - [ ] PC 级专业帖子/回复编辑器
  - [ ] UI 全面重构（分区美化 + 各页面）
  - [ ] 日期显示（发布 + 最近回复）
  - [ ] flash 指出的细节：标题栏缺失图标方块、正文留白不均、首页网格卡片对齐不一致、登录页卡片黑边偏硬

---

## 1. 目标与验收标准

**目标**：完整逆向 klpbbs.com 移动端网页（克米设计 comiis_app）的全部普通用户功能，
并将 Flutter 客户端打磨到「移动端功能 100% 还原 + 整合 PC 端独有功能」，无明显 bug。

**验收标准（全部满足才算完成）**：
1. 帖子/回复信息**正确爬取**且**正确显示**（标题、作者、时间、楼层、正文、附件、图片、
   回复数、浏览量、来源分类、IP 归属地、用户等级、勋章、签名、打赏记录等）。
2. 额外标签正确显示：**「精」精华、「推荐」、「热门」、「悬赏」、「售价」** 等。
3. 接近网页的帖子正文渲染：Discuz 代码（quote/code/spoiler/table/attach/hide/img/video/audio/网盘）全部还原。
4. 视频播放、音乐播放可用（B 站 iframe / 原生 mp4 / 音频）。
5. 正确排版、优雅流畅页面、无溢出、无崩溃、无明显 bug。
6. 双端 UI：移动端（<600px 单列 + 底栏）、PC 桌面端（≥600px 侧栏/多栏网格），各自正确。
7. 完美多功能的 UI 风格设置（主题色/暗色 OLED/字号/密度/卡片样式/头像形状/省流等）。
8. 完整分区（版块树 + 主题分类 + 子版块）。
9. 完整帖子/回复编辑器：Discuz 代码渲染预览、网页效果预览、文件上传、强大的编辑器。
10. 签名编辑、用户空间（资料/主题/回复/收藏/好友/勋章）。
11. 原站全部表情（帖子/回复/小喇叭），比例显示正确。
12. 发帖 UA 自定义等超多功能设置。
13. 所有写操作（发帖/悬赏/回复/编辑/小喇叭/签到/收藏/评分/私信/举报/资料修改/上传）
    在**本地测试论坛**完整实现并验证通过。

---

## 2. 安全红线（最高优先级，违反即停止）

> ⚠️ 真实论坛（klpbbs.com）管理严格，写操作可能触发风控导致账号禁言/警告。

1. **真实论坛只读**：客户端在真实模式（baseUrl = klpbbs.com）下**只允许 GET 浏览 + 登录**，
   发帖/悬赏/回复/编辑/删除/小喇叭/签到/收藏/评分/打赏/举报/资料修改/上传等一切写操作
   **一律由网络层拦截**（`ReadWritePolicy` + `AppConfig.allowWrite = isLocalTestMode`）。
2. **写操作仅在本地测试论坛（127.0.0.1:8000）实测**。
3. **逆向阶段全部使用只读 GET**（curl/http_request），绝不带写参数请求真实论坛。
4. 登录账号 `nnbnnbnnb` 仅用于真实论坛的**只读逆向**（获取登录态以观察编辑器/签名等需登录页面）；
   若登录需要验证码，停止并通知用户输入，绝不绕过。

---

## 3. 现状盘点（2026-08）

### 3.1 已存在（基础较完整，需逐项验证正确性）
- 网络层 `dio_client.dart`（CookieJar 会话、重定向跟随、host 白名单、写策略）
- 解析器 `comiis_parser.dart`（1151 行，覆盖版块/帖子列表/详情/签到/小黑屋/私信/勋章/道具/任务/推广/好友/用户空间/通知等）
- API 封装 `klpbbs_api.dart`（登录/注册/发帖/回复/楼中楼/编辑/删除/私信/签到/收藏/评分/打赏/举报/资料修改/图片上传）
- 模型：forum / thread_summary / post_floor / post_block(11 类) / horn_message / sign_entry / darkroom_entry / user_space / pm_models
- 页面：首页/导读/签到/小黑屋/搜索/排行榜/帖子详情/版块列表/登录/注册/发帖/编辑资料/私信(列表+详情)/用户空间/用户主题/通知/好友/勋章/道具/任务/推广/收藏版块/视频播放/设置
- 双端自适应 `responsive_layout.dart`、桌面快捷入口 `desktop_shortcuts.dart`
- 主题系统 `app_config.dart`（AppStyle 7 种/暗色 OLED/字号/密度/卡片样式/头像形状/省流/黑名单/默认起始页）

### 3.2 已知缺陷与待补（重点，随推进持续追加）
- [x] ~~真实论坛写操作安全红线（allowWrite 恒 true）~~ → 已修复
- [x] ~~`ThreadSummary` 缺「精/推荐/悬赏/售价」等状态字段~~ → 已补精/荐/热度/置顶字段+渲染（悬赏/售价待补）
- [x] ~~版块树（分区→版块）~~ → ForumGroup + parseForumGroups + 首页分组渲染
- [ ] 原站表情系统未实现（帖子/回复/小喇叭表情，比例正确）
- [ ] 发帖 UA 自定义设置未实现
- [ ] 帖子编辑器需强化（Discuz 预览 / 网页预览 / 附件上传进度 / 表情面板）
- [ ] 悬赏帖（发悬赏/采纳答案）需完整实现
- [ ] 回帖可见/购买可见（hide）隐藏内容的一键回复 + 局部刷新
- [ ] B 站视频桌面端原生全屏播放强化
- [ ] 音乐播放器（audio）渲染验证
- [ ] 小喇叭（ahome_horn）读 + 写（本地）完整实现
- [ ] 离线缓存（SQLite/Hive）未实现（可选增强）
- [ ] 大量页面存在未验证的 UI 溢出/bug（需逐页截图核验）

---

## 4. 逆向计划（只读 GET，逐页核验 HTML 结构）

> 样本统一保存到 `mock-server/samples/`，解析器适配后用样本写单元测试。

- [x] 首页 `forum.php?mobile=2`（已抓 `home.html`，含版块树 + forumlist_li）
- [ ] 版块列表 `forum.php?mod=forumdisplay&fid={fid}&mobile=2`（含精/推荐/热门图标、子版块、主题分类、公告）
- [ ] 帖子详情 `forum.php?mod=viewthread&tid={tid}&mobile=2`（楼层/正文/附件/评分/签名/勋章/楼中楼/IP/等级/悬赏）
- [ ] 导读 hot/new/newthread
- [ ] 用户空间 `home.php?mod=space&uid={uid}`（资料/主题/回复/收藏/好友/勋章）
- [ ] 发帖页 `forum.php?mod=post&action=newthread&fid={fid}`（编辑器表单：typeid/悬赏/投票/附件/表情/UA）
- [ ] 回复页 `forum.php?mod=post&action=reply&tid={tid}`
- [ ] 编辑页 `forum.php?mod=post&action=edit&...`
- [ ] 签名编辑页 `home.php?mod=spacecp&ac=profile&op=info`（签名 Discuz 代码）
- [ ] 小喇叭 `plugin.php?id=ahome_horn:index`（读 + 写表单）
- [ ] 签到 `plugin.php?id=k_misign:sign`（今日/本月/总榜/日历 + 签到按钮）
- [ ] 表情接口/静态资源（sunju_facemall 表情商城 + Discuz 内置表情 smilies 目录）
- [ ] 搜索 `search.php?mod=forum`
- [ ] 勋章/道具/任务/推广/好友/通知/收藏（已存在，需核验）
- [ ] 积分/用户组/消息提示（systempm 等）
- [ ] PC 端独有：小黑屋 `showdarkroom`、排行榜 `misc.php?mod=ranklist`、发帖 UA 自定义、主题分类多选等

---

## 5. 功能实现清单（Checklist）

### 5.1 浏览与信息展示
- [ ] 首页版块树 + 首页推荐帖 + 小喇叭广播
- [ ] 版块帖子列表（分页/主题分类过滤/排序/公告/子版块）
- [ ] 帖子详情（楼层分页/倒序/只看作者/跳页）
- [ ] 帖子正文 11 类 Block 渲染（Text/Quote/Code/Spoiler/Table/Video/Audio/Attach/Netdisk/Image/Divider + Hide）
- [ ] 精/推荐/热门/悬赏/售价标签
- [ ] 导读（热门/最新/新主题）
- [ ] 签到排行（今日/本月/总榜/日历）
- [ ] 小黑屋、排行榜
- [ ] 搜索（帖子/用户/版块）
- [ ] 用户空间（资料/主题/回复/收藏/好友/勋章/签名）

### 5.2 写操作（仅本地测试论坛验证）
- [ ] 登录（SecCode 验证码 + Cookie 导入）
- [ ] 注册
- [ ] 发帖（普通/悬赏/投票/主题分类）
- [ ] 回复（普通/楼中楼点评）
- [ ] 编辑帖子（主题+回复，Discuz 代码）
- [ ] 删除帖子/主题
- [ ] 小喇叭发布
- [ ] 签到
- [ ] 收藏（帖子/版块）
- [ ] 评分/打赏、点赞/踩
- [ ] 举报
- [ ] 私信（发送/删除会话）
- [ ] 资料修改（签名/性别/生日/头像）
- [ ] 附件/图片上传（swfupload + hash 回填 + 进度条）
- [ ] 回帖可见/购买可见一键回复 + 局部刷新

### 5.3 编辑器（重点强化）
- [ ] 富文本/BBCode 编辑（Discuz 代码渲染预览）
- [ ] 网页效果预览（近似真实网页渲染）
- [ ] 文件/图片上传 + 进度
- [ ] 表情面板（全站表情，比例正确）
- [ ] 主题分类选择、悬赏金额、投票选项、UA 自定义

### 5.4 UI 与设置
- [ ] 双端自适应（移动端/PC 端）正确性
- [ ] 主题色（7 预设 + 自定义）/暗色/OLED 纯黑/护眼
- [ ] 字号缩放、视觉密度、卡片样式、头像形状
- [ ] 省流（无图/低清/原图）、图片缓存上限
- [ ] 黑名单（关键词/UID）、默认起始页、自动签到
- [ ] 发帖 UA 自定义、超多功能设置

---

## 6. 测试策略

1. **单元测试**：解析器对 `mock-server/samples/` 真实样本 + 本地论坛样本逐项断言。
2. **写操作**：全部在本地测试论坛（127.0.0.1:8000，admin/testuser 账号）实测；真实论坛绝不写。
3. **UI 截图核验**：`flutter test` 渲染截图逐页检查溢出/bug（移动端 390px、PC 1280px 两种宽度）。
4. **静态检查**：`flutter analyze` 保持 0 error。
5. **真机只读回归**：以 `nnbnnbnnb` 登录态在真实论坛只读浏览，核验解析正确性（不写）。

---

## 7. 账号与验证码协作约定

- 真实论坛只读/登录态逆向账号：`nnbnnbnnb` / `qx114514`（注意：早期文档记的 zz114514 是错误的）。
- 若登录页面出现**图形验证码（SecCode）**：停止自动流程，把验证码图片展示给用户并等待输入。
- 本地测试论坛账号：`admin/Admin@123456`、`testuser/Test@123456`（见 REVERSE_ENGINEERING.md §6.2）。
- 绝不使用真实账号进行任何写操作测试。

---

## 8. 每轮推进方法（供自动续跑）

1. 读取上一轮「推进记录」确定当前焦点。
2. 逆向：只读 GET 抓取/核验目标页面 HTML，保存样本，更新 REVERSE_ENGINEERING.md。
3. 实现：改代码（解析器/模型/API/页面/渲染器）。
4. 测试：`flutter analyze` + 相关 `flutter test`（本地环境可用时）。
5. 把发现的新遗漏追加到本文档对应清单，更新「推进记录」。
6. 无阻塞则继续下一项；同一阻塞持续多轮则标记 blocked 并说明原因。

---

## 9. 交接快照（换会话继续必读）

### 9.1 环境与工具
- **Flutter**：`D:\fullter\flutter\bin\flutter.bat`（3.32.5 / Dart 3.8.1）。不在 PATH，需用绝对路径调用。
- **项目根**：`F:\klpbbs`，Flutter 工程 `F:\klpbbs\klpbbs_app`。
- **本地测试论坛**：Discuz X3.4 + 克米插件，源码 `F:\klpbbs\local-env\www`，地址 `http://127.0.0.1:8000/`。
  - 启动：MariaDB `F:\klpbbs\local-env\mariadb-10.4.32-winx64\bin\mysqld.exe --datadir=F:\klpbbs\local-env\mariadb-data --port=3306 --bind-address=127.0.0.1`
  - PHP `F:\klpbbs\local-env\php\php.exe -S 127.0.0.1:8000 -t F:\klpbbs\local-env\www`
  - 账号 `admin/Admin@123456`、`testuser/Test@123456`、`baduser/Bad@123456`
  - 本地已装插件：comiis_app 系列 + k_misign + comiis_sms；**无 replyfloor（楼中楼）插件**
- **构建/测试**：`cd F:\klpbbs\klpbbs_app` 后
  - `D:\fullter\flutter\bin\flutter.bat analyze`
  - `D:\fullter\flutter\bin\flutter.bat test`（39 项，需本地论坛已启动）
  - `D:\fullter\flutter\bin\flutter.bat build windows --release`（产物 `build\windows\x64\runner\Release\klpbbs_app.exe`）

### 9.2 用反重力 flash 模型做 UI 视觉核验（关键工具）
运行中的 Antigravity IDE 语言服务器 `language_server.exe` 监听 `127.0.0.1:1759`。调用 agentapi：
```powershell
$env:ANTIGRAVITY_LS_ADDRESS='127.0.0.1:1759'
$env:ANTIGRAVITY_CSRF_TOKEN='dcdaf8e4-eb37-447d-b5f5-8916d7030ac5'   # 从语言服务器命令行 --csrf_token 读取
$env:ANTIGRAVITY_PROJECT_ID='785a8d40-1b4a-42b2-b6aa-b8099bc2309f'  # 从 get-conversation-metadata 读取
$exe='C:\Users\Administrator\AppData\Local\Programs\antigravity\resources\bin\language_server.exe'
& $exe agentapi new-conversation --model=flash "提示词(附图片绝对路径)" 2>&1
# 返回 JSON 里的 conversationId；等 ~40s 后读回复：
# C:\Users\Administrator\.gemini\antigravity\brain\{conversationId}\.system_generated\logs\transcript.jsonl
# 取 source=MODEL 且 type=PLANNER_RESPONSE 且含 content 的最后一条（中文是 GBK 字节，需按 936 解码）
```
- 截图目录：`C:\Users\Administrator\.gemini\antigravity\brain\a25e4450-ae81-4820-8909-3ca7553ea5ed\screenshot_*.png`
- 截图由 `test/render_screenshots_test.dart` 生成（已加载 SimHei + MaterialIcons 字体，避免豆腐块）。

### 9.3 当前状态速览（截至 2026-08 交接）
**已能工作**：解析器双结构兼容、精/荐/热/置顶标签、版块树折叠、表情系统+渲染、登录/注册验证码、本地写操作全链路、小喇叭（头像+进主页）、链接应用内跳转、图片放大、楼中楼（replyfloor 解析+渲染）、点评/打赏记录渲染、用户徽章（top_lev 用户组/管理员/版主 + comiis_verify 认证）、勋章（用户空间解析+渲染）、使用道具（mgc_post_{pid} 菜单+本地写）、分享（复制标题+链接）、编辑器 BBCode 工具栏+全站表情面板+Discuz 预览、日期显示（发布+最近回复）、登录页卡片柔化、首页网格卡片对齐一致。
**已知未完成**：小喇叭发布（本地无 ahome_horn 插件）、PC 编辑器（附件上传/UA/悬赏待补）、UI 继续打磨（首页分区 PC 多列化/正文留白）。

### 9.4 接手建议顺序
1. 先 `git`/文档对齐，读 `docs/REVERSE_ENGINEERING.md` §7（编辑器/表情/小喇叭/验证码逆向结论）。
2. ~~楼中楼~~：已完成（逆向 §8 + `_parseReplyFloor` + `ReplyFloorComment` + `InlineHtmlText`）。
3. ~~VIP/SVIP/管理员徽章~~：已完成（逆向 §9 + levelGid/levelColor/verifies + _badgeColor 渲染）。
4. ~~勋章~~：已完成（逆向 §10 + `UserSpace.medals` + `parseUserSpace` 勋章解析 + `user_space_page` 渲染）。
5. ~~使用道具/分享~~：已完成（逆向 §11 + `magicItems` + `useMagic` + 分享复制标题链接）。
6. 编辑器预览/附件上传/UA/悬赏、首页分区 PC 多列美化、小喇叭发布（本地无 ahome_horn 插件，可先做只读入口）（**下一轮焦点**）。
7. 每轮：改代码 → `analyze`+`test` → `build` → flash 截图核验 → 更新本文件推进记录。
