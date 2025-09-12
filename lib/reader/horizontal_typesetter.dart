// lib/reader/horizontal_typesetter.dart
import 'package:flutter/material.dart';
import 'layout/grid_layout.dart';

class HPageRange {
  final int start;
  final int end;
  HPageRange(this.start, this.end);
}

class HorizontalTypesetter {
  HorizontalTypesetter({
    required this.text,
    required this.style,
    required this.padding,
    this.columnGap = 0, // 橫排一般不需要字距補償
  });

  final String text;
  final TextStyle style;
  final EdgeInsets padding;
  final double columnGap;

  List<HPageRange> paginate(Size pageSize) {
    final pages = <HPageRange>[];
    final grid = computeGrid(
      style: style,
      padding: padding,
      columnGap: columnGap,
      pageSize: pageSize,
    );

    final cols = grid.cols; // 一行可容納字數
    final rows = grid.rows; // 一頁可容納行數

    int i = 0;
    while (i < text.length) {
      int col = 0;
      int row = 0;
      int cursor = i;
      while (cursor < text.length) {
        final ch = text[cursor];
        if (ch == '\n') {
          // 換行：到下一行
          row += 1;
          col = 0;
          cursor += 1;
          if (row >= rows) break;
          continue;
        }
        if (col >= cols) {
          row += 1;
          col = 0;
          if (row >= rows) break;
        }
        col += 1;
        cursor += 1;
      }
      pages.add(HPageRange(i, cursor));
      i = cursor;
    }
    return pages;
  }
}
