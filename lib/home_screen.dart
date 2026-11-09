import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'app_provider.dart';
import 'book.dart';
import 'book_card.dart';
import 'ebook_readers.dart';
import 'reader_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedIndex = 0;
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _resultsScrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _resultsScrollController.addListener(_loadMoreResults);
  }

  void _loadMoreResults() {
    if (_resultsScrollController.hasClients &&
        _resultsScrollController.position.extentAfter < 350) {
      context.read<AppProvider>().loadMore();
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _resultsScrollController.dispose();
    super.dispose();
  }

  void _openBook(Book book) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ReaderScreen(book: book)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppProvider>();
    final pages = [
      _discoverPage(app),
      _libraryPage(app),
      _collectionPage(app.favorites, 'Your saved books',
          'Books you add to favorites will appear here.'),
      _collectionPage(app.history, 'Recently opened',
          'Open a book to start building your reading history.'),
      _downloadsPage(app),
    ];

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 16,
        title: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Image.asset(
                'assets/global_library_logo.jpeg',
                width: 38,
                height: 38,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Icon(
                  Icons.menu_book_rounded,
                  color: Theme.of(context).colorScheme.primary,
                  size: 30,
                ),
              ),
            ),
            const SizedBox(width: 10),
            const Text(
              'Global Library',
              style:
                  TextStyle(fontWeight: FontWeight.w800, letterSpacing: -0.4),
            ),
          ],
        ),
        actions: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                app.isDark ? Icons.dark_mode_rounded : Icons.light_mode_rounded,
                size: 18,
              ),
              Switch.adaptive(
                value: app.isDark,
                onChanged: (_) => app.toggleTheme(),
              ),
            ],
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: IndexedStack(
          index: _selectedIndex,
          children: pages,
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (index) =>
            setState(() => _selectedIndex = index),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.explore_outlined),
            selectedIcon: Icon(Icons.explore_rounded),
            label: 'Discover',
          ),
          NavigationDestination(
            icon: Icon(Icons.collections_bookmark_outlined),
            selectedIcon: Icon(Icons.collections_bookmark_rounded),
            label: 'My Library',
          ),
          NavigationDestination(
            icon: Icon(Icons.favorite_border_rounded),
            selectedIcon: Icon(Icons.favorite_rounded),
            label: 'Favorites',
          ),
          NavigationDestination(
            icon: Icon(Icons.history_rounded),
            label: 'History',
          ),
          NavigationDestination(
            icon: Icon(Icons.download_for_offline_outlined),
            selectedIcon: Icon(Icons.download_done_rounded),
            label: 'Downloads',
          ),
        ],
      ),
    );
  }

  Widget _libraryPage(AppProvider app) {
    const statuses = ['Want to Read', 'Currently Reading', 'Finished'];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 22, 18, 16),
          child: Text(
            'My Library',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
        ),
        Expanded(
          child: app.library.isEmpty
              ? const _MessageState(
                  icon: Icons.collections_bookmark_outlined,
                  title: 'Your library is empty',
                  message:
                      'Add books from their details page to keep them here.',
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                  itemCount: app.library.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final book = app.library[index];
                    return Card(
                      child: ListTile(
                        onTap: () => _openBook(book),
                        leading: SizedBox(
                          width: 48,
                          height: 64,
                          child: book.coverUrl == null
                              ? const Icon(Icons.menu_book_rounded)
                              : Image.network(
                                  book.coverUrl!,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) =>
                                      const Icon(Icons.menu_book_rounded),
                                ),
                        ),
                        title: Text(
                          book.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          '${book.authorLine}\n${app.libraryStatus(book)}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        isThreeLine: true,
                        trailing: PopupMenuButton<String>(
                          tooltip: 'Book options',
                          onSelected: (value) {
                            if (value == 'remove') {
                              app.removeFromLibrary(book);
                            } else if (statuses.contains(value)) {
                              app.setLibraryStatus(book, value);
                            }
                          },
                          itemBuilder: (context) => [
                            for (final status in statuses)
                              PopupMenuItem(
                                value: status,
                                child: Text(
                                  app.libraryStatus(book) == status
                                      ? '$status ✓'
                                      : status,
                                ),
                              ),
                            const PopupMenuDivider(),
                            const PopupMenuItem(
                              value: 'remove',
                              child: Text('Remove from library'),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _discoverPage(AppProvider app) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'A world of stories,',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.7,
                    ),
              ),
              Text(
                'one page at a time.',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.7,
                    ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _searchController,
                textInputAction: TextInputAction.search,
                onChanged: app.search,
                onSubmitted: (value) => app.search(value, immediate: true),
                decoration: InputDecoration(
                  hintText: 'Search titles, authors, or topics',
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: _searchController.text.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Clear search',
                          onPressed: () {
                            _searchController.clear();
                            app.search('');
                            setState(() {});
                          },
                          icon: const Icon(Icons.close_rounded),
                        ),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Text(
                    app.query.trim().isEmpty
                        ? 'Explore books'
                        : 'Search results',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                  const Spacer(),
                  if (app.isLoading)
                    const SizedBox(
                      width: 17,
                      height: 17,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                ],
              ),
            ],
          ),
        ),
        Expanded(
          child: _buildDiscoverResults(app),
        ),
      ],
    );
  }

  Widget _buildDiscoverResults(AppProvider app) {
    if (app.error != null) {
      return _MessageState(
        icon: Icons.cloud_off_rounded,
        title: 'Could not load books',
        message: app.error!,
        actionLabel: 'Try again',
        onAction: () => app.search(_searchController.text, immediate: true),
      );
    }

    if (app.query.trim().isEmpty) {
      return const _MessageState(
        icon: Icons.auto_stories_rounded,
        title: 'Find your next favorite',
        message:
            'Search Open Library, Google Books, Project Gutenberg, and Internet Archive.',
      );
    }

    if (app.isLoading && app.results.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (app.results.isEmpty) {
      return const _MessageState(
        icon: Icons.search_off_rounded,
        title: 'No books found',
        message: 'Try another title, author, or keyword.',
      );
    }

    return Column(
      children: [
        if (app.sourceWarnings.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 8),
            child: Text(
              'Some sources could not be reached. Results from available '
              'sources are shown.\n${app.sourceWarnings.join('\n')}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.error,
                  ),
            ),
          ),
        Expanded(
          child: GridView.builder(
            controller: _resultsScrollController,
            padding: const EdgeInsets.fromLTRB(18, 4, 18, 20),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 13,
              mainAxisSpacing: 14,
              childAspectRatio: 0.57,
            ),
            itemCount: app.results.length + (app.isLoadingMore ? 1 : 0),
            itemBuilder: (context, index) {
              if (index >= app.results.length) {
                return const Center(child: CircularProgressIndicator());
              }
              final book = app.results[index];
              return BookCard(
                book: book,
                onTap: () => _openBook(book),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _collectionPage(List<Book> books, String title, String emptyMessage) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 22, 18, 16),
          child: Text(
            title,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
        ),
        Expanded(
          child: books.isEmpty
              ? _MessageState(
                  icon: title == 'Your saved books'
                      ? Icons.favorite_border_rounded
                      : Icons.history_rounded,
                  title: 'Nothing here yet',
                  message: emptyMessage,
                )
              : GridView.builder(
                  padding: const EdgeInsets.fromLTRB(18, 0, 18, 20),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: 13,
                    mainAxisSpacing: 14,
                    childAspectRatio: 0.57,
                  ),
                  itemCount: books.length,
                  itemBuilder: (context, index) => BookCard(
                    book: books[index],
                    onTap: () => _openBook(books[index]),
                  ),
                ),
        ),
      ],
    );
  }

  Widget _downloadsPage(AppProvider app) {
    final downloads = app.downloadedBooks;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 22, 18, 16),
          child: Text(
            'Downloaded books',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
        ),
        Expanded(
          child: downloads.isEmpty
              ? const _MessageState(
                  icon: Icons.download_for_offline_outlined,
                  title: 'No books downloaded',
                  message:
                      'Download an authorized PDF or EPUB from a book details page to read it offline.',
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                  itemCount: downloads.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final download = downloads[index];
                    final book = download.book;
                    return Card(
                      child: ListTile(
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => download.format == 'epub'
                                ? EpubBookReader(book: book)
                                : PdfBookReader(book: book),
                          ),
                        ),
                        leading: SizedBox(
                          width: 48,
                          height: 64,
                          child: book.coverUrl == null
                              ? const Icon(Icons.menu_book_rounded)
                              : Image.network(
                                  book.coverUrl!,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) =>
                                      const Icon(Icons.menu_book_rounded),
                                ),
                        ),
                        title: Text(
                          book.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          '${book.authorLine}\n'
                          '${download.format.toUpperCase()} · '
                          '${_formatFileSize(download.sizeBytes)}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        isThreeLine: true,
                        trailing: IconButton(
                          tooltip: 'Delete downloaded file',
                          icon: const Icon(Icons.delete_outline_rounded),
                          onPressed: () async {
                            final shouldDelete = await showDialog<bool>(
                              context: context,
                              builder: (context) => AlertDialog(
                                title: const Text('Delete download?'),
                                content: Text(
                                  'Remove the saved ${download.format.toUpperCase()} '
                                  'file for “${book.title}”?',
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () =>
                                        Navigator.of(context).pop(false),
                                    child: const Text('Cancel'),
                                  ),
                                  FilledButton(
                                    onPressed: () =>
                                        Navigator.of(context).pop(true),
                                    child: const Text('Delete'),
                                  ),
                                ],
                              ),
                            );
                            if (shouldDelete != true || !context.mounted) {
                              return;
                            }
                            try {
                              await app.deleteDownload(download);
                            } on Exception catch (error) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      'Could not delete download: $error',
                                    ),
                                  ),
                                );
                              }
                            }
                          },
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

class _MessageState extends StatelessWidget {
  const _MessageState({
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 52, color: theme.colorScheme.primary),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.65),
                height: 1.4,
              ),
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 18),
              FilledButton(onPressed: onAction, child: Text(actionLabel!)),
            ],
          ],
        ),
      ),
    );
  }
}
