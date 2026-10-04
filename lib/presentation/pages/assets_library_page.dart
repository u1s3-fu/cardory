// 资产库：跨项目的资产与附件总览。
//
// 资产与附件的登记、删除仍在各项目详情内进行；本页把全量数据汇总展示，
// 支持按项目区分、按到期紧急度分组、标签筛选与名称搜索，并提供附件解密
// 导出与跳转所属项目的入口。详情弹窗内的「编辑资产」经由 [onEditAsset]
// 打开与项目详情一致的编辑器。

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../domain/attachment_repository.dart';
import '../../domain/asset_template.dart';
import '../../domain/cardory_models.dart';
import '../../domain/schedule_queries.dart';
import '../cardory_theme.dart';
import '../widgets/asset_detail_dialog.dart';
import '../widgets/badges.dart';

/// 资产库分区页：资产/附件双标签总览。
///
/// 纯展示组件：数据与回调全部由 Shell 注入；[attachmentStore] 为空时
/// 附件页降级提示（附件正文的读写依赖附件存储）。
class AssetsLibraryPage extends StatefulWidget {
  const AssetsLibraryPage({
    super.key,
    required this.projects,
    required this.assets,
    this.assetTags = const [],
    this.templates = const [],
    this.attachmentStore,
    required this.onOpenProject,
    required this.onEditAsset,
  });

  /// 全部项目（附件挂载在项目上，按项目分组展示）。
  final List<ProjectData> projects;

  /// 全部资产（内存投影本就是跨项目扁平清单）。
  final List<AssetData> assets;
  final List<AssetTag> assetTags;

  /// 资产类型模板（解析模板名与到期字段）。
  final List<AssetTemplate> templates;

  final AttachmentRepository? attachmentStore;

  /// 跳转项目详情。
  final ValueChanged<String> onOpenProject;

  /// 编辑资产（复用 Shell 的资产编辑器；编辑后数据经 Shell 刷新回流）。
  final Future<AssetData?> Function(AssetData asset) onEditAsset;

  @override
  State<AssetsLibraryPage> createState() => _AssetsLibraryPageState();
}

class _AssetsLibraryPageState extends State<AssetsLibraryPage> {
  int _tabIndex = 0;
  String? _filterProjectId;
  String? _filterTagId;
  String _query = '';

  String get _trimmedQuery => _query.trim().toLowerCase();

  bool _matchesQuery(String name) =>
      _trimmedQuery.isEmpty || name.toLowerCase().contains(_trimmedQuery);

  bool _matchesProject(String projectId) =>
      _filterProjectId == null || projectId == _filterProjectId;

  List<AssetData> get _filteredAssets => widget.assets.where((asset) {
    if (!_matchesProject(asset.projectId)) return false;
    final tag = _filterTagId;
    if (tag != null && !asset.tagIds.contains(tag)) return false;
    return _matchesQuery(asset.name);
  }).toList();

  /// 按项目分组的附件（项目保持列表顺序，组内按创建时间倒序）；
  /// 项目筛选命中时只保留对应项目。
  List<({ProjectData project, List<AttachmentData> attachments})>
  get _attachmentGroups => [
    for (final project in widget.projects)
      if (_matchesProject(project.id))
        if (_matchesQuery(project.title) ||
            project.attachments.any(
              (attachment) => _matchesQuery(attachment.fileName),
            ))
          (
            project: project,
            attachments: [
              ...project.attachments.where(
                (attachment) => _matchesQuery(attachment.fileName),
              ),
            ]..sort((a, b) => b.createdAt.compareTo(a.createdAt)),
          ),
  ];

  int get _attachmentCount => widget.projects.fold(
    0,
    (sum, project) => sum + project.attachments.length,
  );

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: SegmentedButton<int>(
                segments: [
                  ButtonSegment(
                    value: 0,
                    icon: const Icon(Icons.category_outlined),
                    label: Text('资产（${widget.assets.length}）'),
                  ),
                  ButtonSegment(
                    value: 1,
                    icon: const Icon(Icons.attach_file_outlined),
                    label: Text('附件（$_attachmentCount）'),
                  ),
                ],
                selected: {_tabIndex},
                onSelectionChanged: (selection) =>
                    setState(() => _tabIndex = selection.first),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        _buildProjectFilter(),
        const SizedBox(height: 6),
        TextField(
          key: const Key('assets-library-search'),
          onChanged: (value) => setState(() => _query = value),
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.search_outlined),
            hintText: '搜索名称',
            isDense: true,
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 14),
        if (_tabIndex == 0) ...[
          _buildTagFilter(),
          const SizedBox(height: 6),
          Expanded(child: _buildAssetsTab()),
        ] else
          Expanded(child: _buildAttachmentsTab()),
      ],
    );
  }

  /// 项目筛选：对资产与附件两个页签同时生效。
  Widget _buildProjectFilter() {
    if (widget.projects.isEmpty) return const SizedBox.shrink();
    return Wrap(
      key: const Key('assets-library-project-filter'),
      spacing: 8,
      runSpacing: 8,
      children: [
        FilterChip(
          label: const Text('全部项目'),
          selected: _filterProjectId == null,
          onSelected: (_) => setState(() => _filterProjectId = null),
        ),
        for (final project in widget.projects)
          FilterChip(
            label: Text(project.title),
            selected: _filterProjectId == project.id,
            onSelected: (_) => setState(() => _filterProjectId = project.id),
          ),
      ],
    );
  }

  Widget _buildTagFilter() {
    if (widget.assetTags.isEmpty) return const SizedBox.shrink();
    final tagNameById = {for (final tag in widget.assetTags) tag.id: tag.name};
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        FilterChip(
          label: const Text('全部'),
          selected: _filterTagId == null,
          onSelected: (_) => setState(() => _filterTagId = null),
        ),
        for (final entry in tagNameById.entries)
          FilterChip(
            label: Text(entry.value),
            selected: _filterTagId == entry.key,
            onSelected: (_) => setState(() => _filterTagId = entry.key),
          ),
      ],
    );
  }

  // ---- 资产总览 ---------------------------------------------------------

  Widget _buildAssetsTab() {
    if (widget.assets.isEmpty) {
      return const EmptyCard(text: '还没有登记任何资产。在项目详情的「资产」面板登记后，会汇总展示在这里。');
    }
    final filtered = _filteredAssets;
    if (filtered.isEmpty) {
      return const EmptyCard(text: '没有符合筛选条件的资产。');
    }
    final dueByAsset = assetNextDueDates(widget.assets, widget.templates);
    final today = localDayKey(DateTime.now());
    final buckets = _DueBuckets(today);
    for (final asset in filtered) {
      buckets.add(asset, dueByAsset[asset.id]);
    }
    final templateNameById = {
      for (final template in widget.templates) template.id: template.name,
    };
    final projectNameById = {
      for (final project in widget.projects) project.id: project.title,
    };
    return ListView(
      children: [
        for (final bucket in buckets.groups)
          _AssetSection(
            header: bucket.label,
            assets: bucket.assets,
            dueByAsset: dueByAsset,
            templateNameById: templateNameById,
            projectNameById: projectNameById,
            tagNameById: {for (final tag in widget.assetTags) tag.id: tag.name},
            onOpenAsset: _openAsset,
            onOpenProject: widget.onOpenProject,
          ),
      ],
    );
  }

  Future<void> _openAsset(AssetData asset) async {
    AssetTemplate? template;
    for (final candidate in widget.templates) {
      if (candidate.id == asset.templateId) template = candidate;
    }
    final project = widget.projects
        .where((item) => item.id == asset.projectId)
        .firstOrNull;
    final editRequested = await showDialog<bool>(
      context: context,
      builder: (_) => AssetDetailDialog(
        asset: asset,
        assetTags: widget.assetTags,
        template: template,
        attachments: project?.attachments ?? const [],
      ),
    );
    if (editRequested == true && mounted) {
      await widget.onEditAsset(asset);
    }
  }

  // ---- 附件总览 ---------------------------------------------------------

  Widget _buildAttachmentsTab() {
    if (widget.attachmentStore == null) {
      return const EmptyCard(text: '附件存储尚未初始化，请重新打开应用后再试。');
    }
    if (_attachmentCount == 0) {
      return const EmptyCard(text: '还没有任何附件。在项目详情的附件面板导入后，会汇总展示在这里。');
    }
    final groups = _attachmentGroups;
    if (groups.every((group) => group.attachments.isEmpty)) {
      return const EmptyCard(text: '没有符合筛选条件的附件。');
    }
    return ListView(
      children: [
        for (final group in groups)
          if (group.attachments.isNotEmpty)
            _AttachmentSection(
              project: group.project,
              attachments: group.attachments,
              onExport: _export,
              onOpenProject: widget.onOpenProject,
            ),
      ],
    );
  }

  Future<void> _export(AttachmentData attachment) async {
    final repository = widget.attachmentStore;
    if (repository == null) return;
    try {
      final bytes = await repository.readAttachmentBytes(attachment);
      final saved = await FilePicker.saveFile(
        fileName: attachment.fileName,
        bytes: bytes,
      );
      if (saved == null) return;
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('附件已解密导出。')));
      }
    } catch (error) {
      debugPrint('Failed to export asset library attachment: $error');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('无法导出附件，请检查目标路径和可用空间后重试。')),
        );
      }
    }
  }
}

/// 按到期紧急度分桶：已逾期 → 7 天内 → 30 天内 → 更晚 → 无到期提醒。
class _DueBuckets {
  _DueBuckets(this.today);

  final DateTime today;

  final List<AssetData> overdue = [];
  final List<AssetData> within7 = [];
  final List<AssetData> within30 = [];
  final List<AssetData> later = [];
  final List<AssetData> none = [];

  void add(AssetData asset, AssetNextDue? due) {
    if (due == null) {
      none.add(asset);
    } else if (due.date.isBefore(today)) {
      overdue.add(asset);
    } else {
      final days = due.date.difference(today).inDays;
      if (days <= 7) {
        within7.add(asset);
      } else if (days <= 30) {
        within30.add(asset);
      } else {
        later.add(asset);
      }
    }
  }

  late final List<_DueBucket> groups = [
    _DueBucket('已逾期到期', overdue, CardoryColors.error),
    _DueBucket('7 天内到期', within7, CardoryColors.warning),
    _DueBucket('30 天内到期', within30, CardoryColors.warning),
    _DueBucket('更晚到期', later, CardoryColors.primary),
    _DueBucket('无到期提醒', none, CardoryColors.gray500),
  ].where((bucket) => bucket.assets.isNotEmpty).toList();
}

class _DueBucket {
  const _DueBucket(this.label, this.assets, this.color);

  final String label;
  final List<AssetData> assets;
  final Color color;
}

/// 一组到期分桶：分组标题 + 该组资产行。
class _AssetSection extends StatelessWidget {
  const _AssetSection({
    required this.header,
    required this.assets,
    required this.dueByAsset,
    required this.templateNameById,
    required this.projectNameById,
    required this.tagNameById,
    required this.onOpenAsset,
    required this.onOpenProject,
  });

  final String header;
  final List<AssetData> assets;
  final Map<String, AssetNextDue> dueByAsset;
  final Map<String, String> templateNameById;
  final Map<String, String> projectNameById;
  final Map<String, String> tagNameById;
  final ValueChanged<AssetData> onOpenAsset;
  final ValueChanged<String> onOpenProject;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 6, bottom: 6),
          child: Row(
            children: [
              Text(
                header,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 13.5,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                '${assets.length}',
                style: TextStyle(fontSize: 12.5, color: CardoryColors.gray500),
              ),
            ],
          ),
        ),
        for (final asset in assets)
          _AssetCard(
            asset: asset,
            due: dueByAsset[asset.id],
            templateName: templateNameById[asset.templateId] ?? '未分类',
            projectTitle: projectNameById[asset.projectId],
            tagNames: [
              for (final tagId in asset.tagIds)
                if (tagNameById[tagId] != null) tagNameById[tagId]!,
            ],
            onOpenAsset: () => onOpenAsset(asset),
            onOpenProject: asset.projectId.isEmpty
                ? null
                : () => onOpenProject(asset.projectId),
          ),
      ],
    );
  }
}

/// 资产行卡片：名称、模板/项目/标签摘要行、最近到期徽标与跳项目入口。
class _AssetCard extends StatelessWidget {
  const _AssetCard({
    required this.asset,
    required this.due,
    required this.templateName,
    required this.projectTitle,
    required this.tagNames,
    required this.onOpenAsset,
    required this.onOpenProject,
  });

  final AssetData asset;
  final AssetNextDue? due;
  final String templateName;
  final String? projectTitle;
  final List<String> tagNames;
  final VoidCallback onOpenAsset;
  final VoidCallback? onOpenProject;

  @override
  Widget build(BuildContext context) {
    final summary = [
      templateName,
      if (projectTitle != null) projectTitle!,
      ...tagNames,
    ].join(' · ');
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 3),
      elevation: 0,
      color: CardoryColors.gray50,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: CardoryColors.gray200),
      ),
      child: ListTile(
        onTap: onOpenAsset,
        leading: const Icon(Icons.category_outlined),
        title: Text(asset.name),
        subtitle: Text(summary, maxLines: 1, overflow: TextOverflow.ellipsis),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (due != null)
              _DueBadge(due: due!, today: localDayKey(DateTime.now())),
            if (onOpenProject != null)
              IconButton(
                tooltip: '打开所属项目',
                icon: const Icon(Icons.open_in_new_outlined, size: 18),
                onPressed: onOpenProject,
              ),
          ],
        ),
      ),
    );
  }
}

/// 最近到期徽标：按紧急度着色（逾期红 / 临近橙 / 其余主色）。
class _DueBadge extends StatelessWidget {
  const _DueBadge({required this.due, required this.today});

  final AssetNextDue due;
  final DateTime today;

  @override
  Widget build(BuildContext context) {
    final days = due.date.difference(today).inDays;
    final overdue = days < 0;
    final urgent = days >= 0 && days <= 7;
    final color = overdue
        ? CardoryColors.error
        : urgent
        ? CardoryColors.warning
        : CardoryColors.primary;
    final label = due.date.toIso8601String().substring(0, 10);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        overdue ? '$label 已逾期' : '$label（$days 天）',
        style: TextStyle(fontSize: 11.5, color: color),
      ),
    );
  }
}

/// 一个项目的附件分组：项目名标题 + 附件行。
class _AttachmentSection extends StatelessWidget {
  const _AttachmentSection({
    required this.project,
    required this.attachments,
    required this.onExport,
    required this.onOpenProject,
  });

  final ProjectData project;
  final List<AttachmentData> attachments;
  final ValueChanged<AttachmentData> onExport;
  final ValueChanged<String> onOpenProject;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 6, bottom: 6),
          child: InkWell(
            onTap: () => onOpenProject(project.id),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  project.title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13.5,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  '${attachments.length}',
                  style: TextStyle(
                    fontSize: 12.5,
                    color: CardoryColors.gray500,
                  ),
                ),
                const Icon(Icons.chevron_right_outlined, size: 16),
              ],
            ),
          ),
        ),
        for (final attachment in attachments)
          _AttachmentCard(
            attachment: attachment,
            onExport: () => onExport(attachment),
            onOpenProject: () => onOpenProject(project.id),
          ),
      ],
    );
  }
}

/// 附件行卡片：文件名、类型/大小/时间摘要、导出与跳项目入口。
class _AttachmentCard extends StatelessWidget {
  const _AttachmentCard({
    required this.attachment,
    required this.onExport,
    required this.onOpenProject,
  });

  final AttachmentData attachment;
  final VoidCallback onExport;
  final VoidCallback onOpenProject;

  static const _kindIcons = {
    AttachmentKind.image: Icons.image_outlined,
    AttachmentKind.document: Icons.description_outlined,
    AttachmentKind.archive: Icons.folder_zip_outlined,
    AttachmentKind.other: Icons.insert_drive_file_outlined,
  };

  @override
  Widget build(BuildContext context) {
    final created = attachment.createdAt.toIso8601String().substring(0, 10);
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 3),
      elevation: 0,
      color: CardoryColors.gray50,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: CardoryColors.gray200),
      ),
      child: ListTile(
        onTap: onOpenProject,
        leading: Icon(
          _kindIcons[attachment.kind] ?? Icons.insert_drive_file_outlined,
        ),
        title: Text(
          attachment.fileName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          '${attachment.kind.label} · ${formatFileSize(attachment.size)} · $created',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: IconButton(
          tooltip: '解密导出',
          icon: const Icon(Icons.download_outlined, size: 20),
          onPressed: onExport,
        ),
      ),
    );
  }
}
