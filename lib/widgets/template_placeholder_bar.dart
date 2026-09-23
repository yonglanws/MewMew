import 'package:flutter/material.dart';

/// 模板占位符：token 为实际写入模板的替换标记，label 为中文名。
class TemplatePlaceholder {
  final String token;
  final String label;
  final String description;

  const TemplatePlaceholder(this.token, this.label, this.description);
}

/// 模板占位符工具条：占位符以芯片呈现（不再是裸文本说明），
/// 点按芯片把 token 插入到输入框光标处。
class TemplatePlaceholderBar extends StatelessWidget {
  final List<TemplatePlaceholder> placeholders;
  final TextEditingController controller;

  const TemplatePlaceholderBar({
    super.key,
    required this.placeholders,
    required this.controller,
  });

  void _insert(String token) {
    final text = controller.text;
    final selection = controller.selection;
    final start = selection.isValid
        ? selection.start.clamp(0, text.length)
        : text.length;
    final end = selection.isValid
        ? selection.end.clamp(0, text.length)
        : text.length;
    controller.value = TextEditingValue(
      text: text.replaceRange(start, end, token),
      selection: TextSelection.collapsed(offset: start + token.length),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (var i = 0; i < placeholders.length; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            Tooltip(
              message: placeholders[i].description,
              child: InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: () => _insert(placeholders[i].token),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    color: cs.surfaceContainerHighest.withValues(alpha: 0.7),
                    border: Border.all(
                      color: cs.outlineVariant.withValues(alpha: 0.5),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.data_object_rounded,
                        size: 12,
                        color: cs.primary,
                      ),
                      const SizedBox(width: 5),
                      Text(
                        placeholders[i].label,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: cs.onSurface,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          color: cs.primary.withValues(alpha: 0.10),
                        ),
                        child: Text(
                          placeholders[i].token,
                          style: TextStyle(
                            fontSize: 10,
                            fontFamily: 'monospace',
                            color: cs.primary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
