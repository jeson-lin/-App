
// lib/reader/horizontal_page_painter.dart
import 'package:flutter/material.dart';

/// 單欄橫排頁面繪製器
/// - 僅負責把「該頁的文字內容」畫到畫布上
/// - 分頁已由 HorizontalTypesetter 完成，這裡依據 [range] 決定要畫的區段
class HorizontalPagePainter extends CustomPainter {
  final String text;
  final TextRange range;
  final TextStyle style;
  final EdgeInsets padding;
  final double columnGap; // 單欄模式不使用，但保留參數相容
  final Color textColor;
  final ValueChanged<int>? onLastPaintedIndex;

  HorizontalPagePainter({
    required this.text,
    required this.range,
    required this.style,
    required this.padding,
    this.columnGap = 0,
    this.textColor = const Color(0xFF222222),
    this.onLastPaintedIndex,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // 內容區域（排除 padding）
    final double contentWidth = (size.width - padding.horizontal).clamp(0.0, size.width);
    final double contentHeight = (size.height - padding.vertical).clamp(0.0, size.height);

    // 防禦：沒有可畫的空間或 range 無效
    if (contentWidth <= 0 || contentHeight <= 0 || range.start >= range.end) {
      return;
    }
    final int start = range.start.clamp(0, text.length);
    final int end = range.end.clamp(0, text.length);
    if (start >= end) return;

    final String pageText = text.substring(start, end);

    // 使用 TextPainter 以確保可靠渲染（避免 Paragraph/clip 參數錯誤導致整頁不顯示）
    final TextPainter tp = TextPainter(
      text: TextSpan(text: pageText, style: style.copyWith(color: textColor)),
      textAlign: TextAlign.left,
      textDirection: TextDirection.ltr,
      ellipsis: null,
      maxLines: null,
    );

    tp.layout(maxWidth: contentWidth);

    // 以 padding 為原點繪製
    canvas.save();
    // clip 成內容區，避免超出
    final Rect contentRect = Rect.fromLTWH(
      padding.left,
      padding.top,
      contentWidth,
      contentHeight,
    );
    canvas.clipRect(contentRect);
    canvas.translate(padding.left, padding.top);

    tp.paint(canvas, Offset.zero);
    canvas.restore();

    // 回報最後繪製到的索引（此頁的最後字元索引）
    if (onLastPaintedIndex != null) {
      onLastPaintedIndex!(end - 1);
    }
  }

  @override
  bool shouldRepaint(covariant HorizontalPagePainter oldDelegate) {
    return identical(this, oldDelegate) == false &&
        (text != oldDelegate.text ||
            range.start != oldDelegate.range.start ||
            range.end != oldDelegate.range.end ||
            padding != oldDelegate.padding ||
            columnGap != oldDelegate.columnGap ||
            textColor != oldDelegate.textColor ||
            style != oldDelegate.style);
  }
}
