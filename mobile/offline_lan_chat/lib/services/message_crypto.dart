import 'dart:convert';
import 'dart:math';
import 'package:cryptography/cryptography.dart';
import 'identity_store.dart';

class MessageCrypto {
  final X25519 _x25519 = X25519();
  final Hkdf _hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);
  final AesGcm _aead = AesGcm.with256bits();

  Future<Map<String, String>> encrypt({
    required DeviceIdentity local, required String recipientPublicKey,
    required String messageId, required String plaintext, required int createdAt,
    required IdentityStore identityStore,
  }) async {
    final pair = await identityStore.loadPrivateKeyPair(local);
    final remote = SimplePublicKey(base64Decode(recipientPublicKey), type: KeyPairType.x25519);
    final shared = await _x25519.sharedSecretKey(keyPair: pair, remotePublicKey: remote);
    final key = await _deriveKey(shared, local.publicKey, recipientPublicKey);
    final aad = utf8.encode('$messageId|$createdAt|\${local.id}');
    final nonce = List<int>.generate(12, (_) => Random.secure().nextInt(256));
    final box = await _aead.encrypt(utf8.encode(plaintext), secretKey: key, nonce: nonce, aad: aad);
    return {'nonce': base64Encode(box.nonce), 'ciphertext': base64Encode(box.cipherText), 'mac': base64Encode(box.mac.bytes)};
  }

  Future<String> decrypt({
    required DeviceIdentity local, required String senderPublicKey, required String senderId,
    required String messageId, required String nonce, required String ciphertext,
    required String mac, required int createdAt, required IdentityStore identityStore,
  }) async {
    final pair = await identityStore.loadPrivateKeyPair(local);
    final remote = SimplePublicKey(base64Decode(senderPublicKey), type: KeyPairType.x25519);
    final shared = await _x25519.sharedSecretKey(keyPair: pair, remotePublicKey: remote);
    final key = await _deriveKey(shared, local.publicKey, senderPublicKey);
    final box = SecretBox(base64Decode(ciphertext), nonce: base64Decode(nonce), mac: Mac(base64Decode(mac)));
    final aad = utf8.encode('$messageId|$createdAt|$senderId');
    return utf8.decode(await _aead.decrypt(box, secretKey: key, aad: aad));
  }

  Future<SecretKey> _deriveKey(SecretKey shared, String publicA, String publicB) {
    final keys = [publicA, publicB]..sort();
    return _hkdf.deriveKey(secretKey: shared, nonce: utf8.encode('LocalLink-v1'), info: utf8.encode(keys.join('|')));
  }
}