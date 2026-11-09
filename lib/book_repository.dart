import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'book.dart';

class BookSearchPage {
  const BookSearchPage({
    required this.books,
    required this.hasMore,
    this.sourceWarnings = const [],
  });

  final List<Book> books;
  final bool hasMore;
  final List<String> sourceWarnings;
}

class BookRepository {
  BookRepository({http.Client? client}) : _client = client ?? http.Client();

  static const _googleBooksUrl =
      'https://www.googleapis.com/books/v1/volumes';
  static const _googleBooksKey =
      String.fromEnvironment('GOOGLE_BOOKS_API_KEY');
  static const _cacheDuration = Duration(minutes: 5);

  final http.Client _client;
  final Map<String, _CachedPage> _cache = {};
  final Map<String, Future<BookSearchPage>> _inFlight = {};

  Future<BookSearchPage> searchBooks(
    String query, {
    int limit = 12,
    int page = 1,
  }) {
    final normalized = query.trim();
    if (normalized.isEmpty) {
      return Future.value(const BookSearchPage(books: [], hasMore: false));
    }

    final boundedLimit = limit.clamp(1, 30);
    final boundedPage = page.clamp(1, 100000);
    final cacheKey = '${normalized.toLowerCase()}|$boundedLimit|$boundedPage';
    final cached = _cache[cacheKey];
    if (cached != null &&
        DateTime.now().difference(cached.createdAt) < _cacheDuration) {
      return Future.value(cached.page);
    }
    final existing = _inFlight[cacheKey];
    if (existing != null) return existing;

    final request = _searchSources(
      normalized,
      limit: boundedLimit,
      page: boundedPage,
    );
    _inFlight[cacheKey] = request;
    return request.whenComplete(() => _inFlight.remove(cacheKey));
  }

  Future<BookSearchPage> _searchSources(
    String query, {
    required int limit,
    required int page,
  }) async {
    final results = await Future.wait([
      _trySource('Open Library', () => _searchOpenLibrary(query, limit, page)),
      _trySource('Google Books', () => _searchGoogleBooks(query, limit, page)),
      _trySource('Project Gutenberg', () => _searchGutendex(query, page)),
      _trySource(
        'Internet Archive',
        () => _searchInternetArchive(query, limit, page),
      ),
    ]);

    final warnings = results
        .where((result) => result.error != null)
        .map((result) => result.error!)
        .toList();
    final successfulSources = results.where((result) => result.error == null);
    if (successfulSources.isEmpty) {
      throw BookRepositoryException(warnings.join('\n'));
    }

    final allBooks = results.expand((result) => result.books).toList();
    final books = _mergeDuplicates(allBooks);
    final pageResult = BookSearchPage(
      books: books,
      hasMore: successfulSources.any((result) => result.hasMore),
      sourceWarnings: warnings,
    );
    _cache['${query.toLowerCase()}|$limit|$page'] =
        _CachedPage(DateTime.now(), pageResult);
    return pageResult;
  }

  Future<_SourceResult> _trySource(
    String source,
    Future<_SourceResult> Function() search,
  ) async {
    try {
      return await search();
    } on Object catch (error) {
      return _SourceResult(
        books: const [],
        hasMore: false,
        error: '$source unavailable: $error',
      );
    }
  }

  Future<_SourceResult> _searchOpenLibrary(
    String query,
    int limit,
    int page,
  ) async {
    final response = await _getJson(
      Uri.https('openlibrary.org', '/search.json', {
        'q': query,
        'limit': '$limit',
        'page': '$page',
        'fields':
            'key,title,author_name,cover_i,first_publish_year,edition_count,'
            'isbn,publisher,language,subject',
      }),
    );
    final docs = response['docs'];
    if (docs is! List) {
      throw const BookRepositoryException('Invalid search response.');
    }
    final books = docs
        .whereType<Map<String, dynamic>>()
        .map(Book.fromOpenLibraryJson)
        .where((book) => book.key.isNotEmpty)
        .toList();
    final total = response['numFound'] is int ? response['numFound'] as int : 0;
    return _SourceResult(
      books: books,
      hasMore: (page * limit) < total && books.isNotEmpty,
    );
  }

  Future<_SourceResult> _searchGoogleBooks(
    String query,
    int limit,
    int page,
  ) async {
    final parameters = <String, String>{
      'q': query,
      'maxResults': '$limit',
      'startIndex': '${(page - 1) * limit}',
      'orderBy': 'relevance',
      'printType': 'books',
    };
    if (_googleBooksKey.isNotEmpty) parameters['key'] = _googleBooksKey;
    final response = await _getJson(
      Uri.parse(_googleBooksUrl).replace(queryParameters: parameters),
    );
    final items = response['items'];
    if (items != null && items is! List) {
      throw const BookRepositoryException('Invalid search response.');
    }
    final books = (items as List? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(Book.fromGoogleBooksJson)
        .where((book) => book.key.isNotEmpty)
        .toList();
    final total = response['totalItems'] is int
        ? response['totalItems'] as int
        : 0;
    return _SourceResult(
      books: books,
      hasMore: (page * limit) < total && books.isNotEmpty,
    );
  }

  Future<_SourceResult> _searchGutendex(String query, int page) async {
    final response = await _getJson(
      Uri.https('gutendex.com', '/books/', {
        'search': query,
        'page': '$page',
      }),
    );
    final items = response['results'];
    if (items is! List) {
      throw const BookRepositoryException('Invalid search response.');
    }
    final books = items
        .whereType<Map<String, dynamic>>()
        .map(Book.fromGutendexJson)
        .where((book) => book.key.isNotEmpty)
        .toList();
    return _SourceResult(
      books: books,
      hasMore: response['next'] is String && books.isNotEmpty,
    );
  }

  Future<_SourceResult> _searchInternetArchive(
    String query,
    int limit,
    int page,
  ) async {
    final response = await _getJson(
      Uri.https('archive.org', '/advancedsearch.php', {
        'q': '(${_archiveQuery(query)}) AND mediatype:texts',
        'fl[]': 'identifier,title,creator,year,description,subject',
        'rows': '$limit',
        'page': '$page',
        'output': 'json',
      }),
    );
    final responseObject = response['response'];
    final docs = responseObject is Map<String, dynamic>
        ? responseObject['docs']
        : null;
    if (docs is! List) {
      throw const BookRepositoryException('Invalid search response.');
    }

    final books = await Future.wait(
      docs.whereType<Map<String, dynamic>>().map(_loadArchiveItem),
    );
    final total = responseObject is Map<String, dynamic> &&
            responseObject['numFound'] is int
        ? responseObject['numFound'] as int
        : 0;
    return _SourceResult(
      books: books.where((book) => book.key.isNotEmpty).toList(),
      hasMore: (page * limit) < total && docs.isNotEmpty,
    );
  }

  Future<Book> _loadArchiveItem(Map<String, dynamic> doc) async {
    final identifier = doc['identifier'];
    if (identifier is! String || identifier.isEmpty) {
      return Book.fromInternetArchiveJson(doc);
    }
    try {
      final metadata = await _getJson(
        Uri.https('archive.org', '/metadata/$identifier'),
      );
      return Book.fromInternetArchiveJson(doc, metadata: metadata);
    } on Exception {
      return Book.fromInternetArchiveJson(doc);
    }
  }

  String _archiveQuery(String query) {
    final escaped = query.replaceAll('"', r'\"');
    return 'title:"$escaped" OR creator:"$escaped"';
  }

  Future<List<Book>> getRecommendations(Book book, {int limit = 8}) async {
    final category =
        book.categories.isEmpty ? null : book.categories.first.split('/').last;
    final query = category != null && category.isNotEmpty
        ? 'subject:$category'
        : book.authors.isNotEmpty
            ? 'inauthor:"${book.authors.first}"'
            : '"${book.title}"';
    final parameters = <String, String>{
      'q': query,
      'maxResults': '${limit.clamp(1, 20) + 1}',
      'orderBy': 'relevance',
      'printType': 'books',
    };
    if (_googleBooksKey.isNotEmpty) parameters['key'] = _googleBooksKey;
    final response = await _getJson(
      Uri.parse(_googleBooksUrl).replace(queryParameters: parameters),
    );
    final items = response['items'];
    if (items != null && items is! List) {
      throw const BookRepositoryException(
        'Google Books returned an invalid recommendations response.',
      );
    }
    return (items as List? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(Book.fromGoogleBooksJson)
        .where((candidate) =>
            candidate.key != book.key &&
            candidate.title.toLowerCase() != book.title.toLowerCase())
        .take(limit)
        .toList();
  }

  List<Book> mergePages(List<Book> existing, List<Book> incoming) =>
      _mergeDuplicates([...existing, ...incoming]);

  Future<String> getPlainText(Book book) async {
    final url = book.plainTextUrl;
    final uri = url == null ? null : Uri.tryParse(url);
    final hostAllowed = uri != null &&
        uri.scheme == 'https' &&
        (uri.host == 'gutenberg.org' ||
            uri.host.endsWith('.gutenberg.org') ||
            uri.host == 'archive.org' ||
            uri.host.endsWith('.archive.org'));
    if (!hostAllowed) {
      throw const BookRepositoryException(
        'This book does not have a supported public text edition.',
      );
    }

    final response = await _client
        .get(uri, headers: const {'Accept': 'text/plain'})
        .timeout(const Duration(seconds: 30));
    if (response.statusCode != 200) {
      throw BookRepositoryException(
        'The book text server returned HTTP ${response.statusCode}.',
      );
    }
    if (response.bodyBytes.length > 10 * 1024 * 1024) {
      throw const BookRepositoryException(
        'This text edition is too large to open in the app.',
      );
    }
    return utf8.decode(response.bodyBytes, allowMalformed: true);
  }

  Future<Uint8List> getEbookBytes(Book book, {required bool epub}) async {
    final url = epub ? book.epubUrl : book.pdfUrl;
    final uri = url == null ? null : Uri.tryParse(url);
    final hostAllowed = uri != null &&
        uri.scheme == 'https' &&
        (uri.host == 'gutenberg.org' ||
            uri.host.endsWith('.gutenberg.org') ||
            uri.host == 'archive.org' ||
            uri.host.endsWith('.archive.org'));
    if (!hostAllowed) {
      throw const BookRepositoryException(
        'This book does not have a supported public edition.',
      );
    }

    final response = await _client
        .get(uri)
        .timeout(const Duration(seconds: 45));
    if (response.statusCode != 200) {
      throw BookRepositoryException(
        'The book file server returned HTTP ${response.statusCode}.',
      );
    }
    if (response.bodyBytes.length > 50 * 1024 * 1024) {
      throw const BookRepositoryException(
        'This book file is too large to open in the app.',
      );
    }
    return response.bodyBytes;
  }

  Future<Map<String, dynamic>> _getJson(Uri uri) async {
    late http.Response response;
    for (var attempt = 0; ; attempt++) {
      try {
        response = await _client
            .get(uri, headers: const {'Accept': 'application/json'})
            .timeout(const Duration(seconds: 20));
      } on Exception {
        if (attempt > 0) rethrow;
        await Future<void>.delayed(const Duration(milliseconds: 350));
        continue;
      }
      if (response.statusCode < 500 ||
          response.statusCode >= 600 ||
          attempt > 0) {
        break;
      }
      await Future<void>.delayed(const Duration(milliseconds: 350));
    }
    if (response.statusCode != 200) {
      if (uri.host == 'www.googleapis.com' &&
          (response.statusCode == 403 || response.statusCode == 429)) {
        throw BookRepositoryException(
          'Google Books HTTP ${response.statusCode}: check the API key, '
          'Books API enablement, and quota.',
        );
      }
      throw BookRepositoryException('HTTP ${response.statusCode}.');
    }
    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (decoded is! Map<String, dynamic>) {
      throw const BookRepositoryException('Invalid JSON response.');
    }
    return decoded;
  }

  List<Book> _mergeDuplicates(List<Book> books) {
    final merged = <Book>[];
    for (final book in books) {
      final duplicateIndex = merged.indexWhere(
        (existing) => _sameBook(existing, book),
      );
      if (duplicateIndex < 0) {
        merged.add(book);
      } else {
        merged[duplicateIndex] = _mergeBook(merged[duplicateIndex], book);
      }
    }
    merged.sort((a, b) => _qualityScore(b).compareTo(_qualityScore(a)));
    return merged;
  }

  bool _sameBook(Book first, Book second) {
    if (first.isbn != null &&
        second.isbn != null &&
        _normalizeIsbn(first.isbn!) == _normalizeIsbn(second.isbn!)) {
      return true;
    }
    final firstTitle = _normalize(first.title);
    final secondTitle = _normalize(second.title);
    if (firstTitle.isEmpty || firstTitle != secondTitle) return false;
    if (first.authors.isEmpty || second.authors.isEmpty) return false;
    final firstAuthors = first.authors.map(_normalize).toSet();
    return second.authors.map(_normalize).any(firstAuthors.contains);
  }

  Book _mergeBook(Book first, Book second) {
    final preferred = _qualityScore(second) > _qualityScore(first)
        ? second
        : first;
    final other = identical(preferred, first) ? second : first;
    return Book(
      key: preferred.key,
      source: preferred.source == other.source
          ? preferred.source
          : '${preferred.source}, ${other.source}',
      title: _hasText(preferred.title) ? preferred.title : other.title,
      authors: preferred.authors.isNotEmpty
          ? preferred.authors
          : other.authors,
      isbn: preferred.isbn ?? other.isbn,
      publisher: preferred.publisher ?? other.publisher,
      language: preferred.language ?? other.language,
      description: _longer(preferred.description, other.description),
      categories: {...preferred.categories, ...other.categories}.toList(),
      coverId: preferred.coverId ?? other.coverId,
      coverImageUrl: preferred.coverImageUrl ?? other.coverImageUrl,
      previewUrl: preferred.previewUrl ?? other.previewUrl,
      previewViewability:
          preferred.previewViewability ?? other.previewViewability,
      plainTextUrl: preferred.plainTextUrl ?? other.plainTextUrl,
      epubUrl: preferred.epubUrl ?? other.epubUrl,
      pdfUrl: preferred.pdfUrl ?? other.pdfUrl,
      recordUrl: preferred.recordUrl ?? other.recordUrl,
      firstPublishYear: preferred.firstPublishYear ?? other.firstPublishYear,
      editionCount: preferred.editionCount ?? other.editionCount,
      publicationDate: preferred.publicationDate ?? other.publicationDate,
      pageCount: preferred.pageCount ?? other.pageCount,
      readingFormat: preferred.readingFormat ?? other.readingFormat,
    );
  }

  int _qualityScore(Book book) =>
      (book.canReadInApp ? 100 : 0) +
      (book.coverUrl != null ? 20 : 0) +
      (book.description?.isNotEmpty == true ? 10 : 0) +
      (book.authors.isNotEmpty ? 5 : 0) +
      (book.isbn != null ? 3 : 0);

  bool _hasText(String value) =>
      value.trim().isNotEmpty && value != 'Untitled book';

  String? _longer(String? first, String? second) {
    if (first == null || first.isEmpty) return second;
    if (second == null || second.length <= first.length) return first;
    return second;
  }

  String _normalize(String value) => value
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
      .trim();

  String _normalizeIsbn(String value) =>
      value.replaceAll(RegExp(r'[^0-9Xx]'), '').toUpperCase();

  void dispose() => _client.close();
}

class BookRepositoryException implements Exception {
  const BookRepositoryException(this.message);
  final String message;

  @override
  String toString() => message;
}

class _SourceResult {
  const _SourceResult({
    required this.books,
    required this.hasMore,
    this.error,
  });

  final List<Book> books;
  final bool hasMore;
  final String? error;
}

class _CachedPage {
  const _CachedPage(this.createdAt, this.page);

  final DateTime createdAt;
  final BookSearchPage page;
}
