import 'dart:math' as math;

import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:provider/provider.dart';

import '../services/memory/graph_layout.dart';
import '../services/memory/graph_memory.dart';
import '../state/app_state.dart';

/// 图谱四类节点配色（与 app 调色板一致：主紫蓝/薄荷绿/金/珊瑚红）
const Map<GraphNodeType, Color> kGraphTypeColors = {
  GraphNodeType.person: Color(0xFF6B66C2),
  GraphNodeType.topic: Color(0xFF3DD598),
  GraphNodeType.fact: Color(0xFFE7B24F),
  GraphNodeType.summary: Color(0xFFEF7D6C),
};

/// 记忆图谱：对齐 LivingMemory 图谱页。
///
/// 默认显示最近 12 条记忆的受限概览（上限 48 节点/72 边），可切全量；
/// 布局为拓扑种子力导向（后台 isolate 计算）；标签按缩放阈值 + 重要性门槛 +
/// 优先级 + 屏幕空间碰撞剔除，杜绝文字重叠；边为贝塞尔曲线，选中时
/// 非邻接元素淡出。点节点弹出详情（画布不动），点空白清除选择，
/// 双击/按钮缩放为可打断的缓动动画。
class MemoryGraphPage extends StatefulWidget {
  const MemoryGraphPage({super.key});

  @override
  State<MemoryGraphPage> createState() => _MemoryGraphPageState();
}

class _MemoryGraphPageState extends State<MemoryGraphPage>
    with SingleTickerProviderStateMixin {
  static const double _minScale = 0.1;
  static const double _maxScale = 4.0;
  static const double _pinchGain = 0.8; // 捏合灵敏度略降
  static const double _doubleTapZoom = 1.8;
  static const int _overviewMemoryLimit = 12;
  static const int _overviewNodeCap = 48;
  static const int _overviewEdgeCap = 72;

  Matrix4 _matrix = Matrix4.identity();
  GraphNodeType? _typeFilter;
  String _query = '';
  String? _selectedKey;
  bool _fullGraph = false;

  // 布局结果（世界坐标）
  Map<String, List<double>>? _positions;
  String? _layoutSignature;
  final Map<String, Map<String, List<double>>> _layoutCache = {};
  Future<Map<String, List<double>>>? _layoutJob;

  // 相机缓动动画（双击/按钮缩放；新手势或新目标可随时打断）
  AnimationController? _cameraController;
  CurvedAnimation? _cameraCurve;
  Matrix4? _cameraFrom;
  Matrix4? _cameraTo;

  // 手动双击检测（不注册 onDoubleTap，单击立即生效无等待）
  DateTime? _lastTapTime;
  Offset? _lastTapPosition;

  @override
  void dispose() {
    _cameraController?.dispose();
    super.dispose();
  }

  // ---------- 数据准备 ----------

  /// 受限概览：最近 N 条记忆的子图（对齐原版 get_recent_memory_ids）
  _GraphData _buildGraphData(AppState state) {
    final store = state.graphStore;
    var memoryIds = state.memories.map((m) => m.id).toSet();
    if (!_fullGraph) {
      memoryIds = state.memories
          .take(_overviewMemoryLimit)
          .map((m) => m.id)
          .toSet();
    }

    final entryKeys = <String>{};
    final nodeKeyToMemories = <String, Set<String>>{};
    final nodeKeyToEntries = <String, int>{};
    for (final entry in store.entries.values) {
      if (!memoryIds.contains(entry.sourceMemoryId)) continue;
      entryKeys.add(entry.entryKey);
      for (final nodeKey in entry.nodeKeys) {
        (nodeKeyToMemories[nodeKey] ??= {}).add(entry.sourceMemoryId);
        nodeKeyToEntries[nodeKey] = (nodeKeyToEntries[nodeKey] ?? 0) + 1;
      }
    }

    final query = _query.trim().toLowerCase();
    var nodeKeys = nodeKeyToMemories.keys.toSet();
    if (_typeFilter != null) {
      nodeKeys = nodeKeys
          .where((k) => store.nodes[k]?.type == _typeFilter)
          .toSet();
    }
    if (query.isNotEmpty) {
      nodeKeys = nodeKeys.where((k) {
        final n = store.nodes[k];
        if (n == null) return false;
        return n.value.toLowerCase().contains(query) ||
            n.canonicalValue.toLowerCase().contains(query);
      }).toSet();
    }
    if (!_fullGraph && nodeKeys.length > _overviewNodeCap) {
      nodeKeys = nodeKeys.take(_overviewNodeCap).toSet();
    }

    var edges =
        store.edges.values
            .where(
              (e) =>
                  nodeKeys.contains(e.sourceKey) &&
                  nodeKeys.contains(e.targetKey),
            )
            .toList()
          ..sort((a, b) => b.weight.compareTo(a.weight));
    if (!_fullGraph && edges.length > _overviewEdgeCap) {
      edges = edges.sublist(0, _overviewEdgeCap);
    }

    final degree = <String, int>{};
    for (final e in edges) {
      degree[e.sourceKey] = (degree[e.sourceKey] ?? 0) + 1;
      degree[e.targetKey] = (degree[e.targetKey] ?? 0) + 1;
    }

    final nodes = <_GraphNodeView>[];
    for (final key in nodeKeys) {
      final node = store.nodes[key];
      if (node == null) continue;
      final memoryCount = nodeKeyToMemories[key]?.length ?? 0;
      final entryCount = nodeKeyToEntries[key] ?? 0;
      final d = degree[key] ?? 0;
      final weight = entryCount + memoryCount * 0.75 + d * 0.35;
      nodes.add(
        _GraphNodeView(
          node: node,
          memoryCount: memoryCount,
          entryCount: entryCount,
          degree: d,
          weight: weight,
        ),
      );
    }

    return _GraphData(
      nodes: nodes,
      edges: edges
          .map(
            (e) => LayoutEdgeInput(
              id: e.semanticKey,
              source: e.sourceKey,
              target: e.targetKey,
              weight: e.weight,
            ),
          )
          .toList(),
      memoryCount: memoryIds.length,
      sessionCount: state.memories
          .map((m) => m.sessionId)
          .whereType<String>()
          .toSet()
          .length,
    );
  }

  String _signature(_GraphData data) =>
      '${data.nodes.map((n) => n.node.key).join(',')}|'
      '${data.edges.map((e) => '${e.source}>${e.target}').join(',')}';

  void _ensureLayout(_GraphData data) {
    final signature = _signature(data);
    if (_layoutSignature == signature && _positions != null) return;
    _layoutSignature = signature;
    final cached = _layoutCache[signature];
    if (cached != null) {
      _positions = cached;
      _layoutJob = null;
      return;
    }
    final inputs = data.nodes
        .map(
          (n) => LayoutNodeInput(
            id: n.node.key,
            radius: nodeWorldRadius(
              weight: n.weight,
              memoryCount: n.memoryCount,
            ),
            weight: n.weight,
            memoryCount: n.memoryCount,
            degree: n.degree,
          ),
        )
        .toList();
    final job = computeGraphLayoutAsync(inputs, data.edges);
    _layoutJob = job;
    job.then((positions) {
      if (!mounted) return;
      if (_layoutJob != job) return;
      _layoutCache[signature] = positions;
      if (_layoutCache.length > 3) {
        _layoutCache.remove(_layoutCache.keys.first);
      }
      setState(() {
        _positions = positions;
        _layoutJob = null;
        _selectedKey = null;
      });
      SchedulerBinding.instance.addPostFrameCallback((_) => _fitViewport());
    });
  }

  void _fitViewport({bool animate = false}) {
    final positions = _positions;
    if (positions == null || positions.isEmpty) return;
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    final size = box.size;
    var minX = double.infinity, minY = double.infinity;
    var maxX = double.negativeInfinity, maxY = double.negativeInfinity;
    for (final p in positions.values) {
      minX = math.min(minX, p[0]);
      minY = math.min(minY, p[1]);
      maxX = math.max(maxX, p[0]);
      maxY = math.max(maxY, p[1]);
    }
    // 预留标签空间
    minX -= 60;
    minY -= 60;
    maxX += 60;
    maxY += 60;
    final fit = fitViewport(
      bounds: SizeInputLike(
        width: maxX - minX,
        height: maxY - minY,
        centerX: (minX + maxX) / 2,
        centerY: (minY + maxY) / 2,
      ),
      viewportWidth: size.width,
      viewportHeight: size.height,
    );
    final target = Matrix4.identity()
      ..translate(fit.tx, fit.ty)
      ..scale(fit.scale);
    if (animate) {
      _animateCameraTo(target);
    } else {
      _stopCameraAnim();
      setState(() => _matrix = target);
    }
  }

  // ---------- 坐标换算与命中 ----------

  double get _scale => _matrix.getMaxScaleOnAxis();

  Offset _toWorld(Offset screen) {
    final storage = _matrix.storage;
    return Offset(
      (screen.dx - storage[12]) / _scale,
      (screen.dy - storage[13]) / _scale,
    );
  }

  _GraphNodeView? _hitNode(Offset screen, _GraphData data) {
    final world = _toWorld(screen);
    final positions = _positions;
    if (positions == null) return null;
    _GraphNodeView? best;
    var bestDistance = double.infinity;
    for (final node in data.nodes) {
      final p = positions[node.node.key];
      if (p == null) continue;
      final radius = nodeWorldRadius(
        weight: node.weight,
        memoryCount: node.memoryCount,
        selected: node.node.key == _selectedKey,
      );
      final hitRadius = math.max(radius, 20 / _scale) + 12 / _scale;
      final distance = (Offset(p[0], p[1]) - world).distance;
      if (distance <= hitRadius && distance < bestDistance) {
        best = node;
        bestDistance = distance;
      }
    }
    return best;
  }

  void _selectNode(_GraphNodeView node) {
    setState(() => _selectedKey = node.node.key);
    _showNodeSheet(node);
  }

  void _showNodeSheet(_GraphNodeView node) {
    final state = context.read<AppState>();
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => _NodeDetailSheet(
        node: node,
        state: state,
        positionOf: (key) => _positions?[key],
      ),
    );
  }

  // ---------- 相机缓动 ----------

  void _stopCameraAnim() {
    _cameraController?.stop();
    _cameraFrom = null;
    _cameraTo = null;
  }

  /// 从当前矩阵缓动到目标矩阵；动画期间新手势/新按钮随时打断重设目标。
  void _animateCameraTo(Matrix4 target) {
    final controller = _cameraController ??= AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
    );
    _cameraCurve ??= CurvedAnimation(
      parent: controller,
      curve: Curves.easeOutCubic,
    )..addListener(_tickCamera);
    _cameraFrom = _matrix.clone();
    _cameraTo = target.clone();
    controller
      ..reset()
      ..forward();
  }

  void _tickCamera() {
    final from = _cameraFrom;
    final to = _cameraTo;
    final curve = _cameraCurve;
    if (from == null || to == null || curve == null) return;
    if (!mounted) return;
    setState(() {
      _matrix = _lerpCameraMatrix(from, to, curve.value);
    });
  }

  /// 相机矩阵插值：平移与缩放分量各自线性过渡（本页矩阵只含平移+均匀缩放）
  static Matrix4 _lerpCameraMatrix(Matrix4 a, Matrix4 b, double t) {
    final scale =
        a.getMaxScaleOnAxis() +
        (b.getMaxScaleOnAxis() - a.getMaxScaleOnAxis()) * t;
    final tx = a.storage[12] + (b.storage[12] - a.storage[12]) * t;
    final ty = a.storage[13] + (b.storage[13] - a.storage[13]) * t;
    return Matrix4.identity()
      ..translate(tx, ty)
      ..scale(scale);
  }

  // ---------- 手势 ----------
  //
  // 触屏优先设计：
  // - 单指拖动 = 平移画布；双指捏合 = 缩放（灵敏度略降）
  // - 单击节点 = 选中 + 详情，画布位置保持不动；单击空白 = 清除选中
  // - 双击（任意位置）= 围绕点击点缓动放大；按钮缩放同走缓动动画
  // - 不注册 onDoubleTap / onLongPress：单击立即生效，无双击等待延迟

  Offset? _gestureStartFocal;
  double? _gestureStartScale;
  double? _gestureStartTx;
  double? _gestureStartTy;

  void _onScaleStart(ScaleStartDetails details) {
    _stopCameraAnim(); // 手指落下即打断进行中的缓动
    _gestureStartFocal = details.localFocalPoint;
    _gestureStartScale = _scale;
    _gestureStartTx = _matrix.storage[12];
    _gestureStartTy = _matrix.storage[13];
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    final data = _latestData;
    final startFocal = _gestureStartFocal;
    final startScale = _gestureStartScale;
    if (data == null || startFocal == null || startScale == null) return;

    // 捏合增量按 _pinchGain 折算，降低放大缩小的幅度
    final gained = 1 + (details.scale - 1) * _pinchGain;
    final scale = (startScale * gained).clamp(_minScale, _maxScale);
    // 起始焦点下的世界点始终钉在当前焦点下（平移 + 缩放一体）
    final world = Offset(
      (startFocal.dx - _gestureStartTx!) / startScale,
      (startFocal.dy - _gestureStartTy!) / startScale,
    );
    setState(() {
      _matrix = Matrix4.identity()
        ..translate(
          details.localFocalPoint.dx - world.dx * scale,
          details.localFocalPoint.dy - world.dy * scale,
        )
        ..scale(scale);
    });
  }

  // ---- 点击：单击立即生效，双击手动识别 ----

  void _onTapUp(TapUpDetails details, _GraphData data) {
    final pos = details.localPosition;
    final now = DateTime.now();
    final isDoubleTap =
        _lastTapTime != null &&
        _lastTapPosition != null &&
        now.difference(_lastTapTime!).inMilliseconds < 300 &&
        (pos - _lastTapPosition!).distance < 24;
    _lastTapTime = now;
    _lastTapPosition = pos;
    if (isDoubleTap) {
      _lastTapTime = null;
      _lastTapPosition = null;
      _animateCameraTo(_zoomMatrix(_scale * _doubleTapZoom, pos));
      return;
    }
    final hit = _hitNode(pos, data);
    if (hit != null) {
      _selectNode(hit);
    } else if (_selectedKey != null) {
      setState(() => _selectedKey = null);
    }
  }

  _GraphData? _latestData;

  /// 围绕屏幕点 focal 缩放到 newScale 的目标矩阵（该点的世界坐标保持不动）
  Matrix4 _zoomMatrix(double newScale, Offset focal) {
    final s = newScale.clamp(_minScale, _maxScale);
    final world = _toWorld(focal);
    return Matrix4.identity()
      ..translate(focal.dx - world.dx * s, focal.dy - world.dy * s)
      ..scale(s);
  }

  void _zoomBy(double factor) {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    final size = box.size;
    _animateCameraTo(
      _zoomMatrix(_scale * factor, Offset(size.width / 2, size.height / 2)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final data = _buildGraphData(state);
    _latestData = data;
    _ensureLayout(data);
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('记忆图谱'),
        actions: [
          TextButton.icon(
            onPressed: () => setState(() {
              _fullGraph = !_fullGraph;
              _selectedKey = null;
            }),
            icon: Icon(_fullGraph ? Icons.filter_center_focus : Icons.public),
            label: Text(_fullGraph ? '概览' : '全量图谱'),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Column(
        children: [
          // 搜索 + 类型筛选（紧凑两行，统计移到底部图例）
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
            child: TextField(
              decoration: const InputDecoration(
                isDense: true,
                prefixIcon: Icon(Icons.search, size: 20),
                hintText: '搜索实体…',
              ),
              onChanged: (v) => setState(() {
                _query = v.trim();
                _selectedKey = null;
              }),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
            child: Row(
              children: [
                _TypeChip(
                  label: '全部',
                  color: cs.primary,
                  selected: _typeFilter == null,
                  onTap: () => setState(() => _typeFilter = null),
                ),
                for (final type in [
                  (
                    GraphNodeType.person,
                    '人物',
                    kGraphTypeColors[GraphNodeType.person]!,
                  ),
                  (
                    GraphNodeType.topic,
                    '主题',
                    kGraphTypeColors[GraphNodeType.topic]!,
                  ),
                  (
                    GraphNodeType.fact,
                    '事实',
                    kGraphTypeColors[GraphNodeType.fact]!,
                  ),
                ])
                  _TypeChip(
                    label: type.$2,
                    color: type.$3,
                    selected: _typeFilter == type.$1,
                    onTap: () => setState(() {
                      _typeFilter = _typeFilter == type.$1 ? null : type.$1;
                      _selectedKey = null;
                    }),
                  ),
              ],
            ),
          ),
          // 画布
          Expanded(
            child: Container(
              margin: const EdgeInsets.fromLTRB(12, 0, 12, 4),
              decoration: BoxDecoration(
                color: cs.surfaceContainerLowest,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: cs.outlineVariant.withValues(alpha: 0.5),
                ),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: Stack(
                  children: [
                    if (data.nodes.isEmpty)
                      Center(
                        child: Text(
                          storeEmptyHint(state),
                          textAlign: TextAlign.center,
                          style: TextStyle(color: cs.outline, height: 1.6),
                        ),
                      )
                    else if (_layoutJob != null || _positions == null)
                      Center(
                        child: _StatusPill(text: '正在准备图谱布局…', color: cs),
                      )
                    else
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final canvasSize = Size(
                            constraints.maxWidth,
                            constraints.maxHeight,
                          );
                          return GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTapUp: (details) => _onTapUp(details, data),
                            onScaleStart: _onScaleStart,
                            onScaleUpdate: _onScaleUpdate,
                            child: CustomPaint(
                              size: canvasSize,
                              painter: _GraphPainter(
                                data: data,
                                positions: _positions!,
                                matrix: _matrix,
                                selectedKey: _selectedKey,
                                scheme: cs,
                              ),
                            ),
                          );
                        },
                      ),
                    // 右下角缩放按钮（缓动动画，可连续点击打断重设目标）
                    if (data.nodes.isNotEmpty)
                      Positioned(
                        right: 12,
                        bottom: 12,
                        child: Column(
                          children: [
                            _RoundButton(
                              icon: Icons.add,
                              tooltip: '放大',
                              onTap: () => _zoomBy(1.3),
                            ),
                            const SizedBox(height: 8),
                            _RoundButton(
                              icon: Icons.remove,
                              tooltip: '缩小',
                              onTap: () => _zoomBy(1 / 1.3),
                            ),
                            const SizedBox(height: 8),
                            _RoundButton(
                              icon: Icons.center_focus_strong,
                              tooltip: '适配全图',
                              onTap: () => _fitViewport(animate: true),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          // 图例 + 统计
          _Legend(data: data),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  static String storeEmptyHint(AppState state) => state.graphStore.nodes.isEmpty
      ? '暂无图谱数据\n对话产生关键事实后会自动出现在这里'
      : '没有符合筛选的节点';
}

// ---------- 数据视图 ----------

class _GraphNodeView {
  final GraphNode node;
  final int memoryCount;
  final int entryCount;
  final int degree;
  final double weight;

  const _GraphNodeView({
    required this.node,
    required this.memoryCount,
    required this.entryCount,
    required this.degree,
    required this.weight,
  });
}

class _GraphData {
  final List<_GraphNodeView> nodes;
  final List<LayoutEdgeInput> edges;
  final int memoryCount;
  final int sessionCount;

  const _GraphData({
    required this.nodes,
    required this.edges,
    required this.memoryCount,
    required this.sessionCount,
  });
}

/// 在 isolate 中计算布局（compute 传 records/plain classes 均可）
Future<Map<String, List<double>>> computeGraphLayoutAsync(
  List<LayoutNodeInput> nodes,
  List<LayoutEdgeInput> edges,
) {
  return compute(
    (List<Object> args) => computeGraphLayout(
      args[0] as List<LayoutNodeInput>,
      args[1] as List<LayoutEdgeInput>,
    ),
    <Object>[nodes, edges],
  );
}

// ---------- 类型筛选 chip ----------

class _TypeChip extends StatelessWidget {
  final String label;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  const _TypeChip({
    required this.label,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: selected
                ? color.withValues(alpha: 0.18)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected ? color : color.withValues(alpha: 0.35),
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ),
      ),
    );
  }
}

class _RoundButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  const _RoundButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.surface,
      // 与 app 一致的描边风格：无阴影，1px outlineVariant
      shape: CircleBorder(
        side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.7)),
      ),
      clipBehavior: Clip.antiAlias,
      child: IconButton(
        tooltip: tooltip,
        onPressed: onTap,
        icon: Icon(icon, size: 20, color: cs.onSurfaceVariant),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  final String text;
  final ColorScheme color;

  const _StatusPill({required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.surface.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.outlineVariant),
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: 12, color: color.onSurfaceVariant),
      ),
    );
  }
}

// ---------- 图例 ----------

class _Legend extends StatelessWidget {
  final _GraphData data;

  const _Legend({required this.data});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final byType = <GraphNodeType, int>{};
    for (final n in data.nodes) {
      byType[n.node.type] = (byType[n.node.type] ?? 0) + 1;
    }
    final typeChips = byType.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final byRelation = <String, int>{};
    for (final e in data.edges) {
      final relation = e.id.split('|').length > 1 ? e.id.split('|')[1] : '相关';
      byRelation[relation] = (byRelation[relation] ?? 0) + 1;
    }
    final relationChips = byRelation.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return Container(
      height: 34,
      margin: const EdgeInsets.symmetric(horizontal: 16),
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          for (final chip in typeChips)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: kGraphTypeColors[chip.key],
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '${_typeLabel(chip.key)} ${chip.value}',
                    style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          for (final chip in relationChips.take(4))
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Text(
                '${chip.key} ${chip.value}',
                style: TextStyle(fontSize: 11, color: cs.outline),
              ),
            ),
          Padding(
            padding: const EdgeInsets.only(left: 4),
            child: Text(
              '节点 ${data.nodes.length} · 关系 ${data.edges.length} · '
              '记忆 ${data.memoryCount} · 会话 ${data.sessionCount}',
              style: TextStyle(fontSize: 11, color: cs.outline),
            ),
          ),
        ],
      ),
    );
  }

  static String _typeLabel(GraphNodeType type) => switch (type) {
    GraphNodeType.person => '人物',
    GraphNodeType.topic => '主题',
    GraphNodeType.fact => '事实',
    GraphNodeType.summary => '摘要',
  };
}

// ---------- 画笔 ----------

class _GraphPainter extends CustomPainter {
  final _GraphData data;
  final Map<String, List<double>> positions;
  final Matrix4 matrix;
  final String? selectedKey;
  final ColorScheme scheme;

  _GraphPainter({
    required this.data,
    required this.positions,
    required this.matrix,
    required this.selectedKey,
    required this.scheme,
  });

  Offset _positionOf(_GraphNodeView node) {
    final p = positions[node.node.key];
    return p == null ? Offset.zero : Offset(p[0], p[1]);
  }

  double _radiusOf(_GraphNodeView node) => nodeWorldRadius(
    weight: node.weight,
    memoryCount: node.memoryCount,
    selected: node.node.key == selectedKey,
  );

  @override
  void paint(Canvas canvas, Size size) {
    final storage = matrix.storage;
    final scale = matrix.getMaxScaleOnAxis();
    final tx = storage[12];
    final ty = storage[13];
    canvas.save();
    canvas.translate(tx, ty);
    canvas.scale(scale);

    final isMuted = selectedKey != null;
    final adjacent = <String>{};
    if (isMuted) {
      for (final e in data.edges) {
        if (e.source == selectedKey) adjacent.add(e.target);
        if (e.target == selectedKey) adjacent.add(e.source);
      }
      adjacent.add(selectedKey!);
    }

    // ---- 点阵背景（原版 dot-grid，世界空间绘制随缩放平移） ----
    _paintDotGrid(canvas, scale, size);

    // ---- 边（贝塞尔；选中时非邻接边不画） ----
    final edgePaint = Paint()..style = PaintingStyle.stroke;
    for (final e in data.edges) {
      if (isMuted && !(e.source == selectedKey || e.target == selectedKey)) {
        continue;
      }
      final a = positions[e.source];
      final b = positions[e.target];
      if (a == null || b == null) continue;
      final active = isMuted;
      final dx = b[0] - a[0];
      final dy = b[1] - a[1];
      final len = math.sqrt(dx * dx + dy * dy);
      final bend = edgeBend(e.id, len);
      final mid = Offset((a[0] + b[0]) / 2, (a[1] + b[1]) / 2);
      // 垂直方向
      final nx = len > 0 ? -dy / len : 1.0;
      final ny = len > 0 ? dx / len : 0.0;
      final control = mid + Offset(nx * bend, ny * bend);
      final weightBonus = math.sqrt(e.weight) / 3.6 * (active ? 0.35 : 0.8);
      edgePaint.strokeWidth = (active ? 1.2 : 0.7) + weightBonus;
      edgePaint.color = scheme.outline.withValues(alpha: active ? 0.55 : 0.22);
      final path = Path()
        ..moveTo(a[0], a[1])
        ..quadraticBezierTo(control.dx, control.dy, b[0], b[1]);
      canvas.drawPath(path, edgePaint);
    }

    // ---- 节点 ----
    for (final node in data.nodes) {
      final key = node.node.key;
      final p = _positionOf(node);
      final muted = isMuted && !adjacent.contains(key);
      final color = kGraphTypeColors[node.node.type] ?? scheme.primary;
      final radius = _radiusOf(node);
      final center = Offset(p.dx, p.dy);

      final isSelected = key == selectedKey;
      final prominent = isProminentNode(
        degree: node.degree,
        memoryCount: node.memoryCount,
        labelScore: labelScoreOf(
          degree: node.degree,
          memoryCount: node.memoryCount,
          entryCount: node.entryCount,
          weight: node.weight,
        ),
      );
      // 光晕：选中 8 / 重点节点静态 2.4（原版为呼吸脉冲，此处取静态值省电）
      final haloBase = isSelected
          ? 8.0
          : prominent
          ? 2.4
          : 0.0;
      if (haloBase > 0) {
        canvas.drawCircle(
          center,
          radius + haloBase,
          Paint()..color = color.withValues(alpha: isSelected ? 0.18 : 0.09),
        );
      }
      canvas.drawCircle(
        center,
        radius,
        Paint()..color = muted ? const Color(0xFF9AA0A6) : color,
      );
      // 背景色描边环（把节点和边视觉分开；世界宽度换算固定屏幕像素）
      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2 / scale
          ..color = scheme.surface,
      );
      if (isSelected) {
        // 选中环：类型色
        canvas.drawCircle(
          center,
          radius + 2.5 / scale,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.6 / scale
            ..color = color.withValues(alpha: 0.9),
        );
      }
      if (muted) {
        // 非邻接节点压暗
        canvas.drawCircle(
          center,
          radius,
          Paint()..color = scheme.surface.withValues(alpha: 0.62),
        );
      }
    }

    canvas.restore();

    // ---- 标签（屏幕空间，独立于画布变换；照抄原版六层防重叠） ----
    _paintLabels(canvas, size, scale, tx, ty);
  }

  void _paintDotGrid(Canvas canvas, double scale, Size size) {
    const dotRadius = 0.75;
    final step = (30 * scale).clamp(22.0, 42.0);
    final paint = Paint()..color = scheme.outline.withValues(alpha: 0.13);
    // 只画可视区域内的点：把屏幕范围换算成世界范围再取整
    final storage = matrix.storage;
    final worldLeft = -storage[12] / scale;
    final worldTop = -storage[13] / scale;
    final worldRight = worldLeft + size.width / scale;
    final worldBottom = worldTop + size.height / scale;
    final startX = (worldLeft / step).floor() * step;
    final startY = (worldTop / step).floor() * step;
    for (var x = startX; x <= worldRight; x += step) {
      for (var y = startY; y <= worldBottom; y += step) {
        canvas.drawCircle(Offset(x, y), dotRadius, paint);
      }
    }
  }

  void _paintLabels(
    Canvas canvas,
    Size size,
    double scale,
    double tx,
    double ty,
  ) {
    // 1. 候选门槛 + 优先级
    final candidates = <(_GraphNodeView, double)>[]; // (node, priority)
    for (final node in data.nodes) {
      final labelScore = labelScoreOf(
        degree: node.degree,
        memoryCount: node.memoryCount,
        entryCount: node.entryCount,
        weight: node.weight,
      );
      final prominent = isProminentNode(
        degree: node.degree,
        memoryCount: node.memoryCount,
        labelScore: labelScore,
      );
      final show = shouldShowLabel(
        scale: scale,
        selected: node.node.key == selectedKey,
        hasSelection: selectedKey != null,
        prominent: prominent,
        degree: node.degree,
      );
      if (!show) continue;
      final priority =
          (node.node.key == selectedKey ? 2 : 0) +
          (prominent ? 1 : 0) +
          labelScore / 1000;
      candidates.add((node, priority));
    }
    if (candidates.isEmpty) return;
    candidates.sort((a, b) => b.$2.compareTo(a.$2));

    // 2. 贪心 AABB 碰撞剔除
    final placedBoxes = <List<double>>[];
    final personNames = data.nodes
        .where((n) => n.node.type == GraphNodeType.person)
        .map((n) => n.node.value)
        .toList();
    final fontSize = labelFontSize(scale);
    for (final (node, _) in candidates) {
      final p = _positionOf(node);
      final screen = Offset(p.dx * scale + tx, p.dy * scale + ty);
      if (screen.dx < -80 ||
          screen.dy < -40 ||
          screen.dx > size.width + 80 ||
          screen.dy > size.height + 40) {
        continue;
      }
      final isSelected = node.node.key == selectedKey;
      final radius = _radiusOf(node) * scale;
      final label = truncateLabel(
        node.node.type == GraphNodeType.fact
            ? cleanupFactLabel(node.node.value, personNames)
            : node.node.value,
      );
      final tp = TextPainter(
        text: TextSpan(
          text: label,
          style: TextStyle(
            fontSize: fontSize,
            height: 1.15,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
            color: scheme.onSurface.withValues(alpha: 0.92),
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      // 标签在节点右侧：x + r + clamp(7*scale, 5, 10)，垂直居中
      final labelX = screen.dx + radius + (7 * scale).clamp(5.0, 10.0);
      final labelY = screen.dy - tp.height / 2;
      final box = [
        labelX - 4,
        labelY - 2,
        labelX + tp.width + 4,
        labelY + tp.height + 2,
      ];
      var collides = false;
      for (final placed in placedBoxes) {
        if (labelBoxesOverlap(box, placed, 0, 0)) {
          collides = true;
          break;
        }
      }
      if (collides && !isSelected) continue; // 碰撞且非选中 → 直接不画
      placedBoxes.add(box);

      tp.paint(canvas, Offset(labelX, labelY));

      // 选中节点的第二行元信息：NM / k链接
      if (isSelected) {
        final meta = TextPainter(
          text: TextSpan(
            text: '${node.memoryCount}M / ${node.degree}链接',
            style: TextStyle(
              fontSize: math.min(12, fontSize - 1),
              color: scheme.outline,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        meta.paint(canvas, Offset(labelX, labelY + tp.height + 2));
      }
    }
  }

  @override
  bool shouldRepaint(covariant _GraphPainter oldDelegate) =>
      oldDelegate.selectedKey != selectedKey ||
      oldDelegate.matrix != matrix ||
      !identical(oldDelegate.positions, positions) ||
      !identical(oldDelegate.data, data);
}

// ---------- 节点详情弹层 ----------

class _NodeDetailSheet extends StatelessWidget {
  final _GraphNodeView node;
  final AppState state;
  final List<double>? Function(String key) positionOf;

  const _NodeDetailSheet({
    required this.node,
    required this.state,
    required this.positionOf,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final store = state.graphStore;
    final color = kGraphTypeColors[node.node.type] ?? cs.primary;
    final links = store.edges.values
        .where(
          (e) => e.sourceKey == node.node.key || e.targetKey == node.node.key,
        )
        .toList();
    final memoryIds = store.entries.values
        .where((e) => e.nodeKeys.contains(node.node.key))
        .map((e) => e.sourceMemoryId)
        .toSet();
    final memories =
        state.memories.where((m) => memoryIds.contains(m.id)).toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.6,
        ),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          children: [
            Row(
              children: [
                // 类型徽章：类型色软底
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: color,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        _typeLabel(node.node.type),
                        style: TextStyle(
                          color: color,
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                Text(
                  '${node.memoryCount} 条记忆 · ${node.degree} 连接 · '
                  '${node.entryCount} 条目 · 权重 ${node.weight.toStringAsFixed(1)}',
                  style: TextStyle(fontSize: 11, color: cs.outline),
                ),
              ],
            ),
            const SizedBox(height: 6),
            SelectableText(
              node.node.value,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 14),
            Text('关系', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 4),
            if (links.isEmpty)
              Text('暂无相连关系', style: TextStyle(color: cs.outline))
            else
              ...links.take(8).map((edge) {
                final otherKey = edge.sourceKey == node.node.key
                    ? edge.targetKey
                    : edge.sourceKey;
                final other = store.nodes[otherKey];
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    children: [
                      Container(
                        width: 7,
                        height: 7,
                        decoration: BoxDecoration(
                          color: kGraphTypeColors[other?.type] ?? cs.outline,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '${edge.relationType} · ${other?.value ?? otherKey}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                );
              }),
            const SizedBox(height: 12),
            Text(
              '关联记忆 ${memories.length}',
              style: Theme.of(context).textTheme.labelLarge,
            ),
            const SizedBox(height: 6),
            if (memories.isEmpty)
              Text('没有仍保留的关联记忆', style: TextStyle(color: cs.outline))
            else
              ...memories
                  .take(8)
                  .map(
                    (m) => Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: cs.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            m.displayContent,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 13, height: 1.5),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '重要性 ${m.importance.toStringAsFixed(2)} · '
                            '${m.createdAt.month}-${m.createdAt.day}',
                            style: TextStyle(fontSize: 11, color: cs.outline),
                          ),
                        ],
                      ),
                    ),
                  ),
          ],
        ),
      ),
    );
  }

  static String _typeLabel(GraphNodeType type) => switch (type) {
    GraphNodeType.person => '人物',
    GraphNodeType.topic => '主题',
    GraphNodeType.fact => '事实',
    GraphNodeType.summary => '摘要',
  };
}
