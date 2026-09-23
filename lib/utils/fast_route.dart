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
    // 二级转场：上层页面推入时，本页（底层）轻微向左视差滑动并压暗一点，
    // 返回时反向恢复——推入/返回的过渡更连续，不再生硬切换。
    final parallax = secondaryAnimation.drive(
      Tween<Offset>(
        begin: Offset.zero,
        end: const Offset(-0.03, 0.0),
      ).chain(CurveTween(curve: Curves.easeOutCubic)),
    );
    final dim = secondaryAnimation.drive(
      Tween<double>(begin: 0.0, end: 0.12).chain(
        CurveTween(curve: Curves.easeOutCubic),
      ),
    );
    return SlideTransition(
      position: parallax,
      child: FadeTransition(
        opacity: Tween<double>(begin: 1.0, end: 1.0 - 0.12).animate(dim),
        child: FadeTransition(
          opacity: fade,
          child: SlideTransition(position: slide, child: child),
        ),
      ),
    );
  }
}

/// 快速路由扩展：方便使用 context.push(widget)
extension FastRouteExtension on BuildContext {
  Future<T?> push<T>(Widget widget) {
    return Navigator.of(this).push<T>(FastRoute(builder: (_) => widget));
  }
}
