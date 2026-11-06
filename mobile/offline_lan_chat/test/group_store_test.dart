import 'package:flutter_test/flutter_test.dart';
import 'package:offline_lan_chat/services/group_store.dart';

void main() {
  test('LocalGroup JSON round-trip preserves identity and members', () {
    final original = LocalGroup(
      id: 'group-123',
      name: 'Study group',
      memberIds: const ['device-a', 'device-b'],
      createdAt: DateTime.fromMicrosecondsSinceEpoch(123456789),
    );

    final restored = LocalGroup.fromJson(original.toJson());
    expect(restored.id, original.id);
    expect(restored.name, original.name);
    expect(restored.memberIds, original.memberIds);
    expect(restored.createdAt, original.createdAt);
  });
}
