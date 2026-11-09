import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart' as sqflite;
import 'package:sqflite_common/sqlite_api.dart';

import 'book.dart';
import 'reading_models.dart';

class LocalLibraryDatabase {
  LocalLibraryDatabase({
    DatabaseFactory? factory,
    Future<String> Function()? databasePath,
  })  : _factory = factory ?? sqflite.databaseFactory,
        _databasePath = databasePath ?? sqflite.getDatabasesPath;

  static const _version = 2;

  final DatabaseFactory _factory;
  final Future<String> Function() _databasePath;
  Database? _database;

  Future<Database> get _db async {
    if (_database != null) return _database!;
    final directory = await _databasePath();
    _database = await _factory.openDatabase(
      p.join(directory, 'global_library.db'),
      options: OpenDatabaseOptions(
        version: _version,
        onConfigure: (database) async {
          await database.execute('PRAGMA foreign_keys = ON');
        },
        onCreate: _createSchema,
        onUpgrade: _upgradeSchema,
      ),
    );
    return _database!;
  }

  Future<void> _createSchema(Database database, int version) async {
    await database.execute('''
      CREATE TABLE books (
        book_id TEXT PRIMARY KEY,
        external_id TEXT,
        isbn TEXT,
        title TEXT NOT NULL,
        authors TEXT NOT NULL,
        description TEXT,
        cover_url TEXT,
        publisher TEXT,
        publication_date TEXT,
        language TEXT,
        categories TEXT NOT NULL,
        page_count INTEGER,
        reading_format TEXT,
        download_status TEXT NOT NULL DEFAULT 'not_downloaded',
        local_file_path TEXT,
        source_api TEXT NOT NULL,
        metadata_json TEXT NOT NULL
      )
    ''');
    await database.execute('''
      CREATE TABLE favorites (
        book_id TEXT PRIMARY KEY REFERENCES books(book_id) ON DELETE CASCADE,
        created_at TEXT NOT NULL
      )
    ''');
    await database.execute('''
      CREATE TABLE library_books (
        book_id TEXT PRIMARY KEY REFERENCES books(book_id) ON DELETE CASCADE,
        status TEXT NOT NULL,
        added_at TEXT NOT NULL
      )
    ''');
    await database.execute('''
      CREATE TABLE reading_history (
        book_id TEXT PRIMARY KEY REFERENCES books(book_id) ON DELETE CASCADE,
        last_read_at TEXT NOT NULL
      )
    ''');
    await database.execute('''
      CREATE TABLE reading_progress (
        book_id TEXT PRIMARY KEY REFERENCES books(book_id) ON DELETE CASCADE,
        current_page INTEGER,
        total_pages INTEGER,
        epub_location TEXT,
        completion REAL,
        last_read_at TEXT NOT NULL,
        last_position TEXT
      )
    ''');
    await database.execute('''
      CREATE TABLE bookmarks (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        book_id TEXT NOT NULL REFERENCES books(book_id) ON DELETE CASCADE,
        name TEXT NOT NULL,
        page_number INTEGER,
        reading_location TEXT,
        reading_format TEXT NOT NULL,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
    await database.execute('''
      CREATE TABLE downloads (
        book_id TEXT NOT NULL REFERENCES books(book_id) ON DELETE CASCADE,
        format TEXT NOT NULL,
        status TEXT NOT NULL,
        local_file_path TEXT,
        file_size INTEGER,
        updated_at TEXT NOT NULL,
        PRIMARY KEY (book_id, format)
      )
    ''');
    await database.execute('''
      CREATE TABLE notes (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        book_id TEXT NOT NULL REFERENCES books(book_id) ON DELETE CASCADE,
        content TEXT NOT NULL,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
    await database.execute('''
      CREATE TABLE app_preferences (
        preference_key TEXT PRIMARY KEY,
        preference_value TEXT NOT NULL
      )
    ''');
    await database.execute(
      'CREATE INDEX idx_bookmarks_book_id ON bookmarks(book_id)',
    );
    await database.execute(
      'CREATE INDEX idx_history_last_read ON reading_history(last_read_at)',
    );
    await database.execute(
      'CREATE INDEX idx_downloads_status ON downloads(status)',
    );
    await database.execute(
      'CREATE INDEX idx_notes_book_id ON notes(book_id)',
    );
  }

  Future<void> _upgradeSchema(
    Database database,
    int oldVersion,
    int newVersion,
  ) async {
    if (oldVersion < 2) {
      await database.execute('''
        CREATE TABLE notes (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          book_id TEXT NOT NULL REFERENCES books(book_id) ON DELETE CASCADE,
          content TEXT NOT NULL,
          created_at TEXT NOT NULL,
          updated_at TEXT NOT NULL
        )
      ''');
      await database.execute(
        'CREATE INDEX idx_notes_book_id ON notes(book_id)',
      );
    }
  }

  Map<String, Object?> _bookValues(Book book) => {
        'book_id': book.key,
        'external_id': book.key,
        'isbn': book.isbn,
        'title': book.title,
        'authors': jsonEncode(book.authors),
        'description': book.description,
        'cover_url': book.coverUrl,
        'publisher': book.publisher,
        'publication_date': book.publicationDate,
        'language': book.language,
        'categories': jsonEncode(book.categories),
        'page_count': book.pageCount,
        'reading_format': book.readingFormat,
        'source_api': book.source,
        'metadata_json': jsonEncode(book.toJson()),
      };

  Future<void> saveBook(Book book) async {
    final database = await _db;
    await database.insert(
      'books',
      {
        ..._bookValues(book),
        'download_status': 'not_downloaded',
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
    await database.update(
      'books',
      _bookValues(book),
      where: 'book_id = ?',
      whereArgs: [book.key],
    );
  }

  Future<List<Book>> getFavorites() => _getBooksFromCollection(
        'favorites',
        orderBy: 'created_at DESC',
      );

  Future<List<Book>> getLibraryBooks() => _getBooksFromCollection(
        'library_books',
        orderBy: 'added_at DESC',
      );

  Future<List<Book>> getHistory() => _getBooksFromCollection(
        'reading_history',
        orderBy: 'last_read_at DESC',
      );

  Future<List<Book>> _getBooksFromCollection(
    String table, {
    required String orderBy,
  }) async {
    final database = await _db;
    final rows = await database.rawQuery('''
      SELECT b.metadata_json
      FROM $table collection
      JOIN books b ON b.book_id = collection.book_id
      ORDER BY collection.$orderBy
    ''');
    return rows.map(_decodeBook).toList();
  }

  Book _decodeBook(Map<String, Object?> row) => Book.fromStoredJson(
        jsonDecode(row['metadata_json']! as String) as Map<String, dynamic>,
      );

  Future<Map<String, String>> getLibraryStatuses() async {
    final database = await _db;
    final rows = await database.query('library_books');
    return {
      for (final row in rows)
        row['book_id']! as String: row['status']! as String,
    };
  }

  Future<void> saveFavorite(Book book, bool favorite) async {
    final database = await _db;
    await database.transaction((txn) async {
      await _saveBook(txn, book);
      if (favorite) {
        await txn.insert(
          'favorites',
          {'book_id': book.key, 'created_at': DateTime.now().toIso8601String()},
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      } else {
        await txn.delete('favorites', where: 'book_id = ?', whereArgs: [book.key]);
      }
    });
  }

  Future<void> saveLibraryBook(Book book, String status) async {
    final database = await _db;
    await database.transaction((txn) async {
      await _saveBook(txn, book);
      await txn.insert(
        'library_books',
        {
          'book_id': book.key,
          'status': status,
          'added_at': DateTime.now().toIso8601String(),
        },
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
      await txn.update(
        'library_books',
        {'status': status},
        where: 'book_id = ?',
        whereArgs: [book.key],
      );
    });
  }

  Future<void> removeLibraryBook(String bookId) async {
    final database = await _db;
    await database.delete(
      'library_books',
      where: 'book_id = ?',
      whereArgs: [bookId],
    );
  }

  Future<void> clearHistory() async {
    final database = await _db;
    await database.delete('reading_history');
  }

  Future<void> recordOpened(Book book) async {
    final database = await _db;
    await database.transaction((txn) async {
      await _saveBook(txn, book);
      await txn.insert(
        'reading_history',
        {'book_id': book.key, 'last_read_at': DateTime.now().toIso8601String()},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      await txn.rawDelete('''
        DELETE FROM reading_history
        WHERE book_id NOT IN (
          SELECT book_id FROM reading_history
          ORDER BY last_read_at DESC LIMIT 100
        )
      ''');
    });
  }

  Future<ReadingProgress?> getProgress(String bookId) async {
    final database = await _db;
    final rows = await database.query(
      'reading_progress',
      where: 'book_id = ?',
      whereArgs: [bookId],
      limit: 1,
    );
    return rows.isEmpty ? null : ReadingProgress.fromRow(rows.single);
  }

  Future<List<ReadingProgress>> getAllProgress() async {
    final database = await _db;
    final rows = await database.query('reading_progress');
    return rows.map(ReadingProgress.fromRow).toList();
  }

  Future<void> saveProgress(
    Book book, {
    int? page,
    int? totalPages,
    String? epubLocation,
    double? completion,
  }) async {
    final database = await _db;
    await database.transaction((txn) async {
      await _saveBook(txn, book);
      final oldRows = await txn.query(
        'reading_progress',
        where: 'book_id = ?',
        whereArgs: [book.key],
        limit: 1,
      );
      final old = oldRows.isEmpty ? null : oldRows.single;
      final currentPage = page ?? old?['current_page'] as int?;
      final pages = totalPages ?? old?['total_pages'] as int?;
      final location = epubLocation ?? old?['epub_location'] as String?;
      final savedCompletion = completion != null
          ? completion.clamp(0.0, 1.0).toDouble()
          : pages != null && pages > 0 && currentPage != null
              ? (currentPage / pages).clamp(0.0, 1.0).toDouble()
              : (old?['completion'] as num?)?.toDouble();
      final now = DateTime.now().toIso8601String();
      await txn.insert(
        'reading_progress',
        {
          'book_id': book.key,
          'current_page': currentPage,
          'total_pages': pages,
          'epub_location': location,
          'completion': savedCompletion,
          'last_read_at': now,
          'last_position': location ?? currentPage?.toString(),
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      await txn.insert(
        'reading_history',
        {'book_id': book.key, 'last_read_at': now},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      await txn.rawDelete('''
        DELETE FROM reading_history
        WHERE book_id NOT IN (
          SELECT book_id FROM reading_history
          ORDER BY last_read_at DESC LIMIT 100
        )
      ''');
    });
  }

  Future<List<ReadingBookmark>> getBookmarks(String bookId) async {
    final database = await _db;
    final rows = await database.query(
      'bookmarks',
      where: 'book_id = ?',
      whereArgs: [bookId],
      orderBy: 'created_at ASC',
    );
    return rows.map(ReadingBookmark.fromRow).toList();
  }

  Future<List<ReadingBookmark>> getAllBookmarks() async {
    final database = await _db;
    final rows = await database.query('bookmarks', orderBy: 'created_at ASC');
    return rows.map(ReadingBookmark.fromRow).toList();
  }

  Future<int> createBookmark(
    Book book, {
    required String name,
    int? page,
    String? location,
    required String format,
  }) async {
    final database = await _db;
    return database.transaction((txn) async {
      await _saveBook(txn, book);
      final existing = await txn.rawQuery(
        '''
        SELECT id FROM bookmarks
        WHERE book_id = ? AND name = ? AND page_number IS ?
          AND reading_location IS ? AND reading_format = ?
        LIMIT 1
        ''',
        [book.key, name.trim(), page, location, format],
      );
      if (existing.isNotEmpty) return existing.single['id']! as int;
      final now = DateTime.now().toIso8601String();
      return txn.insert('bookmarks', {
        'book_id': book.key,
        'name': name.trim(),
        'page_number': page,
        'reading_location': location,
        'reading_format': format,
        'created_at': now,
        'updated_at': now,
      });
    });
  }

  Future<void> renameBookmark(int id, String name) async {
    final database = await _db;
    await database.update(
      'bookmarks',
      {'name': name.trim(), 'updated_at': DateTime.now().toIso8601String()},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> deleteBookmark(int id) async {
    final database = await _db;
    await database.delete('bookmarks', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> markDownloadStatus(
    Book book,
    String format,
    String status,
  ) async {
    final database = await _db;
    await database.transaction((txn) async {
      await _saveBook(txn, book);
      await txn.insert(
        'downloads',
        {
          'book_id': book.key,
          'format': format,
          'status': status,
          'updated_at': DateTime.now().toIso8601String(),
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      final downloaded = await txn.query(
        'downloads',
        columns: ['local_file_path', 'format'],
        where: "book_id = ? AND status = 'downloaded'",
        whereArgs: [book.key],
        limit: 1,
      );
      await txn.update(
        'books',
        {
          'download_status': downloaded.isEmpty ? status : 'downloaded',
          'local_file_path':
              downloaded.isEmpty ? null : downloaded.single['local_file_path'],
          'reading_format':
              downloaded.isEmpty ? null : downloaded.single['format'],
        },
        where: 'book_id = ?',
        whereArgs: [book.key],
      );
    });
  }

  Future<void> saveDownload(
    Book book, {
    required String format,
    required String path,
    required int sizeBytes,
  }) async {
    final database = await _db;
    await database.transaction((txn) async {
      await _saveBook(txn, book);
      await txn.insert(
        'downloads',
        {
          'book_id': book.key,
          'format': format,
          'status': 'downloaded',
          'local_file_path': path,
          'file_size': sizeBytes,
          'updated_at': DateTime.now().toIso8601String(),
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      await txn.update(
        'books',
        {
          'download_status': 'downloaded',
          'local_file_path': path,
          'reading_format': format,
        },
        where: 'book_id = ?',
        whereArgs: [book.key],
      );
    });
  }

  Future<List<DownloadedBook>> getDownloadedBooks() async {
    final database = await _db;
    final rows = await database.rawQuery('''
      SELECT b.metadata_json, d.format, d.local_file_path, d.file_size
      FROM downloads d
      JOIN books b ON b.book_id = d.book_id
      WHERE d.status = 'downloaded' AND d.local_file_path IS NOT NULL
      ORDER BY d.updated_at DESC
    ''');
    return rows
        .map(
          (row) => DownloadedBook(
            book: _decodeBook(row),
            format: row['format']! as String,
            localPath: row['local_file_path']! as String,
            sizeBytes: row['file_size'] as int? ?? 0,
          ),
        )
        .toList();
  }

  Future<DownloadedBook?> getDownload(String bookId, String format) async {
    final database = await _db;
    final rows = await database.rawQuery(
      '''
      SELECT b.metadata_json, d.format, d.local_file_path, d.file_size
      FROM downloads d
      JOIN books b ON b.book_id = d.book_id
      WHERE d.book_id = ? AND d.format = ? AND d.status = 'downloaded'
      ''',
      [bookId, format],
    );
    if (rows.isEmpty || rows.single['local_file_path'] == null) return null;
    final row = rows.single;
    return DownloadedBook(
      book: _decodeBook(row),
      format: row['format']! as String,
      localPath: row['local_file_path']! as String,
      sizeBytes: row['file_size'] as int? ?? 0,
    );
  }

  Future<void> removeDownload(String bookId, String format) async {
    final database = await _db;
    await database.transaction((txn) async {
      await txn.delete(
        'downloads',
        where: 'book_id = ? AND format = ?',
        whereArgs: [bookId, format],
      );
      final remaining = await txn.query(
        'downloads',
        columns: ['format', 'local_file_path'],
        where: "book_id = ? AND status = 'downloaded'",
        whereArgs: [bookId],
        limit: 1,
      );
      await txn.update(
        'books',
        {
          'download_status': remaining.isEmpty ? 'not_downloaded' : 'downloaded',
          'local_file_path':
              remaining.isEmpty ? null : remaining.single['local_file_path'],
          'reading_format':
              remaining.isEmpty ? null : remaining.single['format'],
        },
        where: 'book_id = ?',
        whereArgs: [bookId],
      );
    });
  }

  Future<void> clearHistoryEntry(String bookId) async {
    final database = await _db;
    await database.delete(
      'reading_history',
      where: 'book_id = ?',
      whereArgs: [bookId],
    );
  }

  Future<void> saveNote(String bookId, String content, {int? id}) async {
    final database = await _db;
    final now = DateTime.now().toIso8601String();
    if (id == null) {
      await database.insert('notes', {
        'book_id': bookId,
        'content': content,
        'created_at': now,
        'updated_at': now,
      });
    } else {
      await database.update(
        'notes',
        {'content': content, 'updated_at': now},
        where: 'id = ? AND book_id = ?',
        whereArgs: [id, bookId],
      );
    }
  }

  Future<List<BookNote>> getNotes(String bookId) async {
    final database = await _db;
    final rows = await database.query(
      'notes',
      where: 'book_id = ?',
      whereArgs: [bookId],
      orderBy: 'updated_at DESC',
    );
    return rows.map(BookNote.fromRow).toList();
  }

  Future<void> deleteNote(String bookId, int id) async {
    final database = await _db;
    await database.delete(
      'notes',
      where: 'book_id = ? AND id = ?',
      whereArgs: [bookId, id],
    );
  }

  Future<void> savePreference(String key, String value) async {
    final database = await _db;
    await database.insert(
      'app_preferences',
      {'preference_key': key, 'preference_value': value},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<String?> getPreference(String key) async {
    final database = await _db;
    final rows = await database.query(
      'app_preferences',
      columns: ['preference_value'],
      where: 'preference_key = ?',
      whereArgs: [key],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.single['preference_value'] as String;
  }

  Future<void> _saveBook(Transaction txn, Book book) async {
    await txn.insert(
      'books',
      {
        ..._bookValues(book),
        'download_status': 'not_downloaded',
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
    await txn.update(
      'books',
      _bookValues(book),
      where: 'book_id = ?',
      whereArgs: [book.key],
    );
  }

  Future<void> close() async {
    await _database?.close();
    _database = null;
  }
}
