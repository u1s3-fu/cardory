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
      Text(
        title,
        style: TextStyle(
          color: CardoryColors.gray900,
          fontSize: 16,
          letterSpacing: -0.2,
          fontWeight: FontWeight.w700,
        ),
      ),
      const SizedBox(height: 3),
      Text(
        subtitle,
        style: TextStyle(color: CardoryColors.gray500, fontSize: 12.5),
      ),
    ],
  );
}
