import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class LocalGroup {
  const LocalGroup({required this.id, required this.name, required this.memberIds, required this.createdAt});
  final String id;
  final String name;
  final List<String> memberIds;
  final DateTime createdAt;

  Map<String, Object?> toJson() => {'id': id, 'name': name, 'member_ids': memberIds, 'created_at': createdAt.microsecondsSinceEpoch};

  factory LocalGroup.fromJson(Map<String, dynamic> json) => LocalGroup(
    id: json['id'] as String,
    name: json['name'] as String,
    memberIds: (json['member_ids'] as List).whereType<String>().toList(),
    createdAt: DateTime.fromMicrosecondsSinceEpoch(json['created_at'] as int),
  );
}

class GroupStore {
  static const _key = 'locallink_groups_v1';

  Future<List<LocalGroup>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return const [];
    try {
      final decoded = jsonDecode(raw) as List;
      return decoded.whereType<Map<String, dynamic>>().map(LocalGroup.fromJson).toList();
    } on Object {
      return const [];
    }
  }

  Future<void> save(LocalGroup group) async {
    final groups = await load();
    final updated = [...groups.where((item) => item.id != group.id), group];
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(updated.map((item) => item.toJson()).toList()));
  }
}
