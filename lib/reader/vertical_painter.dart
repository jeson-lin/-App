// lib/reader/vertical_painter.dart
import 'dart:math' as math;
import 'package:flutter/material.dart';

class VerticalPagePainter extends CustomPainter {
  final String fullText;
  final TextRange range;
  final TextStyle style;
  final EdgeInsets padding;
  final double columnGap;
  final int? debugIndex;
  final ValueNotifier<int?>? lastIndexNotifier;

  const VerticalPagePainter({
    required this.fullText,
    required this.range,
    required this.style,
    this.padding = const EdgeInsets.all(20),
    this.columnGap = 12,
    this.debugIndex,
    this.lastIndexNotifier,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final usableWidth = size.width - padding.left - padding.right;
    final usableHeight = size.height - padding.top - padding.bottom;
    if (usableWidth <= 0 || usableHeight <= 0 || range.isCollapsed) return;

    // probe single CJK character size
    final probe = TextPainter(
      text: TextSpan(text: '一', style: style),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: 1000);
    final charW = probe.width;
    final charH = probe.height;

    // number of columns (right-to-left) and rows (top-to-bottom)
    final cols = math.max(1, ((usableWidth + columnGap) / (charW + columnGap)).floor());
    final rows = math.max(1, ((usableHeight + charH * 0.2) / charH).floor());

    int col = 0;
    int row = 0;

    final start = range.start.clamp(0, fullText.length);
    final end = range.end.clamp(0, fullText.length);
    int lastDrawn = start - 1;

    for (int i = start; i < end; ) {
      final ch = fullText[i];

      // paragraph separator: go to next column
      if (ch == '\n') {
        col += 1;
        row = 0;
        if (col >= cols) {
          // full page; stop drawing (this newline belonged to this page)
          lastDrawn = i;
          break;
        }
        lastDrawn = i;
        i += 1;
        continue;
      }

      // if no room for this char, stop (typesetter won't put overflow here)
      if (col >= cols || row >= rows) {
        break;
      }

      // compute glyph origin (vertical layout: right-to-left columns)
      final x = padding.left + usableWidth - (col + 1) * charW - col * columnGap;
      final y = padding.top + row * charH;

      final tp = TextPainter(
        text: TextSpan(text: ch, style: style),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: charW + 1);

      tp.paint(canvas, Offset(x, y));

      // debug dot on last glyph of page preview
      if (debugIndex != null && debugIndex == i) {
        final paint = Paint()..color = const Color(0xFF1E88E5);
        canvas.drawCircle(Offset(x + charW * .5, y + charH * .5), 4, paint);
      }

      lastDrawn = i;
      row += 1;
      i += 1;

      if (row >= rows) {
        row = 0;
        col += 1;
      }
    }

    lastIndexNotifier?.value = lastDrawn;
  }

  @override
  bool shouldRepaint(covariant VerticalPagePainter oldDelegate) {
    return fullText != oldDelegate.fullText ||
           range != oldDelegate.range ||
           style != oldDelegate.style ||
           padding != oldDelegate.padding ||
           columnGap != oldDelegate.columnGap ||
           debugIndex != oldDelegate.debugIndex;
  }
}