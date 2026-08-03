import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';

class SettingsSwitchFab extends StatelessWidget {
  const SettingsSwitchFab({
    super.key,
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => FloatingActionButton.extended(
    onPressed: onPressed,
    icon: Icon(icon),
    label: Text(label),
  );
}

Future<void> showSettingsSwitchSheet(
  BuildContext context, {
  required String title,
  required WidgetBuilder builder,
}) => showModalBottomSheet<void>(
  context: context,
  showDragHandle: true,
  builder: (sheetContext) => Consumer<AppState>(
    builder: (context, _, __) => SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            builder(sheetContext),
          ],
        ),
      ),
    ),
  ),
);
