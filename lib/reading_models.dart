import 'book.dart';

class ReadingProgress {
  const ReadingProgress({
    required this.bookId,
    this.currentPage,
    this.totalPages,
    this.epubLocation,
    this.completion,
    required this.lastReadAt,
    this.lastPosition,
  });

  final String bookId;
  final int? currentPage;
  final int? totalPages;
  final String? epubLocation;
  final double? completion;
  final DateTime lastReadAt;
  final String? lastPosition;

  factory ReadingProgress.fromRow(Map<String, Object?> row) => ReadingProgress(
        bookId: row['book_id']! as String,
        currentPage: row['current_page'] as int?,
        totalPages: row['total_pages'] as int?,
        epubLocation: row['epub_location'] as String?,
        completion: (row['completion'] as num?)?.toDouble(),
        lastReadAt: DateTime.parse(row['last_read_at']! as String),
        lastPosition: row['last_position'] as String?,
      );
}

class ReadingBookmark {
  const ReadingBookmark({
    required this.id,
    required this.bookId,
    required this.name,
    this.page,
    this.location,
    required this.format,
    required this.createdAt,
    required this.updatedAt,
  });

  final int id;
  final String bookId;
  final String name;
  final int? page;
  final String? location;
  final String format;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory ReadingBookmark.fromRow(Map<String, Object?> row) => ReadingBookmark(
        id: row['id']! as int,
        bookId: row['book_id']! as String,
        name: row['name']! as String,
        page: row['page_number'] as int?,
        location: row['reading_location'] as String?,
        format: row['reading_format']! as String,
        createdAt: DateTime.parse(row['created_at']! as String),
        updatedAt: DateTime.parse(row['updated_at']! as String),
      );
}

class DownloadedBook {
  const DownloadedBook({
    required this.book,
    required this.format,
    required this.localPath,
    required this.sizeBytes,
  });

  final Book book;
  final String format;
  final String localPath;
  final int sizeBytes;
}

class BookNote {
  const BookNote({
    required this.id,
    required this.bookId,
    required this.content,
    required this.createdAt,
    required this.updatedAt,
  });

  final int id;
  final String bookId;
  final String content;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory BookNote.fromRow(Map<String, Object?> row) => BookNote(
        id: row['id']! as int,
        bookId: row['book_id']! as String,
        content: row['content']! as String,
        createdAt: DateTime.parse(row['created_at']! as String),
        updatedAt: DateTime.parse(row['updated_at']! as String),
      );
}
