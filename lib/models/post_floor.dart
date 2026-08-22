import 'post_block.dart';

/// 楼中楼（replyfloor 插件）的一条回复
///
/// 逆向依据：mock-server/samples/viewthread.html 中
/// `div.replyfloor_box > div.replyfloor_content > div.replyfloor_content_ul >
/// div.replyfloor_content_li` 结构。
class ReplyFloorComment {
  /// 楼中楼回复 id（replyfloor_content_li_{msgid}）
  final int msgid;

  /// 作者 uid（无则 null）
  final int? uid;

  /// 作者昵称
  final String author;

  /// 头像绝对 URL（size=small）
  final String avatar;

  /// 回复正文 HTML（含行内表情 <img smilieid>）
  final String contentHtml;

  /// 回复时间文本（如 2026-6-24 13:17）
  final String timeText;

  /// IP 归属地（如 IP：Coast / IP:辽宁省）
  final String location;

  /// 头像挂件 URL（空表示无）
  final String faceUrl;

  const ReplyFloorComment({
    required this.msgid,
    this.uid,
    this.author = '',
    this.avatar = '',
    this.faceUrl = '',
    this.contentHtml = '',
    this.timeText = '',
    this.location = '',
  });
}

/// 楼层打赏与评分日志模型
class FloorReward {
  final String username;
  final int? uid;
  final String avatar;
  final String faceUrl;
  final String amount;
  final String reason;
  final String dateline;

  const FloorReward({
    required this.username,
    this.uid,
    this.avatar = '',
    this.faceUrl = '',
    required this.amount,
    required this.reason,
    this.dateline = '',
  });
}

/// 帖子详情页的一层（楼主 / 回帖）
class PostFloor {
  final int? pid;
  final int? uid;
  final String author;
  final String timeText;

  /// 正文 HTML（含 <img>/<blockquote>/<code> 等，渲染时保留）
  final String contentHtml;

  /// 结构化区块列表（顺序保存段落、图片、代码、引用、折叠、多媒体等）
  final List<PostBlock> blocks;

  /// 从正文提取的图片 URL 列表
  final List<String> images;

  /// 附件列表（name, url）
  final List<({String name, String url})> attachments;

  /// 楼中楼点评（Discuz postcomment：author, content）
  final List<({String author, String content})> comments;

  /// 楼中楼（replyfloor 插件）回复列表
  final List<ReplyFloorComment> replyFloors;

  /// 楼中楼回复总数（replyfloor_count_{pid}，可能大于已渲染条数）
  final int replyFloorCount;

  /// 楼中楼楼层号（replyfloor_tail_floor，如 99#）
  final String floorNumber;

  /// 头像挂件（sunju_facemall）URL（空表示无）
  final String faceUrl;

  /// IP 归属地（klpbbs 楼层显示"IP:xx省"）
  final String ipText;

  /// 作者等级（klpbbs 楼层"Lv.x 会员等级" / "管理员" / "版主"）
  final String levelText;

  /// 用户组 gid（top_lev 链接 ac=usergroup&gid={gid}；1=管理员 3=版主 等）
  final int? levelGid;

  /// top_lev 内联背景色（管理员红 #FF0000 / 版主品红 #FF00FF，普通会员为空）
  final String levelColor;

  /// 认证徽章（comiis_verify：Discuz verify 实名认证，img/title/vid）
  final List<({String img, String title, String vid})> verifies;

  /// 本楼层可用道具（mgc_post_{pid} 菜单项：mid/名称/图标/链接/idtype/id）
  final List<({String mid, String name, String img, String idtype, String id})>
  magicItems;

  /// 是否为楼主（主题作者，带「楼主」徽章）
  final bool isThreadAuthor;

  /// 作者勋章图片 URL 列表
  final List<String> medals;

  /// 嵌入内容（iframe/video/audio 的 src）
  final List<String> embeds;

  /// 已有 N 人打赏（空表示无）
  final String rewardCount;

  /// 打赏记录（用户/头像 uid/金额/理由）
  final List<
    ({String user, int? uid, String avatar, String amount, String reason})
  >
  rewards;

  /// 用户个性签名档
  final String signature;

  /// 是否为最佳答案（悬赏贴最佳解答）
  final bool isBestAnswer;

  /// 悬赏金额（首楼悬赏：如 "50 铁粒"）
  final String? bountyPrice;

  /// 悬赏贴是否已结贴/已解决
  final bool isBountySolved;

  /// 本楼点赞数
  final int likes;

  /// 当前登录用户是否已为本楼点赞
  final bool isLiked;

  /// 最后编辑提示（如 "本帖最后由 水稻本尊 于 2026-6-24 14:02 编辑"）
  final String? lastEdited;

  /// 点赞用户列表（首楼/主贴点赞用户头像列表：uid, avatarUrl, username）
  final List<({int? uid, String avatarUrl, String username})> likedUsers;

  const PostFloor({
    this.pid,
    this.uid,
    required this.author,
    this.timeText = '',
    required this.contentHtml,
    this.blocks = const [],
    this.images = const [],
    this.attachments = const [],
    this.comments = const [],
    this.replyFloors = const [],
    this.replyFloorCount = 0,
    this.floorNumber = '',
    this.faceUrl = '',
    this.ipText = '',
    this.levelText = '',
    this.levelGid,
    this.levelColor = '',
    this.verifies = const [],
    this.magicItems = const [],
    this.isThreadAuthor = false,
    this.medals = const [],
    this.embeds = const [],
    this.rewardCount = '',
    this.rewards = const [],
    this.signature = '',
    this.isBestAnswer = false,
    this.bountyPrice,
    this.isBountySolved = false,
    this.likes = 0,
    this.isLiked = false,
    this.lastEdited,
    this.likedUsers = const [],
  });

  PostFloor copyWith({
    int? pid,
    int? uid,
    String? author,
    String? timeText,
    String? contentHtml,
    List<PostBlock>? blocks,
    List<String>? images,
    List<({String name, String url})>? attachments,
    List<({String author, String content})>? comments,
    List<ReplyFloorComment>? replyFloors,
    int? replyFloorCount,
    String? floorNumber,
    String? faceUrl,
    String? ipText,
    String? levelText,
    int? levelGid,
    String? levelColor,
    List<({String img, String title, String vid})>? verifies,
    List<({String mid, String name, String img, String idtype, String id})>? magicItems,
    bool? isThreadAuthor,
    List<String>? medals,
    List<String>? embeds,
    String? rewardCount,
    List<({String user, int? uid, String avatar, String amount, String reason})>? rewards,
    String? signature,
    bool? isBestAnswer,
    String? bountyPrice,
    bool? isBountySolved,
    int? likes,
    bool? isLiked,
    String? lastEdited,
    List<({int? uid, String avatarUrl, String username})>? likedUsers,
  }) {
    return PostFloor(
      pid: pid ?? this.pid,
      uid: uid ?? this.uid,
      author: author ?? this.author,
      timeText: timeText ?? this.timeText,
      contentHtml: contentHtml ?? this.contentHtml,
      blocks: blocks ?? this.blocks,
      images: images ?? this.images,
      attachments: attachments ?? this.attachments,
      comments: comments ?? this.comments,
      replyFloors: replyFloors ?? this.replyFloors,
      replyFloorCount: replyFloorCount ?? this.replyFloorCount,
      floorNumber: floorNumber ?? this.floorNumber,
      faceUrl: faceUrl ?? this.faceUrl,
      ipText: ipText ?? this.ipText,
      levelText: levelText ?? this.levelText,
      levelGid: levelGid ?? this.levelGid,
      levelColor: levelColor ?? this.levelColor,
      verifies: verifies ?? this.verifies,
      magicItems: magicItems ?? this.magicItems,
      isThreadAuthor: isThreadAuthor ?? this.isThreadAuthor,
      medals: medals ?? this.medals,
      embeds: embeds ?? this.embeds,
      rewardCount: rewardCount ?? this.rewardCount,
      rewards: rewards ?? this.rewards,
      signature: signature ?? this.signature,
      isBestAnswer: isBestAnswer ?? this.isBestAnswer,
      bountyPrice: bountyPrice ?? this.bountyPrice,
      isBountySolved: isBountySolved ?? this.isBountySolved,
      likes: likes ?? this.likes,
      isLiked: isLiked ?? this.isLiked,
      lastEdited: lastEdited ?? this.lastEdited,
      likedUsers: likedUsers ?? this.likedUsers,
    );
  }
}
