import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'pages/home_page.dart';
import 'services/logger_service.dart';
import 'services/storage_service.dart';
import 'state/app_state.dart';
import 'theme/app_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // 关键：框架错误 / 异步错误只打控制台，绝不写入 LoggerService。
  // 否则：UI 断言 → 记 error 日志 → notifyListeners → 页面 rebuild
  // → 再次断言 → 疯狂吐 error，并污染持久化日志。
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    debugPrint('[flutter] ${details.exceptionAsString()}');
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    debugPrint('[async] 未捕获的异步错误: $error');
    debugPrint('$stack');
    return true;
  };

  LoggerService.instance.init();
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: LoggerService.instance),
        ChangeNotifierProvider(
          create: (_) => AppState(StorageService())..load(),
        ),
      ],
      child: const MewMewApp(),
    ),
  );
}

class MewMewApp extends StatelessWidget {
  const MewMewApp({super.key});

  @override
  Widget build(BuildContext context) {
    final themeMode = context.select<AppState, ThemeMode>((s) => s.themeMode);
    return MaterialApp(
      title: 'MewMew AI',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme(),
      darkTheme: AppTheme.darkTheme(),
      themeMode: themeMode,
      home: const HomePage(),
    );
  }
}
