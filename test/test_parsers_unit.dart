import 'package:flutter_test/flutter_test.dart';
import 'package:klpbbs_app/api/comiis_parser.dart';

void main() {
  test('parseSiteStats parses mobile tj classes correctly', () {
    const html = '''
<div id="chart">
  <div class="wp cl ct2">
    <div class="chart_tj z cl">
      <p class="tj_today"><span class="bd cshake"><b></b></span><em><i class="fa fa-fw fa-calendar-o"></i> 今日: 57</em></p>
      <p class="tj_yesterday"><span class="bd cshake"><b></b></span><em><i class="fa fa-fw fa-calendar"></i> 昨日: 273</em></p>
      <p class="tj_posts" title="主题: 123595&#10;回帖: 10187193"><span class="bd cshake"><b></b></span><em><i class="fa fa-fw fa-bar-chart"></i> 总帖: 10310790</em></p>
      <p class="tj_members" title="715 人在线"><span class="bd cshake"><b></b></span><em><i class="fa fa-fw fa-users"></i> 会员: 2317628</em></p>
    </div>
  </div>
</div>
''';
    final stats = ComiisParser.parseSiteStats(html);
    expect(stats.todayPosts, 57);
    expect(stats.yesterdayPosts, 273);
    expect(stats.totalPosts, 10310790);
    expect(stats.totalMembers, 2317628);
  });

  test('parseForumGroups parses mobile comiis_forumlist correctly', () {
    const html = '''
<div class="comiis_forumlist comiis_km1 bg_f b_t b_b cl">
  <div class="comiis_bbs_show b_b cl" href="#sub_forum_1"><h2><a href="javascript:;">综合分区</a></h2></div>
  <div id="sub_forum_1" class="comiis_forum_nbox comiis_forum_two">
    <a href="forum-2-1.html"><img src="none.png" alt="游戏资讯" /><p>帖数: 8640</p></a>
    <a href="forum-111-1.html"><img src="none.png" alt="周边创作" /><p>帖数: 4578</p></a>
  </div>
</div>
<div class="comiis_forumlist comiis_km37 bg_f b_t b_b cl">
  <div class="comiis_bbs_show b_b cl" href="#sub_forum_37"><h2><a href="javascript:;">BE资源分区</a></h2></div>
  <div id="sub_forum_37" class="comiis_forum_nbox comiis_forum_one">
    <a href="forum-51-1.html"><img src="none.png" alt="BE地图" /><p>1BE地图别名:存档;世界;World</p></a>
    <a href="forum-52-1.html"><img src="none.png" alt="BE附加包" /><p>32BE附加包别名:行为包;模组;Add-on</p></a>
  </div>
</div>
''';
    final groups = ComiisParser.parseForumGroups(html);
    expect(groups.length, 2);
    expect(groups[0].name, '综合分区');
    expect(groups[0].gid, 1);
    expect(groups[0].forums.length, 2);
    expect(groups[0].forums[0].name, '游戏资讯');
    expect(groups[0].forums[0].fid, 2);
    expect(groups[0].forums[0].threadCount, 8640);

    expect(groups[1].name, 'BE资源分区');
    expect(groups[1].gid, 37);
    expect(groups[1].forums[0].name, 'BE地图');
    expect(groups[1].forums[0].fid, 51);
    expect(groups[1].forums[0].todayCount, 1);
    expect(groups[1].forums[0].description, '别名: 存档;世界;World');
  });

  test('parseTuhaoBanner extracts script JSON correctly', () {
    const html = '''
<script>
(function(){var data=[{"n":"缔造者","a":"<img src=\\"https:\\/\\/user.klpbbs.com\\/data\\/avatar\\/000\\/01\\/20\\/54_avatar_middle.jpg\\" \\/>","m":"热烈庆祝缔造者入坛六周年（点击进入领取铁粒）\\r\\nhttps:\\/\\/klpbbs.com\\/thread-173255-1-1.html"}];})();
</script>
''';
    final tuhao = ComiisParser.parseTuhaoBanner(html);
    expect(tuhao, isNotNull);
    expect(tuhao!.author, '缔造者');
    expect(tuhao.avatarUrl, 'https://user.klpbbs.com/data/avatar/000/01/20/54_avatar_middle.jpg');
    expect(tuhao.tid, 173255);
  });

  test('parseSiteStats ignores forum-level post count and rejects incomplete stats', () {
    const forumListHtml = '''
<div class="comiis_forumlist comiis_km110 bg_f b_t b_b cl">
  <div id="sub_forum_110" class="comiis_forum_nbox comiis_forum_two">
    <a href="forum-41-1.html"><img src="none.png" alt="闲聊讨论" /><p>今日: 10</p></a>
    <a href="forum-68-1.html"><img src="none.png" alt="悬赏问答" /><p>今日: 4</p></a>
  </div>
</div>
''';
    final stats = ComiisParser.parseSiteStats(forumListHtml);
    expect(stats.isComplete, false);
  });

  test('parseForumGroups parses 我关注的 as gid 0 and preserves 综合分区 as gid 1', () {
    const html = '''
<div class="comiis_forumlist comiis_km0 bg_f b_t b_b cl">
  <div class="comiis_bbs_show b_b cl" href="#sub_forum_0"><h2><a href="javascript:;">我关注的\uf107管理</a></h2></div>
  <div id="sub_forum_0" class="comiis_forum_nbox">
    <a href="forum-41-1.html"><img src="none.png" alt="闲聊讨论" /></a>
  </div>
</div>
<div class="comiis_forumlist comiis_km1 bg_f b_t b_b cl">
  <div class="comiis_bbs_show b_b cl" href="#sub_forum_1"><h2><a href="javascript:;">综合分区</a></h2></div>
  <div id="sub_forum_1" class="comiis_forum_nbox comiis_forum_two">
    <a href="forum-2-1.html"><img src="none.png" alt="游戏资讯" /><p>帖数: 8640</p></a>
  </div>
</div>
''';
    final groups = ComiisParser.parseForumGroups(html);
    expect(groups.length, 2);
    expect(groups[0].gid, 0);
    expect(groups[0].name, '我关注的');
    expect(groups[0].forums[0].name, '闲聊讨论');

    expect(groups[1].gid, 1);
    expect(groups[1].name, '综合分区');
    expect(groups[1].forums[0].name, '游戏资讯');
  });
}
