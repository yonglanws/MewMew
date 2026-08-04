# Agent Sticker Sending Fixes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Configure sticker frequency and make Agent tags resolve emotion folders within the current persona's bound sticker groups.

**Architecture:** `StickerSelection` provides the shared persona-scoped candidate lookup, probability gate, and random selection used by prompting and response parsing. `AppState` persists the percentage setting and keeps streaming output as the hard switch that disables sticker prompting/parsing. Chat rendering receives the persona ID and uses the same scope; unavailable historical assets render a placeholder.

**Tech Stack:** Flutter/Dart, Provider, SharedPreferences, Flutter widget tests.

---

### Task 1: Persist the frequency setting

**Files:** `lib/services/storage_service.dart`, `lib/state/app_state.dart`, `test/state/sticker_agent_logic_test.dart`

- [x] Add failing tests for default 10%, 0..100 clamping, and persistence.
- [x] Implement the storage key/getter/setter and AppState load/set methods.
- [x] Verify with the focused state test.

### Task 2: Add the settings page

**Files:** `lib/pages/sticker_send_settings_page.dart`, `lib/pages/settings_page.dart`, `test/pages/sticker_send_settings_page_test.dart`

- [x] Add failing tests for the slider, current percentage, streaming warning, and Settings entry.
- [x] Implement the Material 3 settings page and navigation entry.
- [x] Verify the focused widget test.

### Task 3: Resolve emotion folders and random stickers

**Files:** `lib/state/sticker_selection.dart`, `lib/state/app_state.dart`, `test/state/sticker_agent_logic_test.dart`

- [x] Add failing tests for folder-name matching, persona binding, random candidates, frequency boundaries, and stream behavior.
- [x] Change the prompt to list emotion-folder names/descriptions.
- [x] Parse each tag against the bound folders, gate once per response by the configured probability, and randomly select a valid image with a two-sticker maximum.
- [x] Verify focused tests and preserve the stream-output guard.

### Task 4: Scope previews and handle missing assets

**Files:** `lib/widgets/sticker_message_body.dart`, `lib/pages/chat_page.dart`, `test/widgets/sticker_message_body_test.dart`

- [x] Add failing tests for persona-scoped preview and unavailable-sticker feedback.
- [x] Pass the persona ID into previews and use the shared folder lookup.
- [x] Render an explicit placeholder for deleted or missing sticker assets.
- [x] Verify focused tests.

### Task 5: Verify and hand off

- [x] Format changed Dart files.
- [x] Run targeted analyze with no issues.
- [x] Run the full test suite: 23 tests passed.
- [x] Run full analyze; only four pre-existing infos remain outside this change.
- [ ] Commit the isolated branch and merge into `dev` after reviewing the final diff.
