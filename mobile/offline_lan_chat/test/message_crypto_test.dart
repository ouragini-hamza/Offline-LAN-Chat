import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_lan_chat/services/identity_store.dart';
import 'package:offline_lan_chat/services/message_crypto.dart';

class TestIdentityStore extends IdentityStore {
  TestIdentityStore(this._keyPairs);

  final Map<String, SimpleKeyPair> _keyPairs;

  @override
  Future<SimpleKeyPair> loadPrivateKeyPair(DeviceIdentity identity) async {
    return _keyPairs[identity.id]!;
  }
}

class TestIdentity {
  const TestIdentity({required this.identity, required this.keyPair});

  final DeviceIdentity identity;
  final SimpleKeyPair keyPair;
}

void main() {
  final x25519 = X25519();

  Future<TestIdentity> newIdentity(String id) async {
    final keyPair = await x25519.newKeyPair();
    final publicKey = await keyPair.extractPublicKey();
    return TestIdentity(
      identity: DeviceIdentity(
        id: id,
        name: id,
        publicKey: base64Encode(publicKey.bytes),
      ),
      keyPair: keyPair,
    );
  }

  test('encrypts for a paired peer and authenticates the message metadata',
      () async {
    final sender = await newIdentity('alice');
    final recipient = await newIdentity('bob');
    final store = TestIdentityStore({
      sender.identity.id: sender.keyPair,
      recipient.identity.id: recipient.keyPair,
    });
    final crypto = MessageCrypto();

    final encrypted = await crypto.encrypt(
      local: sender.identity,
      recipientPublicKey: recipient.identity.publicKey,
      messageId: 'message-1',
      plaintext: 'bonjour LocalLink',
      createdAt: 42,
      identityStore: store,
    );

    final plaintext = await crypto.decrypt(
      local: recipient.identity,
      senderPublicKey: sender.identity.publicKey,
      senderId: sender.identity.id,
      messageId: 'message-1',
      nonce: encrypted['nonce']!,
      ciphertext: encrypted['ciphertext']!,
      mac: encrypted['mac']!,
      createdAt: 42,
      identityStore: store,
    );

    expect(plaintext, 'bonjour LocalLink');
    await expectLater(
      crypto.decrypt(
        local: recipient.identity,
        senderPublicKey: sender.identity.publicKey,
        senderId: sender.identity.id,
        messageId: 'message-1',
        nonce: encrypted['nonce']!,
        ciphertext: encrypted['ciphertext']!,
        mac: encrypted['mac']!,
        createdAt: 43,
        identityStore: store,
      ),
      throwsA(anything),
    );
  });

  test('rejects a modified authentication tag', () async {
    final sender = await newIdentity('sender');
    final recipient = await newIdentity('recipient');
    final store = TestIdentityStore({
      sender.identity.id: sender.keyPair,
      recipient.identity.id: recipient.keyPair,
    });
    final crypto = MessageCrypto();
    final encrypted = await crypto.encrypt(
      local: sender.identity,
      recipientPublicKey: recipient.identity.publicKey,
      messageId: 'message-2',
      plaintext: 'secret',
      createdAt: 99,
      identityStore: store,
    );
    final tamperedMac = base64Decode(encrypted['mac']!)..[0] ^= 1;

    await expectLater(
      crypto.decrypt(
        local: recipient.identity,
        senderPublicKey: sender.identity.publicKey,
        senderId: sender.identity.id,
        messageId: 'message-2',
        nonce: encrypted['nonce']!,
        ciphertext: encrypted['ciphertext']!,
        mac: base64Encode(tamperedMac),
        createdAt: 99,
        identityStore: store,
      ),
      throwsA(anything),
    );
  });
}
