import 'package:flutter_test/flutter_test.dart';
import 'package:offline_lan_chat/services/identity_store.dart';

void main() {
  group('DeviceIdentity', () {
    test('copyWith changes the name and preserves identity keys', () {
      const original = DeviceIdentity(
        id: 'device-123',
        name: 'Phone A',
        publicKey: 'cHVibGljLWtleQ==',
      );

      final renamed = original.copyWith(name: 'Phone B');

      expect(renamed.id, original.id);
      expect(renamed.publicKey, original.publicKey);
      expect(renamed.name, 'Phone B');
    });

    test('copyWith without a name preserves all values', () {
      const original = DeviceIdentity(
        id: 'device-123',
        name: 'Phone A',
        publicKey: 'cHVibGljLWtleQ==',
      );

      final copy = original.copyWith();

      expect(copy.id, original.id);
      expect(copy.name, original.name);
      expect(copy.publicKey, original.publicKey);
    });
  });
}
