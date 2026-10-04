// 资产库分区页测试：资产到期分组、项目区分、标签筛选与搜索、附件分组与降级。

import 'dart:typed_data';

import 'package:cardory/domain/attachment_repository.dart';
import 'package:cardory/domain/asset_template.dart';
import 'package:cardory/domain/cardory_models.dart';
import 'package:cardory/presentation/pages/assets_library_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

AssetTemplate _template() => const AssetTemplate(
  id: 'tpl-domain',
  name: '域名',
  fields: [
    AssetTemplateField(
      key: 'expireDate',
      label: '注册到期',
      kind: AssetFieldKind.date,
      remind: true,
    ),
  ],
);

AssetData _asset(
  String id, {
  List<String> tagIds = const [],
  String? expireDate,
  String projectId = 'project-1',
}) => AssetData(
  id: id,
  type: AssetType.software,
  name: '资产-$id',
  projectId: projectId,
  templateId: 'tpl-domain',
  tagIds: tagIds,
  customFields: {if (expireDate != null) 'expireDate': expireDate},
);

String _dateOffset(int days) {
  final date = DateTime.now().add(Duration(days: days));
  return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
}

/// 空操作附件仓储：资产库只读展示，导出动作不在本测试覆盖。
class _NoopAttachmentStore implements AttachmentRepository {
  @override
  Future<AttachmentData> importFile({
    required String sourcePath,
    required String id,
    required String fileName,
    String mimeType = '',
    String note = '',
    DateTime? createdAt,
  }) => throw UnimplementedError();

  @override
  Future<void> exportFile(AttachmentData attachment, String targetPath) async {}

  @override
  Future<Uint8List> readAttachmentBytes(AttachmentData attachment) =>
      throw UnimplementedError();

  @override
  Future<void> delete(AttachmentData attachment) async {}

  @override
  Future<bool> contains(AttachmentData attachment) async => false;

  @override
  String encryptedPath(AttachmentData attachment) => '';

  @override
  Future<void> installEncrypted(
    AttachmentData attachment,
    String downloadedPath,
  ) async {}

  @override
  Future<String> createDownloadTarget(AttachmentData attachment) async => '';

  @override
  Future<void> prune(Set<String> activeStorageKeys) async {}
}

ProjectData _project(
  String id,
  String title, {
  List<AttachmentData> attachments = const [],
}) => ProjectData(
  id: id,
  title: title,
  description: '',
  priority: ProjectPriority.p1,
  stage: ProjectStage.doing,
  progressEntries: const [],
  attachments: attachments,
);

Future<void> pumpPage(
  WidgetTester tester, {
  required List<ProjectData> projects,
  required List<AssetData> assets,
  List<AssetTag> assetTags = const [],
  List<AssetTemplate> templates = const [],
  AttachmentRepository? attachmentStore,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 900,
          height: 700,
          child: AssetsLibraryPage(
            projects: projects,
            assets: assets,
            assetTags: assetTags,
            templates: templates,
            attachmentStore: attachmentStore,
            onOpenProject: (_) {},
            onEditAsset: (_) async => null,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('空数据：两个标签页各显示空态文案', (tester) async {
    await pumpPage(tester, projects: const [], assets: const []);

    expect(find.text('资产（0）'), findsOneWidget);
    expect(find.text('附件（0）'), findsOneWidget);
    expect(find.textContaining('还没有登记任何资产'), findsOneWidget);

    await tester.tap(find.text('附件（0）'));
    await tester.pumpAndSettle();
    expect(find.textContaining('附件存储尚未初始化'), findsOneWidget);
  });

  testWidgets('资产按到期紧急度分组渲染，徽标随逾期/临近着色分组', (tester) async {
    await pumpPage(
      tester,
      projects: [_project('project-1', 'Cardory 桌面端')],
      assets: [
        _asset('a-overdue', expireDate: _dateOffset(-3)),
        _asset('a-soon', expireDate: _dateOffset(5)),
        _asset('a-later', expireDate: _dateOffset(60)),
        _asset('a-none'),
      ],
      templates: [_template()],
    );

    expect(find.text('已逾期到期'), findsOneWidget);
    expect(find.text('7 天内到期'), findsOneWidget);
    expect(find.text('无到期提醒'), findsOneWidget);
    // 四个资产各落一组：逾期/临近/更晚/无提醒。
    // 三个分桶各有条目；「更晚到期」60 天不属于 30 天内。
    expect(find.text('资产-a-overdue'), findsOneWidget);
    expect(find.text('资产-a-soon'), findsOneWidget);
    expect(find.text('资产-a-later'), findsOneWidget);
    expect(find.text('资产-a-none'), findsOneWidget);
    // 30 天内桶为空不渲染（60 天的资产落入更晚到期）。
    expect(find.text('30 天内到期'), findsNothing);
  });

  testWidgets('名称搜索过滤资产清单', (tester) async {
    await pumpPage(
      tester,
      projects: [_project('project-1', 'Cardory 桌面端')],
      assets: [_asset('alpha'), _asset('beta')],
      templates: [_template()],
    );
    expect(find.text('资产-alpha'), findsOneWidget);
    expect(find.text('资产-beta'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('assets-library-search')),
      'alpha',
    );
    await tester.pumpAndSettle();

    expect(find.text('资产-alpha'), findsOneWidget);
    expect(find.text('资产-beta'), findsNothing);
  });

  testWidgets('项目筛选：选中项目后资产与附件只保留该项目', (tester) async {
    final attachment = AttachmentData(
      id: 'att-1',
      fileName: 'license.txt',
      size: 2048,
      createdAt: DateTime(2026, 9, 1),
    );
    await pumpPage(
      tester,
      projects: [
        _project('project-1', '项目甲'),
        _project('project-2', '项目乙', attachments: [attachment]),
      ],
      assets: [
        _asset('p1-asset', projectId: 'project-1'),
        _asset('p2-asset', projectId: 'project-2'),
      ],
      templates: [_template()],
      attachmentStore: _NoopAttachmentStore(),
    );
    expect(find.text('资产-p1-asset'), findsOneWidget);
    expect(find.text('资产-p2-asset'), findsOneWidget);

    // 资产页签：选中「项目甲」。
    await tester.tap(find.text('项目甲'));
    await tester.pumpAndSettle();
    expect(find.text('资产-p1-asset'), findsOneWidget);
    expect(find.text('资产-p2-asset'), findsNothing);

    // 附件页签：项目筛选同时生效，项目乙的附件不再出现
    // （项目名文字仍存在于筛选 chip，故只断言附件内容）。
    await tester.tap(find.text('附件（1）'));
    await tester.pumpAndSettle();
    expect(find.text('license.txt'), findsNothing);

    // 切回「全部项目」恢复。
    await tester.tap(find.text('全部项目'));
    await tester.pumpAndSettle();
    expect(find.text('license.txt'), findsOneWidget);
  });

  testWidgets('标签筛选：选中标签后只保留含该标签的资产', (tester) async {
    await pumpPage(
      tester,
      projects: [_project('project-1', 'Cardory 桌面端')],
      assets: [
        _asset('tagged', tagIds: ['tag-1']),
        _asset('plain'),
      ],
      assetTags: const [AssetTag(id: 'tag-1', name: '生产环境')],
      templates: [_template()],
    );
    expect(find.text('资产-tagged'), findsOneWidget);
    expect(find.text('资产-plain'), findsOneWidget);

    await tester.tap(find.text('生产环境'));
    await tester.pumpAndSettle();

    expect(find.text('资产-tagged'), findsOneWidget);
    expect(find.text('资产-plain'), findsNothing);
  });

  testWidgets('附件页：注入存储后按项目分组展示，含导出入口', (tester) async {
    final attachment = AttachmentData(
      id: 'att-1',
      fileName: 'license.txt',
      size: 2048,
      createdAt: DateTime(2026, 9, 1),
    );
    await pumpPage(
      tester,
      projects: [
        _project('project-1', 'Cardory 桌面端', attachments: [attachment]),
        _project('project-2', '空附件项目'),
      ],
      assets: const [],
      attachmentStore: _NoopAttachmentStore(),
    );

    await tester.tap(find.text('附件（1）'));
    await tester.pumpAndSettle();

    // 项目名同时出现在筛选 chip 与分组标题，断言至少出现一次。
    expect(find.text('Cardory 桌面端'), findsWidgets);
    expect(find.text('license.txt'), findsOneWidget);
    expect(find.textContaining('2.0 KB'), findsOneWidget);
    // 无附件项目只出现在筛选 chip（1 处），不渲染附件分组标题。
    expect(find.text('空附件项目'), findsOneWidget);
    expect(find.byTooltip('解密导出'), findsOneWidget);
  });

  testWidgets('附件页搜索按文件名过滤', (tester) async {
    final a = AttachmentData(
      id: 'att-1',
      fileName: 'report.pdf',
      size: 100,
      createdAt: DateTime(2026, 9, 1),
    );
    final b = AttachmentData(
      id: 'att-2',
      fileName: 'photo.png',
      size: 100,
      createdAt: DateTime(2026, 9, 2),
    );
    await pumpPage(
      tester,
      projects: [
        _project('project-1', 'Cardory 桌面端', attachments: [a, b]),
      ],
      assets: const [],
      attachmentStore: _NoopAttachmentStore(),
    );

    await tester.tap(find.text('附件（2）'));
    await tester.pumpAndSettle();
    expect(find.text('report.pdf'), findsOneWidget);
    expect(find.text('photo.png'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('assets-library-search')),
      'report',
    );
    await tester.pumpAndSettle();

    expect(find.text('report.pdf'), findsOneWidget);
    expect(find.text('photo.png'), findsNothing);
  });
}
