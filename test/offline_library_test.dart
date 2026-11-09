import 'dart:io';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:global_library/app_provider.dart';
import 'package:global_library/book.dart';
import 'package:global_library/book_repository.dart';
import 'package:global_library/local_book_storage.dart';
import 'package:global_library/local_library_database.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  const book = Book(
    key: 'gutendex:1342',
    source: 'Project Gutenberg',
    title: 'Pride and Prejudice',
    authors: ['Jane Austen'],
    epubUrl: 'https://www.gutenberg.org/ebooks/1342.epub.images',
    pdfUrl: 'https://www.gutenberg.org/files/1342/1342-pdf.pdf',
  );

  test('persists collections, progress, named bookmarks, and downloads',
      () async {
    final directory = await Directory.systemTemp.createTemp();
    final database = LocalLibraryDatabase(
      factory: databaseFactoryFfi,
      databasePath: () async => directory.path,
    );
    addTearDown(() async {
      await database.close();
      await directory.delete(recursive: true);
    });

    await database.saveFavorite(book, true);
    await database.saveLibraryBook(book, 'Currently Reading');
    await database.recordOpened(book);
    await database.saveProgress(book, page: 8, totalPages: 40);
    expect((await database.getProgress(book.key))?.completion, 0.2);
    await database.saveProgress(
      book,
      epubLocation: 'epubcfi(/6/4[part]!/4/2)',
      completion: 0.35,
    );
    final bookmarkId = await database.createBookmark(
      book,
      name: 'Important chapter',
      page: 8,
      location: 'epubcfi(/6/4[part]!/4/2)',
      format: 'epub',
    );
    await database.renameBookmark(bookmarkId, 'Review this chapter');
    await database.saveDownload(
      book,
      format: 'epub',
      path: '${directory.path}\\book.epub',
      sizeBytes: 1234,
    );
    await database.saveNote(book.key, 'Important quotation');

    expect((await database.getFavorites()).single.key, book.key);
    expect(
        (await database.getLibraryStatuses())[book.key], 'Currently Reading');
    expect((await database.getHistory()).single.key, book.key);
    final progress = await database.getProgress(book.key);
    expect(progress?.currentPage, 8);
    expect(progress?.totalPages, 40);
    expect(progress?.completion, 0.35);
    expect(progress?.epubLocation, 'epubcfi(/6/4[part]!/4/2)');
    final bookmarks = await database.getBookmarks(book.key);
    expect(bookmarks.single.name, 'Review this chapter');
    expect(bookmarks.single.location, 'epubcfi(/6/4[part]!/4/2)');
    expect((await database.getDownloadedBooks()).single.sizeBytes, 1234);
    expect((await database.getNotes(book.key)).single.content,
        'Important quotation');

    await database.removeLibraryBook(book.key);
    expect(await database.getLibraryBooks(), isEmpty);
    expect(await database.getFavorites(), hasLength(1));
  });

  test('migrates existing SharedPreferences data into SQLite', () async {
    SharedPreferences.setMockInitialValues({
      'global_library_favorites_v1': jsonEncode([book.toJson()]),
      'global_library_library_v1': jsonEncode([book.toJson()]),
      'global_library_library_statuses_v1':
          jsonEncode({book.key: 'Currently Reading'}),
      'global_library_history_v1': jsonEncode([book.toJson()]),
      'global_library_bookmarks_v1': jsonEncode({book.key: 12}),
      'global_library_epub_locations_v1':
          jsonEncode({book.key: 'epubcfi(/6/4[part]!/4/2)'}),
      'global_library_dark_mode_v1': true,
    });
    final directory = await Directory.systemTemp.createTemp();
    final database = LocalLibraryDatabase(
      factory: databaseFactoryFfi,
      databasePath: () async => directory.path,
    );
    final storage = LocalBookStorage(
      client: MockClient((_) async => http.Response('', 500)),
      documentsDirectory: () async => directory,
    );
    final provider = AppProvider(
      database: database,
      bookStorage: storage,
      repository: BookRepository(
        client: MockClient((_) async => http.Response('{}', 500)),
      ),
    );
    try {
      await provider.initialize();
      expect(provider.favorites.single.key, book.key);
      expect(provider.library.single.key, book.key);
      expect(provider.libraryStatus(book), 'Currently Reading');
      expect(provider.history.single.key, book.key);
      expect(provider.bookmarkFor(book), 12);
      expect(provider.epubLocationFor(book), 'epubcfi(/6/4[part]!/4/2)');
      expect(provider.bookmarksFor(book).single.name, 'Reading progress');
      expect(provider.bookmarksFor(book).single.format, 'epub');
      expect(
        provider.bookmarksFor(book).single.location,
        'epubcfi(/6/4[part]!/4/2)',
      );
      expect(provider.isDark, isTrue);
    } finally {
      await database.close();
      provider.dispose();
      await directory.delete(recursive: true);
    }
  });

  test('shows persisted search results when all catalogs are unavailable',
      () async {
    SharedPreferences.setMockInitialValues({});
    final directory = await Directory.systemTemp.createTemp();
    final database = LocalLibraryDatabase(
      factory: databaseFactoryFfi,
      databasePath: () async => directory.path,
    );
    const cachedBook = Book(
      key: 'openlibrary:/works/OL123W',
      source: 'Open Library',
      title: 'Cached Example',
      authors: ['Example Author'],
    );
    await database.cacheSearchPage(
      'keyword|example',
      1,
      [cachedBook],
    );
    final repository = BookRepository(
      client: MockClient((_) async => http.Response('unavailable', 503)),
    );
    final storage = LocalBookStorage(
      client: MockClient((_) async => http.Response('', 500)),
      documentsDirectory: () async => directory,
    );
    final provider = AppProvider(
      database: database,
      repository: repository,
      bookStorage: storage,
    );

    try {
      await provider.initialize();
      await provider.search('example', immediate: true);

      expect(provider.results.map((item) => item.key), [cachedBook.key]);
      expect(provider.error, isNull);
      expect(
        provider.sourceWarnings.single,
        contains('showing locally cached results'),
      );
    } finally {
      await database.close();
      provider.dispose();
      await directory.delete(recursive: true);
    }
  });

  test('stores only verified authorized PDF and EPUB files', () async {
    final directory = await Directory.systemTemp.createTemp();
    final storage = LocalBookStorage(
      client: MockClient((request) async {
        if (request.url.path.endsWith('.epub.images')) {
          return http.Response.bytes([0x50, 0x4b, 0x03, 0x04, 0x00], 200);
        }
        return http.Response.bytes('%PDF-1.7\n'.codeUnits, 200);
      }),
      documentsDirectory: () async => directory,
    );
    addTearDown(() async {
      await storage.dispose();
      await directory.delete(recursive: true);
    });

    final pdf = await storage.download(book, 'pdf');
    final epub = await storage.download(book, 'epub');
    expect(await pdf.exists(), isTrue);
    expect(await epub.exists(), isTrue);
    expect(await pdf.length(), greaterThan(0));
    expect(await epub.length(), greaterThan(0));
    expect(pdf.path, contains('\\books\\'));
  });

  test('rejects unauthorized and invalid book downloads', () async {
    final directory = await Directory.systemTemp.createTemp();
    final storage = LocalBookStorage(
      client: MockClient((_) async => http.Response('not a PDF', 200)),
      documentsDirectory: () async => directory,
    );
    addTearDown(() async {
      await storage.dispose();
      await directory.delete(recursive: true);
    });

    const unauthorized = Book(
      key: 'bad:1',
      title: 'Unknown source',
      authors: [],
      pdfUrl: 'https://example.com/book.pdf',
    );
    await expectLater(
      storage.download(unauthorized, 'pdf'),
      throwsA(isA<LocalBookStorageException>()),
    );
    await expectLater(
      storage.download(book, 'pdf'),
      throwsA(isA<LocalBookStorageException>()),
    );
    final bookDirectory = Directory('${directory.path}\\books');
    if (await bookDirectory.exists()) {
      expect(await bookDirectory.list().toList(), isEmpty);
    }
  });
}
