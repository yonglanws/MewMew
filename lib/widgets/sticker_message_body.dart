import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import 'chat_image_preview.dart';

class StickerUnavailablePlaceholder extends StatelessWidget {
  const StickerUnavailablePlaceholder({super.key});

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.outline;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.broken_image_outlined, color: color, size: 20),
        const SizedBox(width: 8),
        Text('表情包不可用', style: TextStyle(color: color)),
      ],
    );
  }
}

class StickerMessageBody extends StatelessWidget {
  final String content;
  final String? personaId;
  final MarkdownStyleSheet styleSheet;

  const StickerMessageBody({
    super.key,
    required this.content,
    this.personaId,
    required this.styleSheet,
  });

  static final _stickerPattern = RegExp(
    r'''<sticker\s+name\s*=\s*["']([^"']+)["']\s*/\s*>''',
    caseSensitive: false,
  );

  @override
  Widget build(BuildContext context) {
    final state = context.read<AppState>();
    final matches = _stickerPattern.allMatches(content).toList();
    if (matches.isEmpty) {
      return MarkdownBody(
        data: content,
        selectable: true,
        styleSheet: styleSheet,
      );
    }
    final children = <Widget>[];
    var start = 0;
    var count = 0;
    for (final match in matches) {
      final before = content.substring(start, match.start);
      if (before.trim().isNotEmpty) {
        children.add(
          MarkdownBody(data: before, selectable: true, styleSheet: styleSheet),
        );
      }
      final name = match.group(1)!.trim();
      final sticker =
          state.stickersEnabled && count < state.maxStickersPerMessage
          ? state.pickStickerForPersonaFolder(personaId, name)
          : null;
      if (sticker != null) {
        children.add(
          ChatImagePreview(
            filePath: sticker.filePath,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.file(
                  File(sticker.filePath),
                  width: 132,
                  height: 132,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                ),
              ),
            ),
          ),
        );
        count++;
      }
      start = match.end;
    }
    final after = content.substring(start);
    if (after.trim().isNotEmpty) {
      children.add(
        MarkdownBody(data: after, selectable: true, styleSheet: styleSheet),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: children,
    );
  }
}
