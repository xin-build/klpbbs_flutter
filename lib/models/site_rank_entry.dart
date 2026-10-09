class SiteRankEntry {
  final int tid;
  final int? rank;
  final String title;
  final String subtitle;
  const SiteRankEntry(
      {required this.tid, this.rank, required this.title, this.subtitle = ''});
}
