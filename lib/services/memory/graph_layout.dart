/// 图谱力导向布局与标签规则（移植自 LivingMemory pages/dashboard/graph-layout-core.js
/// 与 graph-renderer.js 的防重叠机制）。纯函数，可在 isolate 中运行。
///
/// 原版参数：REPULSION=1680 / LINK_DISTANCE=108 / LINK_STRENGTH=0.032 /
/// GRAVITY=0.0095 / DAMPING=0.82 / MAX_SPEED=15；碰撞在斥力中内建
/// （minSep=(rA+rB)*2.2+16）。标签六层防重叠：缩放阈值 0.64/1.18、
/// 重要性门槛 labelScore>=15、优先级排序、屏幕空间 AABB 碰撞剔除、
/// 整数字号 clamp(11*scale,10,18)、截断 24/28 字符。
library;

import 'dart:math' as math;

// ---- 输入/输出结构（isolate 可序列化） ----

class LayoutNodeInput {
  final String id;
  final double radius; // 世界半径（4-10）
  final double weight; // entryCount + memoryCount*0.75 + degree*0.35
  final int memoryCount;
  final int degree;

  const LayoutNodeInput({
    required this.id,
    required this.radius,
    required this.weight,
    required this.memoryCount,
    required this.degree,
  });
}

class LayoutEdgeInput {
  final String id; // 稳定唯一 key，用于 hash 抖动与弯曲方向
  final String source;
  final String target;
  final double weight;

  const LayoutEdgeInput({
    required this.id,
    required this.source,
    required this.target,
    required this.weight,
  });
}

/// 布局结果：节点 id → 坐标
typedef GraphLayoutPositions = Map<String, List<double>>;

// ---- 常数（照抄原版 graph-layout-core.js / graph-shared.js） ----

const double _repulsion = 1680;
const double _linkDistance = 108;
const double _linkStrength = 0.032;
const double _gravity = 0.0095;
const double _damping = 0.82;
const double _maxSpeed = 15;
final double _goldenAngle = math.pi * (3 - math.sqrt(5)); // ≈2.39996

int _iterationCount(int n) {
  if (n > 2000) return 35;
  if (n > 1000) return 55;
  if (n > 500) return 90;
  if (n > 220) return 150;
  if (n > 100) return 350;
  return 400;
}

/// FNV-1a 稳定哈希（抖动与弯曲方向用，保证确定性）
int fnv1a(String input) {
  var hash = 0x811c9dc5;
  for (final cu in input.codeUnits) {
    hash ^= cu;
    hash = (hash * 0x01000193) & 0xFFFFFFFF;
  }
  return hash;
}

double clampDouble(double v, double min, double max) =>
    v < min ? min : (v > max ? max : v);

/// 计算布局（入口）。返回 id → [x, y]。
GraphLayoutPositions computeGraphLayout(
  List<LayoutNodeInput> nodes,
  List<LayoutEdgeInput> edges,
) {
  if (nodes.isEmpty) return {};
  if (nodes.length == 1) {
    return {nodes.first.id: [0.0, 0.0]};
  }

  // ---- 1. 拓扑种子：社群划分 ----
  final adjacency = <String, Set<String>>{
    for (final n in nodes) n.id: <String>{},
  };
  for (final e in edges) {
    adjacency[e.source]?.add(e.target);
    adjacency[e.target]?.add(e.source);
  }
  final degreeOf = <String, int>{
    for (final n in nodes) n.id: adjacency[n.id]!.length,
  };

  // 枢纽：度数降序（并列按 weight 降序、id 升序保证确定性），枢纽之间不能相邻
  final sorted = List<LayoutNodeInput>.from(nodes)
    ..sort((a, b) {
      final byDegree = degreeOf[b.id]!.compareTo(degreeOf[a.id]!);
      if (byDegree != 0) return byDegree;
      final byWeight = b.weight.compareTo(a.weight);
      if (byWeight != 0) return byWeight;
      return a.id.compareTo(b.id);
    });
  final hubCount = nodes.length < 8
      ? 1
      : clampDouble(math.sqrt(nodes.length / 6), 2.0, 12.0).round();
  final hubs = <String>[];
  final hubSet = <String>{};
  for (final n in sorted) {
    if (hubs.length >= hubCount) break;
    if (hubSet.contains(n.id)) continue;
    if (adjacency[n.id]!.any(hubSet.contains)) continue;
    hubs.add(n.id);
    hubSet.add(n.id);
  }

  // 多源 BFS 分社群；孤儿（不可达）并入一个岛
  final communityOf = <String, int>{};
  for (var i = 0; i < hubs.length; i++) {
    final queue = <String>[hubs[i]];
    communityOf[hubs[i]] = i;
    while (queue.isNotEmpty) {
      final cur = queue.removeLast();
      for (final next in adjacency[cur]!) {
        if (!communityOf.containsKey(next)) {
          communityOf[next] = i;
          queue.add(next);
        }
      }
    }
  }
  final orphans =
      nodes.where((n) => !communityOf.containsKey(n.id)).map((n) => n.id).toList();
  final island = hubs.length;
  if (orphans.length > 1) {
    for (final id in orphans) {
      communityOf[id] = island;
    }
  } else if (orphans.length == 1) {
    // 单个孤儿就近挂到首个已分配邻居（BFS 已覆盖）或直接归岛
    communityOf[orphans.first] = island;
  }

  // ---- 2. 社群中心：黄金角螺旋 + 占位间距 ----
  final members = <int, List<String>>{};
  for (final e in communityOf.entries) {
    (members[e.value] ??= []).add(e.key);
  }
  final communityIds = members.keys.toList()
    ..sort((a, b) => members[b]!.length.compareTo(members[a]!.length));
  final centerOf = <int, List<double>>{};
  final footprints = <int, double>{};
  for (final cid in communityIds) {
    footprints[cid] = math.max(150, math.sqrt(members[cid]!.length) * 31 + 54);
  }
  var spiralRadius = 0.0;
  for (var k = 0; k < communityIds.length; k++) {
    final cid = communityIds[k];
    final fp = footprints[cid]!;
    if (k == 0) {
      centerOf[cid] = [0, 0];
      continue;
    }
    // 沿黄金角螺旋向外找与已放中心保持间距的位置
    var radius = spiralRadius + (fp + footprints[communityIds[0]]!) / 2;
    final angle = k * _goldenAngle;
    final x = radius * math.cos(angle);
    final y = radius * math.sin(angle) * 0.76; // y 压缩
    centerOf[cid] = [x, y];
    spiralRadius = radius;
  }

  // ---- 3. 成员叶序螺旋初位 ----
  final pos = <String, List<double>>{};
  final indexInCommunity = <int, int>{};
  for (final n in nodes) {
    final cid = communityOf[n.id]!;
    final i = indexInCommunity[cid] ?? 0;
    indexInCommunity[cid] = i + 1;
    final c = centerOf[cid]!;
    final radius = i == 0 ? 0.0 : 22 * math.sqrt(i);
    final angle = i * 2.3999632297;
    pos[n.id] = [c[0] + radius * math.cos(angle), c[1] + radius * math.sin(angle)];
  }
  // 重合节点给确定性角度踢
  final seen = <String, String>{};
  for (final n in nodes) {
    final key = '${pos[n.id]![0].toStringAsFixed(3)},${pos[n.id]![1].toStringAsFixed(3)}';
    if (seen.containsKey(key)) {
      final h = fnv1a(n.id);
      final angle = (h % 360) * math.pi / 180;
      pos[n.id]![0] += 12 * math.cos(angle);
      pos[n.id]![1] += 12 * math.sin(angle);
    } else {
      seen[key] = n.id;
    }
  }

  // ---- 4. 力导向迭代 ----
  final nodeById = {for (final n in nodes) n.id: n};
  final iterationCount = _iterationCount(nodes.length);
  final large = nodes.length > 220;
  final double effectiveRange =
      large ? 0.0 : 280.0 + math.min(120.0, nodes.length * 1.2);
  // 大图用均匀网格加速斥力（cell = range/1.8，range = cell*1.8 = 280）
  final gridCell = 156.0;
  final gridRange = gridCell * 1.8;
  final velocity = <String, List<double>>{
    for (final n in nodes) n.id: [0.0, 0.0],
  };

  String cellKey(double x, double y) =>
      '${(x / gridCell).floor()}:${(y / gridCell).floor()}';

  for (var step = 0; step < iterationCount; step++) {
    final alpha = 1.0 - step / iterationCount;
    final cooled = 0.3 + alpha * 0.7;
    final force = <String, List<double>>{
      for (final n in nodes) n.id: [0.0, 0.0],
    };

    // 斥力
    if (!large) {
      for (var i = 0; i < nodes.length; i++) {
        for (var j = i + 1; j < nodes.length; j++) {
          _repelPair(
            nodes[i], nodes[j], pos, force, cooled, effectiveRange,
          );
        }
      }
    } else {
      final grid = <String, List<String>>{};
      for (final n in nodes) {
        (grid[cellKey(pos[n.id]![0], pos[n.id]![1])] ??= []).add(n.id);
      }
      for (final n in nodes) {
        final cx = (pos[n.id]![0] / gridCell).floor();
        final cy = (pos[n.id]![1] / gridCell).floor();
        final neighborIds = <String>{
          for (var dx = -1; dx <= 1; dx++)
            for (var dy = -1; dy <= 1; dy++)
              ...?grid['${cx + dx}:${cy + dy}'],
        };
        for (final otherId in neighborIds) {
          if (otherId == n.id) continue;
          final other = nodeById[otherId]!;
          if (other.id.compareTo(n.id) < 0) continue; // 每对只算一次
          _repelPair(n, other, pos, force, cooled, gridRange);
        }
      }
    }

    // 弹簧
    for (final e in edges) {
      final a = pos[e.source];
      final b = pos[e.target];
      if (a == null || b == null) continue;
      final sameCommunity =
          communityOf[e.source] == communityOf[e.target];
      final h = fnv1a(e.id);
      final jitter = ((h % 100) / 100 - 0.5) * 2; // -1..1
      var desired = (_linkDistance + jitter * 34 -
              math.min(1.5, math.sqrt(e.weight) * 0.3) * 15) *
          (sameCommunity ? 0.82 : 1.55);
      var strength = _linkStrength * cooled;
      strength *= sameCommunity ? 1.0 : (large ? 0.025 : 0.3);
      final dx = b[0] - a[0];
      final dy = b[1] - a[1];
      final dist = math.max(0.01, math.sqrt(dx * dx + dy * dy));
      if (dist > desired * 2) strength *= 0.5; // 过度拉伸减半
      final f = (dist - desired) * strength;
      final fx = dx / dist * f;
      final fy = dy / dist * f;
      force[e.source]![0] += fx;
      force[e.source]![1] += fy;
      force[e.target]![0] -= fx;
      force[e.target]![1] -= fy;
    }

    // 向心（社群锚点 + 原点弱引力）
    for (final n in nodes) {
      final c = centerOf[communityOf[n.id]]!;
      final anchorStrength =
          large ? 0.045 * cooled : _gravity * 1.45;
      final massFactor =
          1 + math.sqrt(n.weight) * 0.1 + math.sqrt(degreeOf[n.id]!) * 0.05;
      force[n.id]![0] += (c[0] - pos[n.id]![0]) * anchorStrength / massFactor;
      force[n.id]![1] += (c[1] - pos[n.id]![1]) * anchorStrength / massFactor;
      final g = _gravity * (large ? 0.015 : 0.12) / massFactor;
      force[n.id]![0] -= pos[n.id]![0] * g;
      force[n.id]![1] -= pos[n.id]![1] * g;
    }

    // 积分
    for (final n in nodes) {
      final v = velocity[n.id]!;
      v[0] = (v[0] + force[n.id]![0]) * _damping;
      v[1] = (v[1] + force[n.id]![1]) * _damping;
      final speed = math.sqrt(v[0] * v[0] + v[1] * v[1]);
      if (speed > _maxSpeed) {
        v[0] = v[0] / speed * _maxSpeed;
        v[1] = v[1] / speed * _maxSpeed;
      }
      pos[n.id]![0] += v[0];
      pos[n.id]![1] += v[1];
    }
  }

  return {
    for (final e in pos.entries) e.key: [e.value[0], e.value[1]],
  };
}

void _repelPair(
  LayoutNodeInput a,
  LayoutNodeInput b,
  Map<String, List<double>> pos,
  Map<String, List<double>> force,
  double cooled,
  double range,
) {
  final pa = pos[a.id]!;
  final pb = pos[b.id]!;
  var dx = pa[0] - pb[0];
  var dy = pa[1] - pb[1];
  var dist = math.sqrt(dx * dx + dy * dy);
  final minSep = (a.radius + b.radius) * 2.2 + 16;
  if (dist < 0.01) {
    dist = 0.01;
    dx = 1;
    dy = 0;
  }
  var repulse = _repulsion * cooled / math.max(dist * dist, minSep * minSep / 4);
  if (range > 0 && dist < range) {
    final falloff = 1 - dist / range;
    repulse *= falloff * falloff;
  } else if (range > 0) {
    repulse *= 0.05;
  }
  var fx = dx / dist * repulse;
  var fy = dy / dist * repulse;
  if (dist < minSep) {
    final extra = (minSep - dist) * 0.35;
    fx += dx / dist * extra;
    fy += dy / dist * extra;
  }
  force[a.id]![0] += fx;
  force[a.id]![1] += fy;
  force[b.id]![0] -= fx;
  force[b.id]![1] -= fy;
}

// ---- 标签规则（照抄 graph-renderer.js 427-441, 695-714） ----

/// 是否为重点节点（prominent）
bool isProminentNode({
  required int degree,
  required int memoryCount,
  required double labelScore,
}) =>
    degree >= 5 || memoryCount >= 4 || labelScore >= 15;

/// labelScore = degree*2 + memoryCount*3 + entryCount + weight
double labelScoreOf({
  required int degree,
  required int memoryCount,
  required int entryCount,
  required double weight,
}) =>
    degree * 2 + memoryCount * 3 + entryCount + weight;

/// 标签可见性门槛。
/// [scale] 当前缩放；[selected] 是否选中；[hasSelection] 画布上是否有选中；
/// [prominent] / [degree] 见上。
bool shouldShowLabel({
  required double scale,
  required bool selected,
  required bool hasSelection,
  required bool prominent,
  required int degree,
}) {
  if (selected) return true;
  if (hasSelection) return false; // 有选中时只显示选中节点标签
  if (scale > 0.64 && prominent) return true;
  if (scale > 1.18 && degree >= 3) return true;
  return false;
}

/// 屏幕空间 AABB 是否相交（±padX/±padY padding）
bool labelBoxesOverlap(
  List<double> a, // [x1, y1, x2, y2]
  List<double> b,
  double padX,
  double padY,
) {
  return a[0] - padX < b[2] + padX &&
      a[2] + padX > b[0] - padX &&
      a[1] - padY < b[3] + padY &&
      a[3] + padY > b[1] - padY;
}

/// 事实标签清理：剥离人物名前缀与日期前缀（照抄 graph-2d.js FACT_DATE_PREFIX_RE）
String cleanupFactLabel(
  String label,
  Iterable<String> personNames,
) {
  var text = label.trim();
  // 日期前缀：2025-11-20、11月20日、2025年11月 等
  final datePrefix = RegExp(
    r'^(?:\d{4}[-/年])?\d{1,2}[-/月]\d{1,2}[日号]?\s*[:：,，-]?\s*',
  );
  text = text.replaceAll(datePrefix, '');
  // 人物名前缀（最长优先，最多剥 2 层）；剥完去掉开头的连接字
  final names = personNames
      .where((n) => n.trim().isNotEmpty)
      .toList()
    ..sort((a, b) => b.length.compareTo(a.length));
  var stripped = 0;
  for (final name in names) {
    if (stripped >= 2) break;
    if (text.startsWith(name) && text.length - name.length >= 2) {
      text = text.substring(name.length).trimLeft();
      while (text.isNotEmpty &&
          const {'的', '在', '是', '要', '已', '把', '和', '说', ':', '：', '，', ' '}
              .contains(text[0])) {
        text = text.substring(1);
      }
      stripped++;
    }
  }
  return text.trim();
}

/// 截断标签（普通 24 字符 / 重点 28 字符）
String truncateLabel(String text, {bool center = false}) {
  final maxChars = center ? 28 : 24;
  if (text.length <= maxChars) return text;
  return '${text.substring(0, maxChars)}…';
}

/// 标签字号：round(clamp(11*scale, 10, 18))，整数化让缩放产生间隙
double labelFontSize(double scale) =>
    clampDouble(11 * scale, 10, 18).roundToDouble();

/// 节点半径：r = 4 + sqrt(weight)*0.75 + sqrt(memoryCount)*0.4，clamp [4,10]
double nodeWorldRadius({
  required double weight,
  required int memoryCount,
  bool isCenter = false,
  bool selected = false,
}) {
  var r = 4.0 +
      math.sqrt(clampDouble(weight, 0, 20)) * 0.75 +
      math.sqrt(clampDouble(memoryCount.toDouble(), 0, 15)) * 0.4;
  if (isCenter) {
    r = math.min(15, r * 1.65);
  }
  if (selected) r += 1.5;
  return clampDouble(r, 4, 10);
}

/// 视口适配：scale = min(w*0.92/W, h*0.92/H) clamp [0.06, 1.65]
({double scale, double tx, double ty}) fitViewport({
  required SizeInputLike bounds,
  required double viewportWidth,
  required double viewportHeight,
}) {
  final w = math.max(1.0, bounds.width);
  final h = math.max(1.0, bounds.height);
  var scale = math.min(
    viewportWidth * 0.92 / w,
    viewportHeight * 0.92 / h,
  );
  scale = clampDouble(scale, 0.06, 1.65);
  final tx = viewportWidth / 2 - bounds.centerX * scale;
  final ty = viewportHeight / 2 - bounds.centerY * scale;
  return (scale: scale, tx: tx, ty: ty);
}

class SizeInputLike {
  final double width;
  final double height;
  final double centerX;
  final double centerY;

  const SizeInputLike({
    required this.width,
    required this.height,
    required this.centerX,
    required this.centerY,
  });
}

/// 边弯曲：垂向 bend = sign * min(24, len*0.065)，方向由边 id hash 决定
double edgeBend(String edgeId, double length) {
  final sign = fnv1a(edgeId).isOdd ? 1.0 : -1.0;
  return sign * math.min(24, length * 0.065);
}

/// 贝塞尔二次曲线上的点（t ∈ [0,1]），粒子与命中测试可用
List<double> quadraticPoint(
  double x0, double y0,
  double cx, double cy,
  double x1, double y1,
  double t,
) {
  final mt = 1 - t;
  return [
    mt * mt * x0 + 2 * mt * t * cx + t * t * x1,
    mt * mt * y0 + 2 * mt * t * cy + t * t * y1,
  ];
}
