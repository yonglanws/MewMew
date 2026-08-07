import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../state/app_state.dart';
import '../utils/large_app_bar_title.dart';

class StickerSendSettingsPage extends StatelessWidget {
  const StickerSendSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final cs = Theme.of(context).colorScheme;
    final mode = state.stickerSendMode;

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar.large(
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new),
              onPressed: () => Navigator.pop(context),
            ),
            title: Text('表情包发送方式', style: largeAppBarTitleStyle(context)),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Card(
                child: Column(
                  children: [
                    ListTile(
                      contentPadding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                      leading: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: cs.tertiary.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          Icons.emoji_emotions_outlined,
                          color: cs.tertiary,
                          size: 22,
                        ),
                      ),
                      title: const Text('表情包发送方式'),
                      subtitle: const Text('人格没有单独设置时使用这里的默认方式'),
                    ),
                    for (final sendMode in StickerSendMode.values)
                      RadioListTile<StickerSendMode>(
                        value: sendMode,
                        groupValue: mode,
                        title: Text(sendMode.label),
                        subtitle: Text(sendMode.description),
                        onChanged: (nextMode) {
                          if (nextMode != null) {
                            context.read<AppState>().setStickerSendMode(
                              nextMode,
                            );
                          }
                        },
                      ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.info_outline, size: 18, color: cs.outline),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '${stickerSendModeHelpText()} 单条回复最多发送 2 个表情包。',
                              style: TextStyle(
                                color: cs.outline,
                                fontSize: 13,
                                height: 1.45,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
