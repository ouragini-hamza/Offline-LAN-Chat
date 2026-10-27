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
      _identity ?? const DeviceIdentity(id: '', name: 'My phone');
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

  Future<ChatMessage> sendText(NearbyPeer peer, String text) async {
    final body = text.trim();
    if (body.isEmpty) {
      throw ArgumentError.value(text, 'text', 'Cannot be empty');
    }
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

    var deliveryStatus = 'sent';
    try {
      await _lan.sendText(
        peer: peer,
        messageId: message.id,
        body: message.body,
        createdAt: message.createdAt,
      );
    } on Object {
      // Network failures are shown in the conversation. Database failures
      // below propagate so the UI does not misreport them as delivery failures.
      deliveryStatus = 'failed';
    }

    final updated = message.withDeliveryStatus(deliveryStatus);
    await _database.updateDeliveryStatus(updated.id, updated.deliveryStatus);
    await _refreshRecentConversations();
    notifyListeners();
    return updated;
  }

  Future<void> renameDevice(String name) async {
    final cleanName = name.trim();
    if (cleanName.isEmpty || cleanName.length > 32) {
      throw ArgumentError.value(name, 'name', 'Use 1–32 characters.');
    }

    final updatedIdentity = identity.copyWith(name: cleanName);
    _identity = updatedIdentity;
    await _identityStore.saveName(cleanName);
    try {
      await _lan.updateIdentity(updatedIdentity);
      networkWarning = null;
    } on Object catch (_) {
      networkWarning =
          'The name was saved, but nearby devices may not see it until the next scan.';
    }
    notifyListeners();
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
      await _database.saveMessage(message);
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
