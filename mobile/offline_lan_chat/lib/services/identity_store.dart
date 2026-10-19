import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

class DeviceIdentity {
  const DeviceIdentity({required this.id, required this.name});

  final String id;
  final String name;

  DeviceIdentity copyWith({String? name}) {
    return DeviceIdentity(id: id, name: name ?? this.name);
  }
}

class IdentityStore {
  static const _idKey = 'device_id';
  static const _nameKey = 'device_name';

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

    return DeviceIdentity(id: id, name: name);
  }

  Future<void> saveName(String name) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_nameKey, name.trim());
  }

  String _randomId() {
    final random = Random.secure();
    return List<String>.generate(
      16,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
  }
}
