/// 积分明细记录模型（Discuz spacecp credit log）
class CreditLogEntry {
  final String creditType; // 积分类型，如：铁粒、金粒、人气
  final String amount; // 变动数值，如：+11, -5, -1, +9
  final String operation; // 操作动作，如：每日签到、购买勋章、帖子评分、发布小喇叭
  final String detail; // 详细描述/扣除原因
  final String timeText; // 时间戳，如：2026-08-23 18:28

  const CreditLogEntry({
    required this.creditType,
    required this.amount,
    required this.operation,
    required this.detail,
    required this.timeText,
  });

  /// 是否为增加积分
  bool get isPositive => amount.startsWith('+') || (!amount.startsWith('-') && (int.tryParse(amount) ?? 0) > 0);

  /// 纯数值（不含正负号）
  int get numericValue {
    final cleaned = amount.replaceAll('+', '').replaceAll('-', '').trim();
    return int.tryParse(cleaned) ?? 0;
  }
}

class CreditBaseInfo {
  final String totalCredits;
  final Map<String, String> details;
  final String? ruleFormula;

  const CreditBaseInfo({
    required this.totalCredits,
    required this.details,
    this.ruleFormula,
  });

  /// 快捷获取当前铁粒数额
  int get iron => int.tryParse(details['铁粒'] ?? details['铁粒:'] ?? '') ?? 0;
}
