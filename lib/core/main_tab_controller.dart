import 'package:flutter/foundation.dart';

/// 全局主 Tab 切换器：让 pushed 页面也能切回首页的某个底部导航页。
final ValueNotifier<int> mainTabIndex = ValueNotifier<int>(0);
