import 'dart:io';

import 'package:flutter/material.dart';

void showChatImagePreview(BuildContext context, String filePath) {
  showDialog<void>(
    context: context,
    barrierColor: Colors.black87,
    builder: (_) => _ChatImagePreviewDialog(filePath: filePath),
  );
}

class ChatImagePreview extends StatelessWidget {
  final String filePath;
  final Widget child;

  const ChatImagePreview({
    super.key,
    required this.filePath,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => showChatImagePreview(context, filePath),
      child: child,
    );
  }
}

class _ChatImagePreviewDialog extends StatelessWidget {
  final String filePath;

  const _ChatImagePreviewDialog({required this.filePath});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: EdgeInsets.zero,
      child: Stack(
        fit: StackFit.expand,
        children: [
          InteractiveViewer(
            minScale: 0.8,
            maxScale: 4,
            boundaryMargin: const EdgeInsets.all(80),
            child: Center(
              child: Image.file(
                File(filePath),
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => const Icon(
                  Icons.broken_image_outlined,
                  color: Colors.white70,
                  size: 56,
                ),
              ),
            ),
          ),
          Positioned(
            top: 24,
            right: 16,
            child: IconButton(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.close_rounded),
              color: Colors.white,
              tooltip: '关闭预览',
            ),
          ),
        ],
      ),
    );
  }
}
