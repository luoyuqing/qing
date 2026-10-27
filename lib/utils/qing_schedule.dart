// SPDX-FileCopyrightText: 2026 清助理
// SPDX-License-Identifier: AGPL-3.0-or-later

/// 清助理 · 执行计划（cron）解析与生成
///
/// 只做两件事：
///  1. 把 cron 转成人话 —— 简报页标题、任务卡片、编辑器预览都用它；
///  2. 把「每天 / 每周 / 每小时」这种傻瓜选项拼回 cron —— 任务编辑器用。
///
/// 支持范围刻意保守：认不出的一律原样显示，绝不猜。
/// hub 那边除标准 cron 外还可能给 `every 30m` / `once at 2026-11-14 09:00`
/// 这类本来就是人话的表达式，直接透传。
class QingSchedule {
  const QingSchedule._();

  static const weekdayNames = <int, String>{
    1: '周一',
    2: '周二',
    3: '周三',
    4: '周四',
    5: '周五',
    6: '周六',
    7: '周日',
  };

  static List<String>? _fields(String expr) {
    final parts = expr.trim().split(RegExp(r'\s+'));
    if (parts.length != 5) return null;
    return parts;
  }

  static int? _int(String v) {
    if (v.isEmpty) return null;
    return int.tryParse(v);
  }

  /// 解析「每天 HH:mm」：`分 时 * * *` → (hour, minute)；其它形式返回 null。
  static ({int hour, int minute})? dailyTime(String expr) {
    final f = _fields(expr);
    if (f == null) return null;
    final minute = _int(f[0]);
    final hour = _int(f[1]);
    if (minute == null || hour == null) return null;
    if (f[2] != '*' || f[3] != '*' || f[4] != '*') return null;
    if (hour < 0 || hour > 23 || minute < 0 || minute > 59) return null;
    return (hour: hour, minute: minute);
  }

  static String two(int n) => n.toString().padLeft(2, '0');

  static String timeText(int hour, int minute) =>
      '${two(hour)}:${two(minute)}';

  /// cron → 人话。认不出的原样返回（不猜）。
  static String describe(String expr) {
    final raw = expr.trim();
    if (raw.isEmpty) return '未设置';
    final f = _fields(raw);
    if (f == null) return raw;

    final minute = _int(f[0]);
    if (minute == null) return raw;

    // 每小时：分 * * * *
    // 注意要在解析 hour 之前判断：这里 hour 字段是 '*'，提前取 int 会失败退出。
    if (f[1] == '*' && f[2] == '*' && f[3] == '*' && f[4] == '*') {
      return '每小时第 $minute 分';
    }

    final hour = _int(f[1]);
    if (hour == null) return raw;

    // 每周：分 时 * * 1,3,5
    if (f[2] == '*' && f[3] == '*' && f[4] != '*') {
      final days = <String>[];
      for (final part in f[4].split(',')) {
        final d = _int(part);
        final name = weekdayNames[d];
        if (name == null) return raw;
        days.add(name);
      }
      if (days.isEmpty) return raw;
      return '每${days.join('、')} ${timeText(hour, minute)}';
    }

    // 每天：分 时 * * *
    final daily = dailyTime(raw);
    if (daily != null) return '每天 ${timeText(daily.hour, daily.minute)}';

    return raw;
  }

  /// 每天某个时刻
  static String daily(int hour, int minute) => '$minute $hour * * *';

  /// 每周某几天（days 取 1..7，1=周一）
  static String weekly(Set<int> days, int hour, int minute) {
    final sorted = days.where((d) => d >= 1 && d <= 7).toList()..sort();
    if (sorted.isEmpty) return daily(hour, minute);
    return '$minute $hour * * ${sorted.join(',')}';
  }

  /// 每小时第 min 分
  static String hourly(int minute) => '$minute * * * *';
}
