# 设置页开关右下角入口设计

## 目标

将设置模块中页面级的开关从设置卡片右侧统一移动到页面右下角，保持现有开关状态、持久化和互斥逻辑不变，并与表情包管理页已经采用的右下角扩展 FAB 风格一致。

## 范围

- `SettingsPage` 的“流式输出”开关：页面只有一个开关，右下角 FAB 直接切换状态。
- `MemorySettingsPage` 的“记忆系统总开关”：页面只有一个开关，右下角 FAB 直接切换状态；未配置嵌入 API 时 FAB 禁用。
- `MessageDebounceSettingsPage` 的“消息防抖动”和“打字防抖”：右下角 FAB 打开底部面板，面板集中承载两个开关。
- `SegmentedSendSettingsPage` 的“启用分段发送”“清理首尾空行”“反向替换”：右下角 FAB 打开底部面板，面板集中承载三个开关。
- `ToolsPage` 每个工具独立的启用开关不改位置，因为它们是列表项级操作，不是页面级开关。

## 交互与视觉

- 页面移除对应卡片中的 `Switch`，保留状态文案和禁用态说明。
- 单开关页面使用 `FloatingActionButton.extended`，根据状态显示“开启/关闭 + 功能名”，图标使用 `toggle_on` / `toggle_off`。
- 多开关页面使用 `FloatingActionButton.extended` 显示“开关管理”，点击 `showModalBottomSheet`，底部面板中的每一项继续使用 `SwitchListTile`，并复用原有回调。
- 页面滚动内容在底部增加安全留白，避免被 FAB 遮挡。
- 不新增模型字段、不改变 `AppState` 或 `StorageService` 的业务 API。

## 测试

- 单开关页面：初始页面不再包含 `Switch`，包含右下角 FAB；点击 FAB 后状态改变。
- 多开关页面：初始页面不再包含 `Switch`，点击 FAB 后底部面板出现完整数量的开关。
- 运行现有测试，确认原有设置状态和页面行为没有回归。
