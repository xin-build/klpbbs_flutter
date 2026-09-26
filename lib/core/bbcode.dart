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

String bbcodeToHtml(String input, {List<SmileyCategory>? customSmileys}) {
  if (input.isEmpty) return '';
  var s = input;

  // 1. 转义 HTML 特殊字符（BBCode 用 []，不受影响）
  s = s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;');

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

  // [size=1..7] 或 [size=12px]...[/size]
  s = s.replaceAllMapped(
    RegExp(r'\[size=([0-9]+(?:px|pt)?)\]([\s\S]*?)\[/size\]', caseSensitive: false),
    (m) {
      final val = m[1]!;
      final numVal = int.tryParse(val);
      if (numVal != null && numVal <= 7) {
        return '<font size="$numVal">${m[2]}</font>';
      }
      return '<span style="font-size:${val.endsWith('px') || val.endsWith('pt') ? val : '${val}px'}">${m[2]}</span>';
    },
  );

  // [font=字体名]...[/font] → <font face="...">...</font>
  s = s.replaceAllMapped(
    RegExp(r'\[font=([^\]]+)\]([\s\S]*?)\[/font\]', caseSensitive: false),
    (m) => '<font face="${m[1]}">${m[2]}</font>',
  );

  // [backcolor=颜色] / [bg=颜色] / [bgcolor=颜色]...[/backcolor] → <span style="background-color:...">...</span>
  s = s.replaceAllMapped(
    RegExp(r'\[(?:backcolor|bg|bgcolor)=([^\]]+)\]([\s\S]*?)\[/(?:backcolor|bg|bgcolor)\]', caseSensitive: false),
    (m) {
      final color = (m[1] ?? '').replaceAll(RegExp(r'''["']'''), '').trim();
      return '<span style="background-color:$color">${m[2]}</span>';
    },
  );

  // [color=xxx]...[/color]
  s = s.replaceAllMapped(
    RegExp(r'\[color=([^\]]+)\]([\s\S]*?)\[/color\]', caseSensitive: false),
    (m) {
      final color = (m[1] ?? '').replaceAll(RegExp(r'''["']'''), '').trim();
      return '<font color="$color">${m[2]}</font>';
    },
  );

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
    RegExp(r'\[img(?:=[^\]]*)?\]([\s\S]*?)\[/img\]', caseSensitive: false),
    (m) => '<img src="${(m[1] ?? '').trim()}" />',
  );

  // [code=lang]...[/code] 与 [code]...[/code]
  s = s.replaceAllMapped(
    RegExp(r'\[code(?:=([^\]]*))?\]([\s\S]*?)\[/code\]', caseSensitive: false),
    (m) => '<pre><code class="language-${m[1] ?? ''}">${m[2]}</code></pre>',
  );

  // [quote]...[/quote] 与 [quote=author,...]...[/quote]
  s = s.replaceAllMapped(
    RegExp(r'\[quote(?:=([^\]]*))?\]([\s\S]*?)\[/quote\]', caseSensitive: false),
    (m) {
      final authorParam = m[1]?.trim() ?? '';
      final inner = m[2] ?? '';
      if (authorParam.isNotEmpty) {
        final author = authorParam.split(',').first.trim();
        return '<div class="quote"><blockquote><font size="2"><font color="#999999">$author 发表于：</font></font><br />$inner</blockquote></div>';
      }
      return '<div class="quote"><blockquote>$inner</blockquote></div>';
    },
  );

  // [spoiler=标题]...[/spoiler] / [collapse] / [fold]
  s = s.replaceAllMapped(
    RegExp(r'\[(?:spoiler|collapse|fold)(?:=([^\]]*))?\]([\s\S]*?)\[/(?:spoiler|collapse|fold)\]', caseSensitive: false),
    (m) => '<details class="spoiler"><summary>${m[1]?.trim().isNotEmpty == true ? m[1]!.trim() : '折叠内容（点击展开）'}</summary>${m[2]}</details>',
  );

  // [hide]...[/hide] 或 [hide=N]...[/hide]（回帖/积分可见）
  s = s.replaceAllMapped(
    RegExp(r'\[(?:hide|reply)(?:=([^\]]*))?\]([\s\S]*?)\[/(?:hide|reply)\]', caseSensitive: false),
    (m) =>
        '<div class="locked_hide" style="padding:10px;margin:8px 0;background-color:#fff3cd;border:1px dashed #ffeeba;border-radius:6px;color:#856404;">🔒 <b>隐藏内容</b>（需回复或达到${m[1] != null && m[1]!.isNotEmpty ? '${m[1]}积分' : ''}可见）</div>',
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
    (m) => '<a class="discuz_media" href="${m[1]?.trim()}">🎬 查看视频/多媒体：${m[1]?.trim()}</a>',
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

  // [attachimg]aid[/attachimg] / [attach]aid[/attach]
  s = s.replaceAllMapped(
    RegExp(r'\[attachimg\](\d+)\[/attachimg\]', caseSensitive: false),
    (m) => '<span>[附件图片 aid=${m[1]}]</span>',
  );
  s = s.replaceAllMapped(
    RegExp(r'\[attach\](\d+)\[/attach\]', caseSensitive: false),
    (m) => '<span>[附件 aid=${m[1]}]</span>',
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
  s = s.replaceAll(RegExp(r'\[hr\]', caseSensitive: false), '<hr>');

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

  return s;
}
