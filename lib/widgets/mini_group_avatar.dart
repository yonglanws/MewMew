import 'dart:io';

import 'package:flutter/material.dart';

import '../models/models.dart';
import 'persona_avatar.dart';

/// 群头像（小尺寸统一组件）：圆角容器内 2x2 均分网格（spaceEvenly），
/// 成员不再重叠错位；单成员居中单头像，空群居中群图标。
/// 主页会话列表与聊天记录管理页共用，保证两处观感一致。
class MiniGroupAvatar extends StatelessWidget {
  final List<Persona> members;
  final String? avatarPath; // 自定义群头像图片，优先展示
  final double size;

  const MiniGroupAvatar({
    super.key,
    required this.members,
    this.avatarPath,
    this.size = 44,
  });

  double get _radius => size * 0.3;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final box = ClipRRect(
      borderRadius: BorderRadius.circular(_radius),
      child: SizedBox(width: size, height: size, child: _buildBody(cs)),
    );
    // 细描边让浅色网格在浅色背景上也有清晰轮廓
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(_radius),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.4)),
      ),
      child: box,
    );
  }

  Widget _buildBody(ColorScheme cs) {
    // 自定义群头像优先
    final path = avatarPath ?? '';
    if (path.isNotEmpty && File(path).existsSync()) {
      return Image.file(
        File(path),
        fit: BoxFit.cover,
        width: size,
        height: size,
        errorBuilder: (_, __, ___) => _gridBody(cs),
      );
    }

    final shown = members.take(4).toList();

    // 空群：居中群图标
    if (shown.isEmpty) {
      return Container(
        width: size,
        height: size,
        color: cs.primaryContainer,
        child: Icon(
          Icons.group_outlined,
          size: size * 0.5,
          color: cs.onPrimaryContainer,
        ),
      );
    }

    // 单成员：居中单头像
    if (shown.length == 1) {
      return Container(
        width: size,
        height: size,
        color: cs.surfaceContainerHighest,
        child: Center(
          child: PersonaAvatar(persona: shown.first, radius: size / 2 - 2),
        ),
      );
    }

    return _gridBody(cs);
  }

  /// 2~4 成员：2x2 等分网格
  Widget _gridBody(ColorScheme cs) {
    final shown = members.take(4).toList();
    final cell = size * 0.386; // 44 → 17：与 8.5 半径匹配
    return Container(
      width: size,
      height: size,
      color: cs.surfaceContainerHighest,
      padding: EdgeInsets.all(size * 0.068),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          for (var row = 0; row < 2; row++)
            Expanded(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  for (var col = 0; col < 2; col++)
                    if (row * 2 + col < shown.length)
                      PersonaAvatar(
                        persona: shown[row * 2 + col],
                        radius: cell / 2,
                      )
                    else
                      SizedBox(width: cell, height: cell),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
