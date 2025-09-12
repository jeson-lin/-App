class Paragraph {
  final String text;
  const Paragraph(this.text);
}

class Chapter {
  final String id;
  final String volumeId;
  final String title;
  final int ord;
  final List<Paragraph> paragraphs;

  const Chapter({
    required this.id,
    required this.volumeId,
    required this.title,
    required this.ord,
    required this.paragraphs,
  });
}

class ReadingMarker {
  final String chapterId;
  final int charIndex;
  const ReadingMarker({required this.chapterId, required this.charIndex});
}