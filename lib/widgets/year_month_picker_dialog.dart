import 'package:flutter/material.dart';
import '../services/auto_sign_service.dart';

/// 签到日历快速年月选择器弹窗
/// 支持年份步进/切换与 12 个月网格直选，自带「回到当月」快捷操作，杜绝点选未来无效月份
class YearMonthPickerDialog extends StatefulWidget {
  final int initialYear;
  final int initialMonth;
  final int minYear;
  final int maxYear;
  final int maxMonth;

  const YearMonthPickerDialog({
    super.key,
    required this.initialYear,
    required this.initialMonth,
    required this.minYear,
    required this.maxYear,
    required this.maxMonth,
  });

  /// 便捷拉起弹窗静态方法
  static Future<(int year, int month)?> show(
    BuildContext context, {
    required int initialYear,
    required int initialMonth,
    int? minYear,
    int? maxYear,
    int? maxMonth,
  }) {
    final serverNow = AutoSignService.instance.estimatedServerNow;
    final effMaxYear = maxYear ?? serverNow.year;
    final effMaxMonth = maxMonth ?? serverNow.month;
    final effMinYear = minYear ?? (effMaxYear - 3).clamp(2020, effMaxYear);

    return showDialog<(int year, int month)>(
      context: context,
      barrierDismissible: true,
      builder: (dialogCtx) => YearMonthPickerDialog(
        initialYear: initialYear,
        initialMonth: initialMonth,
        minYear: effMinYear,
        maxYear: effMaxYear,
        maxMonth: effMaxMonth,
      ),
    );
  }

  @override
  State<YearMonthPickerDialog> createState() => _YearMonthPickerDialogState();
}

class _YearMonthPickerDialogState extends State<YearMonthPickerDialog> {
  late int _selectedYear;
  late int _selectedMonth;

  @override
  void initState() {
    super.initState();
    _selectedYear = widget.initialYear;
    _selectedMonth = widget.initialMonth;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final serverNow = AutoSignService.instance.estimatedServerNow;

    final canPrevYear = _selectedYear > widget.minYear;
    final canNextYear = _selectedYear < widget.maxYear;

    return Dialog(
      backgroundColor: colorScheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 1. 顶部标题栏
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: colorScheme.primary.withAlpha(25),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(Icons.edit_calendar_rounded, size: 20, color: colorScheme.primary),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '快速选择月份',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                        Text(
                          '当前选中：$_selectedYear 年 $_selectedMonth 月',
                          style: TextStyle(fontSize: 12, color: colorScheme.outline),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, size: 20),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // 2. 年份切换条 (带快速年份胶囊)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest.withAlpha(80),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.chevron_left_rounded),
                      onPressed: canPrevYear
                          ? () {
                              setState(() {
                                _selectedYear--;
                                if (_selectedYear == widget.maxYear && _selectedMonth > widget.maxMonth) {
                                  _selectedMonth = widget.maxMonth;
                                }
                              });
                            }
                          : null,
                      tooltip: '上一年',
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '$_selectedYear 年',
                          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                        ),
                        if (_selectedYear == serverNow.year) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                            decoration: BoxDecoration(
                              color: colorScheme.primary.withAlpha(25),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              '今年',
                              style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: colorScheme.primary),
                            ),
                          ),
                        ],
                      ],
                    ),
                    IconButton(
                      icon: const Icon(Icons.chevron_right_rounded),
                      onPressed: canNextYear
                          ? () {
                              setState(() {
                                _selectedYear++;
                                if (_selectedYear == widget.maxYear && _selectedMonth > widget.maxMonth) {
                                  _selectedMonth = widget.maxMonth;
                                }
                              });
                            }
                          : null,
                      tooltip: '下一年',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),

              // 3. 12 个月份直选网格 (4 列 x 3 行)
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: 12,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 4,
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                  childAspectRatio: 1.6,
                ),
                itemBuilder: (context, idx) {
                  final month = idx + 1;
                  final isFuture = (_selectedYear == widget.maxYear && month > widget.maxMonth);
                  final isSelected = (_selectedMonth == month);
                  final isCurrentMonth = (_selectedYear == serverNow.year && month == serverNow.month);

                  return InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: isFuture
                        ? null
                        : () {
                            setState(() => _selectedMonth = month);
                          },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: isSelected
                            ? colorScheme.primary
                            : (isFuture ? colorScheme.surfaceContainerHighest.withAlpha(30) : colorScheme.surfaceContainerHigh),
                        borderRadius: BorderRadius.circular(8),
                        border: isCurrentMonth && !isSelected
                            ? Border.all(color: colorScheme.primary, width: 1.2)
                            : (isSelected ? null : Border.all(color: colorScheme.outlineVariant.withAlpha(50), width: 0.8)),
                      ),
                      child: Text(
                        '$month 月',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: isSelected || isCurrentMonth ? FontWeight.bold : FontWeight.w500,
                          color: isSelected
                              ? colorScheme.onPrimary
                              : (isFuture ? colorScheme.outline.withAlpha(90) : colorScheme.onSurface),
                        ),
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 18),

              // 4. 底部动作栏 (回到当月 / 取消 / 确认)
              Row(
                children: [
                  OutlinedButton.icon(
                    icon: const Icon(Icons.today_rounded, size: 14),
                    label: const Text('本月', style: TextStyle(fontSize: 12)),
                    style: OutlinedButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                      minimumSize: const Size(0, 34),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    onPressed: () {
                      setState(() {
                        _selectedYear = serverNow.year;
                        _selectedMonth = serverNow.month;
                      });
                    },
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('取消'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
                      minimumSize: const Size(0, 36),
                    ),
                    onPressed: () {
                      Navigator.of(context).pop((_selectedYear, _selectedMonth));
                    },
                    child: const Text('确认跳转'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
