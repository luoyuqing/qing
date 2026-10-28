import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../utils/url_launcher.dart';

/// 自研轻量 Markdown 渲染器（不引三方依赖，覆盖日常 AI 输出会用到的语法）。
///
/// 块级：`#`~`######` 标题、``` 代码块 ```、`>` 引用、
///       `-`/`*`/`+` 无序列表（支持缩进嵌套与 `[ ]`/`[x]` 复选框）、
///       `1.` 有序列表、`---` 分隔线、`| 表格 |`、普通段落。
/// 行内：`**粗体**`、`*斜体*`、`__粗体__`、`_斜体_`、`` `行内代码` ``、
///       `~~删除线~~`、`[文字](链接)`、`![图](链接)`、裸 http(s) 链接、
///       `\` 转义。
///
/// 用法：`MarkdownView(data: text)` —— 晨报/晚报、会话详情、收藏等
/// 所有展示模型输出的地方都用它，避免星号、井号原样露出来。
class MarkdownView extends StatelessWidget {
  const MarkdownView({
    super.key,
    required this.data,
    this.baseStyle,
    this.selectable = true,
    this.onTapLink,
    this.padding = EdgeInsets.zero,
    this.maxLines,
  });

  final String data;

  /// 正文字体；不给就用 `bodyMedium`，行高 1.55。
  final TextStyle? baseStyle;

  /// 是否可选中复制（气泡里建议 true，列表摘要里建议 false）。
  final bool selectable;

  /// 点链接的回调；不传就用 UrlLauncher 打开（带二次确认）。
  final void Function(String url)? onTapLink;

  final EdgeInsetsGeometry padding;

  /// 只渲染前 N 块的场景（如列表摘要），为 null 则全渲染。
  final int? maxLines;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final base = baseStyle ??
        (theme.textTheme.bodyMedium ?? const TextStyle(fontSize: 14))
            .copyWith(height: 1.55);
    var blocks = MdParser.parse(data);
    if (maxLines != null && blocks.length > maxLines!) {
      blocks = blocks.sublist(0, maxLines!);
    }
    if (blocks.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: padding,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final b in blocks)
            _buildBlock(context, theme, b, base, data.length > 4000),
        ],
      ),
    );
  }

  Widget _buildBlock(
    BuildContext context,
    ThemeData theme,
    _MdBlock b,
    TextStyle base,
    bool longText,
  ) {
    switch (b.type) {
      case 'h':
        return _heading(context, theme, b, base);
      case 'code':
        return _codeBlock(theme, b);
      case 'quote':
        return _quote(theme, b, base);
      case 'list':
        return _list(theme, b, base);
      case 'hr':
        return const Padding(
          padding: EdgeInsets.symmetric(vertical: 10),
          child: Divider(height: 1),
        );
      case 'table':
        return _table(context, theme, b, base);
      default:
        final text = b.lines.join('\n');
        if (text.trim().isEmpty) return const SizedBox(height: 6);
        final span = MdInline.span(
          text,
          base,
          linkStyle: _linkStyle(theme, base),
          onTapLink: onTapLink ?? _defaultOpen(context),
        );
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: selectable && !longText
              ? SelectableText.rich(span)
              : Text.rich(span),
        );
    }
  }

  void Function(String)? _defaultOpen(BuildContext context) =>
      (url) => UrlLauncher(context, url).launchUrl();

  TextStyle? _linkStyle(ThemeData theme, TextStyle base) =>
      base.copyWith(color: theme.colorScheme.primary);

  Widget _heading(
    BuildContext context,
    ThemeData theme,
    _MdBlock b,
    TextStyle base,
  ) {
    final sizes = {1: 21.0, 2: 18.5, 3: 16.5, 4: 15.0, 5: 14.0, 6: 13.5};
    final top = {1: 12.0, 2: 10.0, 3: 8.0, 4: 6.0, 5: 6.0, 6: 6.0};
    final size = sizes[b.level] ?? 15.0;
    return Padding(
      padding: EdgeInsets.only(top: top[b.level] ?? 8, bottom: 5),
      child: Text.rich(
        MdInline.span(
          b.lines.first,
          base.copyWith(
            fontSize: size,
            height: 1.32,
            fontWeight: FontWeight.w700,
            letterSpacing: b.level <= 2 ? -0.2 : 0,
          ),
          linkStyle: _linkStyle(theme, base),
          onTapLink: onTapLink ?? _defaultOpen(context),
        ),
      ),
    );
  }

  Widget _codeBlock(ThemeData theme, _MdBlock b) {
    final code = b.lines.join('\n');
    final lang = (b.lang ?? '').trim();
    final mono = const TextStyle(
      fontFamily: 'monospace',
      fontFamilyFallback: ['Menlo', 'Consolas', 'Courier New'],
      fontSize: 12.4,
      height: 1.5,
    );
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 7),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh.withAlpha(190),
        borderRadius: BorderRadius.circular(10),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(10, 5, 4, 5),
            color: theme.colorScheme.surfaceContainerHighest.withAlpha(150),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    lang.isEmpty ? '代码' : lang,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      letterSpacing: 0.4,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                _CopyButton(text: code),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SelectableText(code, style: mono),
            ),
          ),
        ],
      ),
    );
  }

  Widget _quote(ThemeData theme, _MdBlock b, TextStyle base) {
    final inner = b.lines.join('\n');
    final style = base.copyWith(
      fontSize: (base.fontSize ?? 14) - 1,
      color: theme.colorScheme.onSurfaceVariant,
    );
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.fromLTRB(12, 9, 12, 9),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh.withAlpha(120),
        borderRadius: BorderRadius.circular(10),
        border: Border(
          left: BorderSide(
            color: theme.colorScheme.primary.withAlpha(150),
            width: 3,
          ),
        ),
      ),
      child: Text.rich(
        MdInline.span(
          inner,
          style,
          linkStyle: _linkStyle(theme, style),
          onTapLink: onTapLink,
        ),
      ),
    );
  }

  Widget _list(ThemeData theme, _MdBlock b, TextStyle base) {
    final items = b.items ?? const <_MdItem>[];
    final bullets = ['•', '◦', '▪', '▫'];
    var orderIndex = 0;
    String? lastMarker;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final it in items)
          Padding(
            padding: EdgeInsets.only(
              left: 2.0 + it.indent * 14.0,
              top: 2.5,
              bottom: 2.5,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 22,
                  child: _marker(theme, it, bullets, () {
                    if (lastMarker != it.marker) {
                      orderIndex = int.tryParse(
                            it.marker.replaceAll(RegExp(r'[^0-9]'), ''),
                          ) ??
                          1;
                      lastMarker = it.marker;
                    } else {
                      orderIndex++;
                    }
                    return orderIndex;
                  }()),
                ),
                Expanded(
                  child: Text.rich(
                    MdInline.span(
                      it.text,
                      base,
                      linkStyle: _linkStyle(theme, base),
                      onTapLink: onTapLink,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _marker(ThemeData theme, _MdItem it, List<String> bullets, int order) {
    var text = it.text;
    var checked = false;
    var isBox = false;
    if (text.startsWith('[ ] ') || text.startsWith('[] ')) {
      isBox = true;
      text = text.substring(4);
    } else if (text.startsWith('[x] ') || text.startsWith('[X] ')) {
      isBox = true;
      checked = true;
      text = text.substring(4);
    }
    it.text = text;
    if (isBox) {
      return Padding(
        padding: const EdgeInsets.only(top: 1),
        child: Icon(
          checked
              ? Icons.check_circle_rounded
              : Icons.radio_button_unchecked_rounded,
          size: 14,
          color: checked
              ? theme.colorScheme.primary
              : theme.colorScheme.outline,
        ),
      );
    }
    if (it.ordered) {
      return Padding(
        padding: const EdgeInsets.only(right: 4),
        child: Text(
          '$order.',
          textAlign: TextAlign.right,
          style: TextStyle(
            fontSize: (theme.textTheme.bodyMedium?.fontSize ?? 14) - 0.5,
            color: theme.colorScheme.primary,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
    }
    return Text(
      bullets[it.indent.clamp(0, bullets.length - 1)],
      style: TextStyle(
        fontSize: (theme.textTheme.bodyMedium?.fontSize ?? 14) + 1,
        color: theme.colorScheme.primary,
      ),
    );
  }

  Widget _table(
    BuildContext context,
    ThemeData theme,
    _MdBlock b,
    TextStyle base,
  ) {
    final header = b.header ?? const <String>[];
    final rows = b.rows ?? const <List<String>>[];
    if (header.isEmpty) return const SizedBox.shrink();
    final cols = header.length;
    final borderColor = theme.colorScheme.outlineVariant.withAlpha(140);
    final cell = (String s, TextStyle st) => Padding(
          padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
          child: Text.rich(
            MdInline.span(
              s,
              st,
              linkStyle: _linkStyle(theme, st),
              onTapLink: onTapLink ?? _defaultOpen(context),
            ),
          ),
        );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Table(
          border: TableBorder.all(color: borderColor, width: 1),
          defaultColumnWidth: const IntrinsicColumnWidth(),
          children: [
            TableRow(
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHigh.withAlpha(170),
              ),
              children: [
                for (final c in header)
                  cell(c, base.copyWith(fontWeight: FontWeight.w700)),
              ],
            ),
            for (final r in rows)
              TableRow(
                children: [
                  for (var x = 0; x < cols; x++)
                    cell(x < r.length ? r[x] : '', base),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _CopyButton extends StatefulWidget {
  const _CopyButton({required this.text});
  final String text;

  @override
  State<_CopyButton> createState() => _CopyButtonState();
}

class _CopyButtonState extends State<_CopyButton> {
  var _done = false;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 32,
      height: 32,
      child: IconButton(
        padding: EdgeInsets.zero,
        iconSize: 15,
        visualDensity: VisualDensity.compact,
        icon: Icon(_done ? Icons.check_rounded : Icons.copy_all_rounded),
        color: _done
            ? Theme.of(context).colorScheme.primary
            : Theme.of(context).colorScheme.onSurfaceVariant,
        onPressed: () async {
          await Clipboard.setData(ClipboardData(text: widget.text));
          if (!mounted) return;
          setState(() => _done = true);
          Future.delayed(const Duration(seconds: 2), () {
            if (mounted) setState(() => _done = false);
          });
        },
      ),
    );
  }
}

/// 行内语法解析：`**粗体**` `*斜体*` `` `代码` `` `~~删除线~~`
/// `[文字](链接)` `![图](链接)` 裸链接、`\` 转义。
class MdInline {
  // 注意：这里的正则**不能带 `^`**。
  // Dart 的 `RegExp.matchAsPrefix(src, i)` 已经保证「只从 i 开始匹配前缀」，
  // 而 `^` 在 matchAsPrefix 里并不被当成「i 这个位置的开头」——实测连 i=0 都返回
  // null（Dart VM 上 `^` 与 matchAsPrefix 组合直接失效）。带 `^` 会导致行内语法
  // 一个都匹配不上，星号原样露出来。
  static final _code = RegExp(r'`([^`]+)`');
  static final _image = RegExp(r'!\[([^\]]*)\]\(([^)\s]*)\)');
  static final _link = RegExp(r'\[([^\]]*)\]\(([^)\s]*)\)');
  static final _url = RegExp(r'https?://[^\s<>()\[\]{}]+');
  static final _strike = RegExp(r'~~([\s\S]+?)~~');
  static final _boldStar = RegExp(r'\*\*([\s\S]+?)\*\*');
  static final _boldUnder = RegExp(r'__([\s\S]+?)__');
  static final _italicStar = RegExp(r'\*([^*\n]+?)\*');
  static final _italicUnder = RegExp(r'_([^_\n]+?)_');
  static const _escapable = {
    '\\', '`', '*', '_', '~', '#', '>', '|', '[', ']', '(', ')', '+', '-',
    '.', '!',
  };

  static bool _isWord(int c) =>
      (c >= 65 && c <= 90) || (c >= 97 && c <= 122) || (c >= 48 && c <= 57);

  static TextSpan span(
    String src,
    TextStyle base, {
    TextStyle? codeStyle,
    TextStyle? linkStyle,
    void Function(String url)? onTapLink,
  }) {
    if (src.isEmpty) return TextSpan(text: '', style: base);
    final children = <InlineSpan>[];
    final buf = StringBuffer();
    var i = 0;

    void flush() {
      if (buf.isNotEmpty) {
        children.add(TextSpan(text: buf.toString()));
        buf.clear();
      }
    }

    InlineSpan child(String inner, TextStyle st) => TextSpan(
          style: st,
          children: [
            span(
              inner,
              st,
              codeStyle: codeStyle,
              linkStyle: linkStyle,
              onTapLink: onTapLink,
            ),
          ],
        );

    while (i < src.length) {
      final ch = src[i];

      // 转义
      if (ch == '\\' && i + 1 < src.length && _escapable.contains(src[i + 1])) {
        buf.write(src[i + 1]);
        i += 2;
        continue;
      }

      // 行内代码（优先级最高，里面的符号不当语法处理）
      if (ch == '`') {
        final m = _code.matchAsPrefix(src, i);
        if (m != null) {
          flush();
          children.add(
            TextSpan(
              text: m.group(1),
              style: codeStyle ??
                  base.copyWith(
                    fontFamily: 'monospace',
                    fontFamilyFallback: const ['Menlo', 'Consolas'],
                    fontSize: (base.fontSize ?? 14) - 1,
                    color: base.color,
                  ),
            ),
          );
          i = m.end;
          continue;
        }
      }

      // 图片 → 退化成可点链接
      if (ch == '!' && i + 1 < src.length && src[i + 1] == '[') {
        final m = _image.matchAsPrefix(src, i);
        if (m != null) {
          flush();
          final alt = (m.group(1) ?? '').trim();
          children.add(
            _linkSpan(alt.isEmpty ? '图片' : alt, m.group(2) ?? '', base,
                linkStyle, onTapLink),
          );
          i = m.end;
          continue;
        }
      }

      if (ch == '[') {
        final m = _link.matchAsPrefix(src, i);
        if (m != null) {
          flush();
          final label = (m.group(1) ?? '').trim();
          children.add(
            _linkSpan(
              label.isEmpty ? (m.group(2) ?? '') : label,
              m.group(2) ?? '',
              base,
              linkStyle,
              onTapLink,
            ),
          );
          i = m.end;
          continue;
        }
      }

      if (ch == '~' && i + 1 < src.length && src[i + 1] == '~') {
        final m = _strike.matchAsPrefix(src, i);
        if (m != null) {
          flush();
          final st = base.copyWith(decoration: TextDecoration.lineThrough);
          children.add(child(m.group(1)!, st));
          i = m.end;
          continue;
        }
      }

      if (ch == '*' || ch == '_') {
        final dbl = i + 1 < src.length && src[i + 1] == ch;
        if (dbl) {
          final m = (ch == '*' ? _boldStar : _boldUnder).matchAsPrefix(src, i);
          if (m != null) {
            flush();
            children.add(
              child(m.group(1)!, base.copyWith(fontWeight: FontWeight.w700)),
            );
            i = m.end;
            continue;
          }
        } else {
          // 下划线形式的斜体要求左边不是单词字符，避免把 foo_bar 拆开
          if (ch == '*' || i == 0 || !_isWord(src.codeUnitAt(i - 1))) {
            final m =
                (ch == '*' ? _italicStar : _italicUnder).matchAsPrefix(src, i);
            if (m != null) {
              final after = m.end < src.length ? src.codeUnitAt(m.end) : 0;
              if (ch == '*' || !_isWord(after)) {
                flush();
                children.add(
                  child(m.group(1)!, base.copyWith(fontStyle: FontStyle.italic)),
                );
                i = m.end;
                continue;
              }
            }
          }
        }
      }

      if (ch == 'h' &&
          (src.startsWith('http://', i) || src.startsWith('https://', i))) {
        final m = _url.matchAsPrefix(src, i);
        if (m != null) {
          flush();
          final url = m.group(0)!;
          children.add(_linkSpan(url, url, base, linkStyle, onTapLink));
          i = m.end;
          continue;
        }
      }

      buf.write(ch);
      i += 1;
    }
    flush();
    if (children.isEmpty) return TextSpan(text: '', style: base);
    return TextSpan(style: base, children: children);
  }

  static InlineSpan _linkSpan(
    String text,
    String url,
    TextStyle base,
    TextStyle? linkStyle,
    void Function(String url)? onTap,
  ) {
    final st = linkStyle ?? base.copyWith(decoration: TextDecoration.underline);
    if (onTap == null || url.isEmpty) return TextSpan(text: text, style: st);
    return TextSpan(
      text: text,
      style: st,
      recognizer: TapGestureRecognizer()..onTap = () => onTap(url),
    );
  }

  /// 把 Markdown 压成纯文本，用于列表摘要、通知、搜索命中这类单行展示。
  ///
  /// 注意：Dart 的 `replaceAll` **不支持 `$1` 反向引用**（那是 JS 的习惯），
  /// 只有 `replaceAllMapped` 能取分组，写 `r'$1'` 会原样吐出 "$1"。
  static String strip(String src) {
    if (src.isEmpty) return '';
    String grp(RegExp re, int group, String s) =>
        s.replaceAllMapped(re, (m) => m.group(group) ?? '');
    var out = src
        .replaceAll(RegExp(r'```[\s\S]*?```'), '［代码］')
        .replaceAll(RegExp(r'^\s{0,3}#{1,6}\s+', multiLine: true), '')
        .replaceAll(RegExp(r'^\s{0,3}>\s?', multiLine: true), '')
        .replaceAll(RegExp(r'^\s{0,3}([-*+]|\d+[.)])\s+', multiLine: true), '')
        .replaceAll(RegExp(r'!\[[^\]]*\]\([^)]*\)'), '');
    out = grp(RegExp(r'\[([^\]]*)\]\([^)]*\)'), 1, out);
    out = grp(RegExp(r'(\*\*|__)(.*?)\1'), 2, out);
    out = grp(RegExp(r'~~(.*?)~~'), 1, out);
    out = out.replaceAll('`', '');
    out = grp(RegExp(r'\*([^*\n]+)\*'), 1, out);
    return out.replaceAll(RegExp(r'\n{2,}'), '\n').trim();
  }
}

/// 块级解析。
class MdParser {
  static final _fence = RegExp(r'^```|^~~~');
  static final _heading = RegExp(r'^(#{1,6})\s+(.*)$');
  static final _hr = RegExp(r'^(-{3,}|\*{3,}|_{3,})$');
  static final _item = RegExp(r'^(\s*)([-*+]|\d+[.)])\s+(.*)$');
  static final _ordered = RegExp(r'^\d');

  static List<_MdBlock> parse(String src) {
    if (src.trim().isEmpty) return const [];
    final lines = src.replaceAll('\r\n', '\n').split('\n');
    final blocks = <_MdBlock>[];
    var i = 0;
    while (i < lines.length) {
      final line = lines[i];
      final t = line.trim();

      // 代码块
      final fm = _fence.firstMatch(t);
      if (fm != null) {
        final fence = fm.group(0)!;
        final lang = t.substring(fence.length).trim();
        final buf = <String>[];
        i++;
        while (i < lines.length && !lines[i].trim().startsWith(fence)) {
          buf.add(lines[i]);
          i++;
        }
        i++; // 吞掉收尾的 fence
        blocks.add(_MdBlock('code', lines: buf, lang: lang));
        continue;
      }

      if (t.isEmpty) {
        i++;
        continue;
      }

      if (_hr.hasMatch(t)) {
        blocks.add(_MdBlock('hr'));
        i++;
        continue;
      }

      final hm = _heading.firstMatch(t);
      if (hm != null) {
        blocks.add(
          _MdBlock('h', lines: [hm.group(2)!.trim()], level: hm.group(1)!.length),
        );
        i++;
        continue;
      }

      if (t.startsWith('>')) {
        final buf = <String>[];
        while (i < lines.length && lines[i].trim().startsWith('>')) {
          buf.add(lines[i].trim().replaceFirst(RegExp(r'^>\s?'), ''));
          i++;
        }
        blocks.add(_MdBlock('quote', lines: buf));
        continue;
      }

      // 表格：| a | b | 下面紧跟 |---|---|
      if (t.startsWith('|') &&
          i + 1 < lines.length &&
          _isTableSep(lines[i + 1].trim())) {
        final header = _row(t);
        i += 2;
        final rows = <List<String>>[];
        while (i < lines.length && lines[i].trim().startsWith('|')) {
          rows.add(_row(lines[i].trim()));
          i++;
        }
        blocks.add(_MdBlock('table', header: header, rows: rows));
        continue;
      }

      if (_item.firstMatch(line) != null) {
        final items = <_MdItem>[];
        while (i < lines.length) {
          final m = _item.firstMatch(lines[i]);
          if (m == null) {
            // 缩进的续行并入上一项
            if (items.isNotEmpty &&
                lines[i].trim().isNotEmpty &&
                lines[i].startsWith(RegExp(r'\s'))) {
              items.last.text = '${items.last.text}\n${lines[i].trim()}';
              i++;
              continue;
            }
            break;
          }
          final indent = m.group(1)!.length ~/ 2;
          items.add(
            _MdItem(
              indent,
              m.group(2)!,
              m.group(3)!,
              _ordered.hasMatch(m.group(2)!),
            ),
          );
          i++;
        }
        blocks.add(_MdBlock('list', items: items));
        continue;
      }

      // 段落：连续非空行
      final buf = <String>[];
      while (i < lines.length && lines[i].trim().isNotEmpty) {
        final cur = lines[i].trim();
        if (_heading.hasMatch(cur) ||
            cur.startsWith('>') ||
            _fence.hasMatch(cur) ||
            _item.firstMatch(lines[i]) != null) {
          break;
        }
        buf.add(cur);
        i++;
      }
      if (buf.isEmpty) {
        buf.add(t);
        i++;
      }
      blocks.add(_MdBlock('p', lines: buf));
    }
    return blocks;
  }

  static bool _isTableSep(String s) {
    if (!s.contains('-') || !s.contains('|')) return false;
    return s.replaceAll(RegExp(r'[|\-:\s]'), '').isEmpty;
  }

  static List<String> _row(String s) {
    var t = s.trim();
    if (t.startsWith('|')) t = t.substring(1);
    if (t.endsWith('|')) t = t.substring(0, t.length - 1);
    return t.split('|').map((e) => e.trim()).toList();
  }
}

class _MdBlock {
  _MdBlock(
    this.type, {
    this.lines = const <String>[],
    this.level = 0,
    this.lang,
    this.items,
    this.header,
    this.rows,
  });

  final String type;
  final List<String> lines;
  final int level;
  final String? lang;
  final List<_MdItem>? items;
  final List<String>? header;
  final List<List<String>>? rows;
}

class _MdItem {
  _MdItem(this.indent, this.marker, this.text, this.ordered);

  final int indent;
  final String marker;
  String text;
  final bool ordered;
}
