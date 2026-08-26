# 苦力怕论坛客户端（KLPBBS App）全平台编译与发布指南

> **适用版本**：v1.0.4+  
> **文档目标**：标准化多平台（Android、Windows、macOS、iOS、Linux）编译规范、签名规则、CI/CD 自动化发布流程与常见错误避坑手册，供后续开发与自动化构建长期参考。

---

## 目录
1. [基准开发与构建环境要求](#1-基准开发与构建环境要求)
2. [Android 签名密钥规范（重要）](#2-android-签名密钥规范重要)
3. [核心代码跨平台兼容避坑规范](#3-核心代码跨平台兼容避坑规范)
4. [五大平台产物打包与命名标准](#4-五大平台产物打包与命名标准)
5. [GitHub Actions CI/CD 自动化配置](#5-github-actions-cicd-自动化配置)
6. [常用本地编译与校验指令速查](#6-常用本地编译与校验指令速查)
7. [标准发布流程清单（Checklist）](#7-标准发布流程清单checklist)

---

## 1. 基准开发与构建环境要求

为确保本地环境与 GitHub Actions 云端 Runner 完全一致，请严格锁定以下工具链版本：

| 组件 / 平台 | 推荐版本 / 配置 | 关键说明 |
| :--- | :--- | :--- |
| **Flutter SDK** | `3.32.5` (`stable` 分支) | Dart SDK `>=3.8.0 <4.0.0` |
| **Java JDK** | `JDK 17` (Eclipse Temurin / OpenJDK 17) | Gradle 8.x 及以上要求必须为 JDK 17 |
| **Android NDK** | `27.0.12077973` (NDK 27) | **必须显式指定**，`flutter_inappwebview_android` / `media_kit` 强依赖 |
| **Android Compile/Target SDK** | `35` (或 `flutter.compileSdkVersion`) | `minSdk = 21`, `multiDexEnabled = true` |
| **Windows 编译工具** | Visual Studio 2022 (C++ Desktop Workload) | MSVC v143, CMake 3.20+, Ninja |
| **macOS / iOS 编译工具** | Xcode 15+ / CocoaPods 1.14+ | macOS 14 (Sonoma) 运行环境 |
| **Linux 编译依赖** | Ubuntu 22.04 LTS | `clang cmake ninja-build pkg-config libgtk-3-dev liblzma-dev libmpv-dev mpv libnotify-dev libayatana-appindicator3-dev libsecret-1-dev libjsoncpp-dev` |

---

## 2. Android 签名密钥规范（重要）

为保证发布的 APK 能够被旧版本客户端无缝覆盖安装升级，**严禁修改或重新生成签名密钥**。

### 2.1 密钥参数详情
- **Keystore 相对路径**：`android/app/klpbbs_release.jks`
- **Key Alias**：`klpbbs`
- **Key / Store Password**：`klpbbs123456`
- **证书所有者 (Owner/Issuer)**：`CN=klpbbs, OU=klpbbs, O=klpbbs, L=Beijing, ST=Beijing, C=CN`
- **证书 SHA-256 指纹**：
  ```text
  58:03:CF:17:23:DB:96:F6:D4:C5:FE:E9:98:85:DB:C8:D3:B2:1C:97:15:64:5B:04:B2:69:07:82:F1:BE:32:97:B
  ```

### 2.2 Gradle 签名配置模板 (`android/app/build.gradle.kts`)
```kotlin
android {
    namespace = "com.klpbbs.klpbbs_app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = "27.0.12077973" // 必须显式指定 NDK 27

    defaultConfig {
        applicationId = "com.klpbbs.klpbbs_app"
        minSdk = 21
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        multiDexEnabled = true
    }

    signingConfigs {
        create("release") {
            keyAlias = "klpbbs"
            keyPassword = "klpbbs123456"
            storeFile = file("klpbbs_release.jks")
            storePassword = "klpbbs123456"
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
            isMinifyEnabled = false
            isShrinkResources = false
        }
    }
}
```

---

## 3. 核心代码跨平台兼容避坑规范

在跨平台编译和 CI 验证过程中，总结了以下关键避坑要点：

### 3.1 Flutter API 语法兼容性
1. **`DropdownButtonFormField` 必须使用 `value:`**：
   - ❌ 错误：`DropdownButtonFormField(initialValue: _val, ...)`（在部分 Flutter 3.x 版本会报 `No named parameter with the name 'initialValue'`）。
   - ✅ 正确：`DropdownButtonFormField(value: _val, ...)`。
2. **`ListView` 滚动缓存必须使用 `cacheExtent:`**：
   - ❌ 错误：`ListView(scrollCacheExtent: ScrollCacheExtent.pixels(800), ...)`（实验性 API 在部分 SDK 上编译报错）。
   - ✅ 正确：`ListView(cacheExtent: 800.0, ...)`。
3. **按钮状态样式统一使用 `WidgetStatePropertyAll`**：
   - ❌ 避免：`WidgetStateProperty.all(...)`（在某些 Flutter 渠道会触发 NoSuchMethodError）。
   - ✅ 正确：`WidgetStatePropertyAll(value)` 或 `ButtonStyle(...)` 原生便捷封装。

### 3.2 静态分析与过滤配置 (`analysis_options.yaml`)
为了防止 CI 阶段因为弃用 API 警告或外部参考目录报错，需配置如下忽略规则：
```yaml
analyzer:
  errors:
    deprecated_member_use: ignore
    deprecated_member_use_from_same_package: ignore
  exclude:
    - build/**
    - android/**
    - ios/**
    - windows/**
    - macos/**
    - linux/**
    - reference_piliplus/**
    - klpbbs_app/**
    - local-env/**
    - mock-server/**
    - tools/**
```

### 3.3 Windows 桌面端 CMake 参数规范 (`windows/CMakeLists.txt`)
- **禁止添加 `/Zm2000`**：该参数在 GitHub Actions CI 虚拟机会导致 MSVC 申请虚拟内存超出上限报错崩溃。
- **保留安全标志**：`/bigobj /WX-`。

---

## 4. 五大平台产物打包与命名标准

每次发布构建必须严格生成并归档以下 5 种产物：

| 目标平台 | 源码编译产物路径 | 发布压缩包标准命名 | 打包方式 |
| :--- | :--- | :--- | :--- |
| **Android** | `build/app/outputs/flutter-apk/app-release.apk` | `klpbbs-android-release.apk` | 直接拷贝重命名 |
| **Windows** | `build/windows/x64/runner/Release/*` | `klpbbs-windows-x64.zip` | ZIP 压缩 Release 目录内全部文件 |
| **macOS** | `build/macos/Build/Products/Release/*.app` | `klpbbs-macos.zip` | ZIP 压缩 `.app` 应用程序包 |
| **iOS** | `build/ios/iphoneos/*.app` | `klpbbs-ios-unsigned.ipa` | 将 `.app` 放入 `Payload/` 目录后 zip 压缩成 `.ipa` |
| **Linux** | `build/linux/x64/release/bundle` | `klpbbs-linux-x64.tar.gz` | TAR.GZ 归档 bundle 目录 |

---

## 5. GitHub Actions CI/CD 自动化配置

完整的自动化工作流配置文件位于 [`.github/workflows/build_release.yml`](file:///f:/klpbbs/.github/workflows/build_release.yml)。

### 5.1 工作流核心机制
- **触发条件**：推送 Tag 形如 `v*`（如 `v1.0.4`）或手动点击 `workflow_dispatch`。
- **并行构建矩阵**：
  - `build-android` (Ubuntu Latest + Java 17 + Flutter 3.32.5)
  - `build-windows` (Windows 2022 + Flutter 3.32.5)
  - `build-macos` (macOS 14 + Flutter 3.32.5)
  - `build-ios` (macOS 14 + Flutter 3.32.5 + `--no-codesign`)
  - `build-linux` (Ubuntu 22.04 + Linux Desktop 依赖 + Flutter 3.32.5)
- **统一汇总发布** (`release` Job)：
  - 等待所有 5 个平台的 Job 完成；
  - 下载全部 Artifacts 并扁平化放置于 `./all-releases/`；
  - 使用 `softprops/action-gh-release@v2` 自动发布至 GitHub Releases；
  - 集成 `Mattraks/delete-workflow-runs@v2` 自动清理历史构建失败的废弃记录。

---

## 6. 常用本地编译与校验指令速查

### 6.1 代码分析与静态检查
```bash
# 检查整个项目的静态分析情况（应提示 No issues found!）
flutter analyze
```

### 6.2 各平台本地 Release 构建
```bash
# 1. Android APK 签名构建
flutter build apk --release

# 2. Windows 桌面版构建
flutter build windows --release

# 3. macOS 桌面版构建 (需在 macOS 环境)
flutter build macos --release

# 4. iOS 免签名 IPA 构建 (需在 macOS 环境)
flutter build ios --release --no-codesign

# 5. Linux 桌面版构建 (需在 Linux 环境)
flutter build linux --release
```

### 6.3 Android 签名指纹校验
```bash
# 校验 APK 签名有效性与证书指纹
apksigner verify --print-certs build/app/outputs/flutter-apk/app-release.apk
```

---

## 7. 标准发布流程清单（Checklist）

每次发布新版本时，严格执行以下标准流程：

1. **版本号递增**：
   在 [`pubspec.yaml`](file:///f:/klpbbs/pubspec.yaml) 中更新版本号（例如 `version: 1.0.5+6`）。
2. **本地静态分析检查**：
   运行 `flutter analyze`，确保 **0 error, 0 warning**。
3. **提交与推送代码**：
   ```bash
   git commit -am "chore: release v1.0.5"
   ```
4. **打 Tag 并强制同步推送**：
   ```bash
   git tag -fa v1.0.5 -m "Release v1.0.5"
   git push origin master -f
   git push origin master:main -f
   git push origin v1.0.5 -f
   ```
5. **监控 GitHub Actions**：
   观察 Actions 页面中 Android、Windows、macOS、iOS、Linux 5 个 Job 是否全部绿标通过。
6. **验证 GitHub Release**：
   访问 `https://github.com/xin-build/klpbbs_flutter/releases/tag/v1.0.5` 确认 5 个平台的安装包全部就绪。
