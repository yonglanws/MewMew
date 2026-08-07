import 'dart:math';

import '../models/models.dart';

/// Provides the persona-scoped sticker candidates used by both prompting and
/// response parsing.
class StickerSelection {
  const StickerSelection._();

  static List<StickerItem> stickersForFolderName({
    required String? personaId,
    required String folderName,
    required List<StickerGroup> stickerGroups,
    required List<StickerFolder> stickerFolders,
    required List<StickerItem> stickers,
    required List<PersonaStickerBinding> bindings,
    Set<String>? allowedFolderIds,
  }) {
    final id = personaId?.trim() ?? '';
    final name = folderName.trim();
    if (id.isEmpty || name.isEmpty) return const [];

    final groupIds = stickerGroups
        .map((group) => group.id)
        .where(
          (groupId) => bindings.any(
            (binding) => binding.personaId == id && binding.groupId == groupId,
          ),
        )
        .toSet();
    if (groupIds.isEmpty) return const [];

    final folderIds = stickerFolders
        .where(
          (folder) =>
              groupIds.contains(folder.groupId) &&
              folder.name == name &&
              (allowedFolderIds == null ||
                  allowedFolderIds.contains(folder.id)),
        )
        .map((folder) => folder.id)
        .toSet();
    if (folderIds.isEmpty) return const [];

    return stickers
        .where(
          (sticker) =>
              folderIds.contains(sticker.folderId) &&
              sticker.filePath.trim().isNotEmpty,
        )
        .toList();
  }

  static StickerItem? pickSticker(
    List<StickerItem> candidates, {
    Random? random,
  }) {
    if (candidates.isEmpty) return null;
    return candidates[(random ?? Random()).nextInt(candidates.length)];
  }

  static bool allowsSticker({required int probability, Random? random}) {
    final percent = probability.clamp(0, 100).toInt();
    if (percent <= 0) return false;
    if (percent >= 100) return true;
    return (random ?? Random()).nextInt(100) < percent;
  }

  static bool allowsStickerForMode({
    required StickerSendMode mode,
    Random? random,
  }) {
    return allowsSticker(probability: mode.gateProbability, random: random);
  }
}
