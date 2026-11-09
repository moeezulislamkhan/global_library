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
    this.averageRating,
    this.ratingsCount,
    this.downloadCount,
    this.authorIdentifiers = const {},
    this.sourceBookIds = const {},
    this.availableFormats = const [],
    this.readingUrl,
    this.readingAvailability,
    this.borrowUrl,
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
  final double? averageRating;
  final int? ratingsCount;
  final int? downloadCount;
  final Map<String, String> authorIdentifiers;
  final Map<String, String> sourceBookIds;
  final List<String> availableFormats;
  final String? readingUrl;
  final String? readingAvailability;
  final String? borrowUrl;

  String get authorLine =>
      authors.isEmpty ? 'Unknown author' : authors.join(', ');

  String? get coverUrl =>
      coverImageUrl ??
      (coverId == null
          ? null
          : 'https://covers.openlibrary.org/b/id/$coverId-L.jpg');

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
    final epubInfo = accessInfo['epub'] is Map<String, dynamic>
        ? accessInfo['epub'] as Map<String, dynamic>
        : const <String, dynamic>{};
    final pdfInfo = accessInfo['pdf'] is Map<String, dynamic>
        ? accessInfo['pdf'] as Map<String, dynamic>
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
      sourceBookIds: json['id'] is String
          ? {'Google Books': json['id'] as String}
          : const {},
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
      averageRating: (info['averageRating'] as num?)?.toDouble(),
      ratingsCount: info['ratingsCount'] as int?,
      availableFormats: [
        if (epubInfo['isAvailable'] == true) 'EPUB',
        if (pdfInfo['isAvailable'] == true) 'PDF',
      ],
      readingUrl: previewUrl,
      readingAvailability: switch (accessInfo['viewability']) {
        'ALL_PAGES' => 'full_view',
        'PARTIAL' => 'preview',
        'NO_PAGES' => 'metadata_only',
        _ => null,
      },
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
    final rawAvailability = json['availability'];
    final availability = rawAvailability is Map<String, dynamic>
        ? rawAvailability
        : const <String, dynamic>{};
    final ebookAccess = availability['ebook_access'] ?? json['ebook_access'];
    final publicScan = availability['public_scan_b'] ?? json['public_scan_b'];
    final isBorrowable = availability['is_borrowable'] ??
        availability['is_lendable'] ??
        json['is_borrowable'] ??
        json['is_lendable'];
    final authorKeys = json['author_key'];
    final authors = rawAuthors is List
        ? rawAuthors.whereType<String>().toList()
        : const <String>[];
    final keys =
        authorKeys is List ? authorKeys.whereType<String>().toList() : <String>[];
    final authorIds = <String, String>{
      for (var index = 0;
          index < keys.length && index < authors.length;
          index++)
        authors[index]: keys[index],
    };
    final keyValue = key is String ? key : null;
    final coverId = cover is int ? cover : null;
    final rawBorrowUrl = availability['borrow_url'] ?? json['borrow_url'];
    final parsedBorrowUrl =
        rawBorrowUrl is String ? Uri.tryParse(rawBorrowUrl) : null;
    final borrowUrl = parsedBorrowUrl?.scheme == 'https' &&
            (parsedBorrowUrl?.host == 'openlibrary.org' ||
                parsedBorrowUrl?.host.endsWith('.openlibrary.org') == true)
        ? rawBorrowUrl as String
        : key is String &&
                (isBorrowable == true ||
                    isBorrowable == 'true' ||
                    ebookAccess == 'borrowable')
            ? 'https://openlibrary.org$key'
            : null;

    return Book(
      key: key is String ? 'openlibrary:$key' : '',
      source: 'Open Library',
      title: rawTitle is String && rawTitle.trim().isNotEmpty
          ? rawTitle.trim()
          : 'Untitled book',
      authors: authors,
      authorIdentifiers: authorIds,
      sourceBookIds: keyValue == null ? const {} : {'Open Library': keyValue},
      coverId: coverId,
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
      readingAvailability: ebookAccess is String && ebookAccess != 'no_ebook'
          ? ebookAccess
          : publicScan == true
              ? 'public_scan'
              : 'catalog_only',
      borrowUrl: borrowUrl,
      availableFormats: [
        if (publicScan == true) 'Open Library scan',
        if (ebookAccess == 'borrowable') 'Borrowable',
      ],
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
    final pdfUrl = _safeGutenbergFormat(formats, const ['application/pdf']);
    final htmlUrl = _safeGutenbergFormat(formats, const [
      'text/html',
      'text/html; charset=utf-8',
    ]);
    final coverValue = formats['image/jpeg'];
    final coverUri =
        coverValue is String ? Uri.tryParse(coverValue) : null;
    final rawTitle = json['title'];
    final rawShelves = json['bookshelves'];
    final rawDownloadCount = json['download_count'];

    final openLibrarySubjects = <String>{
      if (rawSubjects is List) ...rawSubjects.whereType<String>(),
      if (rawShelves is List) ...rawShelves.whereType<String>(),
    };

    return Book(
      key: id is int ? 'gutendex:$id' : '',
      source: 'Project Gutenberg',
      sourceBookIds: id is int ? {'Project Gutenberg': '$id'} : const {},
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
      categories: openLibrarySubjects.take(12).toList(),
      language: rawLanguages is List &&
              rawLanguages.isNotEmpty &&
              rawLanguages.first is String
          ? rawLanguages.first as String
          : null,
      coverImageUrl: coverUri?.scheme == 'https' &&
              (coverUri!.host == 'gutenberg.org' ||
                  coverUri.host.endsWith('.gutenberg.org'))
          ? coverUri.toString()
          : null,
      plainTextUrl: textUrl,
      epubUrl: epubUrl,
      pdfUrl: pdfUrl,
      readingUrl: htmlUrl ?? textUrl,
      readingAvailability: htmlUrl != null || textUrl != null || epubUrl != null
          ? 'public_domain'
          : 'metadata_only',
      downloadCount: rawDownloadCount is int ? rawDownloadCount : null,
      availableFormats: [
        if (textUrl != null) 'Plain text',
        if (epubUrl != null) 'EPUB',
        if (pdfUrl != null) 'PDF',
        if (htmlUrl != null) 'HTML',
      ],
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
      sourceBookIds: id is String ? {'Internet Archive': id} : const {},
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
        averageRating: (json['averageRating'] as num?)?.toDouble(),
        ratingsCount: json['ratingsCount'] as int?,
        downloadCount: json['downloadCount'] as int?,
        authorIdentifiers: _readStringMap(json['authorIdentifiers']),
        sourceBookIds: _readStringMap(json['sourceBookIds']),
        availableFormats: (json['availableFormats'] as List<dynamic>? ?? const [])
            .whereType<String>()
            .toList(),
        readingUrl: json['readingUrl'] as String?,
        readingAvailability: json['readingAvailability'] as String?,
        borrowUrl: json['borrowUrl'] as String?,
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
        'averageRating': averageRating,
        'ratingsCount': ratingsCount,
        'downloadCount': downloadCount,
        'authorIdentifiers': authorIdentifiers,
        'sourceBookIds': sourceBookIds,
        'availableFormats': availableFormats,
        'readingUrl': readingUrl,
        'readingAvailability': readingAvailability,
        'borrowUrl': borrowUrl,
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

  static Map<String, String> _readStringMap(Object? value) {
    if (value is! Map) return const {};
    return {
      for (final entry in value.entries)
        if (entry.key is String && entry.value is String)
          entry.key as String: entry.value as String,
    };
  }

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
