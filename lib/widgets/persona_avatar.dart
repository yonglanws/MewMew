import 'dart:io';

import 'package:flutter/material.dart';

import '../models/models.dart';

/// 角色头像：优先显示图片，回退到 emoji
class PersonaAvatar extends StatelessWidget {
  final Persona? persona;
  final double radius;
  final String fallbackEmoji;

  const PersonaAvatar({
    super.key,
    this.persona,
    this.radius = 16,
    this.fallbackEmoji = '🤖',
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final path = persona?.avatarPath ?? '';
    if (path.isNotEmpty) {
      return CircleAvatar(
        radius: radius,
        backgroundColor: scheme.primaryContainer,
        foregroundImage: FileImage(File(path)),
        onForegroundImageError: (_, __) {},
        child: Text(
          persona?.emoji ?? fallbackEmoji,
          style: TextStyle(fontSize: radius),
        ),
      );
    }
    return CircleAvatar(
      radius: radius,
      backgroundColor: scheme.primaryContainer,
      child: Text(
        persona?.emoji ?? fallbackEmoji,
        style: TextStyle(fontSize: radius),
      ),
    );
  }
}
