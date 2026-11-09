import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:global_library/book.dart';
import 'package:global_library/book_repository.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  group('Book data mapping', () {
    test('maps Open Library identifiers and does not infer reading access', () {
      final book = Book.fromOpenLibraryJson({
        'key': '/works/OL123W',
        'title': 'Example Title',
        'author_name': ['Example Author'],
        'author_key': ['OL456A'],
        'isbn': ['9781234567890'],
        'ebook_access': 'no_ebook',
        'cover_i': 123,
      });

      expect(book.key, 'openlibrary:/works/OL123W');
      expect(book.authorIdentifiers, {'Example Author': 'OL456A'});
      expect(book.isbn, '9781234567890');
      expect(book.coverUrl, contains('/123-L.jpg'));
      expect(book.readingAvailability, 'catalog_only');
      expect(book.canReadInApp, isFalse);
      expect(book.epubUrl, isNull);
    });

    test('maps Gutenberg public text and EPUB formats', () {
      final book = Book.fromGutendexJson({
        'id': 1342,
        'title': 'Pride and Prejudice',
        'authors': [
          {'name': 'Austen, Jane'}
        ],
        'languages': ['en'],
        'formats': {
          'text/plain; charset=utf-8':
              'https://www.gutenberg.org/cache/epub/1342/pg1342.txt',
          'application/epub+zip':
              'https://www.gutenberg.org/cache/epub/1342/pg1342-images.epub',
        },
      });

      expect(book.source, 'Project Gutenberg');
      expect(book.authors, ['Austen, Jane']);
      expect(book.plainTextUrl, contains('pg1342.txt'));
      expect(book.epubUrl, endsWith('.epub'));
      expect(book.canReadInApp, isTrue);
    });

    test('does not invent Gutenberg formats when the response omits them', () {
      final book = Book.fromGutendexJson({
        'id': 42,
        'title': 'Catalog only',
        'authors': [],
        'formats': {'text/html': 'http://example.invalid/book.html'},
      });

      expect(book.availableFormats, isEmpty);
      expect(book.plainTextUrl, isNull);
      expect(book.epubUrl, isNull);
      expect(book.pdfUrl, isNull);
      expect(book.readingAvailability, 'metadata_only');
    });

    test('does not make restricted Archive files readable', () {
      final book = Book.fromInternetArchiveJson(
        {'identifier': 'restricted-book', 'title': 'Restricted'},
        metadata: {
          'metadata': {'access-restricted-item': true},
          'files': [
            {'name': 'book.epub', 'format': 'EPUB', 'private': false},
          ],
        },
      );

      expect(book.epubUrl, isNull);
      expect(book.canReadInApp, isFalse);
    });

    test('only exposes an embeddable Google Books web reader link', () {
      final book = Book.fromGoogleBooksJson({
        'id': 'preview-id',
        'volumeInfo': {
          'title': 'Preview',
          'industryIdentifiers': [
            {'type': 'ISBN_13', 'identifier': '9781234567890'}
          ],
        },
        'accessInfo': {
          'embeddable': true,
          'webReaderLink': 'https://books.google.com/books?id=preview-id',
          'viewability': 'PARTIAL',
        },
      });

      expect(book.previewUrl, contains('books.google.com'));
      expect(book.isbn, '9781234567890');
      expect(book.canReadInApp, isTrue);
    });

    test(
        'makes public Internet Archive EPUB files readable only when known public',
        () {
      final publicBook = Book.fromInternetArchiveJson(
        {'identifier': 'public-book', 'title': 'Public book'},
        metadata: {
          'metadata': {'access-restricted-item': false},
          'files': [
            {'name': 'public-book.epub', 'format': 'EPUB', 'private': false},
          ],
        },
      );
      final unknownAccessBook = Book.fromInternetArchiveJson(
        {'identifier': 'unknown-book', 'title': 'Unknown access'},
        metadata: {
          'metadata': {},
          'files': [
            {'name': 'unknown-book.epub', 'format': 'EPUB', 'private': false},
          ],
        },
      );

      expect(publicBook.epubUrl, contains('public-book.epub'));
      expect(unknownAccessBook.epubUrl, isNull);
    });
  });

  test('returns other catalog results when Google Books fails', () async {
    final client = MockClient((request) async {
      if (request.url.host == 'www.googleapis.com') {
        return http.Response('quota exceeded', 429);
      }
      if (request.url.host == 'openlibrary.org') {
        return http.Response(
          jsonEncode({
            'numFound': 1,
            'docs': [
              {
                'key': '/works/OL123W',
                'title': 'Example Title',
                'author_name': ['Example Author'],
                'cover_i': 123,
                'isbn': ['9781234567890'],
              },
            ],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      if (request.url.host == 'gutendex.com') {
        return http.Response(
          jsonEncode({'count': 0, 'next': null, 'results': []}),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      if (request.url.host == 'archive.org') {
        return http.Response(
          jsonEncode({
            'response': {'numFound': 0, 'docs': []}
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      return http.Response('unexpected request', 500);
    });

    final repository = BookRepository(client: client);
    addTearDown(repository.dispose);

    final result = await repository.searchBooks('example');

    expect(result.books, hasLength(1));
    expect(result.books.single.title, 'Example Title');
    expect(result.sourceWarnings, hasLength(1));
    expect(result.sourceWarnings.single, contains('Google Books'));
  });

  test('searches each catalog with the selected author query and page',
      () async {
    final requests = <Uri>[];
    final client = MockClient((request) async {
      requests.add(request.url);
      if (request.url.host == 'openlibrary.org') {
        return http.Response(
          jsonEncode({
            'numFound': 1,
            'docs': [
              {
                'key': '/works/OL123W',
                'title': 'Example Title',
                'author_name': ['Example Author'],
                'author_key': ['OL456A'],
              },
            ],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      if (request.url.host == 'www.googleapis.com') {
        return http.Response(
          jsonEncode({
            'totalItems': 1,
            'items': [
              {
                'id': 'google-123',
                'volumeInfo': {
                  'title': 'Another Example',
                  'authors': ['Example Author'],
                },
              },
            ],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      if (request.url.host == 'gutendex.com') {
        return http.Response(
          jsonEncode({
            'count': 1,
            'next': 'https://gutendex.com/books/?page=3',
            'results': [
              {
                'id': 42,
                'title': 'Public Domain Example',
                'authors': [],
                'formats': {},
              },
            ],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      return http.Response(
        jsonEncode({
          'response': {'numFound': 0, 'docs': []}
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    });
    final repository = BookRepository(client: client);
    addTearDown(repository.dispose);

    final result = await repository.searchBooks(
      'Example Author',
      type: BookSearchType.author,
      page: 2,
    );

    expect(result.books.map((book) => book.source), contains('Google Books'));
    expect(result.books.map((book) => book.source), contains('Open Library'));
    expect(
      result.books.map((book) => book.source),
      contains('Project Gutenberg'),
    );
    expect(result.hasMore, isTrue);
    final openLibraryUri =
        requests.singleWhere((uri) => uri.host == 'openlibrary.org');
    final googleUri =
        requests.singleWhere((uri) => uri.host == 'www.googleapis.com');
    final gutendexUri =
        requests.singleWhere((uri) => uri.host == 'gutendex.com');
    expect(openLibraryUri.queryParameters['author'], 'Example Author');
    expect(openLibraryUri.queryParameters['page'], '2');
    expect(googleUri.queryParameters['q'], 'inauthor:Example Author');
    expect(googleUri.queryParameters['startIndex'], '12');
    expect(gutendexUri.queryParameters['search'], 'Example Author');
    expect(gutendexUri.queryParameters['page'], '2');
  });

  test('merges duplicate source entries and preserves readable metadata',
      () async {
    final repository = BookRepository(
      client: MockClient((_) async => http.Response('{}', 200)),
    );
    addTearDown(repository.dispose);
    const openLibrary = Book(
      key: 'openlibrary:/works/1',
      source: 'Open Library',
      title: 'The Example',
      authors: ['A. Writer'],
      isbn: '9781234567890',
    );
    const gutenberg = Book(
      key: 'gutendex:1',
      source: 'Project Gutenberg',
      title: 'The Example',
      authors: ['A. Writer'],
      isbn: '978-1-234567-89-0',
      plainTextUrl: 'https://www.gutenberg.org/ebooks/1.txt.utf-8',
      description: 'Public-domain description',
    );

    final merged = repository.mergePages([openLibrary], [gutenberg]);

    expect(merged, hasLength(1));
    expect(merged.single.canReadInApp, isTrue);
    expect(merged.single.description, 'Public-domain description');
    expect(merged.single.source, contains('Project Gutenberg'));
    expect(merged.single.source, contains('Open Library'));
  });
}
