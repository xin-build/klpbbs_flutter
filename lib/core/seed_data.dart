import '../models/forum.dart';
import '../models/forum_header_info.dart';
import '../models/thread_summary.dart';

/// 论坛内置离线种子数据
/// 当苦力怕论坛服务器维护中 (HTTP 521/523) 或首次离线冷启动时，提供完整的分区版块、版规导览卡片与推荐流
class SeedData {
  SeedData._();

  /// 真实分区与版块树（带官方高清网络图标与完整描述）
  static const List<ForumGroup> forumGroups = [
    ForumGroup(
      gid: 0,
      name: '我关注的',
      forums: [
        Forum(
          fid: 41,
          name: '闲聊讨论',
          description: '日常闲聊、交友互动与灌水天地',
          iconUrl: 'https://klpbbs.com/data/attachment/common/34/common_41_icon.png',
          gid: 0,
        ),
        Forum(
          fid: 43,
          name: '软件资源',
          description: '启动器、编辑工具与实用辅助程序',
          iconUrl: 'https://klpbbs.com/data/attachment/common/17/common_43_icon.png',
          gid: 0,
        ),
        Forum(
          fid: 52,
          name: 'BE附加包',
          description: '行为包、模组与 Add-on 扩展组件',
          iconUrl: 'https://klpbbs.com/data/attachment/common/9a/common_52_icon.png',
          gid: 0,
        ),
      ],
    ),
    ForumGroup(
      gid: 1,
      name: '综合分区',
      forums: [
        Forum(
          fid: 2,
          name: '游戏资讯',
          description: 'Minecraft 最新快讯、版本更新与官方动态',
          iconUrl: 'https://klpbbs.com/data/attachment/common/c8/common_2_icon.png',
          gid: 1,
        ),
        Forum(
          fid: 111,
          name: '周边创作',
          description: '同人绘画、小说、动画与手工艺品',
          iconUrl: 'https://klpbbs.com/data/attachment/common/69/common_111_icon.png',
          gid: 1,
        ),
        Forum(
          fid: 43,
          name: '软件资源',
          description: '启动器、编辑工具与实用辅助程序',
          iconUrl: 'https://klpbbs.com/data/attachment/common/17/common_43_icon.png',
          gid: 1,
        ),
        Forum(
          fid: 42,
          name: '视频专区',
          description: '游戏实况、精彩混剪与建筑延时摄影',
          iconUrl: 'https://klpbbs.com/data/attachment/common/a1/common_42_icon.png',
          gid: 1,
        ),
      ],
    ),
    ForumGroup(
      gid: 110,
      name: '灵感交流',
      forums: [
        Forum(
          fid: 41,
          name: '闲聊讨论',
          description: '日常闲聊、交友互动与灌水天地',
          iconUrl: 'https://klpbbs.com/data/attachment/common/34/common_41_icon.png',
          gid: 110,
        ),
        Forum(
          fid: 68,
          name: '悬赏问答',
          description: '铁粒悬赏提问与游戏疑难求助',
          iconUrl: 'https://klpbbs.com/data/attachment/common/a3/common_68_icon.png',
          gid: 110,
        ),
        Forum(
          fid: 123,
          name: '创意港湾',
          description: '创作者的灵感港湾与作品展示',
          iconUrl: 'https://klpbbs.com/data/attachment/common/20/common_123_icon.png',
          gid: 110,
        ),
        Forum(
          fid: 113,
          name: '教程中心',
          description: '红石、建筑、开发与玩法进阶指引',
          iconUrl: 'https://klpbbs.com/data/attachment/common/92/common_113_icon.png',
          gid: 110,
        ),
      ],
    ),
    ForumGroup(
      gid: 37,
      name: 'BE资源分区',
      forums: [
        Forum(
          fid: 51,
          name: 'BE地图',
          description: '基岩版建筑、解密、生存与 PVP 存档',
          iconUrl: 'https://klpbbs.com/data/attachment/common/28/common_51_icon.png',
          gid: 37,
        ),
        Forum(
          fid: 52,
          name: 'BE附加包',
          description: 'Add-on、行为包与玩法模组扩展',
          iconUrl: 'https://klpbbs.com/data/attachment/common/9a/common_52_icon.png',
          gid: 37,
        ),
        Forum(
          fid: 53,
          name: 'BE纹理[材质]',
          description: '基岩版材质包与 Shader 光影渲染',
          iconUrl: 'https://klpbbs.com/data/attachment/common/d8/common_53_icon.png',
          gid: 37,
        ),
        Forum(
          fid: 50,
          name: '皮肤分享',
          description: '原创与高清 Minecraft 角色皮肤',
          iconUrl: 'https://klpbbs.com/data/attachment/common/c4/common_50_icon.png',
          gid: 37,
        ),
        Forum(
          fid: 55,
          name: '其他资源',
          description: '基岩版 UI 与其他附加资源',
          iconUrl: 'https://klpbbs.com/data/attachment/common/3e/common_55_icon.png',
          gid: 37,
        ),
      ],
    ),
    ForumGroup(
      gid: 36,
      name: 'JE资源分区',
      forums: [
        Forum(
          fid: 139,
          name: 'JE地图',
          description: 'Java 版大型建筑、RPG 与冒险存档',
          iconUrl: 'https://klpbbs.com/data/attachment/common/e0/common_139_icon.png',
          gid: 36,
        ),
        Forum(
          fid: 140,
          name: 'JE模组/数据包',
          description: 'Forge/Fabric 模组与原版数据包',
          iconUrl: 'https://klpbbs.com/data/attachment/common/13/common_140_icon.png',
          gid: 36,
        ),
        Forum(
          fid: 141,
          name: 'JE纹理[材质]',
          description: 'Java 版高清材质与光影 Shader',
          iconUrl: 'https://klpbbs.com/data/attachment/common/0f/common_141_icon.png',
          gid: 36,
        ),
        Forum(
          fid: 48,
          name: 'JE整合包',
          description: '科技、魔法、冒险与生存整合包',
          iconUrl: 'https://klpbbs.com/data/attachment/common/d2/common_48_icon.png',
          gid: 36,
        ),
        Forum(
          fid: 50,
          name: '皮肤分享',
          description: '原创与高清 Minecraft 角色皮肤',
          iconUrl: 'https://klpbbs.com/data/attachment/common/c4/common_50_icon.png',
          gid: 36,
        ),
        Forum(
          fid: 49,
          name: 'JE其他资源',
          description: 'Java 版音效包、字体与辅助文件',
          iconUrl: 'https://klpbbs.com/data/attachment/common/58/common_49_icon.png',
          gid: 36,
        ),
      ],
    ),
    ForumGroup(
      gid: 38,
      name: '多人游戏',
      forums: [
        Forum(
          fid: 127,
          name: '联机交友',
          description: '寻找联机好友与开黑组队',
          iconUrl: 'https://klpbbs.com/data/attachment/common/ec/common_127_icon.png',
          gid: 38,
        ),
        Forum(
          fid: 56,
          name: '服务器大厅',
          description: 'Minecraft 优质服务器发布与宣传',
          iconUrl: 'https://klpbbs.com/data/attachment/common/9f/common_56_icon.png',
          gid: 38,
        ),
        Forum(
          fid: 57,
          name: '服务器插件',
          description: 'Bukkit/Spigot/Paper 服务端插件',
          iconUrl: 'https://klpbbs.com/data/attachment/common/72/common_57_icon.png',
          gid: 38,
        ),
        Forum(
          fid: 58,
          name: '服务端整合',
          description: '开箱即用的服务端整合核心',
          iconUrl: 'https://klpbbs.com/data/attachment/common/e4/common_58_icon.png',
          gid: 38,
        ),
      ],
    ),
    ForumGroup(
      gid: 40,
      name: '其他分区',
      forums: [
        Forum(
          fid: 44,
          name: '编程分享',
          description: 'Java、Python、C++ 与开发技术交流',
          iconUrl: 'https://klpbbs.com/data/attachment/common/f7/common_44_icon.png',
          gid: 40,
        ),
      ],
    ),
    ForumGroup(
      gid: 39,
      name: '论坛事务',
      forums: [
        Forum(
          fid: 61,
          name: '全站置顶',
          description: '苦力怕论坛官方重大公告',
          iconUrl: 'https://klpbbs.com/data/attachment/common/7f/common_61_icon.png',
          gid: 39,
        ),
        Forum(
          fid: 62,
          name: '站内活动',
          description: '官方竞赛、节日福利与社区活动',
          iconUrl: 'https://klpbbs.com/data/attachment/common/44/common_62_icon.png',
          gid: 39,
        ),
        Forum(
          fid: 112,
          name: '论坛事务',
          description: '勋章申请、违规举报与版主竞聘',
          iconUrl: 'https://klpbbs.com/data/attachment/common/7f/common_112_icon.png',
          gid: 39,
        ),
      ],
    ),
  ];

  /// 默认推荐帖子种子列表
  static final List<ThreadSummary> homeThreads = [
    ThreadSummary(
      tid: 169092,
      fid: 41,
      forumName: '闲聊讨论',
      title: '【全站 | 长期】KLPBBS 人才引进计划',
      author: '雪球♡',
      timeText: '2026-02-15',
      replies: 18,
      views: 2840,
      isSticky: true,
      excerpt: '诚邀各位优秀的创作者、审核员与开发者加入苦力怕论坛团队！',
    ),
    ThreadSummary(
      tid: 156202,
      fid: 41,
      forumName: '闲聊讨论',
      title: '关于近期部分作品使用付费下载的第三方链接的通告',
      author: '暗魅塔骑士',
      timeText: '2025-01-28',
      replies: 23,
      views: 4520,
      isSticky: true,
      excerpt: '为维护论坛绿色分享生态，严禁使用强制付费诱导类下载网盘。',
    ),
    ThreadSummary(
      tid: 65605,
      fid: 41,
      forumName: '闲聊讨论',
      title: '【2022-11-30】苦力怕论坛总坛规',
      author: '管理员',
      timeText: '2022-11-30',
      replies: 45,
      views: 8930,
      isSticky: true,
      excerpt: '请各位坛友遵守论坛社区公约，共同营造良好的创作与交流氛围。',
    ),
  ];

  /// 各版块专属头部配置（Banner + 海报 + 图形交互按钮）
  static ForumHeaderInfo getForumHeader(int fid, String forumName) {
    return ForumHeaderInfo(
      fid: fid,
      name: forumName,
      bannerUrl: 'https://klpbbs.com/template/the_c_style/images/banner.jpg',
    );
  }
}
