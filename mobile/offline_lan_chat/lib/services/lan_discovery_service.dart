import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../models/nearby_peer.dart';
import 'identity_store.dart';
import 'message_crypto.dart';
import 'package:path_provider/path_provider.dart';

class IncomingText {
  const IncomingText({
    required this.id,
    required this.peerId,
    required this.peerName,
    required this.body,
    required this.createdAt,
  });

  final String id;
  final String peerId;
  final String peerName;
  final String body;
  final DateTime createdAt;
}

class LanDiscoveryService {
  static const _discoveryPort = 45454;
  static const _maxAvatarCharacters = 12 * 1024;
  static const _maxFileBytes = 10 * 1024 * 1024;
  static const _fileChunkBytes = 4096;
  static const _announceInterval = Duration(seconds: 3);
  static const _peerExpiry = Duration(seconds: 12);

  final Map<String, NearbyPeer> _peers = {};
  final Map<String, _IncomingFileBuffer> _incomingFiles = {};
  final StreamController<List<NearbyPeer>> _peersController =
      StreamController<List<NearbyPeer>>.broadcast();
  DeviceIdentity? _identity;
  Future<void> Function(IncomingText message)? _onIncomingText;
  final IdentityStore _identityStore = IdentityStore();
  final MessageCrypto _crypto = MessageCrypto();
  ServerSocket? _server;
  RawDatagramSocket? _discoverySocket;
  Timer? _announceTimer;
  Timer? _pruneTimer;

  Stream<List<NearbyPeer>> get peers => _peersController.stream;

  Future<void> refreshDiscovery() => _announce();

  Future<void> start(
    DeviceIdentity identity, {
    required Future<void> Function(IncomingText message) onIncomingText,
  }) async {
    _identity = identity;
    _onIncomingText = onIncomingText;
    try {
      _server = await ServerSocket.bind(InternetAddress.anyIPv4, 0);
      _server!.listen(_handleConnection, onError: (_) {}, onDone: () {});

      _discoverySocket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        _discoveryPort,
        reuseAddress: true,
        reusePort: true,
      );
      _discoverySocket!.broadcastEnabled = true;
      _discoverySocket!.listen(_handleDatagram, onError: (_) {}, onDone: () {});

      await _announce();
      _announceTimer = Timer.periodic(_announceInterval, (_) {
        unawaited(_announce());
      });
      _pruneTimer = Timer.periodic(_announceInterval, (_) => _prunePeers());
    } catch (_) {
      await stop();
      rethrow;
    }
  }

  Future<void> updateIdentity(DeviceIdentity identity) async {
    _identity = identity;
    await _announce();
  }

  Future<void> sendText({
    required NearbyPeer peer,
    required String messageId,
    required String body,
    required DateTime createdAt,
    required String recipientPublicKey,
  }) async {
    final identity = _identity;
    if (identity == null) throw StateError('Discovery is not running.');

    final trusted = await _identityStore.trustedPeer(peer.id);
    if (trusted == null || trusted.publicKey != recipientPublicKey) {
      throw StateError('Pair with this device by scanning its QR code first.');
    }
    final encrypted = await _crypto.encrypt(
      local: identity,
      recipientPublicKey: trusted.publicKey,
      messageId: messageId,
      plaintext: body,
      createdAt: createdAt.microsecondsSinceEpoch,
      identityStore: _identityStore,
    );

    final socket = await Socket.connect(
      InternetAddress(peer.address),
      peer.port,
      timeout: const Duration(seconds: 5),
    );
    socket.setOption(SocketOption.tcpNoDelay, true);

    final acknowledgement = Completer<void>();
    final subscription = socket
        .cast<List<int>>()
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(
          (line) {
            try {
              final packet = jsonDecode(line) as Map<String, dynamic>;
              if (packet['kind'] == 'ack' && packet['id'] == messageId) {
                if (!acknowledgement.isCompleted) acknowledgement.complete();
              }
            } catch (_) {
              // Ignore malformed acknowledgements.
            }
          },
          onError: (Object error) {
            if (!acknowledgement.isCompleted) {
              acknowledgement.completeError(error);
            }
          },
          onDone: () {
            if (!acknowledgement.isCompleted) {
              acknowledgement.completeError(
                const SocketException('The peer closed before acknowledging.'),
              );
            }
          },
        );

    try {
      socket.write(
        '${jsonEncode({'kind': 'text', 'id': messageId, 'from_id': identity.id, 'from_name': identity.name, 'to_id': peer.id, 'sender_public_key': identity.publicKey, 'nonce': encrypted['nonce'], 'ciphertext': encrypted['ciphertext'], 'mac': encrypted['mac'], 'created_at': createdAt.microsecondsSinceEpoch})}\n',
      );
      await socket.flush();
      await acknowledgement.future.timeout(const Duration(seconds: 8));
    } finally {
      await subscription.cancel();
      socket.destroy();
    }
  }


  Future<void> sendFile({
    required NearbyPeer peer,
    required String transferId,
    required String fileName,
    required Uint8List bytes,
    required DateTime createdAt,
    required String recipientPublicKey,
    void Function(double progress)? onProgress,
  }) async {
    final identity = _identity;
    if (identity == null) throw StateError('Discovery is not running.');
    if (bytes.isEmpty || bytes.length > _maxFileBytes) {
      throw ArgumentError('Files must be between 1 byte and 10 MB.');
    }
    final trusted = await _identityStore.trustedPeer(peer.id);
    if (trusted == null || trusted.publicKey != recipientPublicKey) {
      throw StateError('Pair with this device by scanning its QR code first.');
    }
    final socket = await Socket.connect(
      InternetAddress(peer.address), peer.port,
      timeout: const Duration(seconds: 5),
    );
    socket.setOption(SocketOption.tcpNoDelay, true);
    final acknowledgement = Completer<void>();
    final subscription = socket
        .cast<List<int>>()
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
      try {
        final packet = jsonDecode(line) as Map<String, dynamic>;
        if (packet['kind'] == 'file_ack' && packet['transfer_id'] == transferId &&
            !acknowledgement.isCompleted) {
          acknowledgement.complete();
        }
      } on Object {
        // Ignore unrelated or malformed acknowledgements.
      }
    }, onError: (Object error) {
      if (!acknowledgement.isCompleted) acknowledgement.completeError(error);
    }, onDone: () {
      if (!acknowledgement.isCompleted) {
        acknowledgement.completeError(const SocketException('Peer closed before file acknowledgement.'));
      }
    });

    try {
      final total = (bytes.length / _fileChunkBytes).ceil();
      final timestamp = createdAt.microsecondsSinceEpoch;
      for (var index = 0; index < total; index++) {
        final start = index * _fileChunkBytes;
        final end = (start + _fileChunkBytes < bytes.length)
            ? start + _fileChunkBytes
            : bytes.length;
        final payload = jsonEncode({
          'name': fileName,
          'size': bytes.length,
          'total': total,
          'index': index,
          'data': base64Encode(bytes.sublist(start, end)),
        });
        final encrypted = await _crypto.encrypt(
          local: identity,
          recipientPublicKey: trusted.publicKey,
          messageId: '$transferId:$index',
          plaintext: payload,
          createdAt: timestamp,
          identityStore: _identityStore,
        );
        socket.write('${jsonEncode({
          'kind': 'file_chunk',
          'transfer_id': transferId,
          'index': index,
          'from_id': identity.id,
          'to_id': peer.id,
          'sender_public_key': identity.publicKey,
          'nonce': encrypted['nonce'],
          'ciphertext': encrypted['ciphertext'],
          'mac': encrypted['mac'],
          'created_at': timestamp,
        })}\n');
        await socket.flush();
        onProgress?.call((index + 1) / total);
      }
      socket.write('${jsonEncode({
        'kind': 'file_done',
        'transfer_id': transferId,
        'from_id': identity.id,
        'to_id': peer.id,
        'sender_public_key': identity.publicKey,
      })}\n');
      await socket.flush();
      await acknowledgement.future.timeout(const Duration(minutes: 2));
    } finally {
      await subscription.cancel();
      socket.destroy();
    }
  }

  void _handleDatagram(RawSocketEvent event) {
    if (event != RawSocketEvent.read) return;
    final socket = _discoverySocket;
    if (socket == null) return;

    Datagram? datagram;
    while ((datagram = socket.receive()) != null) {
      try {
        final packet =
            jsonDecode(utf8.decode(datagram!.data)) as Map<String, dynamic>;
        final id = packet['id'];
        final name = packet['name'];
        final port = packet['tcp_port'];
        final publicKey = packet['public_key'];
        final avatar = packet['avatar'];
        if (packet['kind'] != 'announce' ||
            id is! String ||
            name is! String ||
            port is! int ||
            publicKey is! String ||
            publicKey.isEmpty ||
            (avatar != null &&
                (avatar is! String || avatar.length > _maxAvatarCharacters)) ||
            id == _identity?.id) {
          continue;
        }
        if (avatar is String) base64Decode(avatar);

        _peers[id] = NearbyPeer(
          id: id,
          name: name,
          address: datagram.address.address,
          port: port,
          lastSeen: DateTime.now(),
          publicKey: publicKey,
          avatarBase64: avatar as String?,
        );
        _emitPeers();
      } catch (_) {
        // A malformed local-network packet is ignored.
      }
    }
  }

  void _handleConnection(Socket socket) {
    socket.setOption(SocketOption.tcpNoDelay, true);
    var pending = Future<void>.value();
    socket
        .cast<List<int>>()
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(
          (line) {
            pending = pending.then((_) => _handleMessageLine(socket, line));
          },
          onError: (_) => socket.destroy(),
          onDone: socket.destroy,
          cancelOnError: true,
        );
  }

  Future<void> _handleMessageLine(Socket socket, String line) async {
    try {
      if (line.length > 16 * 1024) return;
      final packet = jsonDecode(line) as Map<String, dynamic>;
      if (packet['kind'] == 'file_chunk' || packet['kind'] == 'file_done') {
        await _handleFilePacket(socket, packet);
        return;
      }
      final identity = _identity;
      if (identity == null ||
          packet['kind'] != 'text' ||
          packet['to_id'] != identity.id ||
          packet['id'] is! String ||
          packet['from_id'] is! String ||
          packet['from_name'] is! String ||
          packet['sender_public_key'] is! String ||
          packet['nonce'] is! String ||
          packet['ciphertext'] is! String ||
          packet['mac'] is! String ||
          packet['created_at'] is! int) {
        return;
      }

      final senderId = packet['from_id'] as String;
      final trusted = await _identityStore.trustedPeer(senderId);
      final senderPublicKey = packet['sender_public_key'] as String;
      if (trusted == null || trusted.publicKey != senderPublicKey) return;
      final messageId = packet['id'] as String;
      final createdAt = packet['created_at'] as int;
      final body = await _crypto.decrypt(
        local: identity,
        senderPublicKey: senderPublicKey,
        senderId: senderId,
        messageId: messageId,
        nonce: packet['nonce'] as String,
        ciphertext: packet['ciphertext'] as String,
        mac: packet['mac'] as String,
        createdAt: createdAt,
        identityStore: _identityStore,
      );
      if (body.length > 4000) return;
      final incoming = IncomingText(
        id: messageId,
        peerId: senderId,
        peerName: trusted.name,
        body: body,
        createdAt: DateTime.fromMicrosecondsSinceEpoch(createdAt),
      );
      await _onIncomingText?.call(incoming);
      socket.write('${jsonEncode({'kind': 'ack', 'id': incoming.id})}\n');
      await socket.flush();
    } catch (_) {
      // Ignore invalid packets without closing the discovery service.
    }
  }

  Future<void> _announce() async {
    final identity = _identity;
    final socket = _discoverySocket;
    final server = _server;
    if (identity == null || socket == null || server == null) return;

    final avatar = identity.avatarBase64;
    final packet = utf8.encode(
      jsonEncode({
        'kind': 'announce',
        'id': identity.id,
        'name': identity.name,
        'tcp_port': server.port,
        'public_key': identity.publicKey,
        if (avatar != null && avatar.length <= _maxAvatarCharacters)
          'avatar': avatar,
      }),
    );
    socket.send(packet, InternetAddress('255.255.255.255'), _discoveryPort);
  }

  void _prunePeers() {
    final now = DateTime.now();
    final before = _peers.length;
    _peers.removeWhere(
      (_, peer) => now.difference(peer.lastSeen) > _peerExpiry,
    );
    if (_peers.length != before) _emitPeers();
  }

  void _emitPeers() {
    final peers = _peers.values.toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    _peersController.add(peers);
  }


  Future<void> _handleFilePacket(Socket socket, Map<String, dynamic> packet) async {
    final identity = _identity;
    final senderId = packet['from_id'];
    final transferId = packet['transfer_id'];
    final publicKey = packet['sender_public_key'];
    if (identity == null || senderId is! String || transferId is! String ||
        transferId.isEmpty || transferId.length > 128 || publicKey is! String ||
        packet['to_id'] != identity.id) return;
    final trusted = await _identityStore.trustedPeer(senderId);
    if (trusted == null || trusted.publicKey != publicKey) return;

    if (packet['kind'] == 'file_chunk') {
      if (packet['index'] is! int || packet['created_at'] is! int ||
          packet['nonce'] is! String || packet['ciphertext'] is! String ||
          packet['mac'] is! String) return;
      final index = packet['index'] as int;
      final createdAt = packet['created_at'] as int;
      final plain = await _crypto.decrypt(
        local: identity,
        senderPublicKey: publicKey,
        senderId: senderId,
        messageId: '$transferId:$index',
        nonce: packet['nonce'] as String,
        ciphertext: packet['ciphertext'] as String,
        mac: packet['mac'] as String,
        createdAt: createdAt,
        identityStore: _identityStore,
      );
      final payload = jsonDecode(plain) as Map<String, dynamic>;
      final name = payload['name'];
      final size = payload['size'];
      final total = payload['total'];
      final payloadIndex = payload['index'];
      final data = payload['data'];
      if (name is! String || name.isEmpty || name.length > 255 ||
          size is! int || size < 1 || size > _maxFileBytes ||
          total is! int || total < 1 || total > 3000 ||
          index < 0 || index >= total || payloadIndex != index ||
          data is! String) return;
      final chunk = base64Decode(data);
      if (chunk.isEmpty || chunk.length > _fileChunkBytes) return;
      final buffer = _incomingFiles.putIfAbsent(transferId, () => _IncomingFileBuffer(
        senderId: senderId,
        fileName: name,
        fileSize: size,
        totalChunks: total,
        createdAt: DateTime.fromMicrosecondsSinceEpoch(createdAt),
      ));
      if (buffer.senderId != senderId || buffer.fileName != name ||
          buffer.fileSize != size || buffer.totalChunks != total) {
        _incomingFiles.remove(transferId);
        return;
      }
      buffer.chunks.putIfAbsent(index, () => chunk);
      return;
    }

    final buffer = _incomingFiles.remove(transferId);
    if (buffer == null || buffer.senderId != senderId ||
        buffer.chunks.length != buffer.totalChunks) return;
    final builder = BytesBuilder(copy: false);
    for (var i = 0; i < buffer.totalChunks; i++) {
      final chunk = buffer.chunks[i];
      if (chunk == null) return;
      builder.add(chunk);
    }
    final bytes = builder.takeBytes();
    if (bytes.length != buffer.fileSize) return;
    final documents = await getApplicationDocumentsDirectory();
    final directory = Directory('${documents.path}/received_files');
    await directory.create(recursive: true);
    final safeName = buffer.fileName
        .replaceAll(RegExp(r'[/\\\\]'), '_')
        .replaceAll('..', '_');
    var target = File('${directory.path}/$safeName');
    if (await target.exists()) {
      final stamp = DateTime.now().millisecondsSinceEpoch;
      final dot = safeName.lastIndexOf('.');
      final base = dot > 0 ? safeName.substring(0, dot) : safeName;
      final extension = dot > 0 ? safeName.substring(dot) : '';
      target = File('${directory.path}/${base}_$stamp$extension');
    }
    await target.writeAsBytes(bytes, flush: true);
    final fileMessage = IncomingText(
      id: transferId,
      peerId: senderId,
      peerName: trusted.name,
      body: jsonEncode({
        '_locallink_file': 'v1',
        'name': target.uri.pathSegments.last,
        'path': target.path,
        'size': bytes.length,
      }),
      createdAt: buffer.createdAt,
    );
    await _onIncomingText?.call(fileMessage);
    socket.write('${jsonEncode({'kind': 'file_ack', 'transfer_id': transferId})}\n');
    await socket.flush();
  }

  Future<void> stop() async {
    _announceTimer?.cancel();
    _announceTimer = null;
    _pruneTimer?.cancel();
    _pruneTimer = null;
    _discoverySocket?.close();
    _discoverySocket = null;
    await _server?.close();
    _server = null;
    _peers.clear();
    _incomingFiles.clear();
    _emitPeers();
  }

  Future<void> dispose() async {
    await stop();
    await _peersController.close();
  }
}

class _IncomingFileBuffer {
  _IncomingFileBuffer({
    required this.senderId,
    required this.fileName,
    required this.fileSize,
    required this.totalChunks,
    required this.createdAt,
  });
  final String senderId;
  final String fileName;
  final int fileSize;
  final int totalChunks;
  final DateTime createdAt;
  final Map<int, List<int>> chunks = {};
}
