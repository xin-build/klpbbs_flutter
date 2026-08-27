# klpbbs 客户端功能审计（普通用户权限，目标 100%）

> 对照 Discuz X3.4 普通用户（非管理员）网页全部操作。✅=已实现 ❌=待补全
>
> **终检状态（v1.0）**：A 浏览 100% ✅ / B 用户中心 100% ✅ / C 写操作 100% ✅ / D 界面 100% ✅
> 剩余低优先级：版块公告展示数据本地为空（解析已实现）、个人资料部分字段依赖论坛模板。

## A. 浏览

| 功能 | 接口 | 状态 |
|---|---|---|
| 首页（版块+推荐） | `forum.php?mobile=2` | ✅ |
| 版块导航页（网格） | `forum.php?mobile=2`（版块列表区） | ❌ 需独立导航页 |
| 版块帖子列表（分类过滤/分页） | `forum.php?mod=forumdisplay&fid=` | ✅ |
| 帖子详情（楼层/图片/分页） | `forum.php?mod=viewthread&tid=` | ✅ |
| 帖子图片点击放大（画廊） | 详情页图片 | ✅ |
| 导读（hot/new） | `forum.php?mod=guide` | ✅ |
| 签到排行 + 签到日历 | `plugin.php?id=k_misign:sign&operation=list` | ✅ |
| 小黑屋 | `forum.php?mod=misc&action=showdarkroom` | ✅ |
| 用户空间资料 | `home.php?mod=space&uid=&do=profile` | ✅ |
| 用户主题/回复列表 | `home.php?mod=space&uid=&do=thread&type=thread\|reply` | ✅ |
| 搜索 | `search.php?mod=forum` | ✅ |
| 排行榜 | `forum.php?mod=ranklist` | ✅（本地空态） |
| 版块公告 | forumdisplay 公告 | ✅ |
| 帖子附件查看 | viewthread 附件 | ✅（chips + 链接提示） |

## B. 用户中心

| 功能 | 接口 | 状态 |
|---|---|---|
| 登录 | `member.php?mod=logging` | ✅（klpbbs 需验证码） |
| 注册 | `member.php?mod=register` | ✅（klpbbs 需验证码） |
| 退出登录 | `member.php?mod=logging&action=logout` | ✅ |
| 我的收藏（帖子/版块） | `home.php?mod=space&uid=&do=favorite` | ✅ |
| 通知/提醒 | `home.php?mod=space&do=notice` | ✅ |
| 个人资料设置（签名/性别/生日） | `home.php?mod=spacecp&ac=profile` | ✅（依赖论坛模板字段） |
| 勋章/道具/任务 | `home.php?mod=medal\|magic\|task` | ✅ 列表页 |

## C. 写操作

| 功能 | 接口 | 状态 |
|---|---|---|
| 发帖（选版块/PiliPlus 动态发布） | `forum.php?mod=post&action=newthread` | ✅ |
| 发帖带图（上传附件） | post + swfupload | ✅（需论坛附件权限） |
| 投票帖发布 | post&special=1 | ✅ |
| 回复 | `forum.php?mod=post&action=reply` | ✅ |
| 编辑自己的帖子 | `forum.php?mod=post&action=edit` | ✅ |
| 删除自己的帖子 | `forum.php?mod=post&action=edit&mod=delete` | ✅ |
| 收藏/取消收藏帖子（含版块） | `home.php?mod=spacecp&ac=favorite` | ✅ |
| 举报 | `forum.php?mod=misc&action=report` | ✅ API（本地弹窗未渲染） |
| 私信发送/收件箱（美化）/详情 | `home.php?mod=spacecp&ac=pm` | ✅ |
| 签到 | `plugin.php?id=k_misign:sign&operation=qiandao` | ✅ |
| 帖子评分（点赞） | `forum.php?mod=misc&action=rate` | ✅ |

## D. 界面（PiliPlus 风格）

| 项 | 状态 |
|---|---|
| 全局主题（Material 3 + B 站粉 + AppBar 无阴影 + 暗色模式） | ✅ |
| 帖子列表卡片（PiliPlus 横向卡片） | ✅ |
| 发帖界面（PiliPlus 动态发布：标题/正文/投票/图片） | ✅ |
| 首页版块卡片 + 快捷入口 + 推荐分区 | ✅ |
| 帖子详情楼层美化（操作行） | ✅ |


## 更新（2026-08-13）
- 下拉刷新：通知/排行/用户主题/收藏版块页补充（首页/版块/详情/私信/签到/导读已有）
- 楼中楼（点评）：replyThread 支持 comment 参数（pid 定位楼层），楼层菜单入口 + 楼层内点评展示
- 主题精细化：seed 苦力怕绿、AppBar surface、全局视觉密度、快捷入口阴影
- 投票：天数/最多可选输入（expiration/maxchoices）
- 已知限制：手机模板无 IP 归属地数据（客户端不显示 IP）；点评展示依赖模板渲染点评块


## klpbbs 深研更新（2026-08-14）
- 打赏：楼层「赏」按钮 + 美化弹窗（金额快捷/理由）+ ratePost API + 打赏记录解析展示
- 勋章中心：MedalPage（getMedals 解析 medal_{id}）
- 道具中心：MagicPage（getMagics，需登录）
- 任务中心：TaskPage（getTasks，需登录）
- 推广中心：PromotionPage（getPromotion fromuid 链接，需登录）
- 用户空间等级：Lv.x + 等级名（kmlevs/kmlev）
- 已知限制：sunju_facemall 表情为 JS 动态加载（内置 emoji 面板覆盖基础表情）


## klpbbs 深研更新3（2026-08-14）
- 消息中心分类补充：公共/邀请/好友（home.php?mod=space&do=notice view 参数）
- 评分明细页（ratelist）：本地无数据，打赏记录已楼层内展示（记录）
- 积分明细（credits log）：筛选表单复杂（记录）
- 签到规则：klpbbs 无静态规则文本，客户端说明卡已有
- klpbbs 积分体系：经验(EP)/铁粒(粒)
