import 'package:cardory/domain/cardory_enums.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ProjectStage', () {
    test('三级阶段与中文标签', () {
      expect(ProjectStage.values.map((stage) => stage.label).toList(), [
        '计划中',
        '进行中',
        '已结束',
      ]);
    });

    test('持久化名称原样往返', () {
      for (final stage in ProjectStage.values) {
        expect(ProjectStage.fromName(stage.name), stage);
      }
    });

    test('已删除的 review 阶段归入 done', () {
      expect(ProjectStage.fromName('review'), ProjectStage.done);
    });

    test('未知名称回落 planned', () {
      expect(ProjectStage.fromName('不存在的阶段'), ProjectStage.planned);
    });
  });

  group('ProjectPriority', () {
    test('三级优先级与中文标签', () {
      expect(
        ProjectPriority.values.map((priority) => priority.label).toList(),
        ['高', '普通', '低'],
      );
    });

    test('持久化名称原样往返', () {
      for (final priority in ProjectPriority.values) {
        expect(ProjectPriority.fromName(priority.name), priority);
      }
    });

    test('已删除的 p1（中）并入 p2（普通）', () {
      expect(ProjectPriority.fromName('p1'), ProjectPriority.p2);
    });

    test('存量 p0/p2/p3 名称与含义不变', () {
      expect(ProjectPriority.fromName('p0'), ProjectPriority.p0);
      expect(ProjectPriority.fromName('p2'), ProjectPriority.p2);
      expect(ProjectPriority.fromName('p3'), ProjectPriority.p3);
    });

    test('未知名称回落 p2', () {
      expect(ProjectPriority.fromName('p9'), ProjectPriority.p2);
    });
  });
}
