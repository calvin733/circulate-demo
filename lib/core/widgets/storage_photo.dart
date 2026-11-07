import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/media_urls.dart';

class StoragePhoto extends ConsumerStatefulWidget {
  const StoragePhoto({
    super.key,
    required this.url,
    required this.height,
    this.path,
    this.bucket = 'item-photos',
  });
  final String url;
  final double height;
  final String? path;
  final String bucket;
  @override
  ConsumerState<StoragePhoto> createState() => _StoragePhotoState();
}

class _StoragePhotoState extends ConsumerState<StoragePhoto> {
  late String _url;
  Timer? _expiry;
  bool _refreshing = false;
  bool _automaticTried = false;
  int _generation = 0;
  @override
  void initState() {
    super.initState();
    _url = widget.url;
    _schedule();
  }

  @override
  void didUpdateWidget(covariant StoragePhoto oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url ||
        oldWidget.path != widget.path ||
        oldWidget.bucket != widget.bucket) {
      _url = widget.url;
      _generation++;
      _refreshing = false;
      _automaticTried = false;
      _schedule();
    }
  }

  void _schedule() {
    _expiry?.cancel();
    final at = signedUrlExpiry(_url);
    if (at == null || widget.path == null) return;
    final remaining =
        at.difference(DateTime.now()) - const Duration(seconds: 30);
    _expiry = Timer(remaining.isNegative ? Duration.zero : remaining, _refresh);
  }

  Future<void> _refresh() async {
    final path = widget.path;
    if (_refreshing || path == null || _url.startsWith('data:')) return;
    setState(() {
      _refreshing = true;
      _automaticTried = true;
    });
    final generation = _generation;
    try {
      final signed = await ref.read(mediaUrlSignerProvider)(
        widget.bucket,
        path,
      );
      if (!mounted || generation != _generation) return;
      setState(() => _url = signed);
      _schedule();
    } catch (_) {
      // The visible retry remains available; never spin on a permanently denied file.
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _refreshing = false);
      }
    }
  }

  Widget _failure(BuildContext context, Object error, StackTrace? stack) {
    final compact =
        widget.height < 160 || MediaQuery.textScalerOf(context).scale(14) > 20;
    if (!_automaticTried && widget.path != null && !_url.startsWith('data:')) {
      _automaticTried = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _refresh();
      });
    }
    if (widget.height < 72) {
      const broken = Icon(
        Icons.broken_image_outlined,
        semanticLabel: 'Foto belum dapat dimuat',
      );
      return SizedBox(
        height: widget.height,
        child: Center(
          child: _refreshing
              ? const SizedBox.square(
                  dimension: 24,
                  child: CircularProgressIndicator(
                    semanticsLabel: 'Memuat ulang foto',
                  ),
                )
              : widget.path == null
              ? broken
              : IconButton(
                  tooltip: 'Muat ulang foto',
                  onPressed: _refresh,
                  icon: broken,
                ),
        ),
      );
    }
    return SizedBox(
      height: widget.height,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (compact)
              const Icon(
                Icons.broken_image_outlined,
                semanticLabel: 'Foto belum dapat dimuat',
              )
            else
              const Text(
                'Foto belum dapat dimuat',
                textAlign: TextAlign.center,
                maxLines: 2,
              ),
            if (_refreshing)
              const CircularProgressIndicator(
                semanticsLabel: 'Memuat ulang foto',
              )
            else if (widget.path != null)
              IconButton(
                tooltip: 'Muat ulang foto',
                onPressed: _refresh,
                icon: const Icon(Icons.refresh),
              ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _expiry?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_url.isEmpty) return _failure(context, StateError('Missing URL'), null);
    if (_url.startsWith('data:image/jpeg;base64,')) {
      try {
        return Image.memory(
          base64Decode(_url.split(',').last),
          width: double.infinity,
          height: widget.height,
          fit: BoxFit.cover,
          errorBuilder: _failure,
        );
      } catch (error) {
        return _failure(context, error, null);
      }
    }
    return Image.network(
      _url,
      width: double.infinity,
      height: widget.height,
      fit: BoxFit.cover,
      errorBuilder: _failure,
      loadingBuilder: (_, child, progress) => progress == null
          ? child
          : SizedBox(
              height: widget.height,
              child: const Center(
                child: CircularProgressIndicator(semanticsLabel: 'Memuat foto'),
              ),
            ),
    );
  }
}
