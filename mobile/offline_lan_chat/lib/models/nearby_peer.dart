class NearbyPeer {
  const NearbyPeer({
    required this.id,
    required this.name,
    required this.address,
    required this.port,
    required this.lastSeen,
    required this.publicKey,
    this.avatarBase64,
  });
  final String id;
  final String name;
  final String address;
  final int port;
  final DateTime lastSeen;
  final String publicKey;
  final String? avatarBase64;
  NearbyPeer copyWith({String? name, String? address, int? port, DateTime? lastSeen, String? publicKey, String? avatarBase64}) => NearbyPeer(
    id: id, name: name ?? this.name, address: address ?? this.address,
    port: port ?? this.port, lastSeen: lastSeen ?? this.lastSeen,
    publicKey: publicKey ?? this.publicKey,
    avatarBase64: avatarBase64 ?? this.avatarBase64,
  );
}
