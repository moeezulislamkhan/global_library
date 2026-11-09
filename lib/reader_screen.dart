import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import 'app_provider.dart';
import 'book.dart';
import 'book_card.dart';
import 'ebook_readers.dart';
import 'google_books_reader.dart';
import 'plain_text_reader.dart';
import 'reading_models.dart';

/// Shows book details and opens Google Books' authorized preview in-app.
class ReaderScreen extends StatefulWidget {
  const ReaderScreen({super.key, required this.book});

  final Book book;

  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends State<ReaderScreen> {
  late final TextEditingController _pageController;
  late Future<List<Book>> _recommendationsFuture;
  String? _feedback;
  bool _descriptionExpanded = false;

  @override
  void initState() {
    super.initState();
    final saved = context.read<AppProvider>().bookmarkFor(widget.book);
    _pageController = TextEditingController(text: saved?.toString() ?? '');
    _recommendationsFuture =
        context.read<AppProvider>().getRecommendations(widget.book);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<AppProvider>().recordOpened(widget.book);
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _saveBookmark() async {
    final page = int.tryParse(_pageController.text.trim());
    if (page == null || page <= 0) {
      setState(
          () => _feedback = 'Enter a valid page number greater than zero.');
      return;
    }
    await context.read<AppProvider>().saveBookmark(widget.book, page);
    if (!mounted) return;
    setState(() => _feedback = 'Reading progress saved at page $page.');
    FocusScope.of(context).unfocus();
  }

  Future<void> _editBookmark(ReadingBookmark bookmark) async {
    final controller = TextEditingController(text: bookmark.name);
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit bookmark name'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          onSubmitted: (value) => Navigator.of(context).pop(value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name == null || name.trim().isEmpty || !mounted) return;
    await context.read<AppProvider>().renameBookmark(bookmark, name);
  }

  void _openBookmark(ReadingBookmark bookmark) {
    final Widget reader = switch (bookmark.format) {
      'epub' => EpubBookReader(book: widget.book, bookmark: bookmark),
      'pdf' => PdfBookReader(book: widget.book, bookmark: bookmark),
      _ => PlainTextReader(book: widget.book, bookmark: bookmark),
    };
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => reader),
    );
  }

  String _availabilityLabel(String value) => switch (value) {
        'full_view' => 'full view',
        'preview' => 'publisher-limited preview',
        'metadata_only' ||
        'catalog_only' =>
          'catalog information only; reading is not confirmed',
        'public_domain' => 'public-domain reading copy available',
        'public_scan' => 'public scan reported by the catalog',
        'borrowable' => 'borrowing may be available; check provider terms',
        'printdisabled' =>
          'accessible ebook access may require an eligible account',
        _ => value.replaceAll('_', ' '),
      };

  Future<void> _launchProviderUrl(
    String value, {
    String? successMessage,
  }) async {
    final uri = Uri.tryParse(value);
    if (uri == null || uri.scheme != 'https') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('The provider link is invalid.')),
      );
      return;
    }
    final launched = await launchUrl(
      uri,
      mode: LaunchMode.externalApplication,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          launched
              ? successMessage ?? 'Provider reading page opened.'
              : 'Could not open the provider reading page.',
        ),
      ),
    );
  }

  Widget _downloadButton(AppProvider app, String format, String? sourceUrl) {
    if (sourceUrl == null) return const SizedBox.shrink();
    final matches = app.downloadedBooks.where(
      (item) => item.book.key == widget.book.key && item.format == format,
    );
    final download = matches.isEmpty ? null : matches.first;
    final downloading = app.isDownloading(widget.book, format);
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          OutlinedButton.icon(
            onPressed: downloading
                ? null
                : download == null
                    ? () async {
                        try {
                          await app.downloadBook(widget.book, format);
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  '${format.toUpperCase()} saved for offline reading.',
                                ),
                              ),
                            );
                          }
                        } on Exception catch (error) {
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                  content: Text('Download failed: $error')),
                            );
                          }
                        }
                      }
                    : () async {
                        try {
                          await app.deleteDownload(download);
                        } on Exception catch (error) {
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content:
                                    Text('Could not delete download: $error'),
                              ),
                            );
                          }
                        }
                      },
            icon: downloading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(
                    download == null
                        ? Icons.download_for_offline_outlined
                        : Icons.delete_outline_rounded,
                  ),
            label: Text(
              downloading
                  ? 'Downloading…'
                  : download == null
                      ? 'Download ${format.toUpperCase()} for offline'
                      : 'Remove downloaded ${format.toUpperCase()}',
            ),
          ),
          if (downloading)
            LinearProgressIndicator(
              value: app.downloadProgress(widget.book, format),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppProvider>();
    final theme = Theme.of(context);
    final savedPage = app.bookmarkFor(widget.book);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Book details'),
        actions: [
          IconButton(
            tooltip: app.isInLibrary(widget.book)
                ? 'Remove from My Library'
                : 'Add to My Library',
            onPressed: () => app.isInLibrary(widget.book)
                ? app.removeFromLibrary(widget.book)
                : app.addToLibrary(widget.book),
            icon: Icon(
              app.isInLibrary(widget.book)
                  ? Icons.library_add_check_rounded
                  : Icons.library_add_outlined,
            ),
          ),
          IconButton(
            tooltip: app.isFavorite(widget.book)
                ? 'Remove from favorites'
                : 'Add to favorites',
            onPressed: () => app.toggleFavorite(widget.book),
            icon: Icon(
              app.isFavorite(widget.book)
                  ? Icons.favorite_rounded
                  : Icons.favorite_border_rounded,
              color: app.isFavorite(widget.book) ? Colors.pinkAccent : null,
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(22, 8, 22, 28),
          children: [
            Center(
              child: Container(
                width: 164,
                height: 226,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.18),
                      blurRadius: 22,
                      offset: const Offset(0, 12),
                    ),
                  ],
                ),
                clipBehavior: Clip.antiAlias,
                child: widget.book.coverUrl == null
                    ? Icon(Icons.menu_book_rounded,
                        size: 64, color: theme.colorScheme.primary)
                    : Image.network(
                        widget.book.coverUrl!,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Icon(
                          Icons.menu_book_rounded,
                          size: 64,
                          color: theme.colorScheme.primary,
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 22),
            Text(
              widget.book.title,
              textAlign: TextAlign.center,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w800,
                height: 1.15,
              ),
            ),
            const SizedBox(height: 7),
            Text(
              widget.book.authorLine,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.65),
              ),
            ),
            if (widget.book.description case final description?) ...[
              const SizedBox(height: 18),
              Text(
                'About this book',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                description,
                maxLines: _descriptionExpanded ? null : 5,
                overflow: _descriptionExpanded ? null : TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(height: 1.55),
              ),
              if (description.length > 320)
                TextButton(
                  onPressed: () => setState(
                    () => _descriptionExpanded = !_descriptionExpanded,
                  ),
                  child: Text(_descriptionExpanded ? 'Show less' : 'Read more'),
                ),
            ],
            const SizedBox(height: 18),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: [
                if (widget.book.firstPublishYear != null)
                  _InfoChip(
                      label: 'First published ${widget.book.firstPublishYear}'),
                if (widget.book.editionCount != null)
                  _InfoChip(label: '${widget.book.editionCount} editions'),
                _InfoChip(label: widget.book.source),
                if (widget.book.isbn != null)
                  _InfoChip(label: 'ISBN ${widget.book.isbn}'),
                if (widget.book.publisher != null)
                  _InfoChip(label: widget.book.publisher!),
                if (widget.book.language != null)
                  _InfoChip(label: widget.book.language!),
                if (widget.book.publicationDate != null)
                  _InfoChip(label: widget.book.publicationDate!),
                if (widget.book.averageRating != null)
                  _InfoChip(
                    label: '★ ${widget.book.averageRating!.toStringAsFixed(1)}'
                        '${widget.book.ratingsCount == null ? '' : ' · ${widget.book.ratingsCount} ratings'}',
                  ),
                if (widget.book.downloadCount != null)
                  _InfoChip(
                    label: '${widget.book.downloadCount} public downloads',
                  ),
                for (final category in widget.book.categories.take(4))
                  _InfoChip(label: category),
                for (final format in widget.book.availableFormats)
                  _InfoChip(label: format),
                if (savedPage != null)
                  _InfoChip(label: 'Saved at page $savedPage'),
              ],
            ),
            if (widget.book.readingAvailability != null) ...[
              const SizedBox(height: 12),
              Text(
                'Reading availability: '
                '${_availabilityLabel(widget.book.readingAvailability!)}',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium,
              ),
            ],
            const SizedBox(height: 26),
            Text(
              'Read in the app',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            if (widget.book.previewUrl case final previewUrl?) ...[
              Text(
                widget.book.previewViewability == 'ALL_PAGES'
                    ? 'Google Books provides a full view of this book.'
                    : 'Google Books provides an authorized preview. '
                        'Available pages depend on the publisher.',
                style: theme.textTheme.bodyMedium?.copyWith(height: 1.5),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => GoogleBooksReaderScreen(
                      title: widget.book.title,
                      previewUrl: previewUrl,
                    ),
                  ),
                ),
                icon: const Icon(Icons.menu_book_rounded),
                label: const Text('Read book preview'),
              ),
            ],
            if (widget.book.plainTextUrl != null) ...[
              const SizedBox(height: 8),
              FilledButton.tonalIcon(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => PlainTextReader(book: widget.book),
                  ),
                ),
                icon: const Icon(Icons.menu_book_rounded),
                label: const Text('Read full public-domain text'),
              ),
            ],
            if (widget.book.epubUrl != null) ...[
              const SizedBox(height: 8),
              FilledButton.tonalIcon(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => EpubBookReader(book: widget.book),
                  ),
                ),
                icon: const Icon(Icons.auto_stories_rounded),
                label: const Text('Read EPUB in app'),
              ),
            ],
            if (widget.book.pdfUrl != null) ...[
              const SizedBox(height: 8),
              FilledButton.tonalIcon(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => PdfBookReader(book: widget.book),
                  ),
                ),
                icon: const Icon(Icons.picture_as_pdf_rounded),
                label: const Text('Read PDF in app'),
              ),
            ],
            if (widget.book.borrowUrl case final borrowUrl?) ...[
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () => _launchProviderUrl(
                  borrowUrl,
                  successMessage:
                      'Open Library borrowing options opened in your browser.',
                ),
                icon: const Icon(Icons.menu_book_outlined),
                label: const Text('Check Open Library borrowing access'),
              ),
            ],
            if (widget.book.readingUrl case final readingUrl?
                when readingUrl != widget.book.previewUrl &&
                    readingUrl != widget.book.plainTextUrl) ...[
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () => _launchProviderUrl(readingUrl),
                icon: const Icon(Icons.open_in_browser_rounded),
                label: const Text('Open authorized reading edition'),
              ),
            ],
            _downloadButton(app, 'epub', widget.book.epubUrl),
            _downloadButton(app, 'pdf', widget.book.pdfUrl),
            if (!widget.book.canReadInApp)
              Text(
                'No authorized in-app reading copy is available from the '
                'sources checked. Access depends on source and publisher '
                'permissions.',
                style: theme.textTheme.bodyMedium?.copyWith(height: 1.5),
              ),
            const SizedBox(height: 24),
            Text(
              'Named bookmarks',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            if (app.bookmarksFor(widget.book).isEmpty)
              const Text(
                'Create a bookmark from the reader to save a named location.',
              )
            else
              ...app.bookmarksFor(widget.book).map(
                    (bookmark) => Card(
                      child: ListTile(
                        onTap: () => _openBookmark(bookmark),
                        leading: const Icon(Icons.bookmark_outline_rounded),
                        title: Text(bookmark.name),
                        subtitle: Text(
                          bookmark.location != null
                              ? 'EPUB reading location'
                              : 'Page ${bookmark.page ?? 1}',
                        ),
                        trailing: PopupMenuButton<String>(
                          tooltip: 'Bookmark options',
                          onSelected: (value) async {
                            if (value == 'edit') {
                              await _editBookmark(bookmark);
                            } else if (value == 'delete') {
                              await app.deleteBookmark(bookmark);
                            }
                          },
                          itemBuilder: (context) => const [
                            PopupMenuItem(
                              value: 'edit',
                              child: Text('Edit name'),
                            ),
                            PopupMenuItem(
                              value: 'delete',
                              child: Text('Delete bookmark'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
            const SizedBox(height: 24),
            Text(
              'Recommended books',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 10),
            FutureBuilder<List<Book>>(
              future: _recommendationsFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Padding(
                    padding: EdgeInsets.all(20),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                if (snapshot.hasError) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Recommendations could not be loaded: '
                        '${snapshot.error}',
                      ),
                      TextButton(
                        onPressed: () => setState(() {
                          _recommendationsFuture = context
                              .read<AppProvider>()
                              .getRecommendations(widget.book);
                        }),
                        child: const Text('Try again'),
                      ),
                    ],
                  );
                }
                final recommendations = snapshot.data ?? const <Book>[];
                if (recommendations.isEmpty) {
                  return const Text(
                    'No similar books were found. Try exploring another book.',
                  );
                }
                return SizedBox(
                  height: 258,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: recommendations.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 12),
                    itemBuilder: (context, index) {
                      final recommendation = recommendations[index];
                      return SizedBox(
                        width: 148,
                        child: BookCard(
                          book: recommendation,
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) =>
                                  ReaderScreen(book: recommendation),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                );
              },
            ),
            const SizedBox(height: 22),
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: theme.cardTheme.color,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: theme.colorScheme.primary.withValues(alpha: 0.16),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Save your reading progress',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _pageController,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            hintText: 'Page number',
                            prefixIcon: Icon(Icons.bookmark_border_rounded),
                          ),
                          onSubmitted: (_) => _saveBookmark(),
                        ),
                      ),
                      const SizedBox(width: 10),
                      FilledButton(
                        onPressed: _saveBookmark,
                        child: const Text('Save'),
                      ),
                    ],
                  ),
                  if (_feedback != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      _feedback!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 22),
            OutlinedButton.icon(
              onPressed: () async {
                final uri = widget.book.recordUrl != null
                    ? Uri.tryParse(widget.book.recordUrl!)
                    : widget.book.key.startsWith('google:')
                        ? Uri.https(
                            'books.google.com',
                            '/books',
                            {'id': widget.book.key.substring('google:'.length)},
                          )
                        : Uri.https(
                            'openlibrary.org',
                            widget.book.key.startsWith('/')
                                ? widget.book.key
                                : '/${widget.book.key}',
                          );
                if (uri == null) return;
                final launched = await launchUrl(
                  uri,
                  mode: LaunchMode.externalApplication,
                );
                if (!launched && context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content: Text('Could not open the book record.')),
                  );
                }
              },
              icon: const Icon(Icons.open_in_new_rounded),
              label: const Text('Open book record'),
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Chip(
      label: Text(label),
      visualDensity: VisualDensity.compact,
      side: BorderSide.none,
      backgroundColor:
          Theme.of(context).colorScheme.primary.withValues(alpha: 0.10),
    );
  }
}
