import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as c;
import 'package:cryptography/cryptography.dart';
import 'package:http/http.dart' as http;
import 'package:sqflite_common_ffi/sqflite_ffi.dart' show ConflictAlgorithm;
import 'package:uuid/uuid.dart';

import '../core/db.dart';
import '../core/paths.dart';
import '../core/state.dart';

const _uuid = Uuid();
const int kDiscoveryPort = 47822;

class SyncIdentity {
  SyncIdentity({required this.id, required this.name, required this.keyPair});
  final String id;
  String name;
  final SimpleKeyPair keyPair;

  static SyncIdentity? _current;

  static Future<SyncIdentity> load() async {
    if (_current != null) return _current!;
    final file = File('${AppPaths.i.dataDir}/identity.json');
    final algorithm = X25519();
    if (await file.exists()) {
      try {
        final obj = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
        final priv = base64Decode(obj['private'] as String);
        final pair = await algorithm.newKeyPairFromSeed(priv);
        _current = SyncIdentity(
          id: obj['id'] as String,
          name: obj['name'] as String? ?? 'This device',
          keyPair: pair,
        );
        return _current!;
      } catch (_) {}
    }
    final pair = await algorithm.newKeyPair();
    final seed = await pair.extractPrivateKeyBytes();
    final identity = SyncIdentity(id: _uuid.v4(), name: 'This device', keyPair: pair);
    await file.writeAsString(jsonEncode({
      'id': identity.id,
      'name': identity.name,
      'private': base64Encode(seed),
      'public': base64Encode((await pair.extractPublicKey()).bytes),
    }));
    _current = identity;
    return identity;
  }

  Future<List<int>> publicBytes() async => (await keyPair.extractPublicKey()).bytes;

  Future<List<int>> sessionKey(List<int> remotePublic, String salt) async {
    final algorithm = X25519();
    final shared = await algorithm.sharedSecretKey(
      keyPair: keyPair,
      remotePublicKey: SimplePublicKey(remotePublic, type: KeyPairType.x25519),
    );
    final hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);
    final key = await hkdf.deriveKey(
      secretKey: shared,
      nonce: utf8.encode(salt),
      info: utf8.encode('klaro-sync-v1'),
    );
    return key.extractBytes();
  }
}

class SyncSealed {
  const SyncSealed(this.nonce, this.cipher, this.mac);
  final List<int> nonce;
  final List<int> cipher;
  final List<int> mac;
  String encode() {
    final all = Uint8List.fromList([...nonce, ...mac, ...cipher]);
    return base64Encode(all);
  }

  static SyncSealed decode(String value) {
    final all = base64Decode(value);
    return SyncSealed(
      all.sublist(0, 12),
      all.sublist(28),
      all.sublist(12, 28),
    );
  }
}

Future<SyncSealed> sealJson(Map<String, Object?> payload, List<int> key) async {
  final aes = AesGcm.with256bits();
  final secretKey = SecretKey(key);
  final nonce = List<int>.generate(12, (_) => Random.secure().nextInt(256));
  final box = await aes.encrypt(utf8.encode(jsonEncode(payload)), secretKey: secretKey, nonce: nonce);
  return SyncSealed(nonce, box.cipherText, box.mac.bytes);
}

Future<Map<String, Object?>> openJson(SyncSealed sealed, List<int> key) async {
  final aes = AesGcm.with256bits();
  final box = SecretBox(sealed.cipher, nonce: sealed.nonce, mac: Mac(sealed.mac));
  final clear = await aes.decrypt(box, secretKey: SecretKey(key));
  return jsonDecode(utf8.decode(clear)) as Map<String, Object?>;
}

class SyncHost {
  SyncHost._(this.identity, this.server, this.udp, this.port, this.pairingCode);

  final SyncIdentity identity;
  final HttpServer server;
  final RawDatagramSocket? udp;
  final int port;
  String pairingCode;
  List<String> addresses = const [];

  static SyncHost? _running;
  static SyncHost? get running => _running;

  /// Starts the E2EE sync host and persists both the active state and the
  /// 6-digit pairing code so it stays active across restarts until manually stopped.
  static Future<SyncHost> start({int port = 47821, bool resetCode = false}) async {
    if (_running != null && !resetCode) return _running!;
    if (_running != null && resetCode) {
      await _running!.server.close(force: true);
      _running!.udp?.close();
      _running = null;
    }
    final identity = await SyncIdentity.load();
    var code = AppState.i.syncPairingCode;
    if (code.length != 6 || resetCode) {
      code = (Random.secure().nextInt(900000) + 100000).toString();
      await AppState.i.setString('sync_pairing_code', code);
    }
    await AppState.i.setBool('sync_active', true);

    final server = await HttpServer.bind(InternetAddress.anyIPv4, port, shared: true);
    RawDatagramSocket? udp;
    try {
      udp = await RawDatagramSocket.bind(InternetAddress.anyIPv4, kDiscoveryPort, reuseAddress: true);
      udp.broadcastEnabled = true;
    } catch (_) {}

    final host = SyncHost._(identity, server, udp, port, code);
    host.addresses = await _listAddresses();
    unawaited(host._serve());
    host._listenDiscovery();
    _running = host;
    return host;
  }

  /// Explicitly stops sharing and clears the persisted active flag + pairing code.
  static Future<void> stop({bool clearPersisted = true}) async {
    final h = _running;
    _running = null;
    h?.udp?.close();
    await h?.server.close(force: true);
    if (clearPersisted) {
      await AppState.i.setBool('sync_active', false);
      await AppState.i.setString('sync_pairing_code', '');
    }
  }

  void _listenDiscovery() {
    final socket = udp;
    if (socket == null) return;
    socket.listen((event) {
      if (event != RawSocketEvent.read) return;
      final dg = socket.receive();
      if (dg == null) return;
      try {
        final msg = jsonDecode(utf8.decode(dg.data)) as Map<String, dynamic>;
        if (msg['q'] == 'klaro_discover') {
          final wantHash = msg['code_hash'] as String?;
          final myHash = c.sha256.convert(utf8.encode(pairingCode)).toString();
          if (wantHash == null || wantHash == myHash) {
            final reply = utf8.encode(jsonEncode({
              'app': 'klaro',
              'id': identity.id,
              'name': identity.name,
              'port': port,
              'code_hash': myHash,
            }));
            socket.send(reply, dg.address, dg.port);
          }
        }
      } catch (_) {}
    });
  }

  Future<void> _serve() async {
    await for (final request in server) {
      unawaited(_handle(request));
    }
  }

  Future<void> _handle(HttpRequest request) async {
    final res = request.response;
    res.headers.contentType = ContentType.json;
    try {
      final path = request.uri.path;
      if (path == '/klaro/hello' && request.method == 'GET') {
        res.write(jsonEncode({
          'app': 'klaro',
          'version': 1,
          'id': identity.id,
          'name': identity.name,
          'public': base64Encode(await identity.publicBytes()),
          'code_hash': c.sha256.convert(utf8.encode(pairingCode)).toString(),
        }));
      } else if (path == '/klaro/pair' && request.method == 'POST') {
        final body = jsonDecode(await utf8.decoder.bind(request).join()) as Map<String, dynamic>;
        final codeHash = body['code'] as String? ?? '';
        final expected = c.sha256.convert(utf8.encode(pairingCode)).toString();
        if (codeHash != expected) {
          res.statusCode = 403;
          res.write(jsonEncode({'error': 'The pairing code does not match.'}));
        } else {
          final clientPub = base64Decode(body['public'] as String);
          final clientId = body['id'] as String;
          await Store.i.saveDevice(
            id: clientId,
            name: body['name'] as String? ?? 'Device',
            publicKey: base64Encode(clientPub),
          );
          res.write(jsonEncode({'ok': true, 'host_name': identity.name}));
        }
      } else if (path == '/klaro/manifest' && request.method == 'POST') {
        final deviceId = request.headers.value('x-klaro-device');
        final devices = await Store.i.devices();
        final device = devices.where((d) => d['id'] == deviceId && (d['revoked'] as int? ?? 0) == 0).firstOrNull;
        if (device == null) {
          res.statusCode = 403;
          res.write(jsonEncode({'error': 'Unknown device.'}));
        } else {
          final clientPub = base64Decode(device['public_key'] as String);
          final key = await identity.sessionKey(clientPub, '${identity.id}:$deviceId');
          final raw = await utf8.decoder.bind(request).join();
          final obj = jsonDecode(raw) as Map<String, dynamic>;
          final incoming = await openJson(SyncSealed.decode(obj['payload'] as String), key);
          await _apply(incoming);
          final manifest = await _buildManifest();
          final sealed = await sealJson(manifest, key);
          res.write(jsonEncode({'payload': sealed.encode()}));
        }
      } else {
        res.statusCode = 404;
        res.write(jsonEncode({'error': 'Not found'}));
      }
    } catch (e) {
      res.statusCode = 500;
      res.write(jsonEncode({'error': e.toString()}));
    } finally {
      await res.close();
    }
  }

  Future<Map<String, Object?>> _buildManifest() async {
    final notes = await Store.i.notes();
    final courses = await Store.i.courses(includeArchived: true);
    final providers = await Store.i.providers();
    final cards = await Store.i.db.query('cards');
    final progress = await Store.i.db.query('progress');
    return {
      'device': identity.id,
      'name': identity.name,
      'notes': notes.map((n) => n.toMap()).toList(),
      'courses': courses.map((c) => c.toMap()).toList(),
      'cards': cards,
      'progress': progress,
      'providers': providers.map((p) => {
        'id': p.id, 'name': p.name, 'kind': p.kind, 'base_url': p.baseUrl,
        'model': p.model, 'is_default': p.isDefault ? 1 : 0,
      }).toList(),
    };
  }

  Future<void> _apply(Map<String, Object?> manifest) async {
    for (final raw in (manifest['notes'] as List? ?? [])) {
      final map = (raw as Map).cast<String, Object?>();
      final local = await Store.i.db.query('notes', where: 'id = ?', whereArgs: [map['id']], limit: 1);
      if (local.isEmpty || (local.first['updated_at'] as int) < (map['updated_at'] as int)) {
        await Store.i.db.insert('notes', map, conflictAlgorithm: ConflictAlgorithm.replace);
      }
    }
    for (final raw in (manifest['courses'] as List? ?? [])) {
      final map = (raw as Map).cast<String, Object?>();
      final local = await Store.i.db.query('courses', where: 'id = ?', whereArgs: [map['id']], limit: 1);
      if (local.isEmpty || (local.first['updated_at'] as int) < (map['updated_at'] as int)) {
        await Store.i.db.insert('courses', map, conflictAlgorithm: ConflictAlgorithm.replace);
      }
    }
    for (final raw in (manifest['cards'] as List? ?? [])) {
      final map = (raw as Map).cast<String, Object?>();
      await Store.i.db.insert('cards', map, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    for (final raw in (manifest['progress'] as List? ?? [])) {
      final map = (raw as Map).cast<String, Object?>();
      final local = await Store.i.db.query('progress', where: 'lesson_id = ?', whereArgs: [map['lesson_id']], limit: 1);
      if (local.isEmpty || (local.first['updated_at'] as int) < (map['updated_at'] as int)) {
        await Store.i.db.insert('progress', map, conflictAlgorithm: ConflictAlgorithm.replace);
      }
    }
  }

  static Future<List<String>> _listAddresses() async {
    final out = <String>[];
    try {
      for (final iface in await NetworkInterface.list(type: InternetAddressType.IPv4)) {
        for (final addr in iface.addresses) {
          if (!addr.isLoopback) out.add(addr.address);
        }
      }
    } catch (_) {}
    return out;
  }
}

class SyncResult {
  const SyncResult({required this.notes, required this.courses, required this.cards});
  final int notes;
  final int courses;
  final int cards;
}

class SyncClient {
  /// Automatically discovers the peer on the local network using only the
  /// 6-digit pairing code or a scanned `klaro://pair?...` QR payload.
  static Future<String> pairByCodeOrToken({
    required String input,
    int defaultPort = 47821,
    required String myName,
  }) async {
    final trimmed = input.trim();
    String? host;
    var port = defaultPort;
    String code = trimmed;

    if (trimmed.startsWith('klaro://')) {
      final uri = Uri.tryParse(trimmed);
      if (uri != null) {
        host = uri.queryParameters['host'];
        port = int.tryParse(uri.queryParameters['port'] ?? '') ?? defaultPort;
        code = uri.queryParameters['code'] ?? '';
      }
    }

    if (code.isEmpty) {
      throw Exception('Enter the 6-digit pairing code or paste a QR link.');
    }

    if (host == null || host.isEmpty) {
      final discovered = await _discoverPeerByCode(code, defaultPort: port);
      if (discovered == null) {
        throw Exception(
          'No active Klaro device with code "$code" was found on your local network.',
        );
      }
      host = discovered.$1;
      port = discovered.$2;
    }

    await pair(address: host, port: port, code: code, myName: myName);
    await Store.i.metaSet('sync_host', host);
    return host;
  }

  static Future<(String, int)?> _discoverPeerByCode(String code, {required int defaultPort}) async {
    final codeHash = c.sha256.convert(utf8.encode(code)).toString();
    final completer = Completer<(String, int)?>();

    // 1. Fast UDP broadcast discovery on port 47822
    RawDatagramSocket? socket;
    try {
      socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      socket.broadcastEnabled = true;
      socket.listen((event) {
        if (event != RawSocketEvent.read) return;
        final dg = socket?.receive();
        if (dg == null) return;
        try {
          final obj = jsonDecode(utf8.decode(dg.data)) as Map<String, dynamic>;
          if (obj['app'] == 'klaro' && obj['code_hash'] == codeHash) {
            if (!completer.isCompleted) {
              completer.complete((dg.address.address, (obj['port'] as int?) ?? defaultPort));
            }
          }
        } catch (_) {}
      });
      final query = utf8.encode(jsonEncode({'q': 'klaro_discover', 'code_hash': codeHash}));
      socket.send(query, InternetAddress('255.255.255.255'), kDiscoveryPort);
      for (final addr in await SyncHost._listAddresses()) {
        final parts = addr.split('.');
        if (parts.length == 4) {
          final bcast = '${parts[0]}.${parts[1]}.${parts[2]}.255';
          socket.send(query, InternetAddress(bcast), kDiscoveryPort);
        }
      }
    } catch (_) {}

    final timer = Timer(const Duration(milliseconds: 900), () {
      if (!completer.isCompleted) completer.complete(null);
    });
    final udpHit = await completer.future;
    timer.cancel();
    socket?.close();
    if (udpHit != null) return udpHit;

    // 2. Fallback: quick check on localhost / saved host
    for (final candidate in ['127.0.0.1']) {
      try {
        final res = await http
            .get(Uri.parse('http://$candidate:$defaultPort/klaro/hello'))
            .timeout(const Duration(milliseconds: 450));
        if (res.statusCode == 200) {
          final obj = jsonDecode(res.body) as Map<String, dynamic>;
          if (obj['code_hash'] == codeHash) {
            return (candidate, defaultPort);
          }
        }
      } catch (_) {}
    }
    return null;
  }

  static Future<void> pair({
    required String address,
    int port = 47821,
    required String code,
    required String myName,
  }) async {
    final identity = await SyncIdentity.load();
    final base = 'http://$address:$port';
    final helloRes = await http.get(Uri.parse('$base/klaro/hello')).timeout(const Duration(seconds: 5));
    if (helloRes.statusCode != 200) throw Exception('No klaro. host answered.');
    final hello = jsonDecode(helloRes.body) as Map<String, dynamic>;
    if (hello['app'] != 'klaro') throw Exception('That service is not klaro.');
    final hostId = hello['id'] as String;
    final hostPub = base64Decode(hello['public'] as String);
    final myPub = await identity.publicBytes();
    final res = await http.post(
      Uri.parse('$base/klaro/pair'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'id': identity.id,
        'name': myName,
        'public': base64Encode(myPub),
        'code': c.sha256.convert(utf8.encode(code)).toString(),
      }),
    ).timeout(const Duration(seconds: 8));
    if (res.statusCode != 200) {
      final obj = jsonDecode(res.body) as Map<String, dynamic>;
      throw Exception(obj['error'] ?? 'Pairing refused.');
    }
    await Store.i.saveDevice(
      id: hostId,
      name: hello['name'] as String? ?? 'Paired device',
      publicKey: base64Encode(hostPub),
    );
  }

  static Future<SyncResult> pull({required String address, int port = 47821}) async {
    final identity = await SyncIdentity.load();
    final base = 'http://$address:$port';
    final hello = jsonDecode((await http.get(Uri.parse('$base/klaro/hello')).timeout(const Duration(seconds: 5))).body)
        as Map<String, dynamic>;
    final hostId = hello['id'] as String;
    final hostPub = base64Decode(hello['public'] as String);
    final key = await identity.sessionKey(hostPub, '$hostId:${identity.id}');
    final sealed = await sealJson({
      'device': identity.id,
      'name': identity.name,
      'notes': const [],
      'courses': const [],
      'cards': const [],
      'progress': const [],
    }, key);
    final res = await http.post(
      Uri.parse('$base/klaro/manifest'),
      headers: {
        'Content-Type': 'application/json',
        'x-klaro-device': identity.id,
      },
      body: jsonEncode({'payload': sealed.encode()}),
    ).timeout(const Duration(seconds: 20));
    if (res.statusCode != 200) {
      throw Exception('Sync refused: check that this device is still paired.');
    }
    final obj = jsonDecode(res.body) as Map<String, dynamic>;
    final incoming = await openJson(SyncSealed.decode(obj['payload'] as String), key);
    var notes = 0, courses = 0, cards = 0;
    for (final raw in (incoming['notes'] as List? ?? [])) {
      final map = (raw as Map).cast<String, Object?>();
      await Store.i.db.insert('notes', map, conflictAlgorithm: ConflictAlgorithm.replace);
      notes++;
    }
    for (final raw in (incoming['courses'] as List? ?? [])) {
      final map = (raw as Map).cast<String, Object?>();
      await Store.i.db.insert('courses', map, conflictAlgorithm: ConflictAlgorithm.replace);
      courses++;
    }
    for (final raw in (incoming['cards'] as List? ?? [])) {
      final map = (raw as Map).cast<String, Object?>();
      await Store.i.db.insert('cards', map, conflictAlgorithm: ConflictAlgorithm.replace);
      cards++;
    }
    await Store.i.logSync(hostId, 'pull', notes + courses + cards, 0, 'LAN E2EE');
    return SyncResult(notes: notes, courses: courses, cards: cards);
  }
}
