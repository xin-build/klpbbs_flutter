// Discuz 分类信息 / 发帖模板模型（threadsorts / sortid / typeoption）

/// 单个分类选项字段模型
class SortOptionField {
  /// 字段标识符（如 zwm, bezcbb, zyly, ytdz, xzdz 等）
  final String identifier;

  /// 字段显示标题（如 中文名, 支持版本, 资源来源, 下载地址 等）
  final String title;

  /// 字段类型（text, number, textarea, radio, checkbox, select, calendar, email, url, image）
  final String type;

  /// 是否必填
  final bool required;

  /// 填写说明/帮助提示
  final String description;

  /// 单位（如 KB, MB, 元）
  final String unit;

  /// 最大字符长度或数值
  final int? maxlength;

  /// 选项键值对（单选 radio、多选 checkbox、下拉 select 时使用，如 {'1': '原创', '2': '转载'}）
  final Map<String, String> choices;

  /// 初始值（回填编辑或默认值，单值 String 或多选 `List<String>`）
  final dynamic initialValue;

  const SortOptionField({
    required this.identifier,
    required this.title,
    required this.type,
    this.required = false,
    this.description = '',
    this.unit = '',
    this.maxlength,
    this.choices = const {},
    this.initialValue,
  });

  bool get isText => type == 'text' || type == 'url' || type == 'email';
  bool get isNumber => type == 'number';
  bool get isTextarea => type == 'textarea';
  bool get isRadio => type == 'radio';
  bool get isCheckbox => type == 'checkbox';
  bool get isSelect => type == 'select';
  bool get isCalendar => type == 'calendar' || type == 'date';

  SortOptionField copyWith({
    String? identifier,
    String? title,
    String? type,
    bool? required,
    String? description,
    String? unit,
    int? maxlength,
    Map<String, String>? choices,
    dynamic initialValue,
  }) {
    return SortOptionField(
      identifier: identifier ?? this.identifier,
      title: title ?? this.title,
      type: type ?? this.type,
      required: required ?? this.required,
      description: description ?? this.description,
      unit: unit ?? this.unit,
      maxlength: maxlength ?? this.maxlength,
      choices: choices ?? this.choices,
      initialValue: initialValue ?? this.initialValue,
    );
  }
}

/// 版块分类模板切换 Tab 项（如：模组发布 / 地图发布 / 普通帖子）
class SortTabItem {
  final int sortid;
  final String name;

  const SortTabItem({
    required this.sortid,
    required this.name,
  });
}

/// 帖子/版块分类信息模板总览
class ThreadSortInfo {
  /// 当前激活的分类模板 ID
  final int sortid;

  /// 模板名称（如：模组发布、插件发布）
  final String name;

  /// 该版块发帖是否强制要求选择分类模板（sortrequired = 1）
  final bool sortrequired;

  /// 当前版块可用的全部模板 Tab 列表
  final List<SortTabItem> availableSorts;

  /// 当前模板包含的所有字段列表
  final List<SortOptionField> fields;

  const ThreadSortInfo({
    required this.sortid,
    required this.name,
    this.sortrequired = false,
    this.availableSorts = const [],
    this.fields = const [],
  });

  bool get hasFields => fields.isNotEmpty;
}
