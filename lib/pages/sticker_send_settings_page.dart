import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../utils/large_app_bar_title.dart';

class StickerSendSettingsPage extends StatelessWidget {
  const StickerSendSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final cs = Theme.of(context).colorScheme;
    final probability = state.stickerSendProbability;

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar.large(
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new),
              onPressed: () => Navigator.pop(context),
            ),
            title: Text('表情包发送频率', style: largeAppBarTitleStyle(context)),
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
                      title: const Text('发送概率'),
                      subtitle: const Text('每条回复中接受表情包标签的概率'),
                      trailing: Text(
                        '$probability%',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              color: cs.primary,
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                      child: Slider(
                        value: probability.toDouble(),
                        min: 0,
                        max: 100,
                        divisions: 100,
                        label: '$probability%',
                        onChanged: (value) => context
                            .read<AppState>()
                            .setStickerSendProbability(value.round()),
                      ),
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
                              '开启流式输出时不会发送表情包；关闭后该概率设置才会生效。单条回复最多发送 2 个表情包。',
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
