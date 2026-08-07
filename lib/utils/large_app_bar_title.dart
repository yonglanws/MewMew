import 'package:flutter/material.dart';

/// 全局统一的较大标题样式，用于所有设置页 SliverAppBar.large 标题
///
/// 注意：仅作用于顶部展开的 AppBar title，不会影响分组小标题
/// （分组标题仍使用 `textTheme.titleSmall` 样式，独立于此）。
TextStyle largeAppBarTitleStyle(BuildContext context) =>
    Theme.of(context).textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.bold,
          fontSize: 22,
          letterSpacing: 0.2,
        ) ??
    const TextStyle(fontSize: 22, fontWeight: FontWeight.bold);
