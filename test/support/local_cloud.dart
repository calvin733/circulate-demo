// Loopback-only HTTP fixture for repository recovery. No Supabase account or credential is created.
import 'dart:convert';
import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';

class LocalCloudFixture {
  static const actor = '13000000-0000-4000-8000-000000000001';
  static const itemId = '23000000-0000-4000-8000-000000000001';
  late HttpServer server;
  late SupabaseClient client;
  Map<String, dynamic>? row;
  bool loseSave = false;
  bool loseUpload = false;
  bool loseAttach = false;
  bool losePublish = false;
  bool rejectSave = false;
  bool rejectPublish = false;
  final Set<String> objects = {};
  final Set<String> uploadedPaths = {};
  int attaches = 0;

  Future<void> start() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen(_handle);
    client = SupabaseClient(
      'http://127.0.0.1:${server.port}',
      'sb_publishable_local_fixture',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      storageOptions: const StorageClientOptions(retryAttempts: 0),
    );
    final payload = base64Url
        .encode(
          utf8.encode(
            jsonEncode({
              'sub': actor,
              'role': 'authenticated',
              'exp':
                  DateTime.now()
                      .add(const Duration(hours: 1))
                      .millisecondsSinceEpoch ~/
                  1000,
            }),
          ),
        )
        .replaceAll('=', '');
    // Synthetic local session only; the fixture server is the sole endpoint.
    await client.auth.setInitialSession(
      jsonEncode({
        'access_token': 'e30.$payload.fixture',
        'refresh_token': 'local-fixture',
        'token_type': 'bearer',
        'expires_in': 3600,
        'user': {
          'id': actor,
          'aud': 'authenticated',
          'role': 'authenticated',
          'email': 'fixture@example.test',
          'app_metadata': <String, dynamic>{},
          'user_metadata': <String, dynamic>{},
          'created_at': '2026-11-03T00:00:00Z',
        },
      }),
    );
  }

  Map<String, dynamic> makeRow({String status = 'draft'}) => {
    'id': itemId,
    'owner_id': actor,
    'title': 'Buku belajar Flutter',
    'description': 'Buku lengkap yang masih bersih untuk belajar Flutter.',
    'category_slug': 'books',
    'condition': 'good',
    'city': 'Tangerang',
    'preferences': '',
    'status': status,
    'visibility': 'visible',
    'revision': 1,
    'profiles': {'display_name': 'Fixture owner'},
    'item_photos': <Map<String, dynamic>>[],
  };

  Future<void> _reply(
    HttpRequest request,
    Object? value, {
    int status = 200,
  }) async {
    request.response.statusCode = status;
    request.response.headers.contentType = ContentType.json;
    if (request.method != 'HEAD') request.response.write(jsonEncode(value));
    await request.response.close();
  }

  Future<void> _unavailable(HttpRequest request) => _reply(request, {
    'message': 'Simulated lost response',
    'code': 'FIXTURE_LOST_RESPONSE',
    'error': 'Unavailable',
    'statusCode': '503',
    'details': null,
    'hint': null,
  }, status: 503);

  Future<void> _handle(HttpRequest request) async {
    try {
      final path = request.uri.path;
      if (path == '/rest/v1/items') {
        await _reply(
          request,
          row == null
              ? []
              : request.uri.queryParameters.containsKey('id')
              ? row
              : [row],
        );
        return;
      }
      if (path == '/rest/v1/rpc/save_item') {
        final data = jsonDecode(
          await utf8.decoder.bind(request).join(),
        ) as Map<String, dynamic>;
        if (rejectSave) {
          await _unavailable(request);
          return;
        }
        row ??= makeRow();
        row!.addAll({
          'title': data['p_title'],
          'description': data['p_description'],
          'category_slug': data['p_category_slug'],
          'condition': data['p_condition'],
          'city': data['p_city'],
          'preferences': data['p_preferences'],
        });
        if (loseSave) {
          loseSave = false;
          await _unavailable(request);
        } else {
          await _reply(request, itemId);
        }
        return;
      }
      if (path == '/rest/v1/rpc/attach_item_photo') {
        final data = jsonDecode(
          await utf8.decoder.bind(request).join(),
        ) as Map<String, dynamic>;
        final photos = row!['item_photos'] as List<Map<String, dynamic>>;
        if (!photos.any((p) => p['storage_path'] == data['p_path'])) {
          attaches++;
          photos.add({
            'id': 'photo-id',
            'storage_path': data['p_path'],
            'position': data['p_position'],
          });
          row!['revision'] = (row!['revision'] as int) + 1;
        }
        if (loseAttach) {
          loseAttach = false;
          await _unavailable(request);
        } else {
          await _reply(request, 'photo-id');
        }
        return;
      }
      if (path == '/rest/v1/rpc/set_listing_state') {
        final data = jsonDecode(
          await utf8.decoder.bind(request).join(),
        ) as Map<String, dynamic>;
        if (rejectPublish) {
          await _unavailable(request);
          return;
        }
        row!['status'] = data['p_action'] == 'publish'
            ? 'available'
            : 'archived';
        if (losePublish) {
          losePublish = false;
          await _unavailable(request);
        } else {
          await _reply(request, itemId);
        }
        return;
      }
      if (path.startsWith('/storage/v1/object/sign/')) {
        await request.drain<void>();
        await _unavailable(request);
        return;
      }
      if (path.startsWith('/storage/v1/object/item-photos/')) {
        final object = path.substring('/storage/v1/object/item-photos/'.length);
        if (request.method == 'HEAD') {
          await _reply(
            request,
            null,
            status: objects.contains(object) ? 200 : 404,
          );
          return;
        }
        if (request.method == 'POST') {
          await request.drain<void>();
          if (objects.contains(object)) {
            await _reply(request, {
              'message': 'Duplicate',
              'error': 'Duplicate',
              'statusCode': '409',
            }, status: 409);
            return;
          }
          objects.add(object);
          uploadedPaths.add(object);
          if (loseUpload) {
            loseUpload = false;
            await _unavailable(request);
          } else {
            await _reply(request, {
              'Key': 'item-photos/$object',
              'Id': 'object-id',
            });
          }
          return;
        }
      }
      await request.drain<void>();
      await _reply(request, {
        'message': 'Unknown fixture path: $path',
      }, status: 404);
    } catch (error) {
      try {
        await _reply(request, {'message': error.toString()}, status: 500);
      } catch (_) {
        /* test teardown can close a pending fixture request */
      }
    }
  }

  Future<void> close() async {
    await client.dispose();
    await server.close(force: true);
  }
}
