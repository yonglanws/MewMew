import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../models/models.dart';
import '../state/app_state.dart';

const _uuid = Uuid();

/// 工具管理页面
class ToolsPage extends StatelessWidget {
  const ToolsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final builtins = state.allTools.where((t) => t.type == ToolType.builtin);
    final customs = state.customTools;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          '工具',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showEditSheet(context),
        icon: const Icon(Icons.add),
        label: const Text('自定义工具'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
        children: [
          Text('内置工具', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          ...builtins.map((t) => _ToolTile(tool: t)),
          const SizedBox(height: 16),
          Text('自定义工具（HTTP）',
              style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          if (customs.isEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text('暂无自定义工具，点击右下角添加',
                  style: TextStyle(
                      color: Theme.of(context).colorScheme.outline)),
            ),
          ...customs.map((t) => _ToolTile(tool: t)),
        ],
      ),
    );
  }

  static void _showEditSheet(BuildContext context, {ToolConfig? tool}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _ToolEditSheet(tool: tool),
    );
  }
}

class _ToolTile extends StatelessWidget {
  final ToolConfig tool;
  const _ToolTile({required this.tool});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final isBuiltin = tool.type == ToolType.builtin;
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
            color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: ListTile(
        leading: Icon(isBuiltin ? Icons.extension : Icons.http),
        title: Text(tool.name),
        subtitle: Text(tool.description,
            maxLines: 2, overflow: TextOverflow.ellipsis),
        trailing: Switch(
          value: state.isToolEnabled(tool),
          onChanged: (v) => context.read<AppState>().toggleTool(tool, v),
        ),
        contentPadding: const EdgeInsets.only(left: 16, right: 8),
        onTap: isBuiltin
            ? null
            : () => ToolsPage._showEditSheet(context, tool: tool),
      ),
    );
  }
}

class _ToolEditSheet extends StatefulWidget {
  final ToolConfig? tool;
  const _ToolEditSheet({this.tool});

  @override
  State<_ToolEditSheet> createState() => _ToolEditSheetState();
}

class _ToolEditSheetState extends State<_ToolEditSheet> {
  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.tool?.name ?? '');
  late final _desc =
      TextEditingController(text: widget.tool?.description ?? '');
  late final _url = TextEditingController(text: widget.tool?.url ?? '');
  late final _headers =
      TextEditingController(text: widget.tool?.headersJson ?? '{}');
  late final _schema = TextEditingController(
      text: widget.tool?.paramsSchemaJson ??
          '{"type":"object","properties":{"query":{"type":"string","description":"查询内容"}},"required":["query"]}');
  late String _method = widget.tool?.method ?? 'GET';

  @override
  void dispose() {
    _name.dispose();
    _desc.dispose();
    _url.dispose();
    _headers.dispose();
    _schema.dispose();
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
              Text(widget.tool == null ? '添加自定义工具' : '编辑工具',
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 16),
              TextFormField(
                controller: _name,
                decoration: const InputDecoration(
                  labelText: '函数名（英文）*',
                  hintText: 'search_weather',
                  border: OutlineInputBorder(),
                ),
                validator: (v) => (v == null ||
                        !RegExp(r'^[a-zA-Z_][a-zA-Z0-9_]*$')
                            .hasMatch(v.trim()))
                    ? '仅支持字母、数字、下划线，且不能以数字开头'
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _desc,
                decoration: const InputDecoration(
                  labelText: '功能描述 *',
                  hintText: '告诉 AI 这个工具的用途和使用时机',
                  border: OutlineInputBorder(),
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? '请输入描述' : null,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'GET', label: Text('GET')),
                      ButtonSegment(value: 'POST', label: Text('POST')),
                    ],
                    selected: {_method},
                    onSelectionChanged: (s) =>
                        setState(() => _method = s.first),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _url,
                decoration: const InputDecoration(
                  labelText: '请求 URL *',
                  hintText: 'https://api.example.com/weather',
                  border: OutlineInputBorder(),
                ),
                validator: (v) =>
                    (v == null || !v.trim().startsWith('http'))
                        ? '请输入有效的 URL'
                        : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _headers,
                maxLines: 2,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                decoration: const InputDecoration(
                  labelText: '请求头（JSON）',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _schema,
                maxLines: 4,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                decoration: const InputDecoration(
                  labelText: '参数 JSON Schema',
                  helperText: 'GET 请求参数会拼接到 URL，POST 会作为 JSON body',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  if (widget.tool != null)
                    OutlinedButton(
                      onPressed: () {
                        context.read<AppState>().deleteTool(widget.tool!.id);
                        Navigator.pop(context);
                      },
                      child: const Text('删除'),
                    ),
                  const Spacer(),
                  FilledButton(
                    onPressed: _save,
                    child: const Text('保存'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    final tool = ToolConfig(
      id: widget.tool?.id ?? _uuid.v4(),
      name: _name.text.trim(),
      description: _desc.text.trim(),
      type: ToolType.http,
      enabled: widget.tool?.enabled ?? true,
      url: _url.text.trim(),
      method: _method,
      headersJson: _headers.text.trim(),
      paramsSchemaJson: _schema.text.trim(),
    );
    context.read<AppState>().addOrUpdateTool(tool);
    Navigator.pop(context);
  }
}
