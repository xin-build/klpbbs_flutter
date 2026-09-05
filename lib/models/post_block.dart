import 'package:flutter/foundation.dart';

/// 帖子正文结构化区块基类
@immutable
sealed class PostBlock {
  const PostBlock();
}

/// 纯文本/富文本段落（含行内加粗、斜体、下划线、颜色、字号、超链接）
class TextBlock extends PostBlock {
  final String html;
  final String? align;
  const TextBlock(this.html, {this.align});

  @override
  String toString() => 'TextBlock(html: $html, align: $align)';
}

/// 行内或独占图片区块
class ImageBlock extends PostBlock {
  final String src;
  final String? alt;
  final String? caption;

  /// 是否为表情小图（`static/image/smiley/` 或带 smilieid），按原始比例渲染
  final bool isEmoji;

  /// 排版对齐方式（center / left / right）
  final String? align;

  const ImageBlock({
    required this.src,
    this.alt,
    this.caption,
    this.isEmoji = false,
    this.align,
  });

  @override
  String toString() => 'ImageBlock(src: $src, isEmoji: $isEmoji, align: $align)';
}

/// Discuz 引用区块（[quote] 或 <blockquote>）
class QuoteBlock extends PostBlock {
  final String author;
  final String contentHtml;
  final int? pid;
  final String? align;
  const QuoteBlock({
    required this.author,
    required this.contentHtml,
    this.pid,
    this.align,
  });

  @override
  String toString() => 'QuoteBlock(author: $author, content: $contentHtml, align: $align)';
}

/// 代码块（[code] 或 <pre><code>）
class CodeBlock extends PostBlock {
  final String code;
  final String? language;
  final String? align;
  const CodeBlock({required this.code, this.language, this.align});

  @override
  String toString() => 'CodeBlock(code: $code, align: $align)';
}

/// 折叠 / 收起内容区块（[spoiler]）
class SpoilerBlock extends PostBlock {
  final String title;
  final String contentHtml;
  const SpoilerBlock({required this.title, required this.contentHtml});

  @override
  String toString() => 'SpoilerBlock(title: $title)';
}

/// 表格区块（<table>）
class TableBlock extends PostBlock {
  final List<String> headers;
  final List<List<String>> rows;
  final String? align;
  const TableBlock({
    this.headers = const [],
    this.rows = const [],
    this.align,
  });

  @override
  String toString() => 'TableBlock(headers: $headers, rows: ${rows.length}, align: $align)';
}

/// 排版修饰卡片/容器区块（支持 Discuz 嵌套单列表格 [table=98%,DarkOrange]、背景颜色、边框、阴影与居中卡片）
class CardContainerBlock extends PostBlock {
  final List<PostBlock> children;
  final String? bgColor;
  final String? borderColor;
  final double? widthPercent;
  final String? align;

  const CardContainerBlock({
    required this.children,
    this.bgColor,
    this.borderColor,
    this.widthPercent,
    this.align,
  });

  @override
  String toString() => 'CardContainerBlock(children: ${children.length}, bg: $bgColor, align: $align)';
}

/// 分割线区块（[hr] / <hr>）
class DividerBlock extends PostBlock {
  const DividerBlock();

  @override
  String toString() => 'DividerBlock()';
}

/// Discuz 飞行动画文字区块（`[fly]` / `<marquee>`）
class FlyBlock extends PostBlock {
  final String html;
  final String? align;
  const FlyBlock(this.html, {this.align});

  @override
  String toString() => 'FlyBlock(html: $html, align: $align)';
}

/// 视频/内嵌视频播放区块（原生视频 / Bilibili / 优酷 / YouTube）
class VideoBlock extends PostBlock {
  final String src;
  final bool isBilibili;
  final String? bvid;
  final String? aid;
  final String? align;
  const VideoBlock({
    required this.src,
    this.isBilibili = false,
    this.bvid,
    this.aid,
    this.align,
  });

  @override
  String toString() => 'VideoBlock(src: $src, isBilibili: $isBilibili, align: $align)';
}

/// 音频播放区块
class AudioBlock extends PostBlock {
  final String src;
  final String title;
  final String? align;
  const AudioBlock({
    required this.src,
    this.title = '音频文件',
    this.align,
  });

  @override
  String toString() => 'AudioBlock(src: $src, title: $title, align: $align)';
}

/// 附件下载区块
class AttachmentBlock extends PostBlock {
  final String name;
  final String url;

  /// 文件类型图标（Discuz `static/image/filetype/*.gif`）
  final String? iconUrl;
  final String? sizeText;
  final String? priceText;
  final String? uploadTime;
  final int? downloadCount;
  final String? align;

  const AttachmentBlock({
    required this.name,
    required this.url,
    this.iconUrl,
    this.sizeText,
    this.priceText,
    this.uploadTime,
    this.downloadCount,
    this.align,
  });

  @override
  String toString() => 'AttachmentBlock(name: $name, url: $url, align: $align)';
}

/// 网盘下载与提取码区块（百度网盘/123云盘/夸克网盘/蓝奏云）
class NetdiskBlock extends PostBlock {
  final String panName;
  final String url;
  final String extractCode;
  final String? align;
  const NetdiskBlock({
    required this.panName,
    required this.url,
    required this.extractCode,
    this.align,
  });

  @override
  String toString() => 'NetdiskBlock($panName: $url, code: $extractCode, align: $align)';
}

/// 隐藏内容提示区块（[hide] 回复后可见）
class HideBlock extends PostBlock {
  final String reason;
  const HideBlock({this.reason = '本帖隐藏的内容需要回复才可以浏览'});

  @override
  String toString() => 'HideBlock(reason: $reason)';
}

/// 资源帖/模组/皮肤/分类信息字段
class ResourceInfoField {
  final String label;
  final String value;
  final String? url;

  const ResourceInfoField({
    required this.label,
    required this.value,
    this.url,
  });

  @override
  String toString() => 'ResourceInfoField($label: $value, url: $url)';
}

/// 资源帖分类信息卡片区块（模组发布、附加包、皮肤、软件等分类表单）
class ResourceInfoBlock extends PostBlock {
  final String title;
  final List<ResourceInfoField> fields;

  const ResourceInfoBlock({
    this.title = '资源发布信息',
    required this.fields,
  });

  @override
  String toString() => 'ResourceInfoBlock($title: ${fields.length} fields)';
}

/// 悬赏问答专属悬赏卡片（Discuz 悬赏帖）
class BountyBlock extends PostBlock {
  final int price;
  final String unit;
  final String? message;
  final bool isSolved;
  final String? bestAnswerAuthor;

  const BountyBlock({
    required this.price,
    this.unit = '粒铁粒',
    this.message,
    this.isSolved = false,
    this.bestAnswerAuthor,
  });

  @override
  String toString() => 'BountyBlock(price: $price $unit, solved: $isSolved)';
}

/// 帖子审核通过状态条
class AuditStatusBlock extends PostBlock {
  final String auditor;
  final String timeText;

  const AuditStatusBlock({
    required this.auditor,
    required this.timeText,
  });

  @override
  String toString() => 'AuditStatusBlock(auditor: $auditor, time: $timeText)';
}

/// 投票选项模型
class PollOption {
  final String id;
  final String label;
  final int votes;
  final double percent;
  final bool isChecked;
  final String? colorHex;

  const PollOption({
    required this.id,
    required this.label,
    this.votes = 0,
    this.percent = 0.0,
    this.isChecked = false,
    this.colorHex,
  });
}

/// 投票帖卡片区块（Discuz 投票帖）
class PollBlock extends PostBlock {
  final String title;
  final bool isMultiple;
  final int maxChoices;
  final int votersCount;
  final String? expireText;
  final List<PollOption> options;
  final bool isVoted;
  final bool canVote;
  final bool isClosed;
  final bool loginRequired;
  final String? tipText;

  const PollBlock({
    this.title = '单选投票',
    this.isMultiple = false,
    this.maxChoices = 1,
    this.votersCount = 0,
    this.expireText,
    required this.options,
    this.isVoted = false,
    this.canVote = true,
    this.isClosed = false,
    this.loginRequired = false,
    this.tipText,
  });

  @override
  String toString() => 'PollBlock(title: $title, options: ${options.length}, voters: $votersCount, isClosed: $isClosed)';
}

/// 回帖奖励卡片区块（Discuz 回帖奖励/抢楼红包）
class ReplyRewardBlock extends PostBlock {
  final int totalReward;
  final int perReplyReward;
  final int limitCount;
  final String unit;
  final String rawText;

  const ReplyRewardBlock({
    this.totalReward = 0,
    this.perReplyReward = 0,
    this.limitCount = 1,
    this.unit = '粒铁粒',
    required this.rawText,
  });

  @override
  String toString() => 'ReplyRewardBlock(total: $totalReward, per: $perReplyReward, limit: $limitCount)';
}

/// 辩论帖卡片区块（Discuz 辩论帖）
class DebateBlock extends PostBlock {
  final String affirmpoint; // 正方观点
  final String negatpoint; // 反方观点
  final int affirmvotes;
  final int negatvotes;
  final String? endtime;

  const DebateBlock({
    required this.affirmpoint,
    required this.negatpoint,
    this.affirmvotes = 0,
    this.negatvotes = 0,
    this.endtime,
  });

  @override
  String toString() => 'DebateBlock(affirm: $affirmvotes, negat: $negatvotes)';
}

/// 屏蔽/封禁/审核中/锁定状态区块（Discuz 提示: 作者被禁止或删除 内容自动屏蔽 / 该帖被管理员屏蔽 / 审核中）
class ShieldBlock extends PostBlock {
  final String title;
  final String reason;
  final String? iconType; // 'banned', 'shielded', 'review', 'locked'

  const ShieldBlock({
    this.title = '提示',
    required this.reason,
    this.iconType,
  });

  @override
  String toString() => 'ShieldBlock(title: $title, reason: $reason)';
}

