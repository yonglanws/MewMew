# 设置页开关右下角入口 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将设置模块中的页面级开关统一迁移到右下角 FAB 或 FAB 打开的底部开关面板。

**Architecture:** 保留现有 `AppState` 更新方法和互斥逻辑，只调整各设置页的入口层。单开关页直接由 FAB 触发原有回调，多开关页由 FAB 打开一个底部面板，面板内集中呈现原有 `SwitchListTile`。

**Tech Stack:** Flutter Material 3、Provider、Flutter widget tests、Dart formatter。

---

### Task 1: 添加失败的页面行为测试

**Files:**
- Create: `test/pages/settings_switch_fab_test.dart`
- Reference: `lib/pages/settings_page.dart`, `lib/pages/memory_settings_page.dart`, `lib/pages/message_debounce_settings_page.dart`, `lib/pages/segmented_send_settings_page.dart`

- [ ] **Step 1: 写测试**

测试覆盖：设置页和记忆页初始不显示 `Switch` 且有 FAB；消息防抖动页和分段发送页初始不显示 `Switch`，点击 FAB 后分别出现 2 个和 3 个 `Switch`。

- [ ] **Step 2: 运行测试确认 RED**

运行：`flutter test test/pages/settings_switch_fab_test.dart`

预期：失败，因为现有页面仍将 `Switch` 作为列表项 trailing，且没有对应 FAB。

### Task 2: 实现单开关页的 FAB

**Files:**
- Modify: `lib/pages/settings_page.dart`
- Modify: `lib/pages/memory_settings_page.dart`

- [ ] **Step 1: 移除列表项 trailing Switch**

保留原有状态副标题，删除“流式输出”和“记忆系统总开关”条目的 `trailing: Switch(...)`。

- [ ] **Step 2: 添加右下角扩展 FAB**

设置页直接调用 `setStreamOutputEnabled(!state.streamOutputEnabled)`；记忆页在 `embeddingValid` 为真时调用 `setInjectMemories(!state.injectMemories)`，否则使用禁用 FAB。FAB label 根据状态显示“开启/关闭流式输出”或“开启/关闭记忆系统”。

- [ ] **Step 3: 增加底部滚动留白并运行单页测试**

运行：`flutter test test/pages/settings_switch_fab_test.dart`

预期：单开关页测试通过，多开关页测试仍失败。

### Task 3: 实现多开关页的底部开关面板

**Files:**
- Modify: `lib/pages/message_debounce_settings_page.dart`
- Modify: `lib/pages/segmented_send_settings_page.dart`

- [ ] **Step 1: 移除页面卡片内的 Switch**

保留标题、副标题和依赖禁用状态，将原有状态回调搬到页面私有的 `showModalBottomSheet` 构建方法。

- [ ] **Step 2: 添加 FAB 并展示底部开关面板**

消息防抖动页 FAB 打开包含“消息防抖动”和“打字防抖”的面板；分段发送页 FAB 打开包含“启用分段发送”“清理首尾空行”“反向替换”的面板。每个 `SwitchListTile` 继续调用现有 `AppState`/`_update` 方法，并保留原有互斥禁用条件。

- [ ] **Step 3: 运行跟进测试和全量测试**

运行：`flutter test test/pages/settings_switch_fab_test.dart`，然后运行：`flutter test`。

预期：新增测试和原有测试全部通过。

### Task 4: 格式化、分析和合并前检查

**Files:**
- Modify: `lib/pages/settings_page.dart`
- Modify: `lib/pages/memory_settings_page.dart`
- Modify: `lib/pages/message_debounce_settings_page.dart`
- Modify: `lib/pages/segmented_send_settings_page.dart`
- Create: `test/pages/settings_switch_fab_test.dart`

- [ ] **Step 1: 格式化与定向分析**

运行：`dart format lib/pages/settings_page.dart lib/pages/memory_settings_page.dart lib/pages/message_debounce_settings_page.dart lib/pages/segmented_send_settings_page.dart test/pages/settings_switch_fab_test.dart`；运行：`flutter analyze lib/pages/settings_page.dart lib/pages/memory_settings_page.dart lib/pages/message_debounce_settings_page.dart lib/pages/segmented_send_settings_page.dart test/pages/settings_switch_fab_test.dart`。

- [ ] **Step 2: 检查差异并提交**

运行：`git diff --check`，确认只包含本需求相关文件后提交：`git add -- lib/pages/settings_page.dart lib/pages/memory_settings_page.dart lib/pages/message_debounce_settings_page.dart lib/pages/segmented_send_settings_page.dart test/pages/settings_switch_fab_test.dart && git commit -m "feat: move settings switches to bottom actions"`。
