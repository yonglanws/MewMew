import 'package:flutter/material.dart';

class FastRoute<T> extends MaterialPageRoute<T> {
  FastRoute({required super.builder}) : super(maintainState: true);

  @override
  Duration get transitionDuration => const Duration(milliseconds: 240);

  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 200);

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final curvedAnimation = animation.drive(
      CurveTween(curve: Curves.easeOutCubic),
    );
    final slide = curvedAnimation.drive(
      Tween<Offset>(begin: const Offset(0.035, 0.0), end: Offset.zero),
    );
    final fade = curvedAnimation.drive(Tween<double>(begin: 0.0, end: 1.0));
    return FadeTransition(
      opacity: fade,
      child: SlideTransition(position: slide, child: child),
    );
  }
}

/// 快速路由扩展：方便使用 context.push(widget)
extension FastRouteExtension on BuildContext {
  Future<T?> push<T>(Widget widget) {
    return Navigator.of(this).push<T>(FastRoute(builder: (_) => widget));
  }
}
