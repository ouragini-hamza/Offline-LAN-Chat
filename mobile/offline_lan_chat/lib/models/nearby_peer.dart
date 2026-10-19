class NearbyPeer {
  const NearbyPeer({
    required this.id,
    required this.name,
    required this.address,
    required this.port,
    required this.lastSeen,
  });

  final String id;
  final String name;
  final String address;
  final int port;
  final DateTime lastSeen;

  NearbyPeer copyWith({
    String? name,
    String? address,
    int? port,
    DateTime? lastSeen,
  }) {
    return NearbyPeer(
      id: id,
      name: name ?? this.name,
      address: address ?? this.address,
      port: port ?? this.port,
      lastSeen: lastSeen ?? this.lastSeen,
    );
  }
}
