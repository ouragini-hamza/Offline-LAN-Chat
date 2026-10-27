import 'package:flutter/material.dart';

import '../models/chat_message.dart';
import '../models/nearby_peer.dart';
import '../services/chat_controller.dart';
import 'chat_screen.dart';
import 'identity_qr_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({required this.controller, super.key});

  final ChatController controller;

  @override
  Widget build(BuildContext context) {
    final onlineIds = controller.peers.map((peer) => peer.id).toSet();

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'LocalLink',
          style: TextStyle(fontWeight: FontWeight.w700, letterSpacing: -0.5),
        ),
        actions: [
          IconButton(
            tooltip: 'Secure pairing with QR',
            onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => IdentityQrScreen(controller: controller))),
            icon: const Icon(Icons.qr_code_2_rounded),
          ),
          IconButton(
            tooltip: 'Change device name',
            onPressed: () => _editDeviceName(context),
            icon: const Icon(Icons.edit_outlined),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _NetworkBanner(
              warning: controller.networkWarning,
              nearbyCount: controller.peers.length,
            ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: controller.refreshDiscovery,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 32),
                  children: [
                    const _SectionHeading(
                      title: 'Nearby',
                      caption: 'Phones on this Wi-Fi network',
                    ),
                    const SizedBox(height: 12),
                    if (controller.peers.isEmpty)
                      const _NearbyEmptyState()
                    else
                      ...controller.peers.map(
                        (peer) => _PeerTile(
                          peer: peer,
                          onTap: () => _openChat(
                            context,
                            peerId: peer.id,
                            peerName: peer.name,
                          ),
                        ),
                      ),
                    const SizedBox(height: 28),
                    const _SectionHeading(
                      title: 'Recent chats',
                      caption: 'Your history stays on this phone',
                    ),
                    const SizedBox(height: 12),
                    if (controller.recentConversations.isEmpty)
                      const _HistoryEmptyState()
                    else
                      ...controller.recentConversations.map((conversation) {
                        final peer = _peerById(conversation.peerId);
                        return _ConversationTile(
                          conversation: conversation,
                          isOnline: onlineIds.contains(conversation.peerId),
                          onTap: () => _openChat(
                            context,
                            peerId: conversation.peerId,
                            peerName: peer?.name ?? conversation.peerName,
                          ),
                        );
                      }),
                    const SizedBox(height: 24),
                    const _PrivacyNote(),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  NearbyPeer? _peerById(String id) {
    for (final peer in controller.peers) {
      if (peer.id == id) return peer;
    }
    return null;
  }

  Future<void> _openChat(
    BuildContext context, {
    required String peerId,
    required String peerName,
  }) {
    return Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ChatScreen(
          controller: controller,
          peerId: peerId,
          peerName: peerName,
        ),
      ),
    );
  }

  Future<void> _editDeviceName(BuildContext context) async {
    final fieldController = TextEditingController(
      text: controller.identity.name,
    );
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Your device name'),
        content: TextField(
          controller: fieldController,
          autofocus: true,
          maxLength: 32,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            hintText: 'Name shown to nearby phones',
          ),
          onSubmitted: (value) => Navigator.of(context).pop(value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(fieldController.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    fieldController.dispose();
    if (name == null || !context.mounted) return;

    try {
      await controller.renameDevice(name);
    } on ArgumentError catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message?.toString() ?? 'Invalid name.')),
      );
    }
  }
}

class _NetworkBanner extends StatelessWidget {
  const _NetworkBanner({required this.warning, required this.nearbyCount});

  final String? warning;
  final int nearbyCount;

  @override
  Widget build(BuildContext context) {
    final hasWarning = warning != null;
    final background = hasWarning
        ? const Color(0xFFFFF2DB)
        : const Color(0xFFE8F4ED);
    final foreground = hasWarning
        ? const Color(0xFF845A18)
        : const Color(0xFF246348);
    final message =
        warning ??
        (nearbyCount == 0
            ? 'Offline and ready · looking for nearby phones'
            : '$nearbyCount ${nearbyCount == 1 ? 'phone' : 'phones'} nearby · same Wi-Fi');

    return Container(
      margin: const EdgeInsets.fromLTRB(20, 4, 20, 0),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(
            hasWarning ? Icons.wifi_off_rounded : Icons.wifi_tethering_rounded,
            size: 19,
            color: foreground,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: foreground,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeading extends StatelessWidget {
  const _SectionHeading({required this.title, required this.caption});

  final String title;
  final String caption;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: Color(0xFF193B32),
            fontSize: 21,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.4,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          caption,
          style: const TextStyle(color: Color(0xFF718078), fontSize: 13),
        ),
      ],
    );
  }
}

class _PeerTile extends StatelessWidget {
  const _PeerTile({required this.peer, required this.onTap});

  final NearbyPeer peer;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(17),
        side: const BorderSide(color: Color(0xFFE9EDE9)),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
        leading: const _DeviceAvatar(),
        title: Text(
          peer.name,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: const Text(
          'Pair via QR to enable encrypted chat',
          style: TextStyle(color: Color(0xFF718078), fontSize: 12),
        ),
        trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 15),
        onTap: onTap,
      ),
    );
  }
}

class _ConversationTile extends StatelessWidget {
  const _ConversationTile({
    required this.conversation,
    required this.isOnline,
    required this.onTap,
  });

  final ConversationPreview conversation;
  final bool isOnline;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final prefix = conversation.isOutgoing ? 'You: ' : '';
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(17),
        side: const BorderSide(color: Color(0xFFE9EDE9)),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
        leading: const _DeviceAvatar(),
        title: Text(
          conversation.peerName,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          '$prefix${conversation.lastMessage}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: Color(0xFF718078), fontSize: 13),
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              _formatTime(conversation.createdAt),
              style: const TextStyle(fontSize: 11, color: Color(0xFF849089)),
            ),
            const SizedBox(height: 5),
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                color: isOnline ? const Color(0xFF41A573) : Colors.transparent,
                shape: BoxShape.circle,
              ),
            ),
          ],
        ),
        onTap: onTap,
      ),
    );
  }
}

class _DeviceAvatar extends StatelessWidget {
  const _DeviceAvatar();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: const Color(0xFFE7F2EC),
        borderRadius: BorderRadius.circular(15),
      ),
      child: const Icon(
        Icons.smartphone_rounded,
        color: Color(0xFF28674F),
        size: 22,
      ),
    );
  }
}

class _NearbyEmptyState extends StatelessWidget {
  const _NearbyEmptyState();

  @override
  Widget build(BuildContext context) {
    return const _EmptyCard(
      icon: Icons.wifi_find_rounded,
      title: 'Looking for nearby phones',
      message:
          'Keep LocalLink open on both phones and connect them to the same Wi-Fi.',
    );
  }
}

class _HistoryEmptyState extends StatelessWidget {
  const _HistoryEmptyState();

  @override
  Widget build(BuildContext context) {
    return const _EmptyCard(
      icon: Icons.chat_bubble_outline_rounded,
      title: 'Your conversations will appear here',
      message: 'Choose a nearby phone to start your first local chat.',
    );
  }
}

class _EmptyCard extends StatelessWidget {
  const _EmptyCard({
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 20, 18, 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(17),
        border: Border.all(color: const Color(0xFFE9EDE9)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: const Color(0xFF39735C), size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Color(0xFF193B32),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  message,
                  style: const TextStyle(
                    color: Color(0xFF718078),
                    fontSize: 13,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PrivacyNote extends StatelessWidget {
  const _PrivacyNote();

  @override
  Widget build(BuildContext context) {
    return const Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.lock_outline_rounded, size: 16, color: Color(0xFF718078)),
        SizedBox(width: 8),
        Expanded(
          child: Text(
            'Chats stay on your devices. This early version does not encrypt messages yet.',
            style: TextStyle(
              color: Color(0xFF718078),
              fontSize: 12,
              height: 1.45,
            ),
          ),
        ),
      ],
    );
  }
}

String _formatTime(DateTime dateTime) {
  final now = DateTime.now();
  if (now.year == dateTime.year &&
      now.month == dateTime.month &&
      now.day == dateTime.day) {
    final hour = dateTime.hour % 12 == 0 ? 12 : dateTime.hour % 12;
    final minute = dateTime.minute.toString().padLeft(2, '0');
    return '$hour:$minute ${dateTime.hour >= 12 ? 'PM' : 'AM'}';
  }
  return '${dateTime.day}/${dateTime.month}';
}
