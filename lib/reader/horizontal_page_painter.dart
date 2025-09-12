// lib/reader/horizontal_page_painter.dart
import 'package:flutter/material.dart';
import 'layout/grid_layout.dart';

class HorizontalPagePainter extends CustomPainter {
  HorizontalPagePainter({
    required this.text,
    required this.range,
    required this.style,
    required this.padding,
    this.columnGap = 0,
    this.textColor,
    this.onLastPaintedIndex,
  });

  final String text;
  final TextRange range;
  final TextStyle style;
  final EdgeInsets padding;
  final double columnGap;
  final Color? textColor;
  final ValueChanged<int>? onLastPaintedIndex;

  @override
  void paint(Canvas canvas, Size size) {
    final grid = computeGrid(
      style: style,
      padding: padding,
      columnGap: columnGap,
      pageSize: size,
    );
    final cw = grid.charSize.width;
    final ch = grid.charSize.height;
    final cols = grid.cols;
    final rows = grid.rows;
    final paintStyle = style.copyWith(color: textColor ?? style.color);

    double originX = padding.left;
    double originY = padding.top;

    int col = 0;
    int row = 0;
    int i = range.start;
    int last = range.start - 1;

    final tp = TextPainter(
      textDirection: TextDirection.ltr,
      maxLines: 1,
    );

    while (i < range.end && i < text.length) {
      final chStr = text[i];
      if (chStr == '\n') {
        row += 1;
        col = 0;
        i += 1;
        if (row >= rows) break;
        originX = padding.left;
        originY += ch;
        continue;
      }
      if (col >= cols) {
        row += 1;
        col = 0;
        if (row >= rows) break;
        originX = padding.left;
        originY += ch;
      }
      tp.text = TextSpan(text: chStr, style: paintStyle);
      tp.layout();
      tp.paint(canvas, Offset(originX, originY));
      last = i;
      col += 1;
      originX += cw + columnGap;
      i += 1;
    }
    onLastPaintedIndex?.call(last);
  }

  @override
  bool shouldRepaint(covariant HorizontalPagePainter oldDelegate) {
    return text != oldDelegate.text ||
        range != oldDelegate.range ||
        style != oldDelegate.style ||
        padding != oldDelegate.padding ||
        columnGap != oldDelegate.columnGap ||
        textColor != oldDelegate.textColor;
  }
}
