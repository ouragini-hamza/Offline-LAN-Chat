import 'dart:convert';
import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cryptography/cryptography.dart';

class DeviceIdentity {
  const DeviceIdentity({
    required this.id,
    required this.name,
    required this.publicKey,
  });

  final String id;
  final String name;
  /// Base64-encoded X25519 public key. The matching private key never leaves
  /// secure storage.
  final String publicKey;

  DeviceIdentity copyWith({String? name}) => DeviceIdentity(
        id: id,
        name: name ?? this.name,
        publicKey: publicKey,
      );
}

class TrustedPeer {
  const TrustedPeer({
    required this.id,
    required this.name,
    required this.publicKey,
  });

  final String id;
  final String name;
  final String publicKey;
}

class IdentityStore {
  static const _idKey = 'device_id';
  static const _nameKey = 'device_name';
  static const _privateKeyKey = 'device_x25519_private_v1';
  static const _publicKeyKey = 'device_x25519_public_v1';
  static const _trustedPeersKey = 'trusted_peers_v1';

  static const FlutterSecureStorage _secureStorage = FlutterSecureStorage();
  final X25519 _x25519 = X25519();

  Future<DeviceIdentity> loadOrCreate() async {
    final preferences = await SharedPreferences.getInstance();
    var id = preferences.getString(_idKey);
    if (id == null) {
      id = _randomId();
      await preferences.setString(_idKey, id);
    }

    var name = preferences.getString(_nameKey);
    if (name == null || name.trim().isEmpty) {
      name = 'Phone ${id.substring(0, 4).toUpperCase()}';
      await preferences.setString(_nameKey, name);
    }

    var privateKey = await _secureStorage.read(key: _privateKeyKey);
    var publicKey = await _secureStorage.read(key: _publicKeyKey);
    if (privateKey == null || publicKey == null) {
      final pair = await _x25519.newKeyPair();
      privateKey = base64Encode(await pair.extractPrivateKeyBytes());
      publicKey = base64Encode((await pair.extractPublicKey()).bytes);
      await _secureStorage.write(key: _privateKeyKey, value: privateKey);
      await _secureStorage.write(key: _publicKeyKey, value: publicKey);
    }

    return DeviceIdentity(id: id, name: name, publicKey: publicKey);
  }

  Future<SimpleKeyPair> loadPrivateKeyPair(DeviceIdentity identity) async {
    final privateKey = await _secureStorage.read(key: _privateKeyKey);
    if (privateKey == null) {
      throw StateError('This device has no saved private key.');
    }
    return SimpleKeyPairData(
      base64Decode(privateKey),
      publicKey: SimplePublicKey(
        base64Decode(identity.publicKey),
        type: KeyPairType.x25519,
      ),
      type: KeyPairType.x25519,
    );
  }

  Future<void> saveName(String name) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_nameKey, name.trim());
  }

  Future<List<TrustedPeer>> trustedPeers() async {
    final preferences = await SharedPreferences.getInstance();
    final raw = preferences.getString(_trustedPeersKey);
    if (raw == null) return const [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list.map((item) {
        final map = item as Map<String, dynamic>;
        return TrustedPeer(
          id: map['id'] as String,
          name: map['name'] as String,
          publicKey: map['public_key'] as String,
        );
      }).toList();
    } on Object {
      return const [];
    }
  }

  Future<TrustedPeer?> trustedPeer(String id) async {
    for (final peer in await trustedPeers()) {
      if (peer.id == id) return peer;
    }
    return null;
  }

  Future<void> trustPeer({
    required String id,
    required String name,
    required String publicKey,
  }) async {
    if (id.isEmpty || id.length > 128 || name.trim().isEmpty ||
        publicKey.isEmpty) {
      throw const FormatException('Invalid LocalLink identity QR code.');
    }
    final decodedKey = base64Decode(publicKey);
    if (decodedKey.length != 32) {
      throw const FormatException('The QR code contains an invalid public key.');
    }
    final current = await trustedPeers();
    final updated = [
      ...current.where((peer) => peer.id != id),
      TrustedPeer(id: id, name: name.trim(), publicKey: publicKey),
    ];
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      _trustedPeersKey,
      jsonEncode(updated.map((peer) => {
        'id': peer.id,
        'name': peer.name,
        'public_key': peer.publicKey,
      }).toList()),
    );
  }

  Future<void> untrustPeer(String id) async {
    final current = await trustedPeers();
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      _trustedPeersKey,
      jsonEncode(current.where((peer) => peer.id != id).map((peer) => {
        'id': peer.id,
        'name': peer.name,
        'public_key': peer.publicKey,
      }).toList()),
    );
  }

  String _randomId() {
    final random = Random.secure();
    return List<String>.generate(
      16,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
  }
}
