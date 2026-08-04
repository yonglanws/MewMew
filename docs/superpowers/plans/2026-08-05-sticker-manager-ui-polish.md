# Sticker Manager UI Polish Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Improve the sticker manager list and detail pages with clearer cards, top-positioned frequency controls, and image/icon thumbnails for groups and emotion folders.

**Architecture:** Keep all existing `AppState` and persistence behavior unchanged. Limit changes to the sticker manager widgets and their widget tests, reusing the existing local-file thumbnail fallback pattern.

**Tech Stack:** Flutter Material 3, Provider, existing `AppTheme`, Flutter widget tests.

---

### Task 1: Add thumbnail presentation primitives

**Files:**
- Modify: `lib/pages/sticker_management_page.dart`

- [ ] **Step 1: Add a compact thumbnail widget**

Create a small reusable widget beside the existing sticker thumbnail widgets. It should render the first valid local image path with `Image.file`, crop it to a rounded square, and render the supplied icon when the path is empty or invalid.

- [ ] **Step 2: Add group and folder thumbnail path helpers**

Use the first non-empty `StickerItem.filePath` from the group’s folders or a folder’s stickers. Keep the lookup read-only and return `null` when no image exists.

- [ ] **Step 3: Run formatting**

Run `dart format lib/pages/sticker_management_page.dart` and expect the command to complete without errors.

### Task 2: Polish the manager list and detail layout

**Files:**
- Modify: `lib/pages/sticker_management_page.dart`

- [ ] **Step 1: Improve persona list cards**

Replace the plain list tile presentation with a compact card row that keeps the avatar and adds visible status chips/text for bound group count, send probability, and preferred emotion count.

- [ ] **Step 2: Move frequency section to the top**

In `PersonaStickerSettingsPage`, render the send frequency card immediately after the large app bar, before group binding and emotion preference controls.

- [ ] **Step 3: Add group thumbnails to binding chips**

Use the group thumbnail helper and the compact thumbnail widget as the `FilterChip.avatar`, with the existing group icon as fallback.

- [ ] **Step 4: Add folder thumbnails to emotion chips**

Use the first sticker in each folder as the `FilterChip.avatar`, with the folder icon as fallback. Preserve the current selected/unselected behavior and folder ID persistence.

- [ ] **Step 5: Keep the save action and data flow unchanged**

Do not alter `setPersonaStickerGroups`, `setPersonaStickerSettings`, sticker selection, prompt injection, or stream-output behavior.

### Task 3: Extend widget coverage

**Files:**
- Modify: `test/pages/sticker_management_page_test.dart`

- [ ] **Step 1: Add a manager detail fixture**

Create a persona with one bound group, one folder, and one sticker image path, then open the manager and persona detail page.

- [ ] **Step 2: Assert layout order and labels**

Verify that `发送频率` is present before `绑定的表情包组`, and that `喜欢的情绪分组` remains visible.

- [ ] **Step 3: Assert thumbnail fallback widgets do not throw**

Pump the detail page with both valid and empty file paths, then assert `tester.takeException()` is null.

- [ ] **Step 4: Run targeted tests**

Run `flutter test test/pages/sticker_management_page_test.dart` and expect all tests to pass.

### Task 4: Verify the complete change

**Files:**
- No additional files.

- [ ] **Step 1: Run the full test suite**

Run `flutter test` and expect all tests to pass.

- [ ] **Step 2: Run static analysis**

Run `flutter analyze --no-fatal-infos` and confirm there are no new warnings or errors attributable to this change.

- [ ] **Step 3: Check the diff**

Run `git diff --check` and confirm no whitespace errors.
