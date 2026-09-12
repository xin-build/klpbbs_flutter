class AiSummaryLink {
  final String url;
  final String label;
  final String service;

  const AiSummaryLink({
    required this.url,
    required this.label,
    this.service = '',
  });

  factory AiSummaryLink.fromJson(Map<String, dynamic> json) {
    return AiSummaryLink(
      url: json['url'] as String? ?? '',
      label: json['label'] as String? ?? '',
      service: json['service'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'url': url,
        'label': label,
        'service': service,
      };
}

class AiSummaryData {
  final String headline;
  final String summary;
  final List<String> notices;
  final List<String> downloadSteps;
  final List<AiSummaryLink> links;
  final String? generatedTime;
  final String? statusText;
  final bool isStreaming;
  final bool isFailed;
  final String? errorMessage;
  final String? streamUrl;

  const AiSummaryData({
    this.headline = '',
    this.summary = '',
    this.notices = const [],
    this.downloadSteps = const [],
    this.links = const [],
    this.generatedTime,
    this.statusText,
    this.isStreaming = false,
    this.isFailed = false,
    this.errorMessage,
    this.streamUrl,
  });

  bool get isEmpty =>
      headline.isEmpty &&
      summary.isEmpty &&
      notices.isEmpty &&
      downloadSteps.isEmpty &&
      links.isEmpty;

  bool get hasContent => !isEmpty;

  AiSummaryData copyWith({
    String? headline,
    String? summary,
    List<String>? notices,
    List<String>? downloadSteps,
    List<AiSummaryLink>? links,
    String? generatedTime,
    String? statusText,
    bool? isStreaming,
    bool? isFailed,
    String? errorMessage,
    String? streamUrl,
  }) {
    return AiSummaryData(
      headline: headline ?? this.headline,
      summary: summary ?? this.summary,
      notices: notices ?? this.notices,
      downloadSteps: downloadSteps ?? this.downloadSteps,
      links: links ?? this.links,
      generatedTime: generatedTime ?? this.generatedTime,
      statusText: statusText ?? this.statusText,
      isStreaming: isStreaming ?? this.isStreaming,
      isFailed: isFailed ?? this.isFailed,
      errorMessage: errorMessage ?? this.errorMessage,
      streamUrl: streamUrl ?? this.streamUrl,
    );
  }

  factory AiSummaryData.fromJson(Map<String, dynamic> json, {String? streamUrl}) {
    final rawLinks = json['links'] as List<dynamic>? ?? const [];
    final links = rawLinks
        .map((e) => AiSummaryLink.fromJson(e as Map<String, dynamic>))
        .toList();

    final rawNotices = json['notices'] as List<dynamic>? ?? const [];
    final notices = rawNotices.map((e) => e.toString()).toList();

    final rawDownload = json['download'] as List<dynamic>? ?? const [];
    final downloadSteps = rawDownload.map((e) => e.toString()).toList();

    return AiSummaryData(
      headline: json['headline'] as String? ?? '',
      summary: json['summary'] as String? ?? '',
      notices: notices,
      downloadSteps: downloadSteps,
      links: links,
      generatedTime: json['generated'] as String?,
      streamUrl: streamUrl,
    );
  }

  Map<String, dynamic> toJson() => {
        'headline': headline,
        'summary': summary,
        'notices': notices,
        'download': downloadSteps,
        'links': links.map((e) => e.toJson()).toList(),
        'generated': generatedTime,
      };
}
