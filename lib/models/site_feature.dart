class SiteFeature {
  final String title;
  final String url;
  final String category;
  const SiteFeature({required this.title, required this.url, required this.category});
}

class MembershipOffer {
  final int groupId;
  final String title;
  final String details;
  final String? buyUrl;
  final String? switchUrl;
  final String? exitUrl;
  final String? permissionsUrl;
  const MembershipOffer({required this.groupId, required this.title, this.details = '',
    this.buyUrl, this.switchUrl, this.exitUrl, this.permissionsUrl});
}
