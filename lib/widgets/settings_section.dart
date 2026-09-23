import 'package:flutter/material.dart';

/// 设置子页面的分区容器（与设置页/记忆设置页的 _Section 同款样式）
class SettingsSection extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const SettingsSection({super.key, required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 12, bottom: 8),
            child: Text(
              title,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Card(child: Column(children: children)),
        ],
      ),
    );
  }
}

/// 设置子页面的列表行（与设置页的 _SettingTile 同款样式）
class SettingsTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;

  const SettingsTile({
    super.key,
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    this.trailing,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final visuallyDisabled = onTap == null && trailing == null;
    final cs = Theme.of(context).colorScheme;
    return ListTile(
      enabled: onTap != null || trailing != null,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: (visuallyDisabled ? cs.outline : iconColor).withAlpha(
            (0.15 * 255).toInt(),
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(
          icon,
          color: visuallyDisabled ? cs.outline : iconColor,
          size: 22,
        ),
      ),
      title: Text(
        title,
        style: TextStyle(
          fontWeight: FontWeight.w500,
          color: visuallyDisabled ? cs.outline : null,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: TextStyle(color: visuallyDisabled ? cs.outline : null),
      ),
      trailing:
          trailing ??
          (onTap == null ? null : const Icon(Icons.chevron_right, size: 20)),
      onTap: onTap,
    );
  }
}
