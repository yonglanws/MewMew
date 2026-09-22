<div align="center">

# MewMew

一个基于 Flutter 的 AI 角色扮演对话应用：人格管理、长期记忆、单聊群聊、兼容 OpenAI 格式的 API

[![Flutter][flutter-badge]][flutter-link] [![Dart][dart-badge]][dart-link] [![Android][android-badge]][android-link] [![GPL-3.0][license-badge]][license-link] 
[项目简介](#项目简介) · [主要功能](#主要功能) · [快速开始](#快速开始) · [项目结构](#项目结构) · [故障排除](#故障排除) · [致谢](#致谢)

</div>

> [!IMPORTANT]
> **项目初期开发中**，功能与数据格式都可能变动，欢迎关注但请谨慎用于生产数据。
> 当前开发分支为 [`dev`](https://github.com/yonglanws/MewMew/tree/dev)

## 项目简介

MewMew 是一个跑在 Android 手机上的 AI 角色对话应用。你可以创建任意多个人格（性格、语言风格、背景故事、开场白），和它们单聊，或者把多个角色拉进一个群聊里互相配合；对话基于任何兼容 OpenAI Chat Completions 格式的 API。此外还有一套会自动总结对话的长期记忆系统，让角色记得聊过的内容。

| 特性 | 说明 |
| --- | --- |
| 人格管理 | 性格特征 / 语言风格 / 背景故事 / 开场白，支持完整提示词模式 |
| 单聊 & 群聊 | 群聊多角色 @ 选人发言，消息防抖合并，打字气泡 |
| API 配置 | 多套 OpenAI 兼容配置自由切换，独立嵌入模型配置（可选） |
| 长期记忆 | 对话自动总结、检索召回、可视化图谱与管理页面 |
| 回复模式 | 流式 / 整段 / 分段发送（智能切分 + 线性延迟） |
| 表情包 | 表情包分组管理、人格偏好绑定、AI 按情绪主动发送 |
| Token 统计 | 按天记录 token 用量，仪表盘可视化 |

## 主要功能

- **人格与角色**：可视化编辑人格设定，每个角色独立头像/表情包偏好；群聊中按 @ 决定发言者，多个角色共享完整群聊上下文。
- **对话体验**：流式打字机、智能分段发送（均分切分 + 线性延迟模拟真人）、私聊消息合并防抖、工具调用（时间/计算器/自定义 HTTP 工具）。
- **长期记忆**：对话自动总结、检索召回，提供记忆列表、可视化图谱与仪表盘。
- **表情包**：表情包分组管理、人格偏好绑定、AI 按情绪主动发送。

## 快速开始

> 要求 Flutter SDK ≥ 3.8.1。应用主要面向 Android 手机使用；仓库虽含 iOS/桌面/Web 目录，但未做适配验证。

```bash
# 1. 克隆（开发分支）
git clone -b dev https://github.com/yonglanws/MewMew.git mewmew
cd mewmew

# 2. 安装依赖
flutter pub get

# 3. 运行（连接设备后）
flutter run

# 4. 构建release APK
flutter build apk --release
# 产物：build/app/outputs/flutter-apk/app-release.apk
```

首次启动后进入「设置」：

1. **API 配置**：填入任意 OpenAI 兼容接口（Base URL + Key + 模型）；
2. **人格设定**：创建你的第一个角色，开始对话；

运行测试：

```bash
flutter test
```
## 故障排除

**记忆系统需要配置嵌入 API 吗？**
不需要，属于可选增强；不配置也能自动总结与检索记忆。

**数据存在哪里？**
全部本地存储，卸载应用即清空。「记忆系统」设置页支持导出/导入记忆 JSON（系统文件选择器），可作为备份手段。

**覆盖安装会丢数据吗？**
不会。覆盖安装不清理数据，新旧格式在首次启动时自动迁移。

## 致谢

- [astrbot_plugin_livingmemory](https://github.com/lxfight-s-Astrbot-Plugins/astrbot_plugin_livingmemory) — 记忆系统参考了该插件的设计
- [Flutter](https://flutter.dev) 与开源社区。

## 许可证

本项目基于 [GPL-3.0](LICENSE) 发布。

[flutter-badge]: https://img.shields.io/badge/Flutter-3.8%2B-02569B?style=flat-square&logo=flutter
[flutter-link]: https://flutter.dev
[dart-badge]: https://img.shields.io/badge/Dart-3.8%2B-0175C2?style=flat-square&logo=dart
[dart-link]: https://dart.dev
[android-badge]: https://img.shields.io/badge/Platform-Android-3DDC84?style=flat-square&logo=android
[android-link]: https://www.android.com
[license-badge]: https://img.shields.io/badge/License-GPL--3.0-E7B24F?style=flat-square
[license-link]: LICENSE
[tests-badge]: https://img.shields.io/badge/tests-passing-2EA043?style=flat-square
[tests-link]: https://github.com/yonglanws/MewMew/tree/dev/test
