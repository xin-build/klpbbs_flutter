import 'thread_sort_model.dart';
import '../core/app_config.dart';

/// Discuz 帖子已上传/已有附件模型
class PostAttachmentItem {
  final int aid;
  final String filename;
  final int filesize;
  final bool isImage;
  final String? localPath;
  bool isInserted;

  PostAttachmentItem({
    required this.aid,
    required this.filename,
    required this.filesize,
    this.isImage = false,
    this.localPath,
    this.isInserted = false,
  });

  /// 附件预览或下载 URL
  String get previewUrl => '${AppConfig.baseUrl}forum.php?mod=attachment&aid=$aid';

  String get sizeText {
    if (filesize < 1024) return '$filesize B';
    if (filesize < 1024 * 1024) {
      return '${(filesize / 1024).toStringAsFixed(1)} KB';
    }
    return '${(filesize / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

/// Discuz 帖子/回复编辑信息模型（用于实时拉取并回填已有内容）
class PostEditInfo {
  final String subject;
  final String message;
  final int? typeid;
  final int? sortid;
  final ThreadSortInfo? threadSortInfo;
  final int? readperm;
  final List<String> tags;
  final String? formhash;
  final String? posttime;
  final List<PostAttachmentItem> attachments;
  final bool isFirstFloor;
  final String? errorMessage;
  final PostEditorAttributes? editorAttributes;

  const PostEditInfo({
    this.subject = '',
    this.message = '',
    this.typeid,
    this.sortid,
    this.threadSortInfo,
    this.readperm,
    this.tags = const [],
    this.formhash,
    this.posttime,
    this.attachments = const [],
    this.isFirstFloor = false,
    this.errorMessage,
    this.editorAttributes,
  });

  bool get hasError => errorMessage != null && errorMessage!.isNotEmpty;
}

/// Discuz 单个发帖/回复附加选项特性（例如使用个人签名、HTML代码、禁用表情等）
class PostOptionAttribute {
  final bool available; // 是否在当前版块/用户组中提供
  final bool checked;   // 当前/默认是否勾选
  final bool disabled;  // 是否被网页端禁用置灰（只读）

  const PostOptionAttribute({
    this.available = true,
    this.checked = false,
    this.disabled = false,
  });

  PostOptionAttribute copyWith({
    bool? available,
    bool? checked,
    bool? disabled,
  }) {
    return PostOptionAttribute(
      available: available ?? this.available,
      checked: checked ?? this.checked,
      disabled: disabled ?? this.disabled,
    );
  }
}

/// Discuz 网页发帖/回复附加选项集合（100% 实时对齐 Web 端 post_editor_attribute.htm）
class PostEditorAttributes {
  // 基本属性
  final PostOptionAttribute useSig;            // 使用个人签名 (usesig)
  final PostOptionAttribute isAnonymous;       // 使用匿名发帖 (isanonymous)
  final PostOptionAttribute hiddenReplies;     // 回帖仅作者可见 (hiddenreplies)
  final PostOptionAttribute orderType;         // 回帖倒序排列 (ordertype)
  final PostOptionAttribute allowNoticeAuthor; // 接收回复通知 (allownoticeauthor)

  // 文本特性
  final PostOptionAttribute htmlOn;            // HTML代码 (htmlon)
  final PostOptionAttribute allowImgCode;      // [img]代码 (allowimgcode)
  final PostOptionAttribute allowImgUrl;       // 解析图片链接 (allowimgurl)
  final PostOptionAttribute parseUrlOff;       // 禁用链接识别 (parseurloff)
  final PostOptionAttribute smileyOff;         // 禁用表情 (smileyoff)
  final PostOptionAttribute bbcodeOff;         // 禁用编辑器代码 (bbcodeoff)
  final PostOptionAttribute imgContent;        // 内容生成图片 (imgcontent)

  // 用户组阅读权限选项列表
  final List<({int value, String name})> readPermOptions;

  // 管理用户组专属特性 (Discuz post_editor_extra.htm & post_editpost.htm)
  final List<({int value, String name})> stickTopicOptions; // 置顶选项 (select[name="sticktopic"])
  final List<({int value, String name})> addDigestOptions;  // 加精选项 (select[name="adddigest"])
  final bool canCloseThread;                                // 允许直接锁定主题 (input[name="closed"])
  final bool canDeletePost;                                 // 编辑模式允许直接删除本帖 (input[name="delete"])

  bool get hasManagementOptions =>
      stickTopicOptions.isNotEmpty || addDigestOptions.isNotEmpty || canCloseThread || canDeletePost;

  const PostEditorAttributes({
    this.useSig = const PostOptionAttribute(available: true, checked: true, disabled: false),
    this.isAnonymous = const PostOptionAttribute(available: true, checked: false, disabled: false),
    this.hiddenReplies = const PostOptionAttribute(available: true, checked: false, disabled: false),
    this.orderType = const PostOptionAttribute(available: true, checked: false, disabled: false),
    this.allowNoticeAuthor = const PostOptionAttribute(available: true, checked: true, disabled: false),
    this.htmlOn = const PostOptionAttribute(available: true, checked: false, disabled: true),
    this.allowImgCode = const PostOptionAttribute(available: true, checked: true, disabled: true),
    this.allowImgUrl = const PostOptionAttribute(available: true, checked: true, disabled: false),
    this.parseUrlOff = const PostOptionAttribute(available: true, checked: false, disabled: false),
    this.smileyOff = const PostOptionAttribute(available: true, checked: false, disabled: false),
    this.bbcodeOff = const PostOptionAttribute(available: true, checked: false, disabled: false),
    this.imgContent = const PostOptionAttribute(available: true, checked: false, disabled: true),
    this.readPermOptions = const [],
    this.stickTopicOptions = const [],
    this.addDigestOptions = const [],
    this.canCloseThread = false,
    this.canDeletePost = false,
  });
}
