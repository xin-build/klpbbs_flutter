/// Discuz BBCode → HTML 轻量转换器（编辑器「预览」与离线解析用）
/// 覆盖常用代码：b/i/u/s/color/size/font/backcolor/align/url/img/quote/code/hide/spoiler/collapse/fold/free/password/list/table/attach/audio/media/bili。
/// 表情短码（如 [贴吧_呵呵]）不在本地展开，预览时按原文显示。
library;

String bbcodeToHtml(String input) {
  var s = input;
  // 1. 先转义 HTML 特殊字符（BBCode 用 []，不受影响）
  s = s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;');

  // 2. 成对标签（非贪婪跨行）
  void replacePair(String open, String close, String tag) {
    final re = RegExp(
      RegExp.escape(open) + r'([\s\S]*?)' + RegExp.escape(close),
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

  // [size=1..7]...[/size] → <font size="N">...</font>
  s = s.replaceAllMapped(
    RegExp(r'\[size=([1-7])\]([\s\S]*?)\[/size\]'),
    (m) => '<font size="${m[1]}">${m[2]}</font>',
  );

  // [font=字体名]...[/font] → <font face="...">...</font>
  s = s.replaceAllMapped(
    RegExp(r'\[font=([^\]]+)\]([\s\S]*?)\[/font\]'),
    (m) => '<font face="${m[1]}">${m[2]}</font>',
  );

  // [backcolor=颜色]...[/backcolor] → <span style="background-color:...">...</span>
  s = s.replaceAllMapped(
    RegExp(r'\[backcolor=([^\]]+)\]([\s\S]*?)\[/backcolor\]'),
    (m) => '<span style="background-color:${m[1]}">${m[2]}</span>',
  );

  // [color=xxx]...[/color]
  s = s.replaceAllMapped(
    RegExp(r'\[color=([^\]]+)\]([\s\S]*?)\[/color\]'),
    (m) => '<font color="${m[1]}">${m[2]}</font>',
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

  // [img]...[/img] 与 [img=w,h]...[/img]
  s = s.replaceAllMapped(
    RegExp(r'\[img(?:=[^\]]*)?\]([\s\S]*?)\[/img\]'),
    (m) => '<img src="${m[1]}" />',
  );

  // [code=lang]...[/code] 与 [code]...[/code]
  s = s.replaceAllMapped(
    RegExp(r'\[code(?:=([^\]]*))?\]([\s\S]*?)\[/code\]'),
    (m) => '<pre><code class="language-${m[1] ?? ''}">${m[2]}</code></pre>',
  );

  // [quote]...[/quote]
  s = s.replaceAllMapped(
    RegExp(r'\[quote\]([\s\S]*?)\[/quote\]'),
    (m) => '<blockquote>${m[1]}</blockquote>',
  );

  // [spoiler=标题]...[/spoiler] 与 [spoiler]...[/spoiler]
  s = s.replaceAllMapped(
    RegExp(r'\[spoiler(?:=([^\]]*))?\]([\s\S]*?)\[/spoiler\]'),
    (m) => '<details class="spoiler"><summary>${m[1]?.trim().isNotEmpty == true ? m[1]!.trim() : '折叠内容（点击展开）'}</summary>${m[2]}</details>',
  );

  // [collapse=标题]...[/collapse] 与 [collapse]...[/collapse]
  s = s.replaceAllMapped(
    RegExp(r'\[collapse(?:=([^\]]*))?\]([\s\S]*?)\[/collapse\]'),
    (m) => '<details class="spoiler"><summary>${m[1]?.trim().isNotEmpty == true ? m[1]!.trim() : '折叠内容（点击展开）'}</summary>${m[2]}</details>',
  );

  // [fold=标题]...[/fold] 与 [fold]...[/fold]
  s = s.replaceAllMapped(
    RegExp(r'\[fold(?:=([^\]]*))?\]([\s\S]*?)\[/fold\]'),
    (m) => '<details class="spoiler"><summary>${m[1]?.trim().isNotEmpty == true ? m[1]!.trim() : '折叠内容（点击展开）'}</summary>${m[2]}</details>',
  );

  // [hide]...[/hide] 或 [hide=N]...[/hide]（回帖/积分可见）
  s = s.replaceAllMapped(
    RegExp(r'\[hide(?:=([^\]]*))?\]([\s\S]*?)\[/hide\]'),
    (m) =>
        '<div class="locked_hide" style="padding:10px;margin:8px 0;background-color:#fff3cd;border:1px dashed #ffeeba;border-radius:6px;color:#856404;">🔒 <b>隐藏内容</b>（需回复或达到${m[1] != null && m[1]!.isNotEmpty ? '${m[1]}积分' : ''}可见）</div>',
  );

  // [password=密码]...[/password]
  s = s.replaceAllMapped(
    RegExp(r'\[password(?:=([^\]]*))?\]([\s\S]*?)\[/password\]'),
    (m) =>
        '<div class="password_block" style="padding:10px;margin:8px 0;background-color:#e2e3e5;border:1px dashed #d6d8db;border-radius:6px;color:#383d41;">🔑 <b>加密内容</b>（需输入密码查看）</div>',
  );

  // [audio]...[/audio]
  s = s.replaceAllMapped(
    RegExp(r'\[audio\]([\s\S]*?)\[/audio\]'),
    (m) => '<audio src="${m[1]}" controls></audio>',
  );

  // [media=x,w,h]...[/media]
  s = s.replaceAllMapped(
    RegExp(r'\[media(?:=[^\]]*)?\]([\s\S]*?)\[/media\]'),
    (m) => '<a href="${m[1]}">🎬 点击播放多媒体视频：${m[1]}</a>',
  );

  // [bilibili]...[/bilibili] 或 [bili]...[/bili]
  s = s.replaceAllMapped(
    RegExp(r'\[(?:bilibili|bili)\]([\s\S]*?)\[/(?:bilibili|bili)\]'),
    (m) => '<iframe src="https://player.bilibili.com/player.html?bvid=${m[1]?.trim() ?? ''}"></iframe>',
  );

  // [free]...[/free]（免费内容）
  s = s.replaceAllMapped(RegExp(r'\[free\]([\s\S]*?)\[/free\]'), (m) => m[1]!);

  // [attachimg]aid[/attachimg] / [attach]aid[/attach]
  s = s.replaceAllMapped(
    RegExp(r'\[attachimg\](\d+)\[/attachimg\]'),
    (m) => '<span>[附件图片 aid=${m[1]}]</span>',
  );
  s = s.replaceAllMapped(
    RegExp(r'\[attach\](\d+)\[/attach\]'),
    (m) => '<span>[附件 aid=${m[1]}]</span>',
  );

  // [align=left|center|right]...[/align] → <div style="text-align:...">...</div>
  s = s.replaceAllMapped(
    RegExp(r'\[align=(left|center|right)\]([\s\S]*?)\[/align\]'),
    (m) => '<div style="text-align:${m[1]}">${m[2]}</div>',
  );

  // [float=left|right]...[/float]
  s = s.replaceAllMapped(
    RegExp(r'\[float=(left|right)\]([\s\S]*?)\[/float\]'),
    (m) => '<div style="float:${m[1]};margin:4px 8px;">${m[2]}</div>',
  );

  // [list] / [*] → <ul><li>
  s = s.replaceAllMapped(
    RegExp(r'\[\*\]([\s\S]*?)(?=\[\*\]|\[/list\])'),
    (m) => '<li>${m[1]}</li>',
  );
  s = s.replaceAllMapped(
    RegExp(r'\[list(?:=[^\]]*)?\]([\s\S]*?)\[/list\]'),
    (m) => '<ul>${m[1]}</ul>',
  );

  // [table] / [tr] / [th] / [td]
  s = s.replaceAllMapped(
    RegExp(r'\[table(?:=([^\]]*))?\]([\s\S]*?)\[/table\]'),
    (m) {
      final opts = m[1]?.split(',') ?? [];
      final width = opts.isNotEmpty && opts[0].trim().isNotEmpty ? opts[0].trim() : '100%';
      final bg = opts.length > 1 && opts[1].trim().isNotEmpty ? 'background-color:${opts[1].trim()};' : '';
      return '<table class="t_table" width="$width" border="1" cellspacing="0" cellpadding="4" style="border-collapse:collapse;$bg">${m[2]}</table>';
    },
  );

  s = s.replaceAllMapped(
    RegExp(r'\[tr(?:=([^\]]*))?\]'),
    (m) {
      final bg = m[1] != null && m[1]!.trim().isNotEmpty ? ' style="background-color:${m[1]!.trim()}"' : '';
      return '<tr$bg>';
    },
  );
  s = s.replaceAll('[/tr]', '</tr>');

  s = s.replaceAllMapped(
    RegExp(r'\[th(?:=([^\]]*))?\]'),
    (m) {
      if (m[1] == null || m[1]!.trim().isEmpty) return '<th>';
      final parts = m[1]!.split(',');
      final colspan = parts.isNotEmpty && parts[0].trim().isNotEmpty ? ' colspan="${parts[0].trim()}"' : '';
      final rowspan = parts.length > 1 && parts[1].trim().isNotEmpty ? ' rowspan="${parts[1].trim()}"' : '';
      final width = parts.length > 2 && parts[2].trim().isNotEmpty ? ' width="${parts[2].trim()}"' : '';
      return '<th$colspan$rowspan$width>';
    },
  );
  s = s.replaceAll('[/th]', '</th>');

  s = s.replaceAllMapped(
    RegExp(r'\[td(?:=([^\]]*))?\]'),
    (m) {
      if (m[1] == null || m[1]!.trim().isEmpty) return '<td>';
      final parts = m[1]!.split(',');
      final colspan = parts.isNotEmpty && parts[0].trim().isNotEmpty ? ' colspan="${parts[0].trim()}"' : '';
      final rowspan = parts.length > 1 && parts[1].trim().isNotEmpty ? ' rowspan="${parts[1].trim()}"' : '';
      final width = parts.length > 2 && parts[2].trim().isNotEmpty ? ' width="${parts[2].trim()}"' : '';
      return '<td$colspan$rowspan$width>';
    },
  );
  s = s.replaceAll('[/td]', '</td>');
  s = s.replaceAll('[hr]', '<hr>');

  // 3. 换行 → <br>
  s = s.replaceAll('\n', '<br>');

  // 4. 清理列表/表格块内换行，避免预览出现空行
  s = s.replaceAll('<ul><br>', '<ul>');
  s = s.replaceAll('<ol><br>', '<ol>');
  s = s.replaceAll('<br></li>', '</li>');
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
