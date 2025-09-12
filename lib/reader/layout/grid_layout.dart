// lib/reader/layout/grid_layout.dart
import 'package:flutter/material.dart';

({Size charSize, int cols, int rows, double innerW, double innerH}) computeGrid({
  required TextStyle style,
  required EdgeInsets padding,
  required double columnGap,
  required Size pageSize,
}) {
  final tp = TextPainter(
    text: TextSpan(text: '一', style: style),
    textDirection: TextDirection.ltr,
    maxLines: 1,
  )..layout(maxWidth: double.infinity);

  final cw = tp.size.width;
  final ch = tp.size.height;

  final innerW = pageSize.width - padding.left - padding.right;
  final innerH = pageSize.height - padding.top - padding.bottom;

  final cols = innerW <= 0
      ? 1
      : ((innerW + columnGap) / (cw + columnGap)).floor().clamp(1, 9999);
  final rows = innerH <= 0 ? 1 : (innerH / ch).floor().clamp(1, 9999);

  return (
    charSize: Size(cw, ch),
    cols: cols,
    rows: rows,
    innerW: innerW,
    innerH: innerH,
  );
}
