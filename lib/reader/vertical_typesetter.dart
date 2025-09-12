// lib/reader/vertical_typesetter.dart
import 'package:flutter/material.dart';
import 'layout/grid_layout.dart';

class PageRange {
  final int start;
  final int end;
  PageRange(this.start, this.end);
}

class VerticalTypesetter {
  VerticalTypesetter({required this.text, required this.style, required this.padding, this.columnGap = 12});

  final String text;
  final TextStyle style;
  final EdgeInsets padding;
  final double columnGap;

  List<PageRange> paginate(Size pageSize) {
    final pages = <PageRange>[];
    final grid = computeGrid(style: style, padding: padding, columnGap: columnGap, pageSize: pageSize);
    final cols = grid.cols;
    final rows = grid.rows;

    int i = 0;
    while (i < text.length) {
      int col = 0;
      int row = 0;
      int cursor = i;
      while (cursor < text.length) {
        final ch = text[cursor];
        if (ch == '\n') {
          col += 1;
          row = 0;
          cursor += 1;
          if (col >= cols) break;
          continue;
        }
        if (row >= rows) {
          col += 1;
          row = 0;
          if (col >= cols) break;
        }
        row += 1;
        cursor += 1;
      }
      pages.add(PageRange(i, cursor));
      i = cursor;
    }
    return pages;
  }
}
