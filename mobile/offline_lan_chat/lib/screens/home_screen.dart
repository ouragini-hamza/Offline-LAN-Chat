import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../models/chat_message.dart';
import '../models/nearby_peer.dart';
import '../services/chat_controller.dart';
import '../services/identity_store.dart';
import '../services/group_store.dart';
import 'group_chat_screen.dart';
import 'chat_screen.dart';

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
            tooltip: 'Edit profile',
            onPressed: () => _editProfile(context),
            icon: const Icon(Icons.account_circle_outlined),
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
                            peer: peer,
                          ),
                        ),
                      ),
                    const SizedBox(height: 28),
                    const SizedBox(height: 28),
                    Row(children: [
                      const Expanded(child: _SectionHeading(
                        title: 'Groups',
                        caption: 'Local groups on this Wi-Fi',
                      )),
                      IconButton(
                        tooltip: 'Create group',
                        onPressed: () => _createGroup(context),
                        icon: const Icon(Icons.group_add_outlined),
                      ),
                    ]),
                    const SizedBox(height: 8),
                    if (controller.groups.isEmpty)
                      const _EmptyCard(
                        icon: Icons.groups_outlined,
                        title: 'No groups yet',
                        message: 'Create a group and choose people nearby.',
                      )
                    else
                      ...controller.groups.map((group) => Card(
                        color: Colors.white,
                        elevation: 0,
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          leading: const CircleAvatar(
                            backgroundColor: Color(0xFFE7F2EC),
                            child: Icon(Icons.groups_rounded, color: Color(0xFF28674F)),
                          ),
                          title: Text(group.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                          subtitle: Text('${group.memberIds.length} members · local Wi-Fi'),
                          trailing: const Icon(Icons.chevron_right_rounded),
                          onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                            builder: (_) => GroupChatScreen(controller: controller, group: group),
                          )),
                        ),
                      )),
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

  Future<void> _createGroup(BuildContext context) async {
    final nameController = TextEditingController();
    final selected = <String>{};
    final draft = await showDialog<_GroupDraft>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Create a group'),
          content: SizedBox(
            width: 360,
            child: SingleChildScrollView(child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  maxLength: 48,
                  decoration: const InputDecoration(labelText: 'Group name'),
                ),
                const SizedBox(height: 8),
                if (controller.peers.isEmpty)
                  const Text('No nearby phones yet. Connect to the same Wi-Fi first.')
                else
                  ...controller.peers.map((peer) => CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: selected.contains(peer.id),
                    title: Text(peer.name),
                    subtitle: Text(peer.id.substring(0, peer.id.length > 8 ? 8 : peer.id.length)),
                    onChanged: (value) => setDialogState(() {
                      if (value == true) { selected.add(peer.id); } else { selected.remove(peer.id); }
                    }),
                  )),
              ],
            )),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, _GroupDraft(
                name: nameController.text, memberIds: selected.toList(),
              )),
              child: const Text('Create'),
            ),
          ],
        ),
      ),
    );
    nameController.dispose();
    if (draft == null || !context.mounted) return;
    try {
      await controller.createGroup(name: draft.name, memberIds: draft.memberIds);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Group created. Members must be online to receive messages.'),
      ));
    } on Object catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not create group: $error')));
    }
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
    NearbyPeer? peer,
  }) async {
    try {
      if (peer != null) await controller.trustDiscoveredPeer(peer);
    } on StateError catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error.message.toString())),
        );
      }
      return;
    }
    if (!context.mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ChatScreen(
          controller: controller,
          peerId: peerId,
          peerName: peerName,
        ),
      ),
    );
  }

  Future<void> _editProfile(BuildContext context) async {
    final profile = await showDialog<_ProfileDraft>(
      context: context,
      builder: (_) => _ProfileDialog(identity: controller.identity),
    );
    if (profile == null || !context.mounted) return;

    try {
      await controller.updateProfile(
        name: profile.name,
        avatarBase64: profile.avatarBase64,
      );
    } on ArgumentError catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message.toString())),
      );
    }
  }
}

class _GroupDraft {
  const _GroupDraft({required this.name, required this.memberIds});
  final String name;
  final List<String> memberIds;
}

class _ProfileDraft {
  const _ProfileDraft({required this.name, required this.avatarBase64});

  final String name;
  final String? avatarBase64;
}

class _ProfileDialog extends StatefulWidget {
  const _ProfileDialog({required this.identity});

  final DeviceIdentity identity;

  @override
  State<_ProfileDialog> createState() => _ProfileDialogState();
}

class _ProfileDialogState extends State<_ProfileDialog> {
  static const _maxAvatarCharacters = 12 * 1024;
  late final TextEditingController _fieldController = TextEditingController(
    text: widget.identity.name,
  );
  String? _avatarBase64;
  String? _photoError;

  @override
  void initState() {
    super.initState();
    _avatarBase64 = widget.identity.avatarBase64;
  }

  @override
  void dispose() {
    _fieldController.dispose();
    super.dispose();
  }

  void _submit() {
    Navigator.of(context).pop(
      _ProfileDraft(
        name: _fieldController.text,
        avatarBase64: _avatarBase64,
      ),
    );
  }

  Future<void> _selectPhoto() async {
    final photo = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 128,
      maxHeight: 128,
      imageQuality: 35,
    );
    if (photo == null || !mounted) return;
    final avatarBase64 = base64Encode(await photo.readAsBytes());
    if (!mounted) return;
    if (avatarBase64.length > _maxAvatarCharacters) {
      setState(() => _photoError = 'Choose a smaller photo.');
      return;
    }
    setState(() {
      _avatarBase64 = avatarBase64;
      _photoError = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Your profile'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _DeviceAvatar(avatarBase64: _avatarBase64, size: 72),
          TextButton.icon(
            onPressed: _selectPhoto,
            icon: const Icon(Icons.photo_outlined),
            label: const Text('Choose photo'),
          ),
          if (_avatarBase64 != null)
            TextButton(
              onPressed: () => setState(() => _avatarBase64 = null),
              child: const Text('Remove photo'),
            ),
          if (_photoError != null)
            Text(_photoError!, style: const TextStyle(color: Colors.red)),
          TextField(
            controller: _fieldController,
            autofocus: true,
            maxLength: 32,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              hintText: 'Name shown to nearby phones',
            ),
            onSubmitted: (_) => _submit(),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _submit,
          child: const Text('Save'),
        ),
      ],
    );
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
        leading: _DeviceAvatar(avatarBase64: peer.avatarBase64),
        title: Text(
          peer.name,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: const Text(
          'Tap to start a direct local chat',
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
  const _DeviceAvatar({this.avatarBase64, this.size = 44});

  final String? avatarBase64;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: const Color(0xFFE7F2EC),
        borderRadius: BorderRadius.circular(15),
      ),
      child: avatarBase64 == null
          ? Icon(
              Icons.person_outline_rounded,
              color: const Color(0xFF28674F),
              size: size / 2,
            )
          : ClipRRect(
              borderRadius: BorderRadius.circular(size / 3),
              child: Image.memory(
                base64Decode(avatarBase64!),
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => Icon(
                  Icons.person_outline_rounded,
                  color: const Color(0xFF28674F),
                  size: size / 2,
                ),
              ),
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
            'Paired messages are encrypted before they leave your phone. Keep your QR pairing private.',
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
