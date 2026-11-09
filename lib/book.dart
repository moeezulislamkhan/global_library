/// Minimal book record used throughout the app.
class Book {
  const Book({
    required this.key,
    required this.title,
    required this.authors,
    this.source = 'Google Books',
    this.isbn,
    this.publisher,
    this.language,
    this.description,
    this.categories = const [],
    this.coverId,
    this.coverImageUrl,
    this.previewUrl,
    this.previewViewability,
    this.plainTextUrl,
    this.epubUrl,
    this.pdfUrl,
    this.recordUrl,
    this.firstPublishYear,
    this.editionCount,
    this.publicationDate,
    this.pageCount,
    this.readingFormat,
  });

  final String key;
  final String title;
  final List<String> authors;
  final String source;
  final String? isbn;
  final String? publisher;
  final String? language;
  final String? description;
  final List<String> categories;
  final String? coverImageUrl;
  final String? previewUrl;
  final String? previewViewability;
  final String? plainTextUrl;
  final String? epubUrl;
  final String? pdfUrl;
  final String? recordUrl;
  // Retained to display covers from books saved before the Google Books switch.
  final int? coverId;
  final int? firstPublishYear;
  final int? editionCount;
  final String? publicationDate;
  final int? pageCount;
  final String? readingFormat;

  String get authorLine =>
      authors.isEmpty ? 'Unknown author' : authors.join(', ');

  String? get coverUrl =>
      coverImageUrl ??
      (coverId == null
          ? null
          : 'https://covers.openlibrary.org/b/id/$coverId-M.jpg');

  bool get canReadInApp =>
      plainTextUrl != null || epubUrl != null || pdfUrl != null ||
      previewUrl != null;

  factory Book.fromGoogleBooksJson(Map<String, dynamic> json) {
    final volumeInfo = json['volumeInfo'];
    final info = volumeInfo is Map<String, dynamic>
        ? volumeInfo
        : const <String, dynamic>{};
    final rawAuthors = info['authors'];
    final rawImageLinks = info['imageLinks'];
    final imageLinks = rawImageLinks is Map<String, dynamic>
        ? rawImageLinks
        : const <String, dynamic>{};
    final rawCoverUrl = imageLinks['extraLarge'] ??
        imageLinks['large'] ??
        imageLinks['medium'] ??
        imageLinks['thumbnail'] ??
        imageLinks['smallThumbnail'];
    final coverUrl = rawCoverUrl is String
        ? rawCoverUrl.replaceFirst(RegExp(r'^http:'), 'https:')
        : null;
    final rawDescription = info['description'];
    final description = rawDescription is String
        ? _plainText(rawDescription)
        : null;
    final rawCategories = info['categories'];
    final rawPublishedDate = info['publishedDate'];
    final year = rawPublishedDate is String
        ? int.tryParse(RegExp(r'^\d{4}').stringMatch(rawPublishedDate) ?? '')
        : null;
    final rawAccessInfo = json['accessInfo'];
    final accessInfo = rawAccessInfo is Map<String, dynamic>
        ? rawAccessInfo
        : const <String, dynamic>{};
    final rawPreviewUrl = accessInfo['webReaderLink'];
    final parsedPreviewUrl =
        rawPreviewUrl is String ? Uri.tryParse(rawPreviewUrl) : null;
    final previewUrl = accessInfo['embeddable'] == true &&
            parsedPreviewUrl?.scheme == 'https' &&
            parsedPreviewUrl!.host == 'books.google.com'
        ? rawPreviewUrl as String
        : null;
    final identifiers = info['industryIdentifiers'];
    String? isbn;
    if (identifiers is List) {
      for (final identifier in identifiers.whereType<Map<String, dynamic>>()) {
        final type = identifier['type'];
        final value = identifier['identifier'];
        if (value is String &&
            (type == 'ISBN_13' || (isbn == null && type == 'ISBN_10'))) {
          isbn = value;
          if (type == 'ISBN_13') break;
        }
      }
    }

    return Book(
      key: json['id'] is String ? 'google:${json['id']}' : '',
      source: 'Google Books',
      isbn: isbn,
      publisher: info['publisher'] as String?,
      language: info['language'] as String?,
      title: (info['title'] as String?)?.trim().isNotEmpty == true
          ? (info['title'] as String).trim()
          : 'Untitled book',
      authors: rawAuthors is List
          ? rawAuthors.whereType<String>().toList()
          : <String>[],
      description: description?.isEmpty == true ? null : description,
      categories: rawCategories is List
          ? rawCategories.whereType<String>().toList()
          : <String>[],
      coverImageUrl: coverUrl,
      previewUrl: previewUrl,
      previewViewability: accessInfo['viewability'] as String?,
      recordUrl: info['infoLink'] as String?,
      firstPublishYear: year,
      publicationDate: rawPublishedDate is String ? rawPublishedDate : null,
      pageCount: info['pageCount'] is int ? info['pageCount'] as int : null,
    );
  }

  factory Book.fromOpenLibraryJson(Map<String, dynamic> json) {
    final rawAuthors = json['author_name'];
    final cover = json['cover_i'];
    final isbns = json['isbn'];
    final publishers = json['publisher'];
    final languages = json['language'];
    final subjects = json['subject'];
    final rawTitle = json['title'];
    final key = json['key'];
    final published = json['first_publish_year'];

    return Book(
      key: key is String ? 'openlibrary:$key' : '',
      source: 'Open Library',
      title: rawTitle is String && rawTitle.trim().isNotEmpty
          ? rawTitle.trim()
          : 'Untitled book',
      authors: rawAuthors is List
          ? rawAuthors.whereType<String>().toList()
          : const [],
      coverId: cover is int ? cover : null,
      isbn: isbns is List && isbns.isNotEmpty && isbns.first is String
          ? isbns.first as String
          : null,
      publisher: publishers is List && publishers.isNotEmpty
          ? publishers.first is String
              ? publishers.first as String
              : null
          : null,
      language: languages is List && languages.isNotEmpty
          ? languages.first is String
              ? languages.first as String
              : null
          : null,
      categories: subjects is List
          ? subjects.whereType<String>().take(8).toList()
          : const [],
      firstPublishYear: published is int ? published : null,
      editionCount: json['edition_count'] is int
          ? json['edition_count'] as int
          : null,
      recordUrl: key is String ? 'https://openlibrary.org$key' : null,
    );
  }

  factory Book.fromGutendexJson(Map<String, dynamic> json) {
    final id = json['id'];
    final rawAuthors = json['authors'];
    final formats = json['formats'] is Map<String, dynamic>
        ? json['formats'] as Map<String, dynamic>
        : const <String, dynamic>{};
    final rawSubjects = json['subjects'];
    final rawLanguages = json['languages'];
    final textUrl = _safeGutenbergFormat(formats, const [
      'text/plain; charset=utf-8',
      'text/plain; charset=us-ascii',
      'text/plain',
    ]);
    final epubUrl = _safeGutenbergFormat(formats, const [
      'application/epub+zip',
    ]);
    final cover = formats['image/jpeg'];
    final rawTitle = json['title'];

    return Book(
      key: id is int ? 'gutendex:$id' : '',
      source: 'Project Gutenberg',
      title: rawTitle is String && rawTitle.trim().isNotEmpty
          ? rawTitle.trim()
          : 'Untitled book',
      authors: rawAuthors is List
          ? rawAuthors
              .whereType<Map<String, dynamic>>()
              .map((author) => author['name'])
              .whereType<String>()
              .toList()
          : const [],
      categories: rawSubjects is List
          ? rawSubjects.whereType<String>().take(8).toList()
          : const [],
      language: rawLanguages is List &&
              rawLanguages.isNotEmpty &&
              rawLanguages.first is String
          ? rawLanguages.first as String
          : null,
      coverImageUrl: cover is String ? _https(cover) : null,
      plainTextUrl: textUrl,
      epubUrl: epubUrl,
      recordUrl: id is int ? 'https://www.gutenberg.org/ebooks/$id' : null,
    );
  }

  factory Book.fromInternetArchiveJson(
    Map<String, dynamic> json, {
    Map<String, dynamic>? metadata,
  }) {
    final id = json['identifier'];
    final rawCreators = json['creator'] ?? json['creator__text'];
    final rawSubjects = json['subject'] ?? json['subject__text'];
    final itemMetadata = metadata?['metadata'];
    final files = metadata?['files'];
    String? textUrl;
    String? epubUrl;
    String? pdfUrl;
    final isKnownPublic = itemMetadata is Map<String, dynamic> &&
        (itemMetadata['access-restricted-item'] == false ||
            itemMetadata['access-restricted-item'] == 'false');
    if (isKnownPublic && id is String && files is List) {
      for (final file in files.whereType<Map<String, dynamic>>()) {
        if (file['private'] == true || file['private'] == 'true') continue;
        final name = file['name'];
        final format = file['format'];
        if (name is! String || name.contains('..')) continue;
        final url = 'https://archive.org/download/$id/'
            '${Uri.encodeComponent(name)}';
        if (format == 'EPUB') epubUrl ??= url;
        if (format == 'PDF' || format == 'Text PDF') pdfUrl ??= url;
        if (format == 'DjVuTXT') textUrl ??= url;
      }
    }
    final rawTitle = json['title'];
    final yearValue = json['year'];
    final year = yearValue is int ? yearValue : int.tryParse('$yearValue');

    return Book(
      key: id is String ? 'archive:$id' : '',
      source: 'Internet Archive',
      title: rawTitle is String && rawTitle.trim().isNotEmpty
          ? rawTitle.trim()
          : 'Untitled book',
      authors: rawCreators is List
          ? rawCreators.whereType<String>().toList()
          : rawCreators is String
              ? [rawCreators]
              : const [],
      description: json['description'] is String
          ? json['description'] as String
          : null,
      categories: rawSubjects is List
          ? rawSubjects.whereType<String>().take(8).toList()
          : const [],
      firstPublishYear: year,
      coverImageUrl:
          id is String ? 'https://archive.org/services/img/$id' : null,
      plainTextUrl: textUrl,
      epubUrl: epubUrl,
      pdfUrl: pdfUrl,
      recordUrl: id is String ? 'https://archive.org/details/$id' : null,
    );
  }

  factory Book.fromStoredJson(Map<String, dynamic> json) => Book(
        key: json['key'] as String? ?? '',
        source: json['source'] as String? ?? 'Google Books',
        isbn: json['isbn'] as String?,
        publisher: json['publisher'] as String?,
        language: json['language'] as String?,
        title: json['title'] as String? ?? 'Untitled book',
        authors: (json['authors'] as List<dynamic>? ?? const [])
            .whereType<String>()
            .toList(),
        description: json['description'] as String?,
        categories: (json['categories'] as List<dynamic>? ?? const [])
            .whereType<String>()
            .toList(),
        plainTextUrl: json['plainTextUrl'] as String?,
        epubUrl: json['epubUrl'] as String?,
        pdfUrl: json['pdfUrl'] as String?,
        recordUrl: json['recordUrl'] as String?,
        coverImageUrl: json['coverImageUrl'] as String?,
        previewUrl: json['previewUrl'] as String?,
        previewViewability: json['previewViewability'] as String?,
        coverId: json['coverId'] as int?,
        firstPublishYear: json['firstPublishYear'] as int?,
        editionCount: json['editionCount'] as int?,
        publicationDate: json['publicationDate'] as String?,
        pageCount: json['pageCount'] as int?,
        readingFormat: json['readingFormat'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'key': key,
        'source': source,
        'isbn': isbn,
        'publisher': publisher,
        'language': language,
        'title': title,
        'authors': authors,
        'description': description,
        'categories': categories,
        'coverImageUrl': coverImageUrl,
        'previewUrl': previewUrl,
        'previewViewability': previewViewability,
        'plainTextUrl': plainTextUrl,
        'epubUrl': epubUrl,
        'pdfUrl': pdfUrl,
        'recordUrl': recordUrl,
        'coverId': coverId,
        'firstPublishYear': firstPublishYear,
        'editionCount': editionCount,
        'publicationDate': publicationDate,
        'pageCount': pageCount,
        'readingFormat': readingFormat,
      };

  @override
  bool operator ==(Object other) => other is Book && other.key == key;

  @override
  int get hashCode => key.hashCode;

  static String? _safeGutenbergFormat(
    Map<String, dynamic> formats,
    List<String> mimeTypes,
  ) {
    for (final mime in mimeTypes) {
      final value = formats[mime];
      final uri = value is String ? Uri.tryParse(value) : null;
      if (uri != null &&
          uri.scheme == 'https' &&
          (uri.host == 'gutenberg.org' ||
              uri.host.endsWith('.gutenberg.org'))) {
        return uri.toString();
      }
    }
    return null;
  }

  static String _https(String url) =>
      url.replaceFirst(RegExp(r'^http:'), 'https:');

  static String _plainText(String html) {
    final text = html
        .replaceAll(
          RegExp(r'<br\s*/?>|</p>|</div>', caseSensitive: false),
          '\n',
        )
        .replaceAll(RegExp(r'<[^>]*>'), ' ')
        .replaceAllMapped(
          RegExp(r'&(#x[0-9a-fA-F]+|#\d+|amp|lt|gt|quot|apos|nbsp);'),
          (match) {
            final entity = match[1]!;
            if (entity.startsWith('#x')) {
              return String.fromCharCode(
                int.tryParse(entity.substring(2), radix: 16) ?? 0xFFFD,
              );
            }
            if (entity.startsWith('#')) {
              return String.fromCharCode(
                int.tryParse(entity.substring(1)) ?? 0xFFFD,
              );
            }
            return const {
              'amp': '&',
              'lt': '<',
              'gt': '>',
              'quot': '"',
              'apos': "'",
              'nbsp': ' ',
            }[entity]!;
          },
        )
        .replaceAll(RegExp(r'[ \t]+'), ' ')
        .replaceAll(RegExp(r' *\n *'), '\n')
        .trim();
    return text;
  }
}
