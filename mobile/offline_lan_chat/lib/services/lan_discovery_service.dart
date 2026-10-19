import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../models/nearby_peer.dart';
import 'identity_store.dart';

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
  static const _announceInterval = Duration(seconds: 3);
  static const _peerExpiry = Duration(seconds: 12);

  final Map<String, NearbyPeer> _peers = {};
  final StreamController<List<NearbyPeer>> _peersController =
      StreamController<List<NearbyPeer>>.broadcast();
  DeviceIdentity? _identity;
  Future<void> Function(IncomingText message)? _onIncomingText;
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
  }) async {
    final identity = _identity;
    if (identity == null) throw StateError('Discovery is not running.');

    final socket = await Socket.connect(
      InternetAddress(peer.address),
      peer.port,
      timeout: const Duration(seconds: 5),
    );
    socket.setOption(SocketOption.tcpNoDelay, true);

    final acknowledgement = Completer<void>();
    final subscription = socket
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
        '${jsonEncode({'kind': 'text', 'id': messageId, 'from_id': identity.id, 'from_name': identity.name, 'to_id': peer.id, 'body': body, 'created_at': createdAt.microsecondsSinceEpoch})}\n',
      );
      await socket.flush();
      await acknowledgement.future.timeout(const Duration(seconds: 8));
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
        if (packet['kind'] != 'announce' ||
            id is! String ||
            name is! String ||
            port is! int ||
            id == _identity?.id) {
          continue;
        }

        _peers[id] = NearbyPeer(
          id: id,
          name: name,
          address: datagram.address.address,
          port: port,
          lastSeen: DateTime.now(),
        );
        _emitPeers();
      } catch (_) {
        // A malformed local-network packet is ignored.
      }
    }
  }

  void _handleConnection(Socket socket) {
    socket.setOption(SocketOption.tcpNoDelay, true);
    socket
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(
          (line) => unawaited(_handleMessageLine(socket, line)),
          onError: (_) => socket.destroy(),
          onDone: socket.destroy,
          cancelOnError: true,
        );
  }

  Future<void> _handleMessageLine(Socket socket, String line) async {
    try {
      if (line.length > 16 * 1024) return;
      final packet = jsonDecode(line) as Map<String, dynamic>;
      final identity = _identity;
      if (identity == null ||
          packet['kind'] != 'text' ||
          packet['to_id'] != identity.id ||
          packet['id'] is! String ||
          packet['from_id'] is! String ||
          packet['from_name'] is! String ||
          packet['body'] is! String ||
          (packet['body'] as String).length > 4000 ||
          packet['created_at'] is! int) {
        return;
      }

      final incoming = IncomingText(
        id: packet['id'] as String,
        peerId: packet['from_id'] as String,
        peerName: packet['from_name'] as String,
        body: packet['body'] as String,
        createdAt: DateTime.fromMicrosecondsSinceEpoch(
          packet['created_at'] as int,
        ),
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

    final packet = utf8.encode(
      jsonEncode({
        'kind': 'announce',
        'id': identity.id,
        'name': identity.name,
        'tcp_port': server.port,
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
    _emitPeers();
  }

  Future<void> dispose() async {
    await stop();
    await _peersController.close();
  }
}
