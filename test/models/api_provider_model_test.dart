import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mewmew/models/models.dart';
import 'package:mewmew/services/storage_service.dart';
import 'package:mewmew/state/app_state.dart';

/// 供应商-模型两级配置：数据迁移、选中模型、删除回退
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<AppState> buildState() async {
    SharedPreferences.setMockInitialValues({});
    final storage = StorageService();
    await storage.init();
    final state = AppState(storage);
    await state.load();
    return state;
  }

  group('ApiConfig 模型档位', () {
    test('旧数据迁移：只有 model 字段时包装为单个模型档位', () {
      final config = ApiConfig.fromJson({
        'id': 'p1',
        'name': 'zhipu',
        'baseUrl': 'https://open.bigmodel.cn/api/paas/v4',
        'apiKey': 'sk-test',
        'model': 'glm-5.3',
        'temperature': 0.7,
      });
      expect(config.models, hasLength(1));
      expect(config.models.first.model, 'glm-5.3');
      expect(config.activeModelEntry?.model, 'glm-5.3');
    });

    test('新数据：多模型档位往返序列化，当前模型同步', () {
      final config = ApiConfig(
        id: 'p1',
        name: 'zhipu',
        baseUrl: 'https://x/api/v4',
        apiKey: 'sk',
        model: 'glm-5.2',
        models: [
          ApiModelEntry(id: 'm1', model: 'glm-5.3'),
          ApiModelEntry(id: 'm2', model: 'glm-5.2', label: '便宜'),
        ],
      );
      final restored = ApiConfig.fromJson(config.toJson());
      expect(restored.models, hasLength(2));
      expect(restored.models[0].model, 'glm-5.3');
      expect(restored.models[1].label, '便宜');
      expect(restored.activeModelEntry?.id, 'm2');
    });

    test('model 为空时 models 为空，activeModelEntry 为 null', () {
      final config = ApiConfig(
        id: 'p1',
        name: 'zhipu',
        baseUrl: 'https://x',
        apiKey: 'sk',
        model: '',
      );
      expect(config.models, isEmpty);
      expect(config.activeModelEntry, isNull);
    });
  });

  group('供应商-模型状态操作', () {
    test('setActiveModel 更新当前模型并激活供应商', () async {
      final state = await buildState();
      addTearDown(state.dispose);
      final p1 = ApiConfig(
        id: 'p1',
        name: 'zhipu',
        baseUrl: 'https://x',
        apiKey: 'sk',
        model: 'glm-5.3',
        models: [
          ApiModelEntry(id: 'm1', model: 'glm-5.3'),
          ApiModelEntry(id: 'm2', model: 'glm-5.2'),
        ],
      );
      final p2 = ApiConfig(
        id: 'p2',
        name: 'deepseek',
        baseUrl: 'https://y',
        apiKey: 'sk2',
        model: 'r1',
      );
      await state.addOrUpdateApi(p1);
      await state.addOrUpdateApi(p2);
      // 首个添加的供应商保持激活（activeApiId ??= 只在为空时设置）
      expect(state.activeApi?.id, 'p1');

      await state.setActiveModel('p1', 'm2');
      expect(state.activeApi?.id, 'p1');
      expect(state.activeApi?.model, 'glm-5.2');
    });

    test('deleteModel 移除当前模型时回退到剩余第一个', () async {
      final state = await buildState();
      addTearDown(state.dispose);
      final p1 = ApiConfig(
        id: 'p1',
        name: 'zhipu',
        baseUrl: 'https://x',
        apiKey: 'sk',
        model: 'glm-5.3',
        models: [
          ApiModelEntry(id: 'm1', model: 'glm-5.3'),
          ApiModelEntry(id: 'm2', model: 'glm-5.2'),
        ],
      );
      await state.addOrUpdateApi(p1);

      await state.deleteModel('p1', 'm1');
      expect(state.apiConfigs.first.model, 'glm-5.2');
      expect(state.apiConfigs.first.models, hasLength(1));

      await state.deleteModel('p1', 'm2');
      expect(state.apiConfigs.first.model, isEmpty);
      expect(state.apiConfigs.first.models, isEmpty);
    });

    test('持久化往返：load 后 models 保留', () async {
      final state = await buildState();
      addTearDown(state.dispose);
      await state.addOrUpdateApi(
        ApiConfig(
          id: 'p1',
          name: 'zhipu',
          baseUrl: 'https://x',
          apiKey: 'sk',
          model: 'glm-5.3',
          models: [
            ApiModelEntry(id: 'm1', model: 'glm-5.3'),
            ApiModelEntry(id: 'm2', model: 'glm-5.2'),
          ],
        ),
      );

      final storage = StorageService();
      await storage.init();
      final loaded = storage.loadApiConfigs();
      expect(loaded, hasLength(1));
      expect(loaded.first.models, hasLength(2));
      expect(loaded.first.model, 'glm-5.3');
    });
  });
}
