import 'package:flutter/material.dart';
import '../../core/supabase_config.dart';

class _CachedUrl {
  final String url;
  final DateTime expires;
  const _CachedUrl(this.url, this.expires);
}

class PostImage extends StatefulWidget {
  final String path;
  final double height;
  const PostImage({super.key, required this.path, this.height = 220});

  @override
  State<PostImage> createState() => _PostImageState();
}

class _PostImageState extends State<PostImage> {
  static final Map<String, _CachedUrl> _cache = {};
  late final Future<String> _url = _signedUrl(widget.path);

  static Future<String> _signedUrl(String path) async {
    final cached = _cache[path];
    if (cached != null && cached.expires.isAfter(DateTime.now())) {
      return cached.url;
    }
    // Bucket privado: la URL firmada caduca en 1 hora
    final url =
        await supabase.storage.from('post-images').createSignedUrl(path, 3600);
    _cache[path] =
        _CachedUrl(url, DateTime.now().add(const Duration(minutes: 50)));
    return url;
  }

  void _openFull(String url) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.black,
            foregroundColor: Colors.white,
          ),
          body: Center(child: InteractiveViewer(child: Image.network(url))),
        ),
      ),
    );
  }

  Widget _box(Widget child) =>
      SizedBox(height: widget.height, child: Center(child: child));

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String>(
      future: _url,
      builder: (context, snap) {
        if (snap.hasError) {
          return _box(const Text('No se pudo cargar la imagen'));
        }
        if (!snap.hasData) return _box(const CircularProgressIndicator());
        final url = snap.data!;
        return GestureDetector(
          onTap: () => _openFull(url),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.network(
              url,
              height: widget.height,
              width: double.infinity,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) =>
                  _box(const Text('No se pudo cargar la imagen')),
            ),
          ),
        );
      },
    );
  }
}