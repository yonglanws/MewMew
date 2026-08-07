# 人格表情包管理页顺序与绑定前禁用 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将人格表情包管理页调整为“绑定组 → 情绪偏好 → 发送频率 → 使用策略”，并在未绑定表情包组时禁用后续三个设置区块。

**Architecture:** 继续使用 `PersonaStickerSettingsPage` 当前的本地表单状态和 `AppState` 持久化接口。以 `_selectedGroupIds.isNotEmpty` 计算页面级启用条件，通过一个轻量的禁用包装组件统一控制透明度和指针事件，不新增数据字段或存储格式。

**Tech Stack:** Flutter、Dart、`flutter_test`、Provider、现有 Material 主题组件。

---

### Task 1: 添加失败的页面回归测试

**Files:**
- Modify: `D:\Flutter Projects\mewmew\test\pages\sticker_management_page_test.dart`

- [x] **Step 1: 写出顺序、头像和未绑定禁用行为测试**

在 `PersonaStickerSettingsPage` 测试附近增加测试数据和断言，验证未绑定时：

```dart
final sections = <String>[
  '绑定的表情包组',
  '喜欢的情绪分组',
  '表情包发送方式',
  '表情使用策略',
];
for (var i = 0; i < sections.length - 1; i++) {
  final first = tester.getTopLeft(find.text(sections[i])).dy;
  final second = tester.getTopLeft(find.text(sections[i + 1])).dy;
  expect(first, lessThan(second));
}
expect(find.byType(PersonaAvatar), findsNothing);
expect(
  tester.widgetList<RadioListTile<StickerSendMode>>(
    find.byType(RadioListTile<StickerSendMode>),
  ).every((radio) => radio.onChanged == null),
  isTrue,
);
expect(tester.widget<TextField>(find.byType(TextField)).enabled, isFalse);
```

测试同时保留一个已绑定组的场景，验证绑定后三个设置区块的控件回到可用状态。

- [x] **Step 2: 运行页面测试确认按预期失败**

运行：

```text
flutter test test/pages/sticker_management_page_test.dart
```

预期：新增顺序断言失败，且当前未绑定人格仍能操作发送频率和策略输入，证明测试覆盖的是尚未实现的行为。

### Task 2: 重排页面并加入绑定前禁用状态

**Files:**
- Modify: `D:\Flutter Projects\mewmew\lib\pages\sticker_management_page.dart:393-725`

- [x] **Step 1: 提取当前页面启用条件**

在 `build` 中计算：

```dart
final hasBoundGroups = _selectedGroupIds.isNotEmpty;
```

- [x] **Step 2: 将绑定组卡片移动到页面第一块**

保持现有组选择逻辑和缩略图不变，只移动卡片位置；绑定区域本身不包裹禁用组件。

- [x] **Step 3: 将情绪分组卡片移动到绑定组之后**

继续依据 `_selectedGroupIds` 计算 `folders`，因此未绑定时自然显示无可用情绪分组；同时将整个卡片交给禁用包装组件处理。

- [x] **Step 4: 将发送频率卡片移动到第三块并删除人格头像**

保留三个 `RadioListTile<StickerSendMode>` 和帮助文案，删除 `ListTile.leading: PersonaAvatar(...)`，并将卡片放入禁用包装组件。

- [x] **Step 5: 将表情使用策略卡片放到最后并禁用输入**

保留现有 `TextEditingController` 和 `TextField`，通过同一个禁用包装组件让它在没有绑定组时不可编辑。

- [x] **Step 6: 实现统一的卡片级禁用视觉和交互**

在页面文件中增加私有组合组件，核心行为为：

```dart
class _StickerSettingsDisabled extends StatelessWidget {
  const _StickerSettingsDisabled({required this.enabled, required this.child});

  final bool enabled;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      opacity: enabled ? 1 : 0.45,
      duration: const Duration(milliseconds: 150),
      child: IgnorePointer(ignoring: !enabled, child: child),
    );
  }
}
```

三张下方卡片均使用 `enabled: hasBoundGroups`。保存方法不增加额外限制，继续保存当前页面内状态。

### Task 3: 验证和整理

**Files:**
- Modify: `D:\Flutter Projects\mewmew\test\pages\sticker_management_page_test.dart`
- Modify: `D:\Flutter Projects\mewmew\lib\pages\sticker_management_page.dart`

- [x] **Step 1: 运行页面回归测试**

运行：

```text
flutter test test/pages/sticker_management_page_test.dart
```

预期：页面测试全部通过。

- [x] **Step 2: 格式化修改文件**

运行：

```text
dart format lib/pages/sticker_management_page.dart test/pages/sticker_management_page_test.dart
```

- [x] **Step 3: 运行全量验证**

运行：

```text
flutter test
flutter analyze --no-fatal-infos
git diff --check
```

预期：测试全部通过，静态分析不新增 warning/error，差异检查通过。
