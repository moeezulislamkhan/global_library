import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_epub_viewer/flutter_epub_viewer.dart';
import 'package:pdfx/pdfx.dart';
import 'package:provider/provider.dart';

import 'app_provider.dart';
import 'book.dart';
import 'reading_models.dart';

class EpubBookReader extends StatefulWidget {
  const EpubBookReader({super.key, required this.book, this.bookmark});

  final Book book;
  final ReadingBookmark? bookmark;

  @override
  State<EpubBookReader> createState() => _EpubBookReaderState();
}

class _EpubBookReaderState extends State<EpubBookReader> {
  late final EpubController _controller;
  late final Future<Uint8List> _bytes;
  late String? _lastCfi;
  late bool _readerDark;
  double _fontSize = 18;
  List<EpubChapter> _chapters = [];
  bool _isReady = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller = EpubController();
    _readerDark = context.read<AppProvider>().isDark;
    _lastCfi = widget.bookmark?.location ??
        context.read<AppProvider>().epubLocationFor(widget.book);
    _bytes = context.read<AppProvider>().getEbookBytes(
          widget.book,
          epub: true,
        );
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
            PopupMenuButton<String>(
              enabled: _isReady,
              tooltip: 'Reader settings',
              onSelected: (value) {
                switch (value) {
                  case 'smaller':
                    _changeFontSize(-1);
                  case 'larger':
                    _changeFontSize(1);
                  case 'theme':
                    _toggleReaderTheme();
                  case 'chapters':
                    _showChapters();
                }
              },
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: 'smaller',
                  child: Text('Decrease font size'),
                ),
                const PopupMenuItem(
                  value: 'larger',
                  child: Text('Increase font size'),
                ),
                PopupMenuItem(
                  value: 'theme',
                  child: Text(
                    _readerDark ? 'Use light theme' : 'Use dark theme',
                  ),
                ),
                if (_chapters.isNotEmpty)
                  const PopupMenuItem(
                    value: 'chapters',
                    child: Text('Table of contents'),
                  ),
              ],
            ),
            IconButton(
              tooltip: 'Add named bookmark',
              onPressed: !_isReady || _lastCfi == null
                  ? null
                  : () => createReadingBookmark(
                        context,
                        widget.book,
                        format: 'epub',
                        location: _lastCfi,
                      ),
              icon: const Icon(Icons.bookmark_add_outlined),
            ),
          ],
        ),
        body: FutureBuilder<Uint8List>(
          future: _bytes,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError || _error != null) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    'Could not open this EPUB:\n'
                    '${_error ?? snapshot.error}',
                    textAlign: TextAlign.center,
                  ),
                ),
              );
            }
            return EpubViewer(
              epubController: _controller,
              epubSource: EpubSource.fromData(snapshot.data!),
              initialCfi: _lastCfi,
              displaySettings: EpubDisplaySettings(
                fontSize: _fontSize.round(),
                theme: _readerDark ? EpubTheme.dark() : EpubTheme.light(),
              ),
              onEpubLoaded: () {
                if (mounted) setState(() => _isReady = true);
              },
              onChaptersLoaded: (chapters) {
                if (mounted) setState(() => _chapters = chapters);
              },
              onRelocated: (location) {
                _lastCfi = location.startCfi;
                context.read<AppProvider>().saveEpubLocation(
                      widget.book,
                      location.startCfi,
                      completion: location.progress,
                    );
              },
              onLoadError: (error) {
                if (mounted) setState(() => _error = error.message);
              },
            );
          },
        ),
      );

  Future<void> _changeFontSize(double amount) async {
    setState(() => _fontSize = (_fontSize + amount).clamp(12, 32));
    try {
      await _controller.setFontSize(fontSize: _fontSize);
    } on Exception catch (error) {
      _showReaderActionError(error);
    }
  }

  Future<void> _toggleReaderTheme() async {
    setState(() => _readerDark = !_readerDark);
    try {
      await _controller.updateTheme(
        theme: _readerDark ? EpubTheme.dark() : EpubTheme.light(),
      );
    } on Exception catch (error) {
      _showReaderActionError(error);
    }
  }

  void _showReaderActionError(Object error) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Could not update reader settings: $error')),
    );
  }

  Future<void> _showChapters() async {
    final chapters = _flattenChapters(_chapters);
    final selected = await showModalBottomSheet<EpubChapter>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          children: [
            for (final chapter in chapters)
              ListTile(
                title: Text(chapter.title),
                onTap: () => Navigator.of(context).pop(chapter),
              ),
          ],
        ),
      ),
    );
    if (selected != null && mounted) _controller.display(cfi: selected.href);
  }

  List<EpubChapter> _flattenChapters(List<EpubChapter> chapters) => [
        for (final chapter in chapters) ...[
          chapter,
          ..._flattenChapters(chapter.subitems),
        ],
      ];
}

class PdfBookReader extends StatefulWidget {
  const PdfBookReader({super.key, required this.book, this.bookmark});

  final Book book;
  final ReadingBookmark? bookmark;

  @override
  State<PdfBookReader> createState() => _PdfBookReaderState();
}

class _PdfBookReaderState extends State<PdfBookReader> {
  late final Future<Uint8List> _bytes;
  PdfControllerPinch? _controller;
  int? _pageCount;
  String? _error;

  @override
  void initState() {
    super.initState();
    _bytes = context.read<AppProvider>().getEbookBytes(
          widget.book,
          epub: false,
        );
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
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
            if (_controller != null)
              Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Text('${_controller!.page}/${_pageCount ?? '…'}'),
                ),
              ),
            IconButton(
              tooltip: 'Add named bookmark',
              onPressed: _controller == null
                  ? null
                  : () => createReadingBookmark(
                        context,
                        widget.book,
                        format: 'pdf',
                        page: _controller!.page,
                      ),
              icon: const Icon(Icons.bookmark_add_outlined),
            ),
          ],
        ),
        body: FutureBuilder<Uint8List>(
          future: _bytes,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError || _error != null) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    'Could not open this PDF:\n'
                    '${_error ?? snapshot.error}',
                    textAlign: TextAlign.center,
                  ),
                ),
              );
            }
            final app = context.read<AppProvider>();
            _controller ??= PdfControllerPinch(
              document: PdfDocument.openData(snapshot.data!),
              initialPage:
                  widget.bookmark?.page ?? app.bookmarkFor(widget.book) ?? 1,
            );
            return PdfViewPinch(
              controller: _controller!,
              onDocumentLoaded: (document) {
                if (mounted) setState(() => _pageCount = document.pagesCount);
              },
              onPageChanged: (page) {
                app.saveReadingProgress(
                  widget.book,
                  page: page,
                  totalPages: _pageCount,
                );
                if (mounted) setState(() {});
              },
              onDocumentError: (error) {
                if (mounted) setState(() => _error = error.toString());
              },
            );
          },
        ),
      );
}

Future<void> createReadingBookmark(
  BuildContext context,
  Book book, {
  required String format,
  int? page,
  String? location,
}) async {
  final controller = TextEditingController();
  final name = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Name this bookmark'),
      content: TextField(
        controller: controller,
        autofocus: true,
        textCapitalization: TextCapitalization.sentences,
        decoration: const InputDecoration(hintText: 'For example, Chapter 3'),
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
  if (name == null || name.trim().isEmpty || !context.mounted) return;
  try {
    await context.read<AppProvider>().createBookmark(
          book,
          name: name,
          page: page,
          location: location,
          format: format,
        );
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bookmark saved.')),
      );
    }
  } on Exception catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save bookmark: $error')),
      );
    }
  }
}
