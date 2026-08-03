# Sticker Management Page Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将表情包管理相关页面改造成与设置页一致的“概览 + 分组入口 + 统一列表/空状态 + 可见操作”体验，同时保持现有数据和导航行为不变。

**Architecture:** 所有 UI 变化集中在 `lib/pages/sticker_management_page.dart`，通过文件内私有组件复用设置页的 section、入口行、空状态和统计展示样式。新增 widget 测试通过公开页面和 `AppState` 的内存字段验证用户可见行为，不修改 `AppState` 或存储服务。

**Tech Stack:** Flutter Material 3, `flutter_test`, Provider, 现有 `AppTheme` 令牌。

---

## 文件映射

- Create: `test/pages/sticker_management_page_test.dart` — 首页概览、窄屏布局和空状态的 widget 测试。
- Modify: `lib/pages/sticker_management_page.dart` — 首页、组列表、文件夹列表、表情网格、人格绑定页的 UI 结构和私有复用组件。
- Reference only: `lib/theme/app_theme.dart`, `lib/pages/settings_page.dart` — 复用已存在的主题令牌与设置页视觉基线。

### Task 1: 为首页和窄屏布局写失败测试

**Files:**
- Create: `test/pages/sticker_management_page_test.dart`

- [ ] **Step 1: 写出首页行为测试**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:mewmew/models/models.dart';
import 'package:mewmew/pages/sticker_management_page.dart';
import 'package:mewmew/services/storage_service.dart';
import 'package:mewmew/state/app_state.dart';
import 'package:mewmew/theme/app_theme.dart';

void main() {
  testWidgets('首页在窄屏显示概览和两类管理入口', (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final state = AppState(StorageService())
      ..stickerGroups = [
        StickerGroup(
          id: 'group-1',
          name: '日常',
          createdAt: DateTime(2026),
        ),
      ]
      ..stickerFolders = [
        StickerFolder(
          id: 'folder-1',
          groupId: 'group-1',
          name: '开心',
          description: '',
          createdAt: DateTime(2026),
        ),
      ]
      ..stickers = [
        StickerItem(
          id: 'sticker-1',
          folderId: 'folder-1',
          name: '笑脸',
          description: '',
          filePath: '',
          createdAt: DateTime(2026),
        ),
      ];
    addTearDown(state.dispose);

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: state,
        child: MaterialApp(
          theme: AppTheme.lightTheme(),
          home: const StickerManagementPage(),
        ),
      ),
    );

    expect(find.text('表情包概览'), findsOneWidget);
    expect(find.text('资源管理'), findsOneWidget);
    expect(find.text('使用关系'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
```

- [ ] **Step 2: 运行测试，确认它因新 UI 文案缺失而失败**

Run: `flutter test test/pages/sticker_management_page_test.dart`

Expected: FAIL，当前实现没有 `表情包概览` 和 `资源管理` 文案；失败原因应是断言找不到文本，而不是编译错误。

### Task 2: 实现首页概览与统一入口组件

**Files:**
- Modify: `lib/pages/sticker_management_page.dart`

- [ ] **Step 1: 引入主题令牌并替换首页布局**

在 imports 中增加：

```dart
import '../theme/app_theme.dart';
```

首页保留 `SliverAppBar.large`，将 `_InfoCard` 替换为统计概览卡，并将两个 section 的标题改为“资源管理”和“使用关系”：

```dart
SliverToBoxAdapter(
  child: _StickerOverviewCard(
    groupCount: state.stickerGroups.length,
    folderCount: state.stickerFolders.length,
    stickerCount: state.stickers.length,
  ),
),
```

- [ ] **Step 2: 添加统计概览组件**

使用 `Container` + `primaryContainer.withValues(alpha: 0.45)` + `AppTheme.radiusLg`，说明文字下方使用 `LayoutBuilder` 和 `Wrap`，为三个统计项提供 `label`、`value` 和对应图标。统计项不得写死宽度，以保证 320px 窄屏不溢出。

```dart
class _StickerOverviewCard extends StatelessWidget {
  final int groupCount;
  final int folderCount;
  final int stickerCount;

  const _StickerOverviewCard({
    required this.groupCount,
    required this.folderCount,
    required this.stickerCount,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.primaryContainer.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(AppTheme.radiusLg),
        border: Border.all(color: cs.primary.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('表情包概览', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text('按组和情绪文件夹整理资源，聊天时会按人格绑定结果使用。',
              style: TextStyle(color: cs.onSurfaceVariant, height: 1.4)),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _StickerStat(icon: Icons.collections_bookmark_outlined, label: '表情包组', value: groupCount),
              _StickerStat(icon: Icons.folder_outlined, label: '情绪文件夹', value: folderCount),
              _StickerStat(icon: Icons.emoji_emotions_outlined, label: '表情包', value: stickerCount),
            ],
          ),
        ],
      ),
    );
  }
}
```

`_StickerStat` 只负责图标、数字和标签的布局，使用 `ConstrainedBox(const BoxConstraints(minWidth: 82, maxWidth: 120))`，不要使用依赖屏幕宽度的固定总宽度。

- [ ] **Step 3: 添加设置页风格 section 和入口行**

将原 `_Section` / `_ManagementEntry` 替换或改造为 `_StickerSection` / `_StickerEntry`：section 只创建一张 `Card(child: Column(children: ...))`；入口行使用 40px 图标色块、标题、摘要和 `chevron_right`，不再在入口行内部创建第二张 Card。

```dart
class _StickerEntry extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _StickerEntry({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: iconColor.withAlpha((0.15 * 255).toInt()),
          borderRadius: BorderRadius.circular(AppTheme.radiusSm),
        ),
        child: Icon(icon, color: iconColor, size: 22),
      ),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w500)),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.chevron_right, size: 20),
      onTap: onTap,
    );
  }
}
```

- [ ] **Step 4: 重跑首页测试，确认通过且无窄屏异常**

Run: `flutter test test/pages/sticker_management_page_test.dart`

Expected: PASS，首页出现概览、资源管理和使用关系，`tester.takeException()` 为 null。

### Task 3: 为统一空状态和可见删除入口写失败测试

**Files:**
- Modify: `test/pages/sticker_management_page_test.dart`

- [ ] **Step 1: 添加空网格行为测试**

```dart
testWidgets('空表情包文件夹显示说明和导入操作', (tester) async {
  final state = AppState(StorageService());
  state.stickerFolders = [
    StickerFolder(
      id: 'folder-1',
      groupId: 'group-1',
      name: '开心',
      description: '',
      createdAt: DateTime(2026),
    ),
  ];
  addTearDown(state.dispose);

  await tester.pumpWidget(
    ChangeNotifierProvider.value(
      value: state,
      child: MaterialApp(
        theme: AppTheme.lightTheme(),
        home: const StickerFolderPage(
          folder: StickerFolder(
            id: 'folder-1',
            groupId: 'group-1',
            name: '开心',
            description: '',
            createdAt: DateTime(2026),
          ),
        ),
      ),
    ),
  );

  expect(find.text('导入图片后会显示在这里'), findsOneWidget);
  expect(find.text('导入表情包'), findsOneWidget);
});
```

- [ ] **Step 2: 运行测试，确认当前空状态说明缺失**

Run: `flutter test test/pages/sticker_management_page_test.dart`

Expected: FAIL，当前 `_EmptyStickers` 没有 `导入图片后会显示在这里` 文案；不得因为图片选择器或状态初始化产生编译错误。

### Task 4: 实现列表、空状态、网格和绑定页视觉统一

**Files:**
- Modify: `lib/pages/sticker_management_page.dart`

- [ ] **Step 1: 添加共享空状态组件并替换三处空状态**

```dart
class _StickerEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;
  final String actionLabel;
  final VoidCallback onAction;

  const _StickerEmptyState({
    required this.icon,
    required this.title,
    required this.description,
    required this.actionLabel,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 48, color: Theme.of(context).colorScheme.outline),
          const SizedBox(height: 12),
          Text(title, textAlign: TextAlign.center),
          const SizedBox(height: 6),
          Text(description,
              textAlign: TextAlign.center,
              style: TextStyle(color: Theme.of(context).colorScheme.outline)),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: onAction,
            icon: const Icon(Icons.add_rounded),
            label: Text(actionLabel),
          ),
        ],
      ),
    ),
  );
}
```

组、文件夹和网格分别传入“还没有表情包组”“这个表情包组还没有文件夹”“还没有表情包”以及对应说明和动作。

- [ ] **Step 2: 将组/文件夹/人格绑定列表改为单卡片分组列表**

列表 `ListView` 的 `children` 使用一个 `Card(child: Column(...))` 或通过 `ListView.separated` 生成带 `Divider` 的内容；每行复用 `_StickerEntry` 或同一套 40px 图标色块规则。文件夹行保留 `PopupMenuButton`，不要新增组删除入口。

- [ ] **Step 3: 统一表情网格卡片并增加显式删除菜单**

把当前网格项替换为 `Material + Stack`，右上角放 `PopupMenuButton<String>`：

```dart
PopupMenuButton<String>(
  tooltip: '更多操作',
  onSelected: (value) {
    if (value == 'delete') _deleteSticker(context, sticker);
  },
  itemBuilder: (_) => const [
    PopupMenuItem(value: 'delete', child: Text('删除表情包')),
  ],
)
```

保留原有 `onLongPress` 删除、`Image.file` 错误图标、单行名称省略和导入按钮。

- [ ] **Step 4: 将人格绑定摘要改成数量 + Chip**

在人格行的 `subtitle` 使用 `Column`：第一行显示绑定数量，第二行使用 `Wrap(spacing: 6, runSpacing: 4)` 展示组名 Chip；未绑定时只显示弱化提示。多选对话框的选择集合、保存回调和按钮行为保持不变。

- [ ] **Step 5: 运行测试确认共享 UI 通过**

Run: `flutter test test/pages/sticker_management_page_test.dart`

Expected: PASS，首页和空网格测试全部通过，且不出现 `RenderFlex overflow` 或其他 Flutter framework exception。

### Task 5: 格式化、静态分析、完整测试和改动审查

**Files:**
- Modify: `lib/pages/sticker_management_page.dart`（仅在格式化需要时）
- Modify: `test/pages/sticker_management_page_test.dart`（仅在格式化需要时）

- [ ] **Step 1: 格式化目标文件**

Run: `dart format lib/pages/sticker_management_page.dart test/pages/sticker_management_page_test.dart`

Expected: 命令退出码为 0；若有文件被格式化，继续执行后续验证。

- [ ] **Step 2: 运行完整测试**

Run: `flutter test`

Expected: 退出码为 0，新增测试和现有测试全部通过。

- [ ] **Step 3: 运行静态分析**

Run: `flutter analyze`

Expected: 退出码为 0，无新增 error 或 warning。

- [ ] **Step 4: 审查 diff 和未纳入本次任务的改动**

Run: `git diff --check; git status --short; git diff -- lib/pages/sticker_management_page.dart test/pages/sticker_management_page_test.dart`

Expected: 目标 diff 只包含本次页面和测试改动；`screen1.png`、`screen2.png` 的已有删除状态不被恢复、不被提交。

- [ ] **Step 5: 提交本次实现**

```powershell
git add -- 'lib/pages/sticker_management_page.dart' 'test/pages/sticker_management_page_test.dart'
git commit -m "feat: align sticker management page with app theme"
```

