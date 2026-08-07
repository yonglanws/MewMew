import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../models/models.dart';
import '../services/ai_service.dart';
import '../services/logger_service.dart';
import '../state/app_state.dart';

const _uuid = Uuid();

/// API 配置管理页面
class ApiConfigPage extends StatelessWidget {
  const ApiConfigPage({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    return Scaffold(
      appBar: AppBar(title: const Text('API 配置')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showEditSheet(context),
        icon: const Icon(Icons.add),
        label: const Text('添加接口'),
      ),
      body: state.apiConfigs.isEmpty
          ? const _EmptyHint(
              icon: Icons.cloud_off_outlined,
              text: '暂无 API 配置\n点击右下角按钮添加 AI 服务接口',
            )
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
              itemCount: state.apiConfigs.length,
              itemBuilder: (context, i) {
                final config = state.apiConfigs[i];
                final isActive = config.id == state.activeApi?.id;
                return Card(
                  elevation: 0,
                  margin: const EdgeInsets.only(bottom: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: BorderSide(
                      color: isActive
                          ? Theme.of(context).colorScheme.primary
                          : Theme.of(context).colorScheme.outlineVariant,
                    ),
                  ),
                  child: ListTile(
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    leading: CircleAvatar(
                      backgroundColor: isActive
                          ? Theme.of(context).colorScheme.primaryContainer
                          : Theme.of(context).colorScheme.surfaceContainerHighest,
                      child: Icon(
                        Icons.api,
                        color: isActive
                            ? Theme.of(context).colorScheme.onPrimaryContainer
                            : Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    title: Row(
                      children: [
                        Flexible(child: Text(config.name)),
                        if (isActive) ...[
                          const SizedBox(width: 8),
                          Chip(
                            label: const Text('使用中'),
                            labelStyle:
                                Theme.of(context).textTheme.labelSmall,
                            padding: EdgeInsets.zero,
                            visualDensity: VisualDensity.compact,
                          ),
                        ],
                      ],
                    ),
                    subtitle: Text('${config.model}\n${config.baseUrl}',
                        maxLines: 2, overflow: TextOverflow.ellipsis),
                    trailing: PopupMenuButton<String>(
                      onSelected: (v) {
                        switch (v) {
                          case 'use':
                            context.read<AppState>().setActiveApi(config.id);
                          case 'edit':
                            _showEditSheet(context, config: config);
                          case 'delete':
                            _confirmDelete(context, config);
                        }
                      },
                      itemBuilder: (_) => [
                        if (!isActive)
                          const PopupMenuItem(
                              value: 'use', child: Text('设为当前接口')),
                        const PopupMenuItem(value: 'edit', child: Text('编辑')),
                        const PopupMenuItem(value: 'delete', child: Text('删除')),
                      ],
                    ),
                    onTap: () => context.read<AppState>().setActiveApi(config.id),
                  ),
                );
              },
            ),
    );
  }

  void _confirmDelete(BuildContext context, ApiConfig config) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除接口'),
        content: Text('确定删除「${config.name}」吗？'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(
            onPressed: () {
              context.read<AppState>().deleteApi(config.id);
              Navigator.pop(ctx);
            },
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }

  void _showEditSheet(BuildContext context, {ApiConfig? config}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _ApiEditSheet(config: config),
    );
  }
}

class _ApiEditSheet extends StatefulWidget {
  final ApiConfig? config;
  const _ApiEditSheet({this.config});

  @override
  State<_ApiEditSheet> createState() => _ApiEditSheetState();
}

class _ApiEditSheetState extends State<_ApiEditSheet> {
  final _formKey = GlobalKey<FormState>();
  final _scrollController = ScrollController();
  late final _name =
      TextEditingController(text: widget.config?.name ?? '');
  late final _baseUrl = TextEditingController(
      text: widget.config?.baseUrl ?? '');
  late final _apiKey =
      TextEditingController(text: widget.config?.apiKey ?? '');
  late final _model =
      TextEditingController(text: widget.config?.model ?? '');
  late double _temperature = widget.config?.temperature ?? 0.7;
  bool _obscureKey = false;
  bool _loadingModels = false;
  bool _testing = false;
  // 测试结果（内联展示）
  bool? _testSuccess;
  String? _testMessage;
  String? _testDetail;

  @override
  void dispose() {
    _name.dispose();
    _baseUrl.dispose();
    _apiKey.dispose();
    _model.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  /// 测试完成后自动滚动到结果位置
  void _scrollToResult() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _fetchModels() async {
    final baseUrl = _baseUrl.text.trim();
    final apiKey = _apiKey.text.trim();
    if (!baseUrl.startsWith('http') || apiKey.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先填写 Base URL 和 API Key')),
      );
      return;
    }
    setState(() => _loadingModels = true);
    try {
      final models = await AiService.listModels(
          baseUrl: baseUrl, apiKey: apiKey);
      if (!mounted) return;
      if (models.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('该接口未返回任何模型')),
        );
      } else {
        _showModelPicker(models);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('获取失败：$e')),
      );
    } finally {
      if (mounted) setState(() => _loadingModels = false);
    }
  }

  /// 测试 API 连接：发送一条简单消息验证模型可用性
  Future<void> _testConnection() async {
    final baseUrl = _baseUrl.text.trim();
    final apiKey = _apiKey.text.trim();
    final model = _model.text.trim();
    if (!baseUrl.startsWith('http') || apiKey.isEmpty || model.isEmpty) {
      setState(() {
        _testSuccess = false;
        _testMessage = '请先填写 Base URL、API Key 和模型名称';
        _testDetail = null;
      });
      _scrollToResult();
      return;
    }
    // 清除旧结果，开始测试
    setState(() {
      _testing = true;
      _testSuccess = null;
      _testMessage = null;
      _testDetail = null;
    });
    debugPrint('[API测试] 开始测试: baseUrl=$baseUrl, model=$model');
    log.i('api', 'API 连通性测试开始：baseUrl=$baseUrl, model=$model');
    try {
      final cfg = ApiConfig(
        id: 'test',
        name: 'test',
        baseUrl: baseUrl,
        apiKey: apiKey,
        model: model,
      );
      final start = DateTime.now();
      final resp = await AiService.chat(
        config: cfg,
        messages: [
          {'role': 'user', 'content': '请回复"ok"两个字符'}
        ],
      ).timeout(const Duration(seconds: 30));
      final elapsed = DateTime.now().difference(start).inMilliseconds;
      final reply = (resp.content ?? '').trim();
      debugPrint('[API测试] 成功: ${elapsed}ms, reply=$reply');
      log.i('api', 'API 测试成功：${elapsed}ms 回复="$reply" '
          'token=${resp.inputTokens + resp.outputTokens}');
      if (!mounted) return;
      setState(() {
        _testSuccess = true;
        _testMessage =
            '耗时 ${elapsed}ms · 消耗 token ${resp.inputTokens + resp.outputTokens}';
        _testDetail = reply.isEmpty ? '(空回复)' : reply;
      });
      _scrollToResult();
    } catch (e) {
      debugPrint('[API测试] 失败: $e');
      log.e('api', 'API 测试失败', error: e);
      if (!mounted) return;
      setState(() {
        _testSuccess = false;
        _testMessage = '连接失败';
        _testDetail = e.toString();
      });
      _scrollToResult();
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  /// 构建测试结果卡片（内联展示，避免 Dialog 被 BottomSheet 遮挡）
  Widget _buildTestResult() {
    final cs = Theme.of(context).colorScheme;
    final success = _testSuccess ?? false;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: success
            ? cs.primaryContainer.withValues(alpha: 0.3)
            : cs.errorContainer.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: success
              ? cs.primary.withValues(alpha: 0.4)
              : cs.error.withValues(alpha: 0.4),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(success ? Icons.check_circle : Icons.cancel,
                  color: success ? Colors.green : cs.error, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  success ? '连接成功' : '连接失败',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: success ? cs.primary : cs.error,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(_testMessage!, style: const TextStyle(fontSize: 13)),
          if (_testDetail != null && _testDetail!.isNotEmpty) ...[
            const SizedBox(height: 6),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(6),
              ),
              child: SelectableText(
                _testDetail!,
                style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
              ),
            ),
          ],
        ],
      ),
    );
  }

  void _showModelPicker(List<String> models) {
    final current = _model.text.trim();
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) {
        final query = ValueNotifier('');
        return Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
                child: Row(
                  children: [
                    Text('选择模型（${models.length}）',
                        style: Theme.of(context).textTheme.titleMedium),
                    const Spacer(),
                    TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text('关闭')),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: TextField(
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search, size: 20),
                    hintText: '搜索模型…',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (v) => query.value = v,
                ),
              ),
              const SizedBox(height: 8),
              Flexible(
                child: ValueListenableBuilder<String>(
                  valueListenable: query,
                  builder: (_, q, __) {
                    final filtered = q.isEmpty
                        ? models
                        : models
                            .where((m) => m.toLowerCase().contains(q.toLowerCase()))
                            .toList();
                    return ListView.builder(
                      shrinkWrap: true,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      itemCount: filtered.length,
                      itemBuilder: (_, i) {
                        final m = filtered[i];
                        final selected = m == current;
                        return ListTile(
                          leading: Icon(
                            selected ? Icons.check_circle : Icons.memory,
                            color: selected
                                ? Theme.of(context).colorScheme.primary
                                : null,
                          ),
                          title: Text(m,
                              style: const TextStyle(fontFamily: 'monospace')),
                          dense: true,
                          onTap: () {
                            _model.text = m;
                            Navigator.pop(ctx);
                          },
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _sectionTitle(BuildContext context, String title, IconData icon) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        Icon(icon, size: 16, color: cs.primary),
        const SizedBox(width: 6),
        Text(
          title,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w700,
                color: cs.primary,
              ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          controller: _scrollController,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                widget.config == null ? '添加 API 接口' : '编辑 API 接口',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _name,
                decoration: const InputDecoration(
                  labelText: '名称',
                  border: OutlineInputBorder(),
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? '请输入名称' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _baseUrl,
                decoration: const InputDecoration(
                  labelText: 'Base URL',
                  border: OutlineInputBorder(),
                ),
                validator: (v) =>
                    (v == null || !v.trim().startsWith('http'))
                        ? '请输入有效的 URL'
                        : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _apiKey,
                obscureText: _obscureKey,
                decoration: InputDecoration(
                  labelText: 'API Key',
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    icon: Icon(_obscureKey
                        ? Icons.visibility_off
                        : Icons.visibility),
                    onPressed: () =>
                        setState(() => _obscureKey = !_obscureKey),
                  ),
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? '请输入 API Key' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _model,
                decoration: InputDecoration(
                  labelText: '模型名称',
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    tooltip: '获取模型列表',
                    icon: _loadingModels
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.download_outlined),
                    onPressed: _loadingModels ? null : _fetchModels,
                  ),
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? '请输入模型名称' : null,
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  TextButton.icon(
                    onPressed: _loadingModels ? null : _fetchModels,
                    icon: Icon(_loadingModels ? null : Icons.cloud_download_outlined, size: 18),
                    label: Text(_loadingModels ? '获取中…' : '获取模型列表'),
                  ),
                  const Spacer(),
                  FilledButton.tonalIcon(
                    onPressed: _testing ? null : _testConnection,
                    icon: _testing
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.network_check, size: 18),
                    label: Text(_testing ? '测试中…' : '测试连接'),
                  ),
                ],
              ),
              // 测试结果内联展示（避免 Dialog 被 BottomSheet 遮挡）
              if (_testMessage != null) ...[
                const SizedBox(height: 12),
                _buildTestResult(),
              ],
              const SizedBox(height: 20),
              _sectionTitle(context, '生成参数', Icons.tune),
              const SizedBox(height: 8),
              Text('温度 (Temperature): ${_temperature.toStringAsFixed(1)}',
                  style: Theme.of(context).textTheme.labelLarge),
              Slider(
                value: _temperature,
                min: 0,
                max: 2,
                divisions: 20,
                label: _temperature.toStringAsFixed(1),
                onChanged: (v) => setState(() => _temperature = v),
              ),
              const SizedBox(height: 8),
              FilledButton(
                onPressed: () {
                  if (!_formKey.currentState!.validate()) return;
                  final config = ApiConfig(
                    id: widget.config?.id ?? _uuid.v4(),
                    name: _name.text.trim(),
                    baseUrl: _baseUrl.text.trim(),
                    apiKey: _apiKey.text.trim(),
                    model: _model.text.trim(),
                    temperature: _temperature,
                  );
                  context.read<AppState>().addOrUpdateApi(config);
                  Navigator.pop(context);
                },
                child: const Text('保存'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyHint extends StatelessWidget {
  final IconData icon;
  final String text;
  const _EmptyHint({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon,
              size: 64, color: Theme.of(context).colorScheme.outline),
          const SizedBox(height: 16),
          Text(
            text,
            textAlign: TextAlign.center,
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: Theme.of(context).colorScheme.outline),
          ),
        ],
      ),
    );
  }
}
