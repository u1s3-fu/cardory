import 'package:flutter/material.dart';

import '../cardory_theme.dart';

class SectionTitle extends StatelessWidget {
  const SectionTitle({super.key, required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 重点色竖条：给每个分区一个视觉起点。
          // 此前分区标题只是「16px 深灰字」，与正文的 14px 几乎同级，
          // 长页面上分区之间没有可扫读的锚点。
          Container(
            width: 3,
            height: 17,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 9),
          Flexible(
            child: Text(
              title,
              style: TextStyle(
                color: CardoryColors.gray900,
                fontSize: 17,
                letterSpacing: -0.3,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
      const SizedBox(height: 5),
      Text(
        subtitle,
        style: TextStyle(color: CardoryColors.gray600, fontSize: 13),
      ),
    ],
  );
}
