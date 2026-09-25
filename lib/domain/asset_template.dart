// 资产类型模板领域模型：模板字段定义与内置模板清单。

/// 模板字段类型。
enum AssetFieldKind { text, multiline, number, date, url }

/// 资产模板中的单个字段定义。
class AssetTemplateField {
  const AssetTemplateField({
    required this.key,
    required this.label,
    this.kind = AssetFieldKind.text,
    this.required = false,
    this.remind = false,
  });

  final String key;
  final String label;
  final AssetFieldKind kind;

  /// kind==date 时 required 另有语义：该日期为资产主到期日。
  final bool required;

  /// kind==date 时有效：进入日历（P3 消费）。
  final bool remind;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'key': key,
    'label': label,
    'kind': kind.name,
    'required': required,
    'remind': remind,
  };

  factory AssetTemplateField.fromJson(Map<String, dynamic> json) {
    return AssetTemplateField(
      key: (json['key'] as String?) ?? '',
      label: (json['label'] as String?) ?? '',
      kind: _kindFromName(json['kind'] as String?),
      required: (json['required'] as bool?) ?? false,
      remind: (json['remind'] as bool?) ?? false,
    );
  }

  static AssetFieldKind _kindFromName(String? name) {
    for (final value in AssetFieldKind.values) {
      if (value.name == name) return value;
    }
    return AssetFieldKind.text;
  }

  AssetTemplateField copyWith({
    String? key,
    String? label,
    AssetFieldKind? kind,
    bool? required,
    bool? remind,
  }) {
    return AssetTemplateField(
      key: key ?? this.key,
      label: label ?? this.label,
      kind: kind ?? this.kind,
      required: required ?? this.required,
      remind: remind ?? this.remind,
    );
  }
}

/// 资产类型模板：定义一类资产可编辑的自定义字段集合。
class AssetTemplate {
  const AssetTemplate({
    required this.id,
    required this.name,
    this.typeTag,
    required this.fields,
    this.builtIn = false,
  });

  /// 内置固定 id：tpl-software / tpl-hardware / tpl-domain / tpl-cert。
  final String id;
  final String name;

  /// 'software' | 'hardware' | null，对齐旧 AssetType。
  final String? typeTag;
  final List<AssetTemplateField> fields;
  final bool builtIn;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'name': name,
    if (typeTag != null) 'typeTag': typeTag,
    'fields': fields.map((f) => f.toJson()).toList(),
    'builtIn': builtIn,
  };

  factory AssetTemplate.fromJson(Map<String, dynamic> json) {
    return AssetTemplate(
      id: (json['id'] as String?) ?? '',
      name: (json['name'] as String?) ?? '未命名模板',
      typeTag: json['typeTag'] as String?,
      fields: ((json['fields'] as List<dynamic>?) ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(AssetTemplateField.fromJson)
          .toList(growable: false),
      builtIn: (json['builtIn'] as bool?) ?? false,
    );
  }

  AssetTemplate copyWith({
    String? id,
    String? name,
    String? typeTag,
    bool clearTypeTag = false,
    List<AssetTemplateField>? fields,
    bool? builtIn,
  }) {
    return AssetTemplate(
      id: id ?? this.id,
      name: name ?? this.name,
      typeTag: clearTypeTag ? null : (typeTag ?? this.typeTag),
      fields: fields ?? this.fields,
      builtIn: builtIn ?? this.builtIn,
    );
  }
}

/// 内置模板清单（每处调用返回新实例，防止共享可变状态）。
List<AssetTemplate> builtInAssetTemplates() => [
  AssetTemplate(
    id: 'tpl-software',
    name: '软件',
    typeTag: 'software',
    builtIn: true,
    fields: const [
      AssetTemplateField(key: 'version', label: '版本'),
      AssetTemplateField(key: 'port', label: '端口', kind: AssetFieldKind.number),
      AssetTemplateField(key: 'path', label: '路径'),
    ],
  ),
  AssetTemplate(
    id: 'tpl-hardware',
    name: '硬件',
    typeTag: 'hardware',
    builtIn: true,
    fields: const [
      AssetTemplateField(key: 'serialNumber', label: '服务器序列号'),
      AssetTemplateField(key: 'network', label: '网络 / IP / 网段'),
      AssetTemplateField(key: 'serverType', label: '服务器类型'),
    ],
  ),
  AssetTemplate(
    id: 'tpl-domain',
    name: '域名',
    builtIn: true,
    fields: const [
      AssetTemplateField(key: 'registrar', label: '注册商'),
      AssetTemplateField(
        key: 'expiryDate',
        label: '到期日',
        kind: AssetFieldKind.date,
        required: true,
        remind: true,
      ),
    ],
  ),
  AssetTemplate(
    id: 'tpl-cert',
    name: 'SSL 证书',
    builtIn: true,
    fields: const [
      AssetTemplateField(key: 'issuer', label: '签发方'),
      AssetTemplateField(
        key: 'expiryDate',
        label: '到期日',
        kind: AssetFieldKind.date,
        required: true,
        remind: true,
      ),
    ],
  ),
];
