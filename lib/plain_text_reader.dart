import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'app_provider.dart';
import 'book.dart';
import 'ebook_readers.dart' show createReadingBookmark;
import 'reading_models.dart';

class PlainTextReader extends StatefulWidget {
  const PlainTextReader({super.key, required this.book, this.bookmark});

  final Book book;
  final ReadingBookmark? bookmark;

  @override
  State<PlainTextReader> createState() => _PlainTextReaderState();
}

class _PlainTextReaderState extends State<PlainTextReader> {
  late Future<String> _textFuture;
  late int _pageIndex;
  double _fontSize = 18;

  @override
  void initState() {
    super.initState();
    final app = context.read<AppProvider>();
    _pageIndex = ((widget.bookmark?.page ?? app.bookmarkFor(widget.book) ?? 1) -
            1)
        .clamp(0, 1000000);
    _textFuture = app.getPlainText(widget.book);
  }

  List<String> _paginate(String text) {
    const chunkSize = 5200;
    final pages = <String>[];
    var start = 0;
    while (start < text.length) {
      var end = (start + chunkSize).clamp(0, text.length);
      if (end < text.length) {
        final paragraphEnd = text.lastIndexOf('\n', end);
        if (paragraphEnd > start + (chunkSize ~/ 2)) end = paragraphEnd + 1;
      }
      pages.add(text.substring(start, end).trim());
      start = end;
    }
    return pages.isEmpty ? ['No readable text is available.'] : pages;
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: Text(
            widget.book.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          actions: [
            IconButton(
              tooltip: 'Add named bookmark',
              onPressed: () => createReadingBookmark(
                context,
                widget.book,
                format: 'text',
                page: _pageIndex + 1,
              ),
              icon: const Icon(Icons.bookmark_add_outlined),
            ),
            IconButton(
              tooltip: 'Decrease text size',
              onPressed: () => setState(
                () => _fontSize = (_fontSize - 1).clamp(14, 30),
              ),
              icon: const Icon(Icons.text_decrease_rounded),
            ),
            IconButton(
              tooltip: 'Increase text size',
              onPressed: () => setState(
                () => _fontSize = (_fontSize + 1).clamp(14, 30),
              ),
              icon: const Icon(Icons.text_increase_rounded),
            ),
          ],
        ),
        body: FutureBuilder<String>(
          future: _textFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Could not open this public-domain text:\n'
                        '${snapshot.error}',
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 12),
                      FilledButton(
                        onPressed: () => setState(
                          () => _textFuture =
                              context.read<AppProvider>().getPlainText(
                                    widget.book,
                                  ),
                        ),
                        child: const Text('Try again'),
                      ),
                    ],
                  ),
                ),
              );
            }

            final pages = _paginate(snapshot.data ?? '');
            final index = _pageIndex.clamp(0, pages.length - 1);
            return Column(
              children: [
                LinearProgressIndicator(value: (index + 1) / pages.length),
                Expanded(
                  child: SingleChildScrollView(
                    key: ValueKey(index),
                    padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
                    child: SelectableText(
                      pages[index],
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                            fontSize: _fontSize,
                            height: 1.75,
                          ),
                    ),
                  ),
                ),
                SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 8,
                    ),
                    child: Row(
                      children: [
                        IconButton(
                          tooltip: 'Previous page',
                          onPressed:
                              index == 0 ? null : () => _changePage(index - 1),
                          icon: const Icon(Icons.chevron_left_rounded),
                        ),
                        Expanded(
                          child: Text(
                            'Page ${index + 1} of ${pages.length}',
                            textAlign: TextAlign.center,
                          ),
                        ),
                        IconButton(
                          tooltip: 'Next page',
                          onPressed: index + 1 >= pages.length
                              ? null
                              : () => _changePage(index + 1),
                          icon: const Icon(Icons.chevron_right_rounded),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      );

  void _changePage(int index) {
    setState(() => _pageIndex = index);
    context
        .read<AppProvider>()
        .saveReadingProgress(widget.book, page: index + 1);
  }
}
