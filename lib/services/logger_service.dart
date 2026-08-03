import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 日志级别
enum LogLevel {
  debug,
  info,
  warning,
  error,
}

/// 日志级别工具方法
extension LogLevelX on LogLevel {
  String get label => switch (this) {
        LogLevel.debug => 'DEBUG',
        LogLevel.info => 'INFO',
        LogLevel.warning => 'WARNING',
        LogLevel.error => 'ERROR',
      };

  String get shortLabel => switch (this) {
        LogLevel.debug => 'D',
        LogLevel.info => 'I',
        LogLevel.warning => 'W',
        LogLevel.error => 'E',
      };

  int get severity => switch (this) {
        LogLevel.debug => 0,
        LogLevel.info => 1,
        LogLevel.warning => 2,
        LogLevel.error => 3,
      };

  String get name => switch (this) {
        LogLevel.debug => 'debug',
        LogLevel.info => 'info',
        LogLevel.warning => 'warning',
        LogLevel.error => 'error',
      };

  static LogLevel fromName(String? name) => switch (name) {
        'debug' => LogLevel.debug,
        'warning' => LogLevel.warning,
        'error' => LogLevel.error,
        _ => LogLevel.info,
      };
}

/// 一条日志记录
class LogEntry {
  final String id;
  final DateTime timestamp;
  final LogLevel level;
  final String tag;
  final String message;
  final String? error;
  final String? stackTrace;

  LogEntry({
    required this.id,
    required this.timestamp,
    required this.level,
    required this.tag,
    required this.message,
    this.error,
    this.stackTrace,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'timestamp': timestamp.toIso8601String(),
        'level': level.name,
        'tag': tag,
        'message': message,
        if (error != null) 'error': error,
        if (stackTrace != null) 'stackTrace': stackTrace,
      };

  factory LogEntry.fromJson(Map<String, dynamic> json) => LogEntry(
        id: json['id'] as String,
        timestamp: DateTime.parse(json['timestamp'] as String),
        level: LogLevelX.fromName(json['level'] as String?),
        tag: json['tag'] as String? ?? 'app',
        message: json['message'] as String? ?? '',
        error: json['error'] as String?,
        stackTrace: json['stackTrace'] as String?,
      );

  /// 格式化为可复制文本
  String toText() {
    final buf = StringBuffer(
      '${timestamp.toIso8601String()} [${level.label}] [$tag] $message',
    );
    if (error != null && error!.isNotEmpty) {
      buf.writeln();
      buf.write('  错误: $error');
    }
    if (stackTrace != null && stackTrace!.isNotEmpty) {
      buf.writeln();
      buf.write('  堆栈:\n$stackTrace');
    }
    return buf.toString();
  }

  /// 格式化为 Markdown 表格行
  String toMarkdownRow() {
    final time = DateFormat('yyyy-MM-dd HH:mm:ss.SSS').format(timestamp);
    var msg = message.replaceAll('|', '\\|').replaceAll('\n', ' ');
    if (error != null && error!.isNotEmpty) {
      msg += '  \n  > 错误: ${error!.replaceAll('|', '\\|')}';
    }
    return '| $time | ${level.label} | $tag | $msg |';
  }
}

/// 全局日志服务（单例 + ChangeNotifier，UI 可监听刷新）
///
/// 内存保留最近 [maxInMemory] 条日志；持久化保留最近 [maxPersisted] 条
/// 到 SharedPreferences，便于跨重启查看。
class LoggerService extends ChangeNotifier {
  LoggerService._();
  static final LoggerService instance = LoggerService._();

  static const _kPrefsKey = 'app_logs';
  static const int maxInMemory = 800;
  static const int maxPersisted = 200;
  // 单条 message/error/stack 上限，防止异常文本把日志打爆
  static const int maxFieldChars = 2000;
  // 持久化字符串过大视为损坏（之前 error 洪水会写出数 MB 垃圾）
  static const int maxPersistedRawChars = 500 * 1024;

  final List<LogEntry> _logs = [];
  List<LogEntry> get logs => List.unmodifiable(_logs);

  /// 日志数量（避免 `logs.length` 分配 UnmodifiableListView 包装器）
  int get logCount => _logs.length;

  /// 当前最低显示级别（默认 debug，即全部显示）
  LogLevel minLevel = LogLevel.debug;

  /// 是否将日志同时输出到控制台（debugPrint）
  bool enableConsoleOutput = true;

  SharedPreferences? _prefs;
  bool _initialized = false;
  bool get isInitialized => _initialized;

  /// 防抖通知：高频日志批量刷新 UI，避免每条都触发重建
  Timer? _notifyTimer;
  Timer? _persistTimer;
  bool _persistQueued = false;

  /// 最近一条日志指纹，用于抑制短时间内完全相同的 error 洪水
  String? _lastFingerprint;
  DateTime? _lastFingerprintAt;
  int _suppressedCount = 0;
  bool _isLogging = false; // 防重入：log 内部再 log 直接丢弃

  Future<void> init() async {
    if (_initialized) return;
    _prefs = await SharedPreferences.getInstance();
    await _loadFromDisk();
    _initialized = true;
    log(
      LogLevel.info,
      'app',
      '日志系统已初始化，载入 ${_logs.length} 条历史日志',
    );
  }

  Future<void> _loadFromDisk() async {
    final raw = _prefs?.getString(_kPrefsKey);
    if (raw == null) return;
    // 损坏/过大的持久化数据直接清空，避免启动后立刻卡死
    if (raw.length > maxPersistedRawChars || raw.contains('\u0000')) {
      debugPrint('持久化日志异常（${raw.length} chars），已清空');
      await _prefs?.remove(_kPrefsKey);
      return;
    }
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      final loaded = <LogEntry>[];
      for (final item in list) {
        if (item is! Map<String, dynamic>) continue;
        final entry = LogEntry.fromJson(item);
        // 丢弃明显异常的条目（超长 message = 洪水残留）
        if (entry.message.length > maxFieldChars * 2) continue;
        if ((entry.error?.length ?? 0) > maxFieldChars * 2) continue;
        if ((entry.stackTrace?.length ?? 0) > maxFieldChars * 4) continue;
        loaded.add(entry);
      }
      if (loaded.length > maxInMemory) {
        loaded.removeRange(0, loaded.length - maxInMemory);
      }
      _logs
        ..clear()
        ..addAll(loaded);
      // 若过滤掉大量异常条目，写回干净数据
      if (loaded.length != list.length) {
        await _persist();
      }
    } catch (e) {
      debugPrint('载入日志失败，已清空: $e');
      await _prefs?.remove(_kPrefsKey);
    }
  }

  Future<void> _persist() async {
    if (_prefs == null) return;
    try {
      final toSave = _logs.length > maxPersisted
          ? _logs.sublist(_logs.length - maxPersisted)
          : List<LogEntry>.from(_logs);
      final encoded = jsonEncode(toSave.map((e) => e.toJson()).toList());
      if (encoded.length > maxPersistedRawChars) {
        // 仍过大：只留最近 50 条
        final tiny = toSave.length > 50
            ? toSave.sublist(toSave.length - 50)
            : toSave;
        final small = jsonEncode(tiny.map((e) => e.toJson()).toList());
        await _prefs!.setString(_kPrefsKey, small);
        return;
      }
      await _prefs!.setString(_kPrefsKey, encoded);
    } catch (e) {
      debugPrint('持久化日志失败: $e');
    }
  }

  static String _clip(String? s, [int max = maxFieldChars]) {
    if (s == null) return '';
    if (s.length <= max) return s;
    return '${s.substring(0, max)}…(截断 ${s.length - max} 字)';
  }

  /// 记录一条日志
  void log(
    LogLevel level,
    String tag,
    String message, {
    Object? error,
    StackTrace? stackTrace,
  }) {
    // 防重入：任何 log 路径上再发生 log，直接丢弃，打断反馈环
    if (_isLogging) return;
    if (level.severity < minLevel.severity) return;

    _isLogging = true;
    try {
      final msg = _clip(message);
      final errStr = error == null ? null : _clip(error.toString());
      final stStr =
          stackTrace == null ? null : _clip(stackTrace.toString(), maxFieldChars * 2);

      // 抑制 2 秒内完全相同的 warning/error
      if (level.severity >= LogLevel.warning.severity) {
        final fp = '$level|$tag|$msg|${errStr ?? ''}';
        final now = DateTime.now();
        if (_lastFingerprint == fp &&
            _lastFingerprintAt != null &&
            now.difference(_lastFingerprintAt!) < const Duration(seconds: 2)) {
          _suppressedCount++;
          return;
        }
        if (_suppressedCount > 0) {
          final suppressed = _suppressedCount;
          _suppressedCount = 0;
          _logs.add(LogEntry(
            id: '${now.microsecondsSinceEpoch}_sup',
            timestamp: now,
            level: LogLevel.warning,
            tag: 'app',
            message: '已抑制 $suppressed 条重复日志',
          ));
        }
        _lastFingerprint = fp;
        _lastFingerprintAt = now;
      }

      final entry = LogEntry(
        id: '${DateTime.now().microsecondsSinceEpoch}_${_logs.length}',
        timestamp: DateTime.now(),
        level: level,
        tag: tag,
        message: msg,
        error: errStr,
        stackTrace: stStr,
      );

      _logs.add(entry);
      if (_logs.length > maxInMemory) {
        _logs.removeRange(0, _logs.length - maxInMemory);
      }

      if (enableConsoleOutput) {
        _printToConsole(entry);
      }

      _scheduleNotify();
    } finally {
      _isLogging = false;
    }
  }

  void _printToConsole(LogEntry e) {
    final prefix = '[${e.level.shortLabel}] [${e.tag}]';
    debugPrint('$prefix ${e.message}');
    if (e.error != null) debugPrint('$prefix 错误: ${e.error}');
    if (e.stackTrace != null) debugPrint('$prefix 堆栈:\n${e.stackTrace}');
  }

  /// 防抖通知：50ms 内多条日志合并为一次 UI 重建
  void _scheduleNotify() {
    if (_notifyTimer?.isActive == true) {
      return;
    }
    _notifyTimer = Timer(const Duration(milliseconds: 50), () {
      _notifyTimer = null;
      notifyListeners();
      _schedulePersist();
    });
  }

  void _schedulePersist() {
    _persistQueued = true;
    if (_persistTimer?.isActive == true) return;
    _persistTimer = Timer(const Duration(milliseconds: 180), () {
      _persistTimer = null;
      if (!_persistQueued) return;
      _persistQueued = false;
      WidgetsBinding.instance.addPostFrameCallback((_) => _persist());
    });
  }

  /// 设置最低显示级别（不影响已记录的日志，仅影响后续过滤与记录）
  void setMinLevel(LogLevel level) {
    minLevel = level;
    notifyListeners();
  }

  /// 清空所有日志
  Future<void> clear() async {
    _logs.clear();
    notifyListeners();
    await _prefs?.remove(_kPrefsKey);
  }

  /// 导出全部日志为纯文本
  String exportAsText() {
    return _logs.map((e) => e.toText()).join('\n');
  }

  /// 导出为 Markdown 表格
  String exportAsMarkdown() {
    final buf = StringBuffer();
    buf.writeln('# 应用日志导出');
    buf.writeln();
    buf.writeln('- 导出时间：${DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.now())}');
    buf.writeln('- 日志总数：${_logs.length} 条');
    final counts = levelCounts;
    buf.writeln('- 分布：DEBUG ${counts[LogLevel.debug]} · INFO ${counts[LogLevel.info]} · WARNING ${counts[LogLevel.warning]} · ERROR ${counts[LogLevel.error]}');
    buf.writeln();
    buf.writeln('| 时间 | 级别 | 标签 | 消息 |');
    buf.writeln('|------|------|------|------|');
    for (final e in _logs) {
      buf.writeln(e.toMarkdownRow());
    }
    return buf.toString();
  }

  /// 导出为 JSON 字符串
  String exportAsJson() {
    return const JsonEncoder.withIndent('  ').convert(
      _logs.map((e) => e.toJson()).toList(),
    );
  }

  /// 导出为文件，返回文件路径
  Future<File> exportToFile(LogExportFormat format) async {
    final dir = await getTemporaryDirectory();
    final stamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
    final ext = switch (format) {
      LogExportFormat.text => 'txt',
      LogExportFormat.markdown => 'md',
      LogExportFormat.json => 'json',
    };
    final content = switch (format) {
      LogExportFormat.text => exportAsText(),
      LogExportFormat.markdown => exportAsMarkdown(),
      LogExportFormat.json => exportAsJson(),
    };
    final file = File('${dir.path}/mewmew_logs_$stamp.$ext');
    await file.writeAsString(content);
    return file;
  }

  /// 按条件过滤日志
  ///
  /// [level] 单一级别过滤（与 [minLevel] 互斥，[level] 优先）
  /// [minLevel] 最低级别过滤
  /// [tag] 标签过滤（传 '全部' 或 null 表示不过滤）
  /// [keyword] 关键词（同时匹配 message/error/tag）
  /// [since] 起始时间
  /// [until] 结束时间
  List<LogEntry> filter({
    LogLevel? level,
    LogLevel? minLevel,
    String? tag,
    String? keyword,
    DateTime? since,
    DateTime? until,
  }) {
    final min = minLevel?.severity ?? 0;
    final kw = keyword?.trim().toLowerCase();
    return _logs.where((e) {
      if (level != null && e.level != level) return false;
      if (level == null && e.level.severity < min) return false;
      if (tag != null && tag != '全部' && e.tag != tag) return false;
      if (since != null && e.timestamp.isBefore(since)) return false;
      if (until != null && e.timestamp.isAfter(until)) return false;
      if (kw != null && kw.isNotEmpty) {
        final hay = '${e.message} ${e.error ?? ''} ${e.tag}'.toLowerCase();
        if (!hay.contains(kw)) return false;
      }
      return true;
    }).toList();
  }

  /// 各 tag 的统计（按数量降序）
  Map<String, int> get tagCounts {
    final counts = <String, int>{};
    for (final e in _logs) {
      counts[e.tag] = (counts[e.tag] ?? 0) + 1;
    }
    final sorted = counts.keys.toList()
      ..sort((a, b) => counts[b]!.compareTo(counts[a]!));
    return {for (final k in sorted) k: counts[k]!};
  }

  /// 已使用的标签集合（按出现频率排序）
  List<String> get availableTags {
    final counts = <String, int>{};
    for (final e in _logs) {
      counts[e.tag] = (counts[e.tag] ?? 0) + 1;
    }
    final entries = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return entries.map((e) => e.key).toList();
  }

  /// 各级别日志计数
  Map<LogLevel, int> get levelCounts {
    final counts = <LogLevel, int>{
      LogLevel.debug: 0,
      LogLevel.info: 0,
      LogLevel.warning: 0,
      LogLevel.error: 0,
    };
    for (final e in _logs) {
      counts[e.level] = (counts[e.level] ?? 0) + 1;
    }
    return counts;
  }

  @override
  void dispose() {
    _notifyTimer?.cancel();
    _persistTimer?.cancel();
    super.dispose();
  }
}

/// 便捷日志 API
///
/// 用法：
/// ```dart
/// import '../services/logger_service.dart';
/// log.d('chat', '用户发送消息: $text');
/// log.i('api', 'API 请求开始');
/// log.w('memory', '嵌入向量长度不匹配');
/// log.e('api', '请求失败', error: e, stackTrace: s);
/// ```
class log {
  const log._();

  static void d(String tag, String message) =>
      LoggerService.instance.log(LogLevel.debug, tag, message);

  static void i(String tag, String message) =>
      LoggerService.instance.log(LogLevel.info, tag, message);

  static void w(String tag, String message, {Object? error}) =>
      LoggerService.instance.log(LogLevel.warning, tag, message, error: error);

  static void e(
    String tag,
    String message, {
    Object? error,
    StackTrace? stackTrace,
  }) =>
      LoggerService.instance
          .log(LogLevel.error, tag, message, error: error, stackTrace: stackTrace);
}

/// 日志导出格式
enum LogExportFormat {
  text,
  markdown,
  json;

  String get label => switch (this) {
        LogExportFormat.text => '纯文本 (.txt)',
        LogExportFormat.markdown => 'Markdown (.md)',
        LogExportFormat.json => 'JSON (.json)',
      };
}
