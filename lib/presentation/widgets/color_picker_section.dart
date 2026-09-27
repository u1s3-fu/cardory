// 设置对话框中的颜色编辑区。

import 'package:flutter/material.dart';

import '../cardory_theme.dart';

/// 背景色 / 强调色切换式编辑区。
///
/// 顶部 SegmentedButton 切换编辑目标，下方只渲染一份预设色点、
/// 三通道滑块与十六进制输入，作用于当前选中的颜色；
/// 颜色变化时通过 [onChanged] 实时上报（供外层在保存时读取）。
class ColorPickerSection extends StatefulWidget {
  const ColorPickerSection({
    super.key,
    required this.initialBackgroundColor,
    required this.initialThemeColor,
    this.onChanged,
  });

  final int initialBackgroundColor;
  final int initialThemeColor;

  /// 颜色值变化回调，参数为（背景色，强调色）。
  final void Function(int backgroundColor, int themeColor)? onChanged;

  @override
  State<ColorPickerSection> createState() => _ColorPickerSectionState();
}

/// 当前编辑目标。
enum _ColorTarget { background, accent }

class _ColorPickerSectionState extends State<ColorPickerSection> {
  late int _backgroundColorValue = widget.initialBackgroundColor;
  late int _themeColorValue = widget.initialThemeColor;
  late final TextEditingController _backgroundHex = TextEditingController(
    text: _themeColorHex(_backgroundColorValue),
  );
  late final TextEditingController _themeHex = TextEditingController(
    text: _themeColorHex(_themeColorValue),
  );
  _ColorTarget _target = _ColorTarget.background;

  // 强调色预设（品牌主色）。
  static const _colors = [
    0xFF6B62DF,
    0xFF0EA5E9,
    0xFF12B76A,
    0xFFF97316,
    0xFFCF79DF,
    0xFFEF7180,
    0xFF101828,
  ];
  // 背景色预设（页面底色）。
  static const _backgroundColors = [
    0xFFF5F6FC,
    0xFFFFFFFF,
    0xFFFAFAF7,
    0xFFFDF6EC,
    0xFFF7F2E7,
    0xFF0D1117,
    0xFF161B22,
  ];

  int get _activeValue => switch (_target) {
    _ColorTarget.background => _backgroundColorValue,
    _ColorTarget.accent => _themeColorValue,
  };
  List<int> get _activePresets => switch (_target) {
    _ColorTarget.background => _backgroundColors,
    _ColorTarget.accent => _colors,
  };
  TextEditingController get _activeHex => switch (_target) {
    _ColorTarget.background => _backgroundHex,
    _ColorTarget.accent => _themeHex,
  };
  String get _activeHexLabel =>
      _target == _ColorTarget.background ? '背景色十六进制' : '强调色十六进制';
  String get _activeHexHint =>
      _target == _ColorTarget.background ? '#F5F6FC' : '#6B62DF';
  String get _activeKeyPrefix =>
      _target == _ColorTarget.background ? 'background-color' : 'theme-color';

  void _setActiveColor(int value) {
    if (_target == _ColorTarget.background) {
      _setBackgroundColor(value);
    } else {
      _setThemeColor(value);
    }
  }

  void _setActiveHex(String hex) {
    if (_target == _ColorTarget.background) {
      _setBackgroundHex(hex);
    } else {
      _setThemeHex(hex);
    }
  }

  void _setActiveChannel({int? red, int? green, int? blue}) {
    if (_target == _ColorTarget.background) {
      _setBackgroundChannel(red: red, green: green, blue: blue);
    } else {
      _setThemeChannel(red: red, green: green, blue: blue);
    }
  }

  void _setBackgroundColor(int value) {
    setState(() {
      _backgroundColorValue = value;
      _backgroundHex.value = TextEditingValue(
        text: _themeColorHex(value),
        selection: TextSelection.collapsed(offset: 7),
      );
    });
    widget.onChanged?.call(_backgroundColorValue, _themeColorValue);
  }

  void _setThemeColor(int value) {
    setState(() {
      _themeColorValue = value;
      _themeHex.value = TextEditingValue(
        text: _themeColorHex(value),
        selection: TextSelection.collapsed(offset: 7),
      );
    });
    widget.onChanged?.call(_backgroundColorValue, _themeColorValue);
  }

  void _setBackgroundChannel({int? red, int? green, int? blue}) {
    final current = Color(_backgroundColorValue);
    _setBackgroundColor(
      _withChannels(current, red: red, green: green, blue: blue),
    );
  }

  void _setThemeChannel({int? red, int? green, int? blue}) {
    final current = Color(_themeColorValue);
    _setThemeColor(_withChannels(current, red: red, green: green, blue: blue));
  }

  void _setBackgroundHex(String hex) {
    final value = _parseHex(hex);
    if (value != null) _setBackgroundColor(value);
  }

  void _setThemeHex(String hex) {
    final value = _parseHex(hex);
    if (value != null) _setThemeColor(value);
  }

  @override
  void dispose() {
    _backgroundHex.dispose();
    _themeHex.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: CardoryColors.gray25,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: CardoryColors.gray200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('主题色与背景', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 10),
          SegmentedButton<_ColorTarget>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: _ColorTarget.background, label: Text('背景色')),
              ButtonSegment(value: _ColorTarget.accent, label: Text('强调色')),
            ],
            selected: {_target},
            onSelectionChanged: (selection) =>
                setState(() => _target = selection.first),
          ),
          const SizedBox(height: 12),
          Container(
            height: 40,
            decoration: BoxDecoration(
              color: Color(_activeValue),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: CardoryColors.gray200),
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final color in _activePresets)
                _ColorDot(
                  color: color,
                  selected: _activeValue == color,
                  onTap: () => _setActiveColor(color),
                ),
            ],
          ),
          const SizedBox(height: 10),
          _ColorChannelSlider(
            channel: 'red',
            label: '红',
            value: _colorChannel(Color(_activeValue).r),
            color: Colors.red,
            keyPrefix: _activeKeyPrefix,
            onChanged: (value) => _setActiveChannel(red: value),
          ),
          _ColorChannelSlider(
            channel: 'green',
            label: '绿',
            value: _colorChannel(Color(_activeValue).g),
            color: Colors.green,
            keyPrefix: _activeKeyPrefix,
            onChanged: (value) => _setActiveChannel(green: value),
          ),
          _ColorChannelSlider(
            channel: 'blue',
            label: '蓝',
            value: _colorChannel(Color(_activeValue).b),
            color: Colors.blue,
            keyPrefix: _activeKeyPrefix,
            onChanged: (value) => _setActiveChannel(blue: value),
          ),
          TextField(
            controller: _activeHex,
            maxLength: 7,
            decoration: InputDecoration(
              labelText: _activeHexLabel,
              hintText: _activeHexHint,
              counterText: '',
            ),
            onChanged: _setActiveHex,
          ),
        ],
      ),
    );
  }
}

int _colorChannel(double value) => (value * 255).round().clamp(0, 255).toInt();

int? _parseHex(String hex) {
  final normalized = hex.trim().replaceFirst('#', '').toUpperCase();
  if (normalized.length != 6) return null;
  final value = int.tryParse(normalized, radix: 16);
  if (value == null) return null;
  return 0xFF000000 | value;
}

int _withChannels(Color color, {int? red, int? green, int? blue}) =>
    (0xFF << 24) |
    ((red ?? _colorChannel(color.r)) << 16) |
    ((green ?? _colorChannel(color.g)) << 8) |
    (blue ?? _colorChannel(color.b));

/// 可点的预设色圆点，用于颜色快捷选择。
class _ColorDot extends StatelessWidget {
  const _ColorDot({
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final int color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorHex = _themeColorHex(color);
    return Semantics(
      button: true,
      selected: selected,
      label: '选择颜色 $colorHex',
      child: Tooltip(
        message: '选择 $colorHex',
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: onTap,
          child: SizedBox(
            width: 48,
            height: 48,
            child: Center(
              child: Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: Color(color),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: selected
                        ? CardoryColors.primary
                        : CardoryColors.gray200,
                    width: selected ? 3 : 1,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ColorChannelSlider extends StatelessWidget {
  const _ColorChannelSlider({
    required this.channel,
    required this.label,
    required this.value,
    required this.color,
    required this.onChanged,
    this.keyPrefix = 'theme-color',
  });

  final String channel;
  final String label;
  final int value;
  final Color color;
  final ValueChanged<int> onChanged;
  final String keyPrefix;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      SizedBox(width: 20, child: Text(label)),
      Expanded(
        child: Slider(
          key: ValueKey('$keyPrefix-$channel-slider'),
          value: value.toDouble(),
          min: 0,
          max: 255,
          activeColor: color,
          onChanged: (value) => onChanged(value.round()),
        ),
      ),
      SizedBox(
        width: 34,
        child: Text(value.toString(), textAlign: TextAlign.right),
      ),
    ],
  );
}

String _themeColorHex(int value) =>
    '#${value.toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}';
