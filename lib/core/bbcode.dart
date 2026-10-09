/// Discuz BBCode → HTML 全特性转换器（依据 Discuz! X 官方 function_discuzcode.php 规范）
/// 100% 覆盖官方与论坛自定义代码：
/// - 基础排版：b, i, u, s, strike, del, sub, sup, highlight, mark
/// - 样式与字号：color, backcolor, size (1-7 / px / pt), font
/// - 对齐与段落：align, float, p (支持行高、首行缩进、对齐)
/// - 动画与注音：fly (marquee), ruby (拼音/注音标注), indent (缩进引用)
/// - 链接与媒体：url, email, img, attach, attachimg, audio, media, flash, swf, music, bili, bilibili
/// - 权限与折叠：quote, code, spoiler, collapse, fold, hide, password, free
/// - 表格与列表：table（支持 [tr][td] 及官方管道符 | 快捷语法与多层嵌套）, list, *
/// - 表情：论坛专属表情与自定义短码转换
library;

import '../api/comiis_parser.dart';
import '../models/smiley.dart';
import 'app_config.dart';

String bbcodeToHtml(String input, {List<SmileyCategory>? customSmileys, bool escapeHtml = true}) {
  if (input.isEmpty) return '';
  var s = input;

  // 0. 保护 [code] 代码块，避免代码块内部的 BBCode / 表情 / 换行被二次篡改
  final codeBlocks = <String>[];
  s = s.replaceAllMapped(
    RegExp(r'\[code(?:=([^\]]*))?\]([\s\S]*?)\[/code\]', caseSensitive: false),
    (m) {
      final lang = m[1]?.replaceAll(RegExp(r'''['"]'''), '').trim() ?? '';
      final content = m[2] ?? '';
      final idx = codeBlocks.length;
      final classAttr = lang.isNotEmpty ? ' class="language-$lang"' : '';
      codeBlocks.add('<pre><code$classAttr>$content</code></pre>');
      return '__DISCUZ_CODE_BLOCK_${idx}__';
    },
  );

  // 1. 转义 HTML 特殊字符（仅在纯文本且指定 escapeHtml 时转义，防止破坏已有 HTML 结构）
  if (escapeHtml) {
    s = s
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;');
  }

  // 1.5 表情短码与 Discuz 标准表情代码转换 (如 [贴吧_滑稽], [哔哩_doge], {:12_292:}, {:6_178:} 等)
  if (s.contains('[') || s.contains('{:')) {
    final smileyMap = ComiisParser.getSmileyCodeMap(customSmileys);
    for (final entry in smileyMap.entries) {
      if (entry.key.isEmpty) continue;
      if (s.contains(entry.key)) {
        s = s.replaceAll(
          entry.key,
          '<img src="${entry.value}" class="vm" smilieid="1" alt="${entry.key}" />',
        );
      }
    }
  }

  // 2. 动画效果与注音标注（Discuz 官方特性）
  // [fly]...[/fly] → <marquee width="90%" behavior="scroll" direction="left" class="discuz_fly">...</marquee>
  s = s.replaceAllMapped(
    RegExp(r'\[fly\]([\s\S]*?)\[/fly\]', caseSensitive: false),
    (m) => '<marquee width="90%" behavior="scroll" direction="left" class="discuz_fly">${m[1]}</marquee>',
  );

  // [ruby=拼音]汉字[/ruby]
  s = s.replaceAllMapped(
    RegExp(r'\[ruby=([^\]]+)\]([\s\S]*?)\[/ruby\]', caseSensitive: false),
    (m) => '<ruby>${m[2]}<rt>${m[1]}</rt></ruby>',
  );
  // [ruby]汉字[rt]拼音[/rt][/ruby]
  s = s.replaceAllMapped(
    RegExp(r'\[ruby\]([\s\S]*?)\[rt\]([\s\S]*?)\[/rt\]([\s\S]*?)\[/ruby\]', caseSensitive: false),
    (m) => '<ruby>${m[1]}<rt>${m[2]}</rt>${m[3]}</ruby>',
  );

  // [indent]...[/indent] → <blockquote class="discuz_indent">...</blockquote>
  s = s.replaceAllMapped(
    RegExp(r'\[indent\]([\s\S]*?)\[/indent\]', caseSensitive: false),
    (m) => '<blockquote class="discuz_indent">${m[1]}</blockquote>',
  );

  // 3. 段落排版 [p=行高, 缩进, 对齐]...[/p] 与 [p]...[/p]
  s = s.replaceAllMapped(
    RegExp(r'\[p=(\d+|null)?,\s*(\d+|null)?,\s*(left|center|right)?\]([\s\S]*?)\[/p\]', caseSensitive: false),
    (m) {
      final lh = m[1];
      final ti = m[2];
      final ta = m[3];
      final styles = <String>[];
      if (lh != null && lh != 'null' && lh.isNotEmpty) styles.add('line-height:${lh}px');
      if (ti != null && ti != 'null' && ti.isNotEmpty) styles.add('text-indent:${ti}em');
      if (ta != null && ta != 'null' && ta.isNotEmpty) styles.add('text-align:$ta');
      final styleAttr = styles.isNotEmpty ? ' style="${styles.join(';')}"' : '';
      return '<p$styleAttr>${m[4]}</p>';
    },
  );
  s = s.replaceAllMapped(
    RegExp(r'\[p\]([\s\S]*?)\[/p\]', caseSensitive: false),
    (m) => '<p>${m[1]}</p>',
  );

  // 3.5 快捷对齐标签 [center] / [left] / [right] / [justify]
  s = s.replaceAllMapped(
    RegExp(r'\[center\]([\s\S]*?)\[/center\]', caseSensitive: false),
    (m) => '<div style="text-align:center">${m[1]}</div>',
  );
  s = s.replaceAllMapped(
    RegExp(r'\[left\]([\s\S]*?)\[/left\]', caseSensitive: false),
    (m) => '<div style="text-align:left">${m[1]}</div>',
  );
  s = s.replaceAllMapped(
    RegExp(r'\[right\]([\s\S]*?)\[/right\]', caseSensitive: false),
    (m) => '<div style="text-align:right">${m[1]}</div>',
  );
  s = s.replaceAllMapped(
    RegExp(r'\[justify\]([\s\S]*?)\[/justify\]', caseSensitive: false),
    (m) => '<div style="text-align:justify">${m[1]}</div>',
  );

  // 3.8 提示与说明卡片 [box=标题]...[/box] / [tip] / [notice] / [warning] / [alert] / [info] / [success] / [danger]
  s = s.replaceAllMapped(
    RegExp(r'\[(box|tip|notice|warning|alert|info|success|danger)(?:=([^\]]*))?\]([\s\S]*?)\[/\1\]', caseSensitive: false),
    (m) {
      final type = (m[1] ?? 'box').toLowerCase();
      final param = m[2]?.replaceAll(RegExp(r'''['"]'''), '').trim() ?? '';
      final content = m[3] ?? '';
      String borderColor = '#1976D2';
      String bgColor = '#f0f4f8';
      String icon = 'ℹ️';
      if (type == 'warning' || type == 'alert') {
        borderColor = '#FFA000';
        bgColor = '#fff8e1';
        icon = '⚠️';
      } else if (type == 'danger') {
        borderColor = '#E53935';
        bgColor = '#ffebee';
        icon = '🚫';
      } else if (type == 'success') {
        borderColor = '#43A047';
        bgColor = '#e8f5e9';
        icon = '✅';
      } else if (type == 'tip' || type == 'notice') {
        borderColor = '#00ACC1';
        bgColor = '#e0f7fa';
        icon = '💡';
      }
      final titleText = param.isNotEmpty ? param : (type == 'warning' ? '警告' : (type == 'danger' ? '危险' : (type == 'tip' ? '提示' : '')));
      return '<div class="discuz_box discuz_$type" style="padding:10px 14px;margin:8px 0;background-color:$bgColor;border-left:4px solid $borderColor;border-radius:4px;">'
          '${titleText.isNotEmpty ? '<div style="font-weight:bold;margin-bottom:4px;color:$borderColor;">$icon $titleText</div>' : ''}'
          '$content</div>';
    },
  );

  // 3.9 键盘按键 [kbd]...[/kbd] / [keyboard]...[/keyboard]
  s = s.replaceAllMapped(
    RegExp(r'\[(?:kbd|keyboard)\]([\s\S]*?)\[/(?:kbd|keyboard)\]', caseSensitive: false),
    (m) => '<kbd style="background:#eee;border:1px solid #ccc;border-radius:3px;box-shadow:0 1px 0 rgba(0,0,0,0.2);color:#333;display:inline-block;font-size:0.85em;font-family:monospace;padding:1px 5px;margin:0 2px;">${m[1]}</kbd>',
  );

  // 3.10 匿名内容 [anonymouse]...[/anonymouse]
  s = s.replaceAllMapped(
    RegExp(r'\[anonymouse\]([\s\S]*?)\[/anonymouse\]', caseSensitive: false),
    (m) => '<div class="discuz_anonymouse" style="font-style:italic;color:#666;">🕶️ 匿名内容：${m[1]}</div>',
  );

  // 4. 基础文本修饰标签
  void replacePair(String open, String close, String tag) {
    final re = RegExp(
      RegExp.escape(open) + r'([\s\S]*?)' + RegExp.escape(close),
      caseSensitive: false,
    );
    s = s.replaceAllMapped(
      re,
      (m) => tag + m[1]! + tag.replaceFirst('<', '</'),
    );
  }

  replacePair('[b]', '[/b]', '<b>');
  replacePair('[i]', '[/i]', '<i>');
  replacePair('[u]', '[/u]', '<u>');
  replacePair('[s]', '[/s]', '<s>');
  replacePair('[strike]', '[/strike]', '<strike>');
  replacePair('[del]', '[/del]', '<strike>');
  replacePair('[sub]', '[/sub]', '<sub>');
  replacePair('[sup]', '[/sup]', '<sup>');
  replacePair('[highlight]', '[/highlight]', '<mark>');
  replacePair('[mark]', '[/mark]', '<mark>');

  // [mask]...[/mask] 与 [heimu]...[/heimu]（黑幕 / 刮刮乐 / 防剧透）
  s = s.replaceAllMapped(
    RegExp(r'\[(?:mask|heimu)\]([\s\S]*?)\[/(?:mask|heimu)\]', caseSensitive: false),
    (m) => '<span class="heimu" style="background-color:black;color:black;">${m[1]}</span>',
  );

  // [color=black][backcolor=black]...[/backcolor][/color] 与反序嵌套（论坛常用经典黑幕语法）
  s = s.replaceAllMapped(
    RegExp(
      r'\[color=["\x27]?(?:black|#000|#000000|rgb\(0,0,0\))["\x27]?\]\s*\[(?:backcolor|bg|bgcolor)=["\x27]?(?:black|#000|#000000|rgb\(0,0,0\))["\x27]?\]([\s\S]*?)\[/(?:backcolor|bg|bgcolor)\]\s*\[/color\]',
      caseSensitive: false,
    ),
    (m) => '<span class="heimu" style="background-color:black;color:black;">${m[1]}</span>',
  );
  s = s.replaceAllMapped(
    RegExp(
      r'\[(?:backcolor|bg|bgcolor)=["\x27]?(?:black|#000|#000000|rgb\(0,0,0\))["\x27]?\]\s*\[color=["\x27]?(?:black|#000|#000000|rgb\(0,0,0\))["\x27]?\]([\s\S]*?)\[/color\]\s*\[/(?:backcolor|bg|bgcolor)\]',
      caseSensitive: false,
    ),
    (m) => '<span class="heimu" style="background-color:black;color:black;">${m[1]}</span>',
  );

  // [size=1..7] 或 [size=12px] / [size="5"]...[/size]（循环展开多层嵌套）
  for (var round = 0; round < 3; round++) {
    final prev = s;
    s = s.replaceAllMapped(
      RegExp(r'\[size=["\x27]?([0-9]+(?:px|pt)?|\+[1-7]|-[1-7])["\x27]?\]((?:(?!\[size)[\s\S])*?)\[/size\]', caseSensitive: false),
      (m) {
        final val = m[1]!;
        final numVal = int.tryParse(val);
        if (numVal != null && numVal >= 1 && numVal <= 7) {
          return '<font size="$numVal">${m[2]}</font>';
        }
        final cleanVal = val.startsWith('+') ? val.substring(1) : val;
        return '<span style="font-size:${cleanVal.endsWith('px') || cleanVal.endsWith('pt') ? cleanVal : '${cleanVal}px'}">${m[2]}</span>';
      },
    );
    if (s == prev) break;
  }

  // [font=字体名] / [font="微软雅黑"]...[/font] → <font face="...">...</font>（循环展开多层嵌套）
  for (var round = 0; round < 3; round++) {
    final prev = s;
    s = s.replaceAllMapped(
      RegExp(r'\[font=["\x27]?([^\]"\x27]+)["\x27]?\]((?:(?!\[font)[\s\S])*?)\[/font\]', caseSensitive: false),
      (m) => '<font face="${m[1]}">${m[2]}</font>',
    );
    if (s == prev) break;
  }

  // [backcolor=颜色] / [bg=颜色] / [bgcolor=颜色]...[/backcolor]（循环展开多层嵌套，黑幕自动识别）
  for (var round = 0; round < 3; round++) {
    final prev = s;
    s = s.replaceAllMapped(
      RegExp(r'\[(?:backcolor|bg|bgcolor)=["\x27]?([^\]"\x27]+)["\x27]?\]((?:(?!\[(?:backcolor|bg|bgcolor))[\s\S])*?)\[/(?:backcolor|bg|bgcolor)\]', caseSensitive: false),
      (m) {
        final color = (m[1] ?? '').trim();
        final clean = color.toLowerCase();
        final isBlack = clean == 'black' || clean == '#000' || clean == '#000000' || clean == 'rgb(0,0,0)';
        final classAttr = isBlack ? ' class="heimu"' : '';
        return '<span$classAttr style="background-color:$color">${m[2]}</span>';
      },
    );
    if (s == prev) break;
  }

  // [color=xxx] / [color="#ff0000"]...[/color]（循环展开多层嵌套）
  for (var round = 0; round < 3; round++) {
    final prev = s;
    s = s.replaceAllMapped(
      RegExp(r'\[color=["\x27]?([^\]"\x27]+)["\x27]?\]((?:(?!\[color)[\s\S])*?)\[/color\]', caseSensitive: false),
      (m) {
        final color = (m[1] ?? '').trim();
        return '<font color="$color">${m[2]}</font>';
      },
    );
    if (s == prev) break;
  }

  // [url=xxx]...[/url] 与 [url]...[/url]
  s = s.replaceAllMapped(
    RegExp(r'\[url=["\x27]?([^\]"\x27]+)["\x27]?\]([\s\S]*?)\[/url\]', caseSensitive: false),
    (m) => '<a href="${m[1]}">${m[2]}</a>',
  );
  s = s.replaceAllMapped(
    RegExp(r'\[url\]([\s\S]*?)\[/url\]', caseSensitive: false),
    (m) => '<a href="${m[1]}">${m[1]}</a>',
  );

  // [email=xxx]...[/email] 与 [email]...[/email]
  s = s.replaceAllMapped(
    RegExp(r'\[email=["\x27]?([^\]"\x27]+)["\x27]?\]([\s\S]*?)\[/email\]', caseSensitive: false),
    (m) => '<a href="mailto:${m[1]?.trim()}">${m[2]}</a>',
  );
  s = s.replaceAllMapped(
    RegExp(r'\[email\]([\s\S]*?)\[/email\]', caseSensitive: false),
    (m) => '<a href="mailto:${m[1]?.trim()}">${m[1]?.trim()}</a>',
  );

  // [img]...[/img] 与 [img=w,h]...[/img]
  s = s.replaceAllMapped(
    RegExp(r'\[img(?:=([0-9]+)\s*,\s*([0-9]+))?\]([\s\S]*?)\[/img\]', caseSensitive: false),
    (m) {
      final w = m[1];
      final h = m[2];
      final src = (m[3] ?? '').trim();
      final sizeAttrs = (w != null && h != null) ? ' width="$w" height="$h"' : '';
      return '<img src="$src"$sizeAttrs />';
    },
  );

  // [quote]...[/quote] 与 [quote=author,...]...[/quote]（支持最多 4 层嵌套引用解析）
  for (var round = 0; round < 4; round++) {
    final prev = s;
    s = s.replaceAllMapped(
      RegExp(r'\[quote(?:=([^\]]*))?\]((?:(?!\[quote)[\s\S])*?)\[/quote\]', caseSensitive: false),
      (m) {
        final authorParam = m[1]?.replaceAll(RegExp(r'''['"]'''), '').trim() ?? '';
        final inner = m[2] ?? '';
        if (authorParam.isNotEmpty) {
          final author = authorParam.split(',').first.trim();
          return '<div class="quote"><blockquote><font size="2"><font color="#999999">$author 发表于：</font></font><br />$inner</blockquote></div>';
        }
        return '<div class="quote"><blockquote>$inner</blockquote></div>';
      },
    );
    if (s == prev) break;
  }

  // [spoiler=标题]...[/spoiler]（带标题折叠）与 [spoiler]...[/spoiler]（行内防剧透黑幕）
  s = s.replaceAllMapped(
    RegExp(r'\[spoiler(?:=([^\]]*))?\]([\s\S]*?)\[/spoiler\]', caseSensitive: false),
    (m) {
      final title = m[1]?.trim();
      if (title != null && title.isNotEmpty) {
        return '<details class="spoiler"><summary>$title</summary>${m[2]}</details>';
      }
      return '<span class="heimu" style="background-color:black;color:black;">${m[2]}</span>';
    },
  );

  // [collapse] / [fold]（折叠块）
  s = s.replaceAllMapped(
    RegExp(r'\[(?:collapse|fold)(?:=([^\]]*))?\]([\s\S]*?)\[/(?:collapse|fold)\]', caseSensitive: false),
    (m) => '<details class="spoiler"><summary>${m[1]?.trim().isNotEmpty == true ? m[1]!.trim() : '折叠内容（点击展开）'}</summary>${m[2]}</details>',
  );

  // [hide]...[/hide] 或 [hide=N]...[/hide]（回帖/积分可见）
  s = s.replaceAllMapped(
    RegExp(r'\[(?:hide|reply)(?:=([^\]]*))?\]([\s\S]*?)\[/(?:hide|reply)\]', caseSensitive: false),
    (m) =>
        '<div class="locked_hide" style="padding:10px;margin:8px 0;background-color:#fff3cd;border:1px dashed #ffeeba;border-radius:6px;color:#856404;">🔒 <b>隐藏内容</b>（需回复或达到${m[1] != null && m[1]!.isNotEmpty ? '${m[1]}积分' : ''}可见）</div>',
  );

  // [price=N]...[/price]（Discuz 3.4 售价主题/付费可见）
  s = s.replaceAllMapped(
    RegExp(r'\[price=([^\]]+)\]([\s\S]*?)\[/price\]', caseSensitive: false),
    (m) =>
        '<div class="locked_hide discuz_price" style="padding:10px;margin:8px 0;background-color:#fff3cd;border:1px dashed #ffeeba;border-radius:6px;color:#856404;">💰 <b>付费主题内容</b>（售价 ${m[1]} 积分/金粒，购买后可见）<br />${m[2]}</div>',
  );

  // [pay]...[/pay]（Discuz 付费内容）
  s = s.replaceAllMapped(
    RegExp(r'\[pay\]([\s\S]*?)\[/pay\]', caseSensitive: false),
    (m) =>
        '<div class="discuz_pay" style="padding:8px 12px;margin:8px 0;background-color:#e8f4fd;border:1px solid #b8daff;border-radius:6px;color:#004085;">💎 <b>付费专属内容：</b>${m[1]}</div>',
  );

  // [video=w,h]...[/video] 与 [video]...[/video] / [mp4]...[/mp4]（原生视频与 B 站智能识别）
  s = s.replaceAllMapped(
    RegExp(r'\[(?:video|mp4)(?:=[^\]]*)?\]([\s\S]*?)\[/(?:video|mp4)\]', caseSensitive: false),
    (m) {
      final text = m[1]?.trim() ?? '';
      final bvMatch = RegExp(r'(BV[a-zA-Z0-9]{10})', caseSensitive: false).firstMatch(text);
      if (bvMatch != null) {
        final bvid = bvMatch.group(1)!;
        return '<iframe src="https://player.bilibili.com/player.html?bvid=$bvid" data-bvid="$bvid"></iframe>';
      }
      final avMatch = RegExp(r'(?:av|aid=?)(\d+)', caseSensitive: false).firstMatch(text);
      if (avMatch != null) {
        final aid = avMatch.group(1)!;
        return '<iframe src="https://player.bilibili.com/player.html?aid=$aid" data-aid="$aid"></iframe>';
      }
      return '<video src="$text" controls></video>';
    },
  );

  // [qq]...[/qq]（Discuz QQ 联系）
  s = s.replaceAllMapped(
    RegExp(r'\[qq\](\d+)\[/qq\]', caseSensitive: false),
    (m) => '<a href="https://wpa.qq.com/msgrd?v=3&uin=${m[1]}&site=qq&menu=yes" class="discuz_qq">🐧 QQ联系：${m[1]}</a>',
  );

  // [index]...[/index]（Discuz 3.4 楼层目录索引）
  s = s.replaceAllMapped(
    RegExp(r'\[index\]([\s\S]*?)\[/index\]', caseSensitive: false),
    (m) => '<div class="discuz_index" style="padding:8px 12px;margin:6px 0;border-left:3px solid #4CAF50;background:#f9f9f9;border-radius:4px;">📑 <b>楼层目录索引：</b><br />${m[1]}</div>',
  );

  // [password=密码]...[/password]
  s = s.replaceAllMapped(
    RegExp(r'\[password(?:=([^\]]*))?\]([\s\S]*?)\[/password\]', caseSensitive: false),
    (m) =>
        '<div class="password_block" style="padding:10px;margin:8px 0;background-color:#e2e3e5;border:1px dashed #d6d8db;border-radius:6px;color:#383d41;">🔑 <b>加密内容</b>（需输入密码查看）</div>',
  );

  // [audio]...[/audio] 与 [audio=1]...[/audio]
  s = s.replaceAllMapped(
    RegExp(r'\[audio(?:=[^\]]*)?\]([\s\S]*?)\[/audio\]', caseSensitive: false),
    (m) => '<audio src="${m[1]?.trim()}" controls></audio>',
  );

  // [music]id[/music] → 网易云音乐
  s = s.replaceAllMapped(
    RegExp(r'\[music\]([\s\S]*?)\[/music\]', caseSensitive: false),
    (m) =>
        '<div class="discuz_music" data-music-id="${m[1]?.trim()}"><a class="discuz_music_link" href="https://music.163.com/#/song?id=${m[1]?.trim()}">🎵 网易云音乐: ${m[1]?.trim()}</a></div>',
  );

  // [media=x,w,h]...[/media] 与 [flash=w,h]...[/flash] / [swf]...[/swf]
  s = s.replaceAllMapped(
    RegExp(r'\[(?:media|flash|swf)(?:=[^\]]*)?\]([\s\S]*?)\[/(?:media|flash|swf)\]', caseSensitive: false),
    (m) {
      final url = m[1]?.trim() ?? '';
      return '<iframe class="discuz_media" src="$url"></iframe>';
    },
  );

  // [bilibili]...[/bilibili] 或 [bili]...[/bili]（自动智能提取 BV / AV / AID）
  s = s.replaceAllMapped(
    RegExp(r'\[(?:bilibili|bili)(?:=[^\]]*)?\]([\s\S]*?)\[/(?:bilibili|bili)\]', caseSensitive: false),
    (m) {
      final text = m[1]?.trim() ?? '';
      final bvMatch = RegExp(r'(BV[a-zA-Z0-9]{10})', caseSensitive: false).firstMatch(text);
      if (bvMatch != null) {
        final bvid = bvMatch.group(1)!;
        return '<iframe src="https://player.bilibili.com/player.html?bvid=$bvid" data-bvid="$bvid"></iframe>';
      }
      final avMatch = RegExp(r'(?:av|aid=?)(\d+)', caseSensitive: false).firstMatch(text);
      if (avMatch != null) {
        final aid = avMatch.group(1)!;
        return '<iframe src="https://player.bilibili.com/player.html?aid=$aid" data-aid="$aid"></iframe>';
      }
      return '<iframe src="https://player.bilibili.com/player.html?bvid=$text" data-bvid="$text"></iframe>';
    },
  );

  // [pan=网盘名]链接 密码[/pan] / [netdisk] / [down=名称] / [download]
  s = s.replaceAllMapped(
    RegExp(r'\[(?:pan|netdisk)(?:=([^\]]*))?\]([\s\S]*?)\[/(?:pan|netdisk)\]', caseSensitive: false),
    (m) {
      final panName = m[1]?.trim().isNotEmpty == true ? m[1]!.trim() : '网盘下载';
      final content = m[2]?.trim() ?? '';
      return '<div class="comiis_pan" style="padding:10px;margin:8px 0;background-color:#f0f9eb;border:1px solid #e1f3d8;border-radius:6px;"><b>💾 $panName:</b> $content</div>';
    },
  );
  s = s.replaceAllMapped(
    RegExp(r'\[(?:down|download)(?:=([^\]]*))?\]([\s\S]*?)\[/(?:down|download)\]', caseSensitive: false),
    (m) {
      final downName = m[1]?.trim().isNotEmpty == true ? m[1]!.trim() : '资源下载';
      final content = m[2]?.trim() ?? '';
      return '<div class="comiis_pan" style="padding:10px;margin:8px 0;background-color:#ecf5ff;border:1px solid #d9ecff;border-radius:6px;"><b>⬇️ $downName:</b> $content</div>';
    },
  );

  // [free]...[/free]（免费内容）
  s = s.replaceAllMapped(RegExp(r'\[free\]([\s\S]*?)\[/free\]', caseSensitive: false), (m) => m[1]!);

  // [attachimg]aid[/attachimg] / [attach]aid[/attach]（智能转换为官方附件与图片真实下载节点）
  s = s.replaceAllMapped(
    RegExp(r'\[attachimg\](\d+)\[/attachimg\]', caseSensitive: false),
    (m) => '<img src="${AppConfig.baseUrl}forum.php?mod=attachment&aid=${m[1]}&noupdate=yes" alt="附件图片 ${m[1]}" />',
  );
  s = s.replaceAllMapped(
    RegExp(r'\[attach\](\d+)\[/attach\]', caseSensitive: false),
    (m) => '<a href="${AppConfig.baseUrl}forum.php?mod=attachment&aid=${m[1]}" class="discuz_attach">📎 附件下载 (AID: ${m[1]})</a>',
  );

  // 5. 表格标签（依据官方 Discuz 规范优先解析外层与内层 table，支持多层嵌套展开与管道符快捷语法）
  for (var round = 0; round < 4; round++) {
    final prev = s;
    s = s.replaceAllMapped(
      RegExp(r'\[table(?:=([^\]]*))?\]((?:(?!\[table)[\s\S])*?)\[/table\]', caseSensitive: false),
      (m) {
        final opts = m[1]?.split(',') ?? [];
        String width = '100%';
        String bgcolor = '';
        if (opts.length > 1) {
          width = opts[0].trim().isNotEmpty ? opts[0].trim() : '100%';
          bgcolor = opts[1].trim();
        } else if (opts.length == 1 && opts[0].trim().isNotEmpty) {
          final opt = opts[0].trim();
          if (opt.endsWith('%') || opt.endsWith('px') || int.tryParse(opt) != null) {
            width = opt;
          } else {
            bgcolor = opt;
          }
        }
        final bgAttr = bgcolor.isNotEmpty ? ' bgcolor="$bgcolor"' : '';
        final bgStyle = bgcolor.isNotEmpty ? 'background-color:$bgcolor;' : '';
        var inner = m[2] ?? '';

        // 官方 Discuz parsetable() 管道符语法检测：
        // 若没有 [/tr] 和 [/td] 且含有 |，则按行切分，每行 | 切分为单元格
        if (!inner.toLowerCase().contains('[/tr]') &&
            !inner.toLowerCase().contains('[/td]') &&
            !inner.toLowerCase().contains('<tr>') &&
            inner.contains('|')) {
          final lines = inner.split(RegExp(r'\r?\n'));
          final buffer = StringBuffer();
          for (final line in lines) {
            final trimmedLine = line.trim();
            if (trimmedLine.isEmpty) continue;
            // 保护 \| 转义管道符
            final escaped = trimmedLine
                .replaceAll(r'\|', '__DISCUZ_ESCAPED_PIPE__')
                .split('|');
            buffer.write('<tr>');
            for (final cell in escaped) {
              final cellContent = cell.replaceAll('__DISCUZ_ESCAPED_PIPE__', '|');
              buffer.write('<td>$cellContent</td>');
            }
            buffer.write('</tr>');
          }
          inner = buffer.toString();
        }

        return '<table width="$width"$bgAttr border="1" cellspacing="0" cellpadding="4" class="t_table" style="border-collapse:collapse;$bgStyle">$inner</table>';
      },
    );
    if (s == prev) break;
  }

  // 表格内部 [tr] [th] [td]
  s = s.replaceAllMapped(
    RegExp(r'\[tr(?:=([^\]]*))?\]', caseSensitive: false),
    (m) {
      final bg = m[1] != null && m[1]!.trim().isNotEmpty ? ' style="background-color:${m[1]!.trim()}"' : '';
      return '<tr$bg>';
    },
  );
  s = s.replaceAll(RegExp(r'\[/tr\]', caseSensitive: false), '</tr>');

  s = s.replaceAllMapped(
    RegExp(r'\[th(?:=([^\]]*))?\]', caseSensitive: false),
    (m) {
      if (m[1] == null || m[1]!.trim().isEmpty) return '<th>';
      final parts = m[1]!.split(',');
      final colspan = parts.isNotEmpty && parts[0].trim().isNotEmpty ? ' colspan="${parts[0].trim()}"' : '';
      final rowspan = parts.length > 1 && parts[1].trim().isNotEmpty ? ' rowspan="${parts[1].trim()}"' : '';
      final width = parts.length > 2 && parts[2].trim().isNotEmpty ? ' width="${parts[2].trim()}"' : '';
      return '<th$colspan$rowspan$width>';
    },
  );
  s = s.replaceAll(RegExp(r'\[/th\]', caseSensitive: false), '</th>');

  s = s.replaceAllMapped(
    RegExp(r'\[td(?:=([^\]]*))?\]', caseSensitive: false),
    (m) {
      if (m[1] == null || m[1]!.trim().isEmpty) return '<td>';
      final parts = m[1]!.split(',');
      if (parts.length == 1) {
        final val = parts[0].trim();
        if (val.endsWith('%') || val.endsWith('px') || (int.tryParse(val) != null && int.parse(val) > 10)) {
          return '<td width="$val">';
        }
        return '<td colspan="$val">';
      }
      final colspan = parts.isNotEmpty && parts[0].trim().isNotEmpty ? ' colspan="${parts[0].trim()}"' : '';
      final rowspan = parts.length > 1 && parts[1].trim().isNotEmpty ? ' rowspan="${parts[1].trim()}"' : '';
      final width = parts.length > 2 && parts[2].trim().isNotEmpty ? ' width="${parts[2].trim()}"' : '';
      return '<td$colspan$rowspan$width>';
    },
  );
  s = s.replaceAll(RegExp(r'\[/td\]', caseSensitive: false), '</td>');
  s = s.replaceAll(RegExp(r'\[hr(?:\s*/)?(?:=[^\]]*)?\]', caseSensitive: false), '<hr class="solidline">');

  // 6. 对齐与浮动标签（循环展开多层嵌套 align）
  for (var round = 0; round < 4; round++) {
    final prev = s;
    s = s.replaceAllMapped(
      RegExp(r'\[align=(left|center|right|justify)\]([\s\S]*?)\[/align\]', caseSensitive: false),
      (m) => '<div style="text-align:${m[1]}">${m[2]}</div>',
    );
    if (s == prev) break;
  }

  s = s.replaceAllMapped(
    RegExp(r'\[float=(left|right)\]([\s\S]*?)\[/float\]', caseSensitive: false),
    (m) => '<div style="float:${m[1]};margin:4px 8px;">${m[2]}</div>',
  );

  // [postbg]背景图[/postbg] 清理
  s = s.replaceAll(RegExp(r'\[postbg\][\s\S]*?\[/postbg\]', caseSensitive: false), '');

  // 7. 列表标签 [list=1] / [list=a] / [list=A] / [list=i] / [list=I] / [list] / [*]
  // 依据 Discuz 规范，支持嵌套列表解析，循环由内向外依次展开
  for (var round = 0; round < 4; round++) {
    final prev = s;
    // 匹配最内层的有序列表 [list=...]...[/list]
    s = s.replaceAllMapped(
      RegExp(r'\[list=([^\]]+)\]((?:(?!\[list)[\s\S])*?)\[/list\]', caseSensitive: false),
      (m) {
        final type = m[1]!.trim();
        var inner = m[2] ?? '';
        inner = inner.replaceAllMapped(
          RegExp(r'\[\*\]([\s\S]*?)(?:\[/\*\]|(?=\[\*\]|$))', caseSensitive: false),
          (item) => '<li>${item[1]?.trim() ?? ''}</li>',
        );
        return '<ol type="$type">$inner</ol>';
      },
    );
    // 匹配最内层的无序列表 [list]...[/list]
    s = s.replaceAllMapped(
      RegExp(r'\[list\]((?:(?!\[list)[\s\S])*?)\[/list\]', caseSensitive: false),
      (m) {
        var inner = m[1] ?? '';
        inner = inner.replaceAllMapped(
          RegExp(r'\[\*\]([\s\S]*?)(?:\[/\*\]|(?=\[\*\]|$))', caseSensitive: false),
          (item) => '<li>${item[1]?.trim() ?? ''}</li>',
        );
        return '<ul>$inner</ul>';
      },
    );
    if (s == prev) break;
  }


  // 7. 换行与块标签格式化
  s = s.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  s = s.replaceAll('\n', '<br>');

  // 清理列表/表格/段落块内的冗余换行，避免产生多余空白行
  s = s.replaceAllMapped(RegExp(r'(<ul[^>]*>)\s*<br>'), (m) => m[1]!);
  s = s.replaceAllMapped(RegExp(r'(<ol[^>]*>)\s*<br>'), (m) => m[1]!);
  s = s.replaceAll('<br></li>', '</li>');
  s = s.replaceAll('</li><br>', '</li>');
  s = s.replaceAll('</tr><br><tr>', '</tr><tr>');
  s = s.replaceAll('</tr><br>', '</tr>');
  s = s.replaceAll('<br></tr>', '</tr>');
  s = s.replaceAll('</td><br><td>', '</td><td>');
  s = s.replaceAll('</th><br><th>', '</th><th>');
  s = s.replaceAll('<br></td>', '</td>');
  s = s.replaceAll('<br></th>', '</th>');
  s = s.replaceAll('<br></table>', '</table>');
  s = s.replaceAllMapped(RegExp(r'(<table[^>]*>)<br>'), (m) => m[1]!);
  s = s.replaceAllMapped(RegExp(r'(<tr[^>]*>)<br>'), (m) => m[1]!);

  // 8. 还原受保护的代码块
  for (var i = 0; i < codeBlocks.length; i++) {
    s = s.replaceAll('__DISCUZ_CODE_BLOCK_${i}__', codeBlocks[i]);
  }

  return s;
}
