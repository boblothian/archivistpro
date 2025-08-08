import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_pdfview/flutter_pdfview.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PdfViewerScreen extends StatefulWidget {
  final File file;

  const PdfViewerScreen({super.key, required this.file});

  @override
  State<PdfViewerScreen> createState() => _PdfViewerScreenState();
}

class _PdfViewerScreenState extends State<PdfViewerScreen> {
  PDFViewController? _pdfViewController;
  int _totalPages = 0;
  int _currentPage = 0;
  int? _initialPage;
  late String _prefsKey;
  bool _resumeConfirmed = false;
  bool _isPageVisible = false;

  bool _readyToLoad = false; // 👈 Add this line at top of _PdfViewerScreenState

  @override
  void initState() {
    super.initState();
    _prefsKey = 'last_page_${widget.file.path.hashCode}';
    _initResumeAndUI();
  }

  Future<void> _initResumeAndUI() async {
    await _checkAndPromptResume();
    // Hide status & nav bars after prompt
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    setState(() => _readyToLoad = true); // 👈 Only now trigger loading PDF
  }

  @override
  void dispose() {
    // Restore system UI
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  Future<void> _checkAndPromptResume() async {
    final prefs = await SharedPreferences.getInstance();
    final lastPage = prefs.getInt(_prefsKey) ?? 0;
    if (lastPage > 0) {
      final shouldResume = await showDialog<bool>(
        context: context,
        builder:
            (context) => AlertDialog(
              title: const Text('Resume Reading'),
              content: Text('Resume from page ${lastPage + 1}?'),
              actions: [
                TextButton(
                  child: const Text('No'),
                  onPressed: () => Navigator.pop(context, false),
                ),
                TextButton(
                  child: const Text('Yes'),
                  onPressed: () => Navigator.pop(context, true),
                ),
              ],
            ),
      );
      if (shouldResume == true) {
        _initialPage = lastPage;
        _resumeConfirmed = true;
      }
    }
  }

  Future<void> _saveLastPage(int page) async {
    final prefs = await SharedPreferences.getInstance();
    prefs.setInt(_prefsKey, page);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          if (_readyToLoad)
            AnimatedOpacity(
              opacity: _isPageVisible ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 300),
              child: PDFView(
                filePath: widget.file.path,
                swipeHorizontal: true,
                autoSpacing: false,
                pageFling: true,
                fitEachPage: true,
                fitPolicy: FitPolicy.BOTH,
                defaultPage: _initialPage ?? 0,
                onRender: (_pages) async {
                  setState(() {
                    _totalPages = _pages ?? 0;
                    _isPageVisible = true;
                  });
                  if (_resumeConfirmed &&
                      _initialPage != null &&
                      _pdfViewController != null) {
                    await _pdfViewController!.setPage(_initialPage!);
                  }
                },
                onViewCreated: (controller) async {
                  _pdfViewController = controller;
                  final page = await controller.getCurrentPage();
                  setState(() => _currentPage = page ?? 0);
                },
                onPageChanged: (page, total) {
                  setState(() {
                    _currentPage = page ?? 0;
                    _totalPages = total ?? 0;
                  });
                  _saveLastPage(_currentPage);
                },
              ),
            ),
          Positioned(
            top: 32,
            left: 8,
            child: SafeArea(
              child: IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.black),
                onPressed: () => Navigator.pop(context),
              ),
            ),
          ),
          if (_readyToLoad)
            Positioned(
              bottom: 16,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    'Page ${_currentPage + 1} / $_totalPages',
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
