import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../models/chat_message.dart';
import '../models/nearby_peer.dart';
import 'chat_database.dart';
import 'identity_store.dart';
import 'lan_discovery_service.dart';

class ChatController extends ChangeNotifier {
  final IdentityStore _identityStore = IdentityStore();
  final ChatDatabase _database = ChatDatabase();
  final LanDiscoveryService _lan = LanDiscoveryService();
  final StreamController<ChatMessage> _incomingMessages =
      StreamController<ChatMessage>.broadcast();

  DeviceIdentity? _identity;
  List<NearbyPeer> _peers = [];
  List<ConversationPreview> _recentConversations = [];
  StreamSubscription<List<NearbyPeer>>? _peersSubscription;

  bool isReady = false;
  String? networkWarning;

  DeviceIdentity get identity =>
      _identity ?? const DeviceIdentity(id: '', name: 'My phone', publicKey: '');
  List<NearbyPeer> get peers => List.unmodifiable(_peers);
  List<ConversationPreview> get recentConversations =>
      List.unmodifiable(_recentConversations);
  Stream<ChatMessage> get incomingMessages => _incomingMessages.stream;

  Future<void> initialize() async {
    _identity = await _identityStore.loadOrCreate();
    _peersSubscription = _lan.peers.listen((peers) {
      _peers = peers;
      notifyListeners();
    });
    try {
      await _lan.start(identity, onIncomingText: _saveIncoming);
      networkWarning = null;
    } on Object catch (_) {
      networkWarning =
          'Local network access is unavailable. Check the app permissions and Wi-Fi connection.';
    }

    await _refreshRecentConversations();
    isReady = true;
    notifyListeners();
  }

  Future<List<ChatMessage>> loadMessages(String peerId) {
    return _database.loadMessages(peerId);
  }

  Future<void> refreshDiscovery() => _lan.refreshDiscovery();

  Future<List<TrustedPeer>> get trustedPeers => _identityStore.trustedPeers();

  Future<bool> isTrusted(String peerId) async =>
      await _identityStore.trustedPeer(peerId) != null;

  Future<void> trustPeer({required String id, required String name, required String publicKey}) async {
    await _identityStore.trustPeer(id: id, name: name, publicKey: publicKey);
    notifyListeners();
  }

  Future<void> trustDiscoveredPeer(NearbyPeer peer) async {
    final existing = await _identityStore.trustedPeer(peer.id);
    if (existing != null && existing.publicKey != peer.publicKey) {
      throw StateError('This profile identity changed. Remove it before trusting the new key.');
    }
    await _identityStore.trustPeer(
      id: peer.id,
      name: peer.name,
      publicKey: peer.publicKey,
    );
  }

  Future<ChatMessage> sendText(NearbyPeer peer, String text) async {
    final body = text.trim();
    if (body.isEmpty)
      throw ArgumentError.value(text, 'text', 'Cannot be empty');
    if (body.length > 4000) {
      throw ArgumentError.value(text, 'text', 'Message is too long');
    }

    final message = ChatMessage(
      id: _newId(),
      peerId: peer.id,
      peerName: peer.name,
      body: body,
      createdAt: DateTime.now(),
      isOutgoing: true,
      deliveryStatus: 'sending',
    );
    await _database.saveMessage(message);
    await _refreshRecentConversations();
    notifyListeners();

    try {
      final trusted = await _identityStore.trustedPeer(peer.id);
      if (trusted == null || trusted.publicKey != peer.publicKey) {
        throw StateError('Pair with this device by scanning its QR code first.');
      }
      await _lan.sendText(
        peer: peer,
        messageId: message.id,
        body: message.body,
        createdAt: message.createdAt,
        recipientPublicKey: trusted.publicKey,
      );
      final sent = message.withDeliveryStatus('sent');
      await _database.updateDeliveryStatus(sent.id, sent.deliveryStatus);
      await _refreshRecentConversations();
      notifyListeners();
      return sent;
    } on Object {
      final failed = message.withDeliveryStatus('failed');
      await _database.updateDeliveryStatus(failed.id, failed.deliveryStatus);
      await _refreshRecentConversations();
      notifyListeners();
      return failed;
    }
  }

  Future<void> updateProfile({required String name, String? avatarBase64}) async {
    final cleanName = name.trim();
    if (cleanName.isEmpty || cleanName.length > 32) {
      throw ArgumentError.value(name, 'name', 'Use 1–32 characters.');
    }

    final updatedIdentity = DeviceIdentity(
      id: identity.id,
      name: cleanName,
      publicKey: identity.publicKey,
      avatarBase64: avatarBase64,
    );
    _identity = updatedIdentity;
    await _identityStore.saveName(cleanName);
    await _identityStore.saveAvatar(avatarBase64);
    try {
      await _lan.updateIdentity(updatedIdentity);
      networkWarning = null;
    } on Object catch (_) {
      networkWarning =
          'The name was saved, but nearby devices may not see it until the next scan.';
    }
    notifyListeners();
  }

  Future<void> renameDevice(String name) {
    return updateProfile(name: name, avatarBase64: identity.avatarBase64);
  }

  Future<void> _saveIncoming(IncomingText incoming) async {
    final message = ChatMessage(
      id: incoming.id,
      peerId: incoming.peerId,
      peerName: incoming.peerName,
      body: incoming.body,
      createdAt: incoming.createdAt,
      isOutgoing: false,
      deliveryStatus: 'received',
    );
    try {
      final isNewMessage = await _database.saveIncomingMessage(message);
      if (!isNewMessage) return;
      _incomingMessages.add(message);
      await _refreshRecentConversations();
      notifyListeners();
    } on Object catch (_) {
      networkWarning =
          'A message arrived but could not be saved on this phone.';
      notifyListeners();
      rethrow;
    }
  }

  Future<void> _refreshRecentConversations() async {
    _recentConversations = await _database.loadRecentConversations();
  }

  String _newId() {
    final random = Random.secure();
    return List<String>.generate(
      16,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
  }

  @override
  void dispose() {
    unawaited(_peersSubscription?.cancel());
    unawaited(_lan.dispose());
    unawaited(_database.close());
    unawaited(_incomingMessages.close());
    super.dispose();
  }
}
