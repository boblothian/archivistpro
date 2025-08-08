import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

class TextViewerScreen extends StatefulWidget {
  final String url;
  final String title;

  const TextViewerScreen({super.key, required this.url, required this.title});

  @override
  State<TextViewerScreen> createState() => _TextViewerScreenState();
}

class _TextViewerScreenState extends State<TextViewerScreen> {
  String? _content;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadText();
  }

  Future<void> _loadText() async {
    try {
      final response = await http.get(Uri.parse(widget.url));
      if (response.statusCode == 200) {
        final decoded = utf8.decode(response.bodyBytes);
        setState(() {
          _content = decoded;
          _loading = false;
        });
      } else {
        throw Exception('Failed to load text');
      }
    } catch (e) {
      setState(() {
        _content = 'Error loading text.';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body:
          _loading
              ? const Center(child: CircularProgressIndicator())
              : SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Text(
                  _content ?? '',
                  style: const TextStyle(fontSize: 16, fontFamily: 'monospace'),
                ),
              ),
    );
  }
}
