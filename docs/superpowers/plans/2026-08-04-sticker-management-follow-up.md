# Sticker Management Follow-up Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 为表情包管理页增加组名编辑、文件夹缩略图和 FAB 主操作入口，同时让表情包名称成为内部兼容信息而不是用户必须维护的界面字段。

**Architecture:** 继续把 UI 改动集中在 `lib/pages/sticker_management_page.dart`，通过私有 `_StickerThumbnail` 组件从现有 `AppState` 数据动态渲染文件夹代表图。复用已有 `AppState.updateStickerGroup`，不增加模型字段、不修改持久化格式；测试通过公开页面和真实 `AppState` 验证用户可见行为。

**Tech Stack:** Flutter Material 3, `flutter_test`, Provider, SharedPreferences mock initialization.

---

## 文件映射

- Create: `test/pages/sticker_management_follow_up_test.dart` — 组名编辑、FAB、组副标题、缩略图回退和无名称展示的 widget 测试。
- Modify: `lib/pages/sticker_management_page.dart` — 组名编辑入口、组列表 FAB、人格绑定 FAB、文件夹缩略图、空状态按钮和表情网格文案。
- Reference: `lib/state/app_state.dart` — 复用已有 `updateStickerGroup`，不修改业务状态接口。

### Task 1: 写出后续需求的失败 widget 测试

**Files:**
- Create: `test/pages/sticker_management_follow_up_test.dart`

- [ ] **Step 1: 写组列表标题、FAB 和空状态测试**

```dart
testWidgets('组列表用组名和表情包组副标题，并把新建放到 FAB', (tester) async {
  final state = AppState(StorageService())
    ..stickerGroups = [
      StickerGroup(
        id: 'group-1',
        name: '日常反应',
        createdAt: DateTime(2026),
      ),
    ];
  addTearDown(state.dispose);

  await tester.pumpWidget(_host(state, const StickerGroupListPage()));

  expect(find.text('日常反应'), findsOneWidget);
  expect(find.text('表情包组'), findsOneWidget);
  expect(find.text('新建表情包组'), findsOneWidget);
  expect(find.byType(FloatingActionButton), findsOneWidget);
  expect(find.byTooltip('新建表情包组'), findsNothing);
});

testWidgets('空组列表通过右下角 FAB 创建，不重复显示中心按钮', (tester) async {
  final state = AppState(StorageService());
  addTearDown(state.dispose);

  await tester.pumpWidget(_host(state, const StickerGroupListPage()));

  expect(find.text('还没有表情包组'), findsOneWidget);
  expect(find.text('新建表情包组'), findsOneWidget);
  expect(find.byType(FloatingActionButton), findsOneWidget);
  expect(find.byType(FilledButton), findsNothing);
});
```

测试文件提供以下真实 widget host，避免 mock 业务状态：

```dart
Widget _host(AppState state, Widget child) => ChangeNotifierProvider.value(
  value: state,
  child: MaterialApp(theme: AppTheme.lightTheme(), home: child),
);
```

- [ ] **Step 2: 写组名编辑和人格绑定 FAB 测试**

组名编辑测试初始化 `SharedPreferences.setMockInitialValues({})`、`StorageService.init()`，点击 `编辑组名`，输入“新的组名”，点击“保存”，最后断言 `state.stickerGroups.single.name == '新的组名'`。人格绑定测试渲染 `PersonaStickerBindingPage`，断言存在 `绑定人格` 文案和 `FloatingActionButton`，且不存在 AppBar 的 `IconButton` 新增入口。

- [ ] **Step 3: 写缩略图回退和无名称展示测试**

```dart
testWidgets('没有图片路径的文件夹显示默认文件夹图标', (tester) async {
  final state = AppState(StorageService())
    ..stickerFolders = [
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
    _host(
      state,
      const StickerGroupPage(
        group: StickerGroup(
          id: 'group-1',
          name: '日常',
          createdAt: DateTime(2026),
        ),
      ),
    ),
  );

  expect(find.byIcon(Icons.folder_outlined), findsOneWidget);
});

testWidgets('表情网格不显示历史表情包名称', (tester) async {
  final state = AppState(StorageService())
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
        name: 'legacy-name',
        description: '',
        filePath: '',
        createdAt: DateTime(2026),
      ),
  ];
  addTearDown(state.dispose);

  await tester.pumpWidget(
    _host(
      state,
      const StickerFolderPage(
        folder: StickerFolder(
          id: 'folder-1',
          groupId: 'group-1',
          name: '开心',
          description: '',
          createdAt: DateTime(2026),
        ),
      ),
    ),
  );
  expect(find.text('legacy-name'), findsNothing);
});
```

- [ ] **Step 4: 运行测试确认它们因新行为缺失而失败**

Run: `flutter test test/pages/sticker_management_follow_up_test.dart`

Expected: FAIL 至少包含：组副标题未显示、FAB 未存在、编辑按钮未存在或缩略图/无名称断言不满足；如果出现编译错误，先修正测试本身，再重新运行到行为断言失败。

### Task 2: 实现组名编辑、组列表 FAB 和标题层级

**Files:**
- Modify: `lib/pages/sticker_management_page.dart`

- [ ] **Step 1: 将组列表新建入口迁移到 FAB**

从 `StickerGroupListPage` 的 AppBar actions 移除新建 IconButton，给 Scaffold 增加：

```dart
floatingActionButton: FloatingActionButton.extended(
  onPressed: () => StickerGroupListPage._createGroup(context),
  icon: const Icon(Icons.add_rounded),
  label: const Text('新建表情包组'),
),
```

把 `_StickerEmptyState` 的 `actionLabel` 和 `onAction` 改为可选，仅组列表空状态传 null；其他文件夹/表情包空状态继续显示中心操作按钮。

- [ ] **Step 2: 调整组列表行主副标题**

组行使用：

```dart
title: group.name,
subtitle: const Text('表情包组'),
```

保持点击整行进入 `StickerGroupPage`，数量继续由首页概览和组详情展示，不把数量挤进主标题。

- [ ] **Step 3: 增加组详情编辑按钮和对话框**

组详情页从 `AppState.stickerGroups` 按 id 取当前组对象，AppBar 增加 `Icons.edit_outlined`，点击后打开预填充当前名称的对话框。保存时调用：

```dart
await context.read<AppState>().updateStickerGroup(
  StickerGroup(
    id: group.id,
    name: name.text,
    createdAt: group.createdAt,
  ),
);
```

空白名称直接关闭/不保存，保持 `AppState.addStickerGroup` 的非空规则；保存后使用最新组对象渲染标题和新增文件夹回调。

- [ ] **Step 4: 运行后续测试确认组管理行为通过**

Run: `flutter test test/pages/sticker_management_follow_up_test.dart`

Expected: 组名/副标题、FAB 和编辑组名测试 PASS；缩略图和无名称测试仍可能 FAIL。

### Task 3: 实现文件夹缩略图和创建文件夹表单间距

**Files:**
- Modify: `lib/pages/sticker_management_page.dart`

- [ ] **Step 1: 添加 `_StickerThumbnail` 组件**

```dart
class _StickerThumbnail extends StatelessWidget {
  final String? filePath;
  final IconData fallbackIcon;

  const _StickerThumbnail({required this.filePath, required this.fallbackIcon});

  @override
  Widget build(BuildContext context) {
    final path = filePath?.trim() ?? '';
    final fallback = Icon(
      fallbackIcon,
      color: Theme.of(context).colorScheme.tertiary,
      size: 22,
    );
    if (path.isEmpty) return fallback;
    return Image.file(
      File(path),
      fit: BoxFit.cover,
      cacheWidth: 160,
      errorBuilder: (_, __, ___) => fallback,
    );
  }
}
```

外层用 40px 方形容器和 `ClipRRect`，文件夹行通过 `state.stickersForFolder(folder.id).firstOrNull?.filePath` 传入。

- [ ] **Step 2: 把文件夹行 leading 替换为缩略图**

用 `_StickerThumbnail` 替换文件夹列表中固定的 `Icons.folder_outlined`，保留文件夹标题、摘要、更多菜单和点击导航。

- [ ] **Step 3: 增加创建文件夹表单间距**

在“文件夹名称” `TextField` 和“使用场景描述” `TextField` 之间增加：

```dart
const SizedBox(height: 12),
```

不改变两个字段的 label、保存调用和非空校验。

- [ ] **Step 4: 运行缩略图/文件夹相关测试**

Run: `flutter test test/pages/sticker_management_follow_up_test.dart`

Expected: 默认文件夹图标测试 PASS，字段间距代码通过静态分析。

### Task 4: 实现无名称表情包和人格绑定 FAB

**Files:**
- Modify: `lib/pages/sticker_management_page.dart`

- [ ] **Step 1: 将人格绑定主操作迁移到右下角**

在 `PersonaStickerBindingPage` 的 Scaffold 增加 `FloatingActionButton.extended`，label 为“绑定人格”，onPressed 调用已有 `_showGroups`；AppBar 只保留标题。

- [ ] **Step 2: 隐藏表情包名称展示并调整删除文案**

网格卡片移除底部 `Text(sticker.name)`，让缩略图占据主要空间；保留右上角菜单和长按删除。删除对话框改为：

```dart
content: const Text('确定删除这张表情包吗？'),
```

导入逻辑继续为旧标签生成稳定的内部名称，不新增用户输入步骤。

- [ ] **Step 3: 运行全部后续 widget 测试**

Run: `flutter test test/pages/sticker_management_follow_up_test.dart`

Expected: 所有后续测试 PASS，且无 framework exception 或窄屏溢出。

### Task 5: 格式化、分析、完整测试和合并

**Files:**
- Modify: `lib/pages/sticker_management_page.dart`
- Create: `test/pages/sticker_management_follow_up_test.dart`

- [ ] **Step 1: 格式化**

Run: `dart format lib/pages/sticker_management_page.dart test/pages/sticker_management_follow_up_test.dart`

Expected: 退出码 0。

- [ ] **Step 2: 定向分析**

Run: `flutter analyze lib/pages/sticker_management_page.dart test/pages/sticker_management_follow_up_test.dart`

Expected: `No issues found!`。

- [ ] **Step 3: 完整测试**

Run: `flutter test`

Expected: 上一轮 2 个测试和本轮后续测试全部通过。

- [ ] **Step 4: 检查 diff**

Run: `git diff --check; git status --short; git diff -- lib/pages/sticker_management_page.dart test/pages/sticker_management_follow_up_test.dart`

Expected: 仅包含本次目标页面和测试改动；不触碰既有 `screen1.png`、`screen2.png` 删除状态。

- [ ] **Step 5: 提交并合并**

```powershell
git add -- 'lib/pages/sticker_management_page.dart' 'test/pages/sticker_management_follow_up_test.dart'
git commit -m "feat: refine sticker group management interactions"
```
