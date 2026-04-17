import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

class InAppWebViewScreen extends StatefulWidget {
  const InAppWebViewScreen({super.key, required this.url, required this.title});

  final String url;
  final String title;

  @override
  State<InAppWebViewScreen> createState() => _InAppWebViewScreenState();
}

class _InAppWebViewScreenState extends State<InAppWebViewScreen> {
  late final WebViewController _controller;
  int _loadingProgress = 0;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (progress) {
            if (!mounted) return;
            setState(() => _loadingProgress = progress);
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.url));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: Stack(
        children: [
          WebViewWidget(controller: _controller),
          if (_loadingProgress < 100)
            LinearProgressIndicator(value: _loadingProgress / 100),
        ],
      ),
    );
  }
}
