// 设置对话框中的颜色编辑区。

import 'package:flutter/material.dart';

import '../cardory_theme.dart';

/// 背景色 / 强调色编辑区。
///
/// 内部管理两个主题色的预设色点、三通道滑块与十六进制输入，
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

class _ColorPickerSectionState extends State<ColorPickerSection> {
  late int _backgroundColorValue = widget.initialBackgroundColor;
  late int _themeColorValue = widget.initialThemeColor;
  late final TextEditingController _backgroundHex = TextEditingController(
    text: _themeColorHex(_backgroundColorValue),
  );
  late final TextEditingController _themeHex = TextEditingController(
    text: _themeColorHex(_themeColorValue),
  );

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

  int _colorChannel(double value) =>
      (value * 255).round().clamp(0, 255).toInt();

  void _notify() =>
      widget.onChanged?.call(_backgroundColorValue, _themeColorValue);

  void _setThemeColor(int value, {bool updateHex = true}) {
    setState(() => _themeColorValue = value);
    if (updateHex) _themeHex.text = _themeColorHex(value);
    _notify();
  }

  void _setThemeChannel({int? red, int? green, int? blue}) {
    final current = Color(_themeColorValue);
    _setThemeColor(
      Color.fromARGB(
        255,
        red ?? _colorChannel(current.r),
        green ?? _colorChannel(current.g),
        blue ?? _colorChannel(current.b),
      ).toARGB32(),
    );
  }

  void _setThemeHex(String value) {
    final normalized = value.replaceFirst('#', '');
    if (!RegExp(r'^[0-9a-fA-F]{6}$').hasMatch(normalized)) return;
    _setThemeColor(
      0xFF000000 | int.parse(normalized, radix: 16),
      updateHex: false,
    );
  }

  void _setBackgroundColor(int value, {bool updateHex = true}) {
    setState(() => _backgroundColorValue = value);
    if (updateHex) _backgroundHex.text = _themeColorHex(value);
    _notify();
  }

  void _setBackgroundChannel({int? red, int? green, int? blue}) {
    final current = Color(_backgroundColorValue);
    _setBackgroundColor(
      Color.fromARGB(
        255,
        red ?? _colorChannel(current.r),
        green ?? _colorChannel(current.g),
        blue ?? _colorChannel(current.b),
      ).toARGB32(),
    );
  }

  void _setBackgroundHex(String value) {
    final normalized = value.replaceFirst('#', '');
    if (!RegExp(r'^[0-9a-fA-F]{6}$').hasMatch(normalized)) return;
    _setBackgroundColor(
      0xFF000000 | int.parse(normalized, radix: 16),
      updateHex: false,
    );
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
          const Text('背景色', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 10),
          Container(
            height: 40,
            decoration: BoxDecoration(
              color: Color(_backgroundColorValue),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: CardoryColors.gray200),
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final color in _backgroundColors)
                _ColorDot(
                  color: color,
                  selected: _backgroundColorValue == color,
                  onTap: () => _setBackgroundColor(color),
                ),
            ],
          ),
          const SizedBox(height: 10),
          _ColorChannelSlider(
            channel: 'red',
            label: '红',
            value: _colorChannel(Color(_backgroundColorValue).r),
            color: Colors.red,
            keyPrefix: 'background-color',
            onChanged: (value) => _setBackgroundChannel(red: value),
          ),
          _ColorChannelSlider(
            channel: 'green',
            label: '绿',
            value: _colorChannel(Color(_backgroundColorValue).g),
            color: Colors.green,
            keyPrefix: 'background-color',
            onChanged: (value) => _setBackgroundChannel(green: value),
          ),
          _ColorChannelSlider(
            channel: 'blue',
            label: '蓝',
            value: _colorChannel(Color(_backgroundColorValue).b),
            color: Colors.blue,
            keyPrefix: 'background-color',
            onChanged: (value) => _setBackgroundChannel(blue: value),
          ),
          TextField(
            controller: _backgroundHex,
            maxLength: 7,
            decoration: const InputDecoration(
              labelText: '背景色十六进制',
              hintText: '#F5F6FC',
              counterText: '',
            ),
            onChanged: _setBackgroundHex,
          ),
          const SizedBox(height: 16),
          const Divider(),
          const SizedBox(height: 16),
          const Text('强调色', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 10),
          Container(
            height: 40,
            decoration: BoxDecoration(
              color: Color(_themeColorValue),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: CardoryColors.gray200),
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final color in _colors)
                _ColorDot(
                  color: color,
                  selected: _themeColorValue == color,
                  onTap: () => _setThemeColor(color),
                ),
            ],
          ),
          const SizedBox(height: 10),
          _ColorChannelSlider(
            channel: 'red',
            label: '红',
            value: _colorChannel(Color(_themeColorValue).r),
            color: Colors.red,
            onChanged: (value) => _setThemeChannel(red: value),
          ),
          _ColorChannelSlider(
            channel: 'green',
            label: '绿',
            value: _colorChannel(Color(_themeColorValue).g),
            color: Colors.green,
            onChanged: (value) => _setThemeChannel(green: value),
          ),
          _ColorChannelSlider(
            channel: 'blue',
            label: '蓝',
            value: _colorChannel(Color(_themeColorValue).b),
            color: Colors.blue,
            onChanged: (value) => _setThemeChannel(blue: value),
          ),
          TextField(
            controller: _themeHex,
            maxLength: 7,
            decoration: const InputDecoration(
              labelText: '强调色十六进制',
              hintText: '#6B62DF',
              counterText: '',
            ),
            onChanged: _setThemeHex,
          ),
        ],
      ),
    );
  }
}

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
