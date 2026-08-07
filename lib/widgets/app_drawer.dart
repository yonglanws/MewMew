import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../pages/dashboard_page.dart';
import '../pages/logs_page.dart';
import '../pages/settings_page.dart';
import '../pages/user_profile_page.dart';
import '../state/app_state.dart';
import '../utils/fast_route.dart';

/// 手机端侧边抽屉
class AppDrawer extends StatelessWidget {
  const AppDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final scheme = Theme.of(context).colorScheme;
    final user = state.userProfile;

    return Drawer(
      child: SafeArea(
        child: Column(
          children: [
            // 用户资料头部
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(context,
                      FastRoute(builder: (_) => const UserProfilePage()));
                },
                child: Row(
                  children: [
                    _UserAvatar(path: user.avatarPath, radius: 28),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            user.name,
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '点击编辑资料',
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(color: scheme.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                    Icon(Icons.edit_outlined,
                        size: 18, color: scheme.onSurfaceVariant),
                  ],
                ),
              ),
            ),
            const Divider(indent: 20, endIndent: 20),
            const Spacer(),
            const Divider(indent: 20, endIndent: 20),
            // 底部菜单项
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Column(
                children: [
                  _DrawerItem(
                    icon: Icons.dashboard_outlined,
                    color: scheme.primary,
                    label: '仪表盘',
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(
                          context,
                          FastRoute(
                              builder: (_) => const DashboardPage()));
                    },
                  ),
                  _DrawerItem(
                    icon: Icons.article_outlined,
                    color: scheme.onSurfaceVariant,
                    label: '日志',
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(
                          context,
                          FastRoute(
                              builder: (_) => const LogsPage()));
                    },
                  ),
                  _DrawerItem(
                    icon: Icons.settings_outlined,
                    color: scheme.onSurfaceVariant,
                    label: '设置',
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(
                          context,
                          FastRoute(
                              builder: (_) => const SettingsPage()));
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}

/// 用户头像
class _UserAvatar extends StatelessWidget {
  final String path;
  final double radius;
  const _UserAvatar({required this.path, required this.radius});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (path.isNotEmpty && File(path).existsSync()) {
      return CircleAvatar(
        radius: radius,
        backgroundColor: scheme.surfaceContainerHigh,
        backgroundImage: FileImage(File(path)),
      );
    }
    return CircleAvatar(
      radius: radius,
      backgroundColor: scheme.secondaryContainer,
      child: Icon(Icons.person, size: radius, color: scheme.onSecondaryContainer),
    );
  }
}

/// 抽屉菜单项
class _DrawerItem extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final VoidCallback onTap;

  const _DrawerItem({
    required this.icon,
    required this.color,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        child: Row(
          children: [
            Icon(icon, size: 22, color: color),
            const SizedBox(width: 14),
            Text(
              label,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
            ),
            const Spacer(),
            Icon(Icons.chevron_right_rounded,
                size: 20, color: Theme.of(context).colorScheme.outline),
          ],
        ),
      ),
    );
  }
}
