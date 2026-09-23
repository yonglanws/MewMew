import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../models/models.dart';
import '../services/ai_service.dart';
import '../services/logger_service.dart';
import '../state/app_state.dart';
import '../utils/fast_route.dart';

const _uuid = Uuid();

/// API 配置页：供应商 - 模型两级结构。
/// 先配置供应商（Base URL + API Key），再在供应商详情里一并添加多个模型
/// （如 zhipu 下的 glm-5.3、glm-5.2），无需为每个模型重复填写供应商信息。
class ApiConfigPage extends StatelessWidget {
  const ApiConfigPage({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('API 配置')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _addProvider(context),
        icon: const Icon(Icons.add),
        label: const Text('添加供应商'),
      ),
      body: state.apiConfigs.isEmpty
          ? const _EmptyHint(
              icon: Icons.cloud_off_outlined,
              text: '暂无供应商\n点击右下角按钮先配置供应商，再添加模型',
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
                          ? cs.primary
                          : cs.outlineVariant.withValues(alpha: 0.6),
                    ),
                  ),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    leading: CircleAvatar(
                      backgroundColor: isActive
                          ? cs.primaryContainer
                          : cs.surfaceContainerHighest,
                      child: Icon(
                        Icons.cloud_outlined,
                        color: isActive
                            ? cs.onPrimaryContainer
                            : cs.onSurfaceVariant,
                      ),
                    ),
                    title: Row(
                      children: [
                        Flexible(child: Text(config.name)),
                        if (isActive) ...[
                          const SizedBox(width: 8),
                          Chip(
                            label: const Text('使用中'),
                            labelStyle: Theme.of(context).textTheme.labelSmall,
                            padding: EdgeInsets.zero,
                            visualDensity: VisualDensity.compact,
                          ),
                        ],
                      ],
                    ),
                    subtitle: Text(
                      config.models.isEmpty
                          ? '${config.baseUrl}\n尚未添加模型'
                          : '${config.models.length} 个模型 · 当前 ${config.model.isEmpty ? '未选择' : config.model}\n${config.baseUrl}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    // 跳转符号：进入供应商详情管理模型
                    trailing: Icon(
                      Icons.chevron_right_rounded,
                      color: cs.onSurfaceVariant.withValues(alpha: 0.6),
                    ),
                    onTap: () => Navigator.push(
                      context,
                      FastRoute(builder: (_) => _ProviderDetailPage(config)),
                    ),
                  ),
                );
              },
            ),
    );
  }

  void _addProvider(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _ProviderEditSheet(),
    );
  }
}

/// 供应商详情页：编辑供应商信息 + 一并管理多个模型档位
class _ProviderDetailPage extends StatefulWidget {
  final ApiConfig config;
  const _ProviderDetailPage(this.config);

  @override
  State<_ProviderDetailPage> createState() => _ProviderDetailPageState();
}

class _ProviderDetailPageState extends State<_ProviderDetailPage> {
  bool _testing = false;
  bool? _testSuccess;
  String? _testMessage;
  String? _testDetail;

  ApiConfig get _config =>
      context.read<AppState>().apiConfigs.firstWhere(
            (c) => c.id == widget.config.id,
            orElse: () => widget.config,
          );

  Future<void> _testConnection() async {
    final config = _config;
    final model = config.model.trim();
    if (model.isEmpty) {
      setState(() {
        _testSuccess = false;
        _testMessage = '请先添加并选择一个模型';
        _testDetail = null;
      });
      return;
    }
    setState(() {
      _testing = true;
      _testSuccess = null;
      _testMessage = null;
      _testDetail = null;
    });
    Log.i('api', 'API 连通性测试开始：${config.baseUrl} / $model');
    try {
      final start = DateTime.now();
      final resp = await AiService.chat(
        config: config,
        messages: [
          {'role': 'user', 'content': '请回复"ok"两个字符'},
        ],
      ).timeout(const Duration(seconds: 30));
      final elapsed = DateTime.now().difference(start).inMilliseconds;
      final reply = (resp.content ?? '').trim();
      Log.i(
        'api',
        'API 测试成功：${elapsed}ms 回复="$reply" '
            'token=${resp.inputTokens + resp.outputTokens}',
      );
      if (!mounted) return;
      setState(() {
        _testSuccess = true;
        _testMessage =
            '耗时 ${elapsed}ms · 消耗 token ${resp.inputTokens + resp.outputTokens}';
        _testDetail = reply.isEmpty ? '(空回复)' : reply;
      });
    } catch (e) {
      Log.e('api', 'API 测试失败', error: e);
      if (!mounted) return;
      setState(() {
        _testSuccess = false;
        _testMessage = '连接失败';
        _testDetail = e.toString();
      });
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  Future<void> _editProvider() async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _ProviderEditSheet(config: _config),
    );
    if (mounted) setState(() {});
  }

  void _addModels() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _AddModelsSheet(config: _config),
    );
  }

  void _confirmDeleteProvider() {
    final config = _config;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除供应商'),
        content: Text(
          '确定删除「${config.name}」吗？其下 ${config.models.length} 个模型配置将一并移除。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              context.read<AppState>().deleteApi(config.id);
              Navigator.pop(ctx); // 关闭对话框
              Navigator.pop(context); // 返回列表页
            },
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final cs = Theme.of(context).colorScheme;
    final config = _config;
    final isActiveProvider = config.id == state.activeApi?.id;
    final models = config.models;

    return Scaffold(
      appBar: AppBar(
        title: Text(config.name),
        actions: [
          IconButton(
            tooltip: '编辑供应商信息',
            icon: const Icon(Icons.edit_outlined),
            onPressed: _editProvider,
          ),
          IconButton(
            tooltip: '删除供应商',
            icon: const Icon(Icons.delete_outline),
            onPressed: _confirmDeleteProvider,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addModels,
        icon: const Icon(Icons.add),
        label: const Text('添加模型'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
        children: [
          // —— 供应商信息卡 ——
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: cs.surfaceContainerLow,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: cs.outlineVariant.withValues(alpha: 0.5),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.cloud_outlined, size: 18, color: cs.primary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        config.name,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    if (isActiveProvider)
                      Chip(
                        label: const Text('使用中'),
                        labelStyle: Theme.of(context).textTheme.labelSmall,
                        padding: EdgeInsets.zero,
                        visualDensity: VisualDensity.compact,
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  config.baseUrl,
                  style: TextStyle(
                    fontSize: 12,
                    fontFamily: 'monospace',
                    color: cs.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    TextButton.icon(
                      onPressed: _editProvider,
                      icon: const Icon(Icons.edit_outlined, size: 16),
                      label: const Text('编辑信息'),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.tonalIcon(
                      onPressed: _testing ? null : _testConnection,
                      icon: _testing
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                              ),
                            )
                          : const Icon(Icons.network_check, size: 16),
                      label: Text(_testing ? '测试中…' : '测试当前模型'),
                    ),
                  ],
                ),
                if (_testMessage != null) ...[
                  const SizedBox(height: 8),
                  _buildTestResult(cs),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),
          // —— 模型列表 ——
          Row(
            children: [
              Icon(Icons.memory_outlined, size: 16, color: cs.primary),
              const SizedBox(width: 6),
              Text(
                '模型（${models.length}）',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: cs.onSurface,
                ),
              ),
              const Spacer(),
              Text(
                '点按模型设为当前使用',
                style: TextStyle(fontSize: 11, color: cs.outline),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (models.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: cs.surfaceContainerLowest,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: cs.outlineVariant.withValues(alpha: 0.5),
                ),
              ),
              child: Column(
                children: [
                  Icon(
                    Icons.memory_outlined,
                    size: 32,
                    color: cs.outline.withValues(alpha: 0.6),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '还没有模型\n点右下角「添加模型」，可一键拉取供应商全部模型',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, color: cs.outline),
                  ),
                ],
              ),
            )
          else
            ...[
              for (var i = 0; i < models.length; i++) ...[
                if (i > 0) const SizedBox(height: 8),
                _ModelRow(
                  config: config,
                  entry: models[i],
                  isActive:
                      isActiveProvider && config.model == models[i].model,
                  onDelete: () => context
                      .read<AppState>()
                      .deleteModel(config.id, models[i].id),
                  onSelect: () =>
                      context.read<AppState>().setActiveModel(
                        config.id,
                        models[i].id,
                      ),
                ),
              ],
            ],
        ],
      ),
    );
  }

  Widget _buildTestResult(ColorScheme cs) {
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
              Icon(
                success ? Icons.check_circle : Icons.cancel,
                color: success ? Colors.green : cs.error,
                size: 18,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  success ? '连接成功' : '连接失败',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    color: success ? cs.primary : cs.error,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(_testMessage!, style: const TextStyle(fontSize: 12)),
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
                style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// 单个模型档位行：点按设为当前使用（供应商同步激活）
class _ModelRow extends StatelessWidget {
  final ApiConfig config;
  final ApiModelEntry entry;
  final bool isActive;
  final VoidCallback onDelete;
  final VoidCallback onSelect;

  const _ModelRow({
    required this.config,
    required this.entry,
    required this.isActive,
    required this.onDelete,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: isActive
          ? cs.primaryContainer.withValues(alpha: 0.25)
          : cs.surfaceContainerLow,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: isActive ? null : onSelect,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isActive
                  ? cs.primary.withValues(alpha: 0.6)
                  : cs.outlineVariant.withValues(alpha: 0.5),
            ),
          ),
          child: Row(
            children: [
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 160),
                transitionBuilder: (child, animation) => ScaleTransition(
                  scale: animation,
                  child: child,
                ),
                child: Icon(
                  isActive
                      ? Icons.check_circle_rounded
                      : Icons.radio_button_unchecked,
                  key: ValueKey(isActive),
                  size: 20,
                  color: isActive ? cs.primary : cs.outline,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.model,
                      style: TextStyle(
                        fontSize: 14,
                        fontFamily: 'monospace',
                        fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                        color: cs.onSurface,
                      ),
                    ),
                    if (entry.label.isNotEmpty)
                      Text(
                        entry.label,
                        style: TextStyle(
                          fontSize: 11,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
              if (isActive)
                Text(
                  '使用中',
                  style: TextStyle(fontSize: 11, color: cs.primary),
                )
              else
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: '移除模型',
                  icon: Icon(
                    Icons.close_rounded,
                    size: 16,
                    color: cs.onSurfaceVariant.withValues(alpha: 0.6),
                  ),
                  onPressed: onDelete,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 供应商编辑弹层（新建 / 编辑信息），不包含模型——模型在详情页一并管理
class _ProviderEditSheet extends StatefulWidget {
  final ApiConfig? config; // null = 新建
  const _ProviderEditSheet({this.config});

  @override
  State<_ProviderEditSheet> createState() => _ProviderEditSheetState();
}

class _ProviderEditSheetState extends State<_ProviderEditSheet> {
  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.config?.name ?? '');
  late final _baseUrl = TextEditingController(
    text: widget.config?.baseUrl ?? '',
  );
  late final _apiKey = TextEditingController(text: widget.config?.apiKey ?? '');
  late double _temperature = widget.config?.temperature ?? 0.7;
  bool _obscureKey = true;

  @override
  void dispose() {
    _name.dispose();
    _baseUrl.dispose();
    _apiKey.dispose();
    super.dispose();
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
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                widget.config == null ? '添加供应商' : '编辑供应商信息',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 4),
              Text(
                'Base URL 与 API Key 只需配置一次，模型在保存后于详情页统一添加。',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _name,
                decoration: const InputDecoration(
                  labelText: '供应商名称（如 zhipu）',
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
                  hintText: 'https://open.bigmodel.cn/api/paas/v4',
                  border: OutlineInputBorder(),
                ),
                validator: (v) => (v == null || !v.trim().startsWith('http'))
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
                    icon: Icon(
                      _obscureKey ? Icons.visibility_off : Icons.visibility,
                    ),
                    onPressed: () => setState(() => _obscureKey = !_obscureKey),
                  ),
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? '请输入 API Key' : null,
              ),
              const SizedBox(height: 16),
              Text(
                '温度 (Temperature): ${_temperature.toStringAsFixed(1)}',
                style: Theme.of(context).textTheme.labelLarge,
              ),
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
                  final state = context.read<AppState>();
                  if (widget.config == null) {
                    final config = ApiConfig(
                      id: _uuid.v4(),
                      name: _name.text.trim(),
                      baseUrl: _baseUrl.text.trim(),
                      apiKey: _apiKey.text.trim(),
                      model: '',
                      temperature: _temperature,
                    );
                    state.addOrUpdateApi(config);
                    Navigator.pop(context);
                    // 创建后直接进入详情页添加模型
                    Navigator.push(
                      context,
                      FastRoute(builder: (_) => _ProviderDetailPage(config)),
                    );
                  } else {
                    final config = widget.config!;
                    config
                      ..name = _name.text.trim()
                      ..baseUrl = _baseUrl.text.trim()
                      ..apiKey = _apiKey.text.trim()
                      ..temperature = _temperature;
                    state.addOrUpdateApi(config);
                    Navigator.pop(context);
                  }
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

/// 添加模型弹层：手动输入或从供应商拉取模型列表多选，一次一并添加
class _AddModelsSheet extends StatefulWidget {
  final ApiConfig config;
  const _AddModelsSheet({required this.config});

  @override
  State<_AddModelsSheet> createState() => _AddModelsSheetState();
}

class _AddModelsSheetState extends State<_AddModelsSheet> {
  final _manualCtrl = TextEditingController();
  final _searchCtrl = TextEditingController();
  List<String> _fetched = const [];
  final Set<String> _checked = {};
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _manualCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _fetchModels() async {
    final config = widget.config;
    if (!config.baseUrl.startsWith('http') || config.apiKey.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先完善供应商的 Base URL 和 API Key')),
      );
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final models = await AiService.listModels(
        baseUrl: config.baseUrl,
        apiKey: config.apiKey,
      );
      if (!mounted) return;
      setState(() => _fetched = models);
      if (models.isEmpty) {
        setState(() => _error = '该接口未返回任何模型，可手动输入添加');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '获取失败：$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// 保存：手动输入 + 勾选的远程模型一并加入（按模型名去重）
  void _save() {
    final config = widget.config;
    final state = context.read<AppState>();
    final existing = config.models.map((m) => m.model).toSet();
    final toAdd = <String>[..._checked];
    final manual = _manualCtrl.text.trim();
    if (manual.isNotEmpty) toAdd.add(manual);

    var added = 0;
    for (final model in toAdd) {
      if (model.isEmpty || existing.contains(model)) continue;
      config.models.add(ApiModelEntry(id: _uuid.v4(), model: model));
      existing.add(model);
      added++;
    }
    // 供应商还没有当前模型时，选中第一个
    if (config.model.isEmpty && config.models.isNotEmpty) {
      config.model = config.models.first.model;
    }
    if (added > 0) {
      state.addOrUpdateApi(config);
      Log.i('api', '供应商 ${config.name} 新增 $added 个模型');
    }
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final query = _searchCtrl.text.trim().toLowerCase();
    final filtered = query.isEmpty
        ? _fetched
        : _fetched.where((m) => m.toLowerCase().contains(query)).toList();
    final canSave =
        _manualCtrl.text.trim().isNotEmpty || _checked.isNotEmpty;

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.75,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 4),
              child: Text(
                '添加模型 · ${widget.config.name}',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
              child: Text(
                '从供应商拉取列表勾选，或直接手动输入模型名；可一次添加多个。',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _manualCtrl,
                      decoration: const InputDecoration(
                        labelText: '手动输入模型名（如 glm-5.3）',
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filledTonal(
                    tooltip: '获取模型列表',
                    onPressed: _loading ? null : _fetchModels,
                    icon: _loading
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.cloud_download_outlined),
                  ),
                ],
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Text(
                  _error!,
                  style: TextStyle(fontSize: 12, color: cs.error),
                ),
              ),
            if (_fetched.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 4, 24, 4),
                child: TextField(
                  controller: _searchCtrl,
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search, size: 20),
                    hintText: '搜索模型…',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Row(
                  children: [
                    Text(
                      '已勾选 ${_checked.length} 个',
                      style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: () => setState(() {
                        if (_checked.length == filtered.length) {
                          _checked.clear();
                        } else {
                          _checked
                            ..clear()
                            ..addAll(filtered);
                        }
                      }),
                      child: Text(
                        _checked.length == filtered.length && filtered.isNotEmpty
                            ? '取消全选'
                            : '全选',
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: filtered.length,
                  itemBuilder: (_, i) {
                    final m = filtered[i];
                    final checked = _checked.contains(m);
                    return CheckboxListTile(
                      value: checked,
                      dense: true,
                      controlAffinity: ListTileControlAffinity.leading,
                      title: Text(
                        m,
                        style: const TextStyle(fontFamily: 'monospace'),
                      ),
                      onChanged: (v) => setState(() {
                        v == true ? _checked.add(m) : _checked.remove(m);
                      }),
                    );
                  },
                ),
              ),
            ],
            if (_fetched.isEmpty)
              Expanded(
                child: Center(
                  child: Text(
                    _loading ? '获取中…' : '点右上按钮拉取模型列表，或直接手动输入',
                    style: TextStyle(fontSize: 12, color: cs.outline),
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
              child: FilledButton(
                onPressed: canSave ? _save : null,
                child: const Text('添加'),
              ),
            ),
          ],
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
          Icon(icon, size: 64, color: Theme.of(context).colorScheme.outline),
          const SizedBox(height: 16),
          Text(
            text,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.outline,
            ),
          ),
        ],
      ),
    );
  }
}
