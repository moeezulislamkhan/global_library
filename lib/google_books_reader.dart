import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

class GoogleBooksReaderScreen extends StatefulWidget {
  const GoogleBooksReaderScreen({
    super.key,
    required this.title,
    required this.previewUrl,
  });

  final String title;
  final String previewUrl;

  @override
  State<GoogleBooksReaderScreen> createState() =>
      _GoogleBooksReaderScreenState();
}

class _GoogleBooksReaderScreenState extends State<GoogleBooksReaderScreen> {
  late final WebViewController _controller;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted);
    final uri = Uri.tryParse(widget.previewUrl);
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host != 'books.google.com') {
      _isLoading = false;
      _error = 'Google Books provided an invalid preview address.';
      return;
    }
    _controller
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) {
            if (mounted) {
              setState(() {
                _isLoading = true;
                _error = null;
              });
            }
          },
          onPageFinished: (_) {
            if (mounted) setState(() => _isLoading = false);
          },
          onWebResourceError: (error) {
            if (error.isForMainFrame == true && mounted) {
              setState(() {
                _isLoading = false;
                _error = 'Could not load this Google Books preview.';
              });
            }
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.previewUrl));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: Text(
            widget.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        body: Stack(
          children: [
            WebViewWidget(controller: _controller),
            if (_isLoading) const LinearProgressIndicator(),
            if (_error case final error?)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(error, textAlign: TextAlign.center),
                      const SizedBox(height: 12),
                      FilledButton(
                        onPressed: () => _controller.reload(),
                        child: const Text('Try again'),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      );
}
