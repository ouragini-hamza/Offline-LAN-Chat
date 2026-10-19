class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.peerId,
    required this.peerName,
    required this.body,
    required this.createdAt,
    required this.isOutgoing,
    required this.deliveryStatus,
  });

  final String id;
  final String peerId;
  final String peerName;
  final String body;
  final DateTime createdAt;
  final bool isOutgoing;
  final String deliveryStatus;

  ChatMessage withDeliveryStatus(String status) {
    return ChatMessage(
      id: id,
      peerId: peerId,
      peerName: peerName,
      body: body,
      createdAt: createdAt,
      isOutgoing: isOutgoing,
      deliveryStatus: status,
    );
  }

  factory ChatMessage.fromDatabase(Map<String, Object?> row) {
    return ChatMessage(
      id: row['id']! as String,
      peerId: row['peer_id']! as String,
      peerName: row['peer_name']! as String,
      body: row['body']! as String,
      createdAt: DateTime.fromMicrosecondsSinceEpoch(row['created_at']! as int),
      isOutgoing: (row['is_outgoing']! as int) == 1,
      deliveryStatus: row['delivery_status']! as String,
    );
  }

  Map<String, Object?> toDatabase() {
    return {
      'id': id,
      'peer_id': peerId,
      'peer_name': peerName,
      'body': body,
      'created_at': createdAt.microsecondsSinceEpoch,
      'is_outgoing': isOutgoing ? 1 : 0,
      'delivery_status': deliveryStatus,
    };
  }
}

class ConversationPreview {
  const ConversationPreview({
    required this.peerId,
    required this.peerName,
    required this.lastMessage,
    required this.createdAt,
    required this.isOutgoing,
  });

  final String peerId;
  final String peerName;
  final String lastMessage;
  final DateTime createdAt;
  final bool isOutgoing;

  factory ConversationPreview.fromDatabase(Map<String, Object?> row) {
    return ConversationPreview(
      peerId: row['peer_id']! as String,
      peerName: row['peer_name']! as String,
      lastMessage: row['body']! as String,
      createdAt: DateTime.fromMicrosecondsSinceEpoch(row['created_at']! as int),
      isOutgoing: (row['is_outgoing']! as int) == 1,
    );
  }
}
