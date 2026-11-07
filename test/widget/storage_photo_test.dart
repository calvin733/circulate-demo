import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;
import 'package:swapcycle/core/data/media_urls.dart';
import 'package:swapcycle/core/widgets/storage_photo.dart';
import 'package:swapcycle/features/items/domain/item.dart';
import 'package:swapcycle/features/items/presentation/item_widgets.dart';

Uint8List pixels(int color) {
  final photo = image.Image(width: 2, height: 2);
  image.fill(photo, color: image.ColorRgb8(color, 0, 0));
  return Uint8List.fromList(image.encodeJpg(photo));
}

String dataUrl(Uint8List bytes) =>
    'data:image/jpeg;base64,${base64Encode(bytes)}';

Widget preview(
  MediaUrlSigner signer, {
  required String path,
  String url = '',
}) => ProviderScope(
  overrides: [mediaUrlSignerProvider.overrideWithValue(signer)],
  child: MaterialApp(
    home: Scaffold(
      body: StoragePhoto(
        key: const ValueKey('same-photo'),
        url: url,
        height: 160,
        path: path,
      ),
    ),
  ),
);

void main() {
  testWidgets('A compact failed thumbnail fits at large text size', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          mediaUrlSignerProvider.overrideWithValue(
            (bucket, path) async => throw StateError('offline'),
          ),
        ],
        child: MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2)),
            child: const Scaffold(
              body: SizedBox(
                width: 120,
                child: StoragePhoto(
                  url: '',
                  path: 'owner/item/photo.jpg',
                  height: 110,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byTooltip('Muat ulang foto'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('A 48 dp editor thumbnail can retry a failed image', (
    tester,
  ) async {
    var signingAttempts = 0;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          mediaUrlSignerProvider.overrideWithValue((bucket, path) async {
            if (++signingAttempts == 1) throw StateError('offline');
            return dataUrl(pixels(100));
          }),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: SizedBox.square(
              dimension: 48,
              child: StoragePhoto(
                url: '',
                path: 'owner/item/photo.jpg',
                height: 48,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.byTooltip('Muat ulang foto'));
    await tester.pumpAndSettle();
    expect(find.byType(Image), findsOneWidget);
    expect(signingAttempts, 2);
  });

  testWidgets('Gallery buttons navigate photos with reduced motion', (
    tester,
  ) async {
    final item = Item(
      id: 'gallery-fixture',
      ownerId: 'owner',
      ownerName: 'Pemilik',
      title: 'Buku contoh',
      description: 'Dua gambar uji untuk galeri.',
      category: ItemCategory.books,
      condition: ItemCondition.good,
      city: '',
      preferences: '',
      imageUrls: [dataUrl(pixels(80)), dataUrl(pixels(180))],
    );
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: Scaffold(body: ItemGallery(item: item)),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Foto 1 dari 2'), findsOneWidget);
    await tester.tap(find.byTooltip('Foto berikutnya'));
    await tester.pumpAndSettle();
    expect(find.text('Foto 2 dari 2'), findsOneWidget);
    await tester.tap(find.byTooltip('Foto sebelumnya'));
    await tester.pumpAndSettle();
    expect(find.text('Foto 1 dari 2'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test(
    'URL expiry parsing handles token metadata and malformed URLs safely',
    () {
      final payload = base64Url
          .encode(utf8.encode(jsonEncode({'exp': 1800000000})))
          .replaceAll('=', '');
      expect(
        signedUrlExpiry(
          'https://fixture.invalid/photo?token=e30.$payload.fixture',
        ),
        DateTime.fromMillisecondsSinceEpoch(1800000000000, isUtc: true),
      );
      expect(signedUrlExpiry('https://fixture.invalid/photo'), isNull);
      expect(
        signedUrlExpiry('https://fixture.invalid/photo?token=broken'),
        isNull,
      );
    },
  );

  testWidgets(
    'One automatic photo refresh fails safely and manual retry can recover',
    (tester) async {
      var calls = 0;
      final bytes = pixels(80);
      Future<String> sign(String bucket, String path) async {
        calls++;
        if (calls == 1) throw StateError('simulated temporary signing failure');
        return dataUrl(bytes);
      }

      await tester.pumpWidget(preview(sign, path: 'owner/item/photo.jpg'));
      await tester.pumpAndSettle();
      expect(calls, 1);
      expect(find.text('Foto belum dapat dimuat'), findsOneWidget);
      await tester.tap(find.byTooltip('Muat ulang foto'));
      await tester.pumpAndSettle();
      expect(calls, 2);
      final rendered = tester.widget<Image>(find.byType(Image));
      expect((rendered.image as MemoryImage).bytes, orderedEquals(bytes));
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'A late signed URL for an old identity/path cannot replace the new photo',
    (tester) async {
      final pending = Completer<String>();
      Future<String> sign(String bucket, String path) => pending.future;
      final a = pixels(20);
      final b = pixels(180);
      await tester.pumpWidget(preview(sign, path: 'A/private.jpg'));
      await tester.pump();
      await tester.pumpWidget(
        preview(sign, path: 'B/own.jpg', url: dataUrl(b)),
      );
      pending.complete(dataUrl(a));
      await tester.pumpAndSettle();
      final rendered = tester.widget<Image>(find.byType(Image));
      expect((rendered.image as MemoryImage).bytes, orderedEquals(b));
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
