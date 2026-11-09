import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'book.dart';
import 'book_repository.dart';
import 'local_book_storage.dart';
import 'local_library_database.dart';
import 'reading_models.dart';

/// Owns application state and persists user data in the local database.
class AppProvider extends ChangeNotifier {
  AppProvider({
    BookRepository? repository,
    LocalLibraryDatabase? database,
    LocalBookStorage? bookStorage,
  })  : _repository = repository ?? BookRepository(),
        _database = database ?? LocalLibraryDatabase(),
        _bookStorage = bookStorage ?? LocalBookStorage();

  static const _favoritesKey = 'global_library_favorites_v1';
  static const _libraryKey = 'global_library_library_v1';
  static const _libraryStatusesKey = 'global_library_library_statuses_v1';
  static const _historyKey = 'global_library_history_v1';
  static const _bookmarksKey = 'global_library_bookmarks_v1';
  static const _epubLocationsKey = 'global_library_epub_locations_v1';
  static const _themeKey = 'global_library_dark_mode_v1';
  static const _migrationKey = 'global_library_sqlite_migrated_v1';

  final BookRepository _repository;
  final LocalLibraryDatabase _database;
  final LocalBookStorage _bookStorage;
  final Set<String> _downloadsInProgress = {};
  final Map<String, double?> _downloadProgress = {};
  SharedPreferences? _prefs;
  Timer? _debounce;

  List<Book> _results = [];
  List<Book> _favorites = [];
  List<Book> _library = [];
  final Map<String, String> _libraryStatuses = {};
  List<Book> _history = [];
  List<DownloadedBook> _downloadedBooks = [];
  final Map<String, ReadingProgress> _progress = {};
  final Map<String, List<ReadingBookmark>> _bookmarks = {};
  bool _isLoading = false;
  bool _isLoadingMore = false;
  bool _hasMore = false;
  String? _error;
  List<String> _sourceWarnings = [];
  String _query = '';
  bool _isDark = false;
  BookSearchType _searchType = BookSearchType.keyword;
  int _nextPage = 1;
  int _searchGeneration = 0;

  List<Book> get results => List.unmodifiable(_results);
  List<Book> get favorites => List.unmodifiable(_favorites);
  List<Book> get library => List.unmodifiable(_library);
  List<Book> get history => List.unmodifiable(_history);
  List<DownloadedBook> get downloadedBooks =>
      List.unmodifiable(_downloadedBooks);
  bool get isLoading => _isLoading;
  bool get isLoadingMore => _isLoadingMore;
  bool get hasMore => _hasMore;
  String? get error => _error;
  List<String> get sourceWarnings => List.unmodifiable(_sourceWarnings);
  String get query => _query;
  bool get isDark => _isDark;
  BookSearchType get searchType => _searchType;
  ThemeMode get themeMode => _isDark ? ThemeMode.dark : ThemeMode.light;

  Future<List<Book>> getRecommendations(Book book) =>
      _repository.getRecommendations(book);

  Future<String> getPlainText(Book book) => _repository.getPlainText(book);

  Future<Uint8List> getEbookBytes(Book book, {required bool epub}) async {
    final format = epub ? 'epub' : 'pdf';
    final download = await _database.getDownload(book.key, format);
    if (download != null) {
      final file = File(download.localPath);
      if (!await file.exists()) {
        throw FileSystemException(
          'The downloaded ${format.toUpperCase()} file is missing.',
          download.localPath,
        );
      }
      return file.readAsBytes();
    }
    return _repository.getEbookBytes(book, epub: epub);
  }

  Future<void> initialize() async {
    _prefs = await SharedPreferences.getInstance();
    if (!(_prefs!.getBool(_migrationKey) ?? false)) {
      await _migrateLegacyPreferences();
    }

    _favorites = await _database.getFavorites();
    _library = await _database.getLibraryBooks();
    _libraryStatuses
      ..clear()
      ..addAll(await _database.getLibraryStatuses());
    _history = await _database.getHistory();
    _progress
      ..clear()
      ..addEntries(
        (await _database.getAllProgress()).map(
          (item) => MapEntry(item.bookId, item),
        ),
      );
    _bookmarks.clear();
    for (final bookmark in await _database.getAllBookmarks()) {
      _bookmarks.putIfAbsent(bookmark.bookId, () => []).add(bookmark);
    }
    _downloadedBooks = await _database.getDownloadedBooks();
    final availableDownloads = <DownloadedBook>[];
    for (final item in _downloadedBooks) {
      if (await File(item.localPath).exists()) {
        availableDownloads.add(item);
      } else {
        await _database.removeDownload(item.book.key, item.format);
      }
    }
    _downloadedBooks = availableDownloads;
    final savedTheme = await _database.getPreference(_themeKey);
    _isDark = savedTheme == null
        ? _prefs!.getBool(_themeKey) ?? false
        : savedTheme == 'true';
    if (savedTheme == null) {
      await _database.savePreference(_themeKey, '$_isDark');
    }
    notifyListeners();
  }

  Future<void> _migrateLegacyPreferences() async {
    final preferences = _prefs!;
    final favorites = _decodeBooks(preferences.getString(_favoritesKey));
    final library = _decodeBooks(preferences.getString(_libraryKey));
    final history = _decodeBooks(preferences.getString(_historyKey));
    final statuses = _decodeStringMap(
      preferences.getString(_libraryStatusesKey),
    );
    final legacyBookmarks = _decodeIntMap(
      preferences.getString(_bookmarksKey),
    );
    final epubLocations = _decodeStringMap(
      preferences.getString(_epubLocationsKey),
    );

    for (final book in favorites) {
      await _database.saveFavorite(book, true);
    }
    for (final book in library) {
      await _database.saveLibraryBook(
        book,
        statuses[book.key] ?? 'Want to Read',
      );
    }
    for (final book in history) {
      await _database.recordOpened(book);
    }

    final knownBooks = <String, Book>{
      for (final book in [...favorites, ...library, ...history])
        book.key: book,
    };
    for (final entry in legacyBookmarks.entries) {
      final book = knownBooks[entry.key];
      if (book == null || entry.value <= 0) continue;
      final epubLocation = epubLocations[entry.key];
      final format = epubLocation != null
          ? 'epub'
          : book.pdfUrl != null
              ? 'pdf'
              : book.plainTextUrl != null
                  ? 'text'
                  : book.epubUrl != null
                      ? 'epub'
                      : 'text';
      await _database.saveProgress(book, page: entry.value);
      await _database.createBookmark(
        book,
        name: 'Reading progress',
        page: entry.value,
        location: epubLocation,
        format: format,
      );
    }
    for (final entry in epubLocations.entries) {
      final book = knownBooks[entry.key];
      if (book != null && entry.value.isNotEmpty) {
        await _database.saveProgress(book, epubLocation: entry.value);
      }
    }
    final savedTheme = preferences.getBool(_themeKey) ?? false;
    await _database.savePreference(_themeKey, '$savedTheme');
    await preferences.setBool(_migrationKey, true);
  }

  List<Book> _decodeBooks(String? raw) {
    if (raw == null) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      return decoded
          .whereType<Map<String, dynamic>>()
          .map(Book.fromStoredJson)
          .where((book) => book.key.isNotEmpty)
          .toList();
    } on FormatException catch (error) {
      debugPrint('Ignoring malformed legacy book data: $error');
      return [];
    } on TypeError catch (error) {
      debugPrint('Ignoring malformed legacy book data: $error');
      return [];
    }
  }

  Map<String, String> _decodeStringMap(String? raw) {
    if (raw == null) return {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return {};
      return {
        for (final entry in decoded.entries)
          if (entry.key is String && entry.value is String)
            entry.key as String: entry.value as String,
      };
    } on FormatException catch (error) {
      debugPrint('Ignoring malformed legacy settings: $error');
      return {};
    } on TypeError catch (error) {
      debugPrint('Ignoring malformed legacy settings: $error');
      return {};
    }
  }

  Map<String, int> _decodeIntMap(String? raw) {
    if (raw == null) return {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return {};
      return {
        for (final entry in decoded.entries)
          if (entry.key is String &&
              entry.value is int &&
              (entry.value as int) > 0)
            entry.key as String: entry.value as int,
      };
    } on FormatException catch (error) {
      debugPrint('Ignoring malformed legacy bookmarks: $error');
      return {};
    } on TypeError catch (error) {
      debugPrint('Ignoring malformed legacy bookmarks: $error');
      return {};
    }
  }

  bool isInLibrary(Book book) =>
      _library.any((item) => item.key == book.key);

  String libraryStatus(Book book) =>
      _libraryStatuses[book.key] ?? 'Want to Read';

  Future<void> addToLibrary(
    Book book, {
    String status = 'Want to Read',
  }) async {
    await _database.saveLibraryBook(book, status);
    if (!isInLibrary(book)) _library.insert(0, book);
    _libraryStatuses[book.key] = status;
    notifyListeners();
  }

  Future<void> removeFromLibrary(Book book) async {
    await _database.removeLibraryBook(book.key);
    _library.removeWhere((item) => item.key == book.key);
    _libraryStatuses.remove(book.key);
    notifyListeners();
  }

  Future<void> setLibraryStatus(Book book, String status) async {
    if (!isInLibrary(book)) return;
    await _database.saveLibraryBook(book, status);
    _libraryStatuses[book.key] = status;
    notifyListeners();
  }

  ReadingProgress? progressFor(Book book) => _progress[book.key];

  int? bookmarkFor(Book book) => progressFor(book)?.currentPage;

  String? epubLocationFor(Book book) => progressFor(book)?.epubLocation;

  List<ReadingBookmark> bookmarksFor(Book book) =>
      List.unmodifiable(_bookmarks[book.key] ?? const []);

  Future<void> saveReadingProgress(
    Book book, {
    int? page,
    int? totalPages,
    String? epubLocation,
    double? completion,
  }) async {
    await _database.saveProgress(
      book,
      page: page,
      totalPages: totalPages,
      epubLocation: epubLocation,
      completion: completion,
    );
    final saved = await _database.getProgress(book.key);
    if (saved != null) _progress[book.key] = saved;
    _history.removeWhere((item) => item.key == book.key);
    _history.insert(0, book);
    if (_history.length > 100) _history = _history.take(100).toList();
    if (isInLibrary(book) && libraryStatus(book) == 'Want to Read') {
      await setLibraryStatus(book, 'Currently Reading');
    }
  }

  Future<void> saveBookmark(Book book, int page) async {
    if (page <= 0) return;
    await saveReadingProgress(book, page: page);
  }

  Future<void> createBookmark(
    Book book, {
    required String name,
    int? page,
    String? location,
    required String format,
  }) async {
    final id = await _database.createBookmark(
      book,
      name: name,
      page: page,
      location: location,
      format: format,
    );
    final now = DateTime.now();
    final bookmark = ReadingBookmark(
      id: id,
      bookId: book.key,
      name: name.trim(),
      page: page,
      location: location,
      format: format,
      createdAt: now,
      updatedAt: now,
    );
    _bookmarks.putIfAbsent(book.key, () => []).add(bookmark);
    notifyListeners();
  }

  Future<void> renameBookmark(
    ReadingBookmark bookmark,
    String name,
  ) async {
    await _database.renameBookmark(bookmark.id, name);
    final entries = _bookmarks[bookmark.bookId];
    if (entries == null) return;
    final index = entries.indexWhere((item) => item.id == bookmark.id);
    if (index >= 0) {
      final old = entries[index];
      entries[index] = ReadingBookmark(
        id: old.id,
        bookId: old.bookId,
        name: name.trim(),
        page: old.page,
        location: old.location,
        format: old.format,
        createdAt: old.createdAt,
        updatedAt: DateTime.now(),
      );
    }
    notifyListeners();
  }

  Future<void> deleteBookmark(ReadingBookmark bookmark) async {
    await _database.deleteBookmark(bookmark.id);
    _bookmarks[bookmark.bookId]
        ?.removeWhere((item) => item.id == bookmark.id);
    notifyListeners();
  }

  Future<void> saveEpubLocation(
    Book book,
    String cfi, {
    double? completion,
  }) async {
    await saveReadingProgress(
      book,
      epubLocation: cfi,
      completion: completion,
    );
  }

  Future<bool> isDownloaded(Book book, String format) async {
    final saved = await _database.getDownload(book.key, format);
    return saved != null && await File(saved.localPath).exists();
  }

  bool isDownloading(Book book, String format) =>
      _downloadsInProgress.contains('${book.key}:$format');

  double? downloadProgress(Book book, String format) =>
      _downloadProgress['${book.key}:$format'];

  Future<void> downloadBook(Book book, String format) async {
    if (format != 'epub' && format != 'pdf') {
      throw ArgumentError.value(format, 'format', 'Expected epub or pdf.');
    }
    final key = '${book.key}:$format';
    if (!_downloadsInProgress.add(key)) return;
    _downloadProgress[key] = null;
    notifyListeners();
    File? downloadedFile;
    try {
      final existing = await _database.getDownload(book.key, format);
      if (existing != null && await File(existing.localPath).exists()) return;

      await _database.markDownloadStatus(book, format, 'downloading');
      downloadedFile = await _bookStorage.download(
        book,
        format,
        onProgress: (received, total) {
          if (total == null || total <= 0) return;
          _downloadProgress[key] = (received / total).clamp(0.0, 1.0);
          notifyListeners();
        },
      );
      final size = await downloadedFile.length();
      await _database.saveDownload(
        book,
        format: format,
        path: downloadedFile.path,
        sizeBytes: size,
      );
      _downloadedBooks = await _database.getDownloadedBooks();
    } catch (error) {
      if (downloadedFile != null) {
        await _bookStorage.delete(downloadedFile.path);
      }
      await _database.markDownloadStatus(book, format, 'failed');
      rethrow;
    } finally {
      _downloadsInProgress.remove(key);
      _downloadProgress.remove(key);
      notifyListeners();
    }
  }

  Future<void> deleteDownload(DownloadedBook download) async {
    await _bookStorage.delete(download.localPath);
    await _database.removeDownload(download.book.key, download.format);
    _downloadedBooks = await _database.getDownloadedBooks();
    notifyListeners();
  }

  Future<List<BookNote>> notesFor(Book book) => _database.getNotes(book.key);

  Future<void> saveNote(Book book, String content, {int? id}) async {
    await _database.saveBook(book);
    await _database.saveNote(book.key, content, id: id);
  }

  Future<void> deleteNote(Book book, int noteId) =>
      _database.deleteNote(book.key, noteId);

  Future<void> toggleFavorite(Book book) async {
    final favorite = !_favorites.any((item) => item.key == book.key);
    await _database.saveFavorite(book, favorite);
    if (favorite) {
      _favorites.insert(0, book);
    } else {
      _favorites.removeWhere((item) => item.key == book.key);
    }
    notifyListeners();
  }

  bool isFavorite(Book book) =>
      _favorites.any((item) => item.key == book.key);

  Future<void> recordOpened(Book book) async {
    await _database.recordOpened(book);
    _history.removeWhere((item) => item.key == book.key);
    _history.insert(0, book);
    if (_history.length > 100) _history = _history.take(100).toList();
    if (isInLibrary(book) && libraryStatus(book) == 'Want to Read') {
      await setLibraryStatus(book, 'Currently Reading');
    }
    notifyListeners();
  }

  Future<void> clearHistory() async {
    await _database.clearHistory();
    _history.clear();
    notifyListeners();
  }

  Future<void> search(
    String value, {
    bool immediate = false,
    BookSearchType? type,
  }) async {
    if (type != null) _searchType = type;
    _query = value;
    final generation = ++_searchGeneration;
    _debounce?.cancel();
    if (value.trim().isEmpty) {
      _results = [];
      _error = null;
      _sourceWarnings = [];
      _isLoading = false;
      _isLoadingMore = false;
      _hasMore = false;
      _nextPage = 1;
      notifyListeners();
      return;
    }

    if (!immediate) {
      _debounce = Timer(const Duration(milliseconds: 450), () {
        _performSearch(value, generation: generation, type: _searchType);
      });
      _results = [];
      _sourceWarnings = [];
      _error = null;
      _hasMore = false;
      notifyListeners();
      return;
    }
    await _performSearch(value, generation: generation, type: _searchType);
  }

  Future<void> _performSearch(
    String value, {
    required int generation,
    required BookSearchType type,
    bool append = false,
  }) async {
    final requestedQuery = value.trim();
    if (requestedQuery.isEmpty) return;
    if (append) {
      _isLoadingMore = true;
    } else {
      _isLoading = true;
      _error = null;
      _sourceWarnings = [];
      _nextPage = 1;
    }
    notifyListeners();

    try {
      final page = append ? _nextPage : 1;
      final result = await _repository.searchBooks(
        requestedQuery,
        page: page,
        type: type,
      );
      if (generation == _searchGeneration &&
          _query.trim() == requestedQuery) {
        await _database.cacheSearchPage(
          _repository.searchCacheKey(requestedQuery, type),
          page,
          result.books,
        );
        _results = append
            ? _repository.mergePages(_results, result.books)
            : result.books;
        _sourceWarnings = result.sourceWarnings;
        _hasMore = result.hasMore;
        _nextPage = append ? _nextPage + 1 : 2;
      }
    } catch (error) {
      if (generation == _searchGeneration &&
          _query.trim() == requestedQuery) {
        final cached = await _database.getCachedSearchPage(
          _repository.searchCacheKey(requestedQuery, type),
          append ? _nextPage : 1,
        );
        if (cached.isNotEmpty) {
          _results = append
              ? _repository.mergePages(_results, cached)
              : cached;
          _sourceWarnings = [
            'Catalog services are unavailable; showing locally cached results.',
          ];
          _error = null;
        } else {
          _error = error.toString().replaceFirst('Exception: ', '');
          if (!append) _results = [];
        }
      }
    } finally {
      if (generation == _searchGeneration &&
          _query.trim() == requestedQuery) {
        _isLoading = false;
        _isLoadingMore = false;
        notifyListeners();
      }
    }
  }

  Future<void> loadMore() async {
    if (!_hasMore || _isLoading || _isLoadingMore || _query.trim().isEmpty) {
      return;
    }
    await _performSearch(
      _query,
      generation: _searchGeneration,
      type: _searchType,
      append: true,
    );
  }

  Future<void> toggleTheme() async {
    _isDark = !_isDark;
    await _database.savePreference(_themeKey, '$_isDark');
    await _prefs?.setBool(_themeKey, _isDark);
    notifyListeners();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _repository.dispose();
    unawaited(_bookStorage.dispose());
    unawaited(_database.close());
    super.dispose();
  }
}
