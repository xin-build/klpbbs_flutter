# KLPBBS Flutter 客户端

基于 Flutter 3 与 Material Design 3 构建的 **苦力怕论坛 (klpbbs.com)** 现代化全平台客户端。

---

## ✨ 特性亮点

- 🎨 **Material You 现代设计**：遵循 Material 3 设计规范，支持动态取色（Monet）、深色/浅色模式自适应与微质感苦力怕矢量图标。
- 📱 **全平台支持**：原生适配 **Android**、**iOS**、**Windows**、**macOS** 与 **Linux**。
- 📖 **原汁原味的浏览体验**：
  - 支持首页、导读（热门/最新）、全部版块分类、帖子详情与多页翻页。
  - 深度解析 Discuz! 富文本与 BBCode（表格、折叠块、代码高亮、投票、附件下载等）。
  - 内嵌音视频组件（哔哩哔哩视频、网易云音乐播放器）。
- 👤 **完整社区互动**：
  - 支持论坛登录、发帖（含投票/图片）、楼层回复、点评、评分与点赞。
  - 个人空间、私信消息、系统通知、任务中心、勋章与头像挂件展示。
- ⚡ **高性能与离线优化**：优化的 HTML 结构解析引擎与多级图片/数据缓存机制。

---

## 🛠️ 构建与运行

### 准备环境
- Flutter SDK `>= 3.24.0`
- Dart SDK `>= 3.5.0`

### 快速启动

```bash
# 1. 克隆仓库
git clone https://github.com/xin-build/klpbbs_flutter.git
cd klpbbs_flutter

# 2. 安装依赖
flutter pub get

# 3. 运行项目（以当前连接的设备或桌面运行）
flutter run
```

---

## 📦 各平台安装包下载

请前往 [GitHub Releases](https://github.com/xin-build/klpbbs_flutter/releases) 下载对应平台的最新安装包：

| 平台 | 安装包格式 |
| :--- | :--- |
| **Android** | `.apk` / `.aab` |
| **Windows** | `.zip` (免安装绿色版) |
| **macOS** | `.zip` (`.app` 压缩包) |
| **Linux** | `.tar.gz` (x64 二进制) |
| **iOS** | `.ipa` (未签名包，可自签安装) |

---

## 📄 开源许可

本项目遵循 MIT 开源协议。
