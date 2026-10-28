import 'dart:async';
import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:cross_file/cross_file.dart';
import 'package:share_plus/share_plus.dart';

import 'package:flutter/material.dart';

import '../models/chat_message.dart';
import '../models/nearby_peer.dart';
import '../services/chat_controller.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({
    required this.controller,
    required this.peerId,
    required this.peerName,
    super.key,
  });

  final ChatController controller;
  final String peerId;
  final String peerName;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<ChatMessage> _messages = [];
  StreamSubscription<ChatMessage>? _incomingSubscription;
  bool _loading = true;
  bool _sending = false;
  bool _sendingFile = false;
  double _fileProgress = 0;

  NearbyPeer? get _activePeer {
    for (final peer in widget.controller.peers) {
      if (peer.id == widget.peerId) return peer;
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    _loadHistory();
    widget.controller.addListener(_onControllerChanged);
    _incomingSubscription = widget.controller.incomingMessages.listen((
      message,
    ) {
      if (message.peerId != widget.peerId || !mounted) return;
      setState(() => _messages.add(message));
      _scrollToLatest();
    });
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    unawaited(_incomingSubscription?.cancel());
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onControllerChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _loadHistory() async {
    final history = await widget.controller.loadMessages(widget.peerId);
    if (!mounted) return;
    setState(() {
      _messages
        ..clear()
        ..addAll(history);
      _loading = false;
    });
    _scrollToLatest();
  }

  Future<void> _send() async {
    final peer = _activePeer;
    final text = _textController.text.trim();
    if (_sending || peer == null || text.isEmpty) return;

    _textController.clear();
    setState(() => _sending = true);
    try {
      final message = await widget.controller.sendText(peer, text);
      if (!mounted) return;
      setState(() => _messages.add(message));
      _scrollToLatest();
      if (message.deliveryStatus == 'failed') {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Message not delivered. Check that both phones are on the same Wi-Fi.',
            ),
          ),
        );
      }
    } on Object {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not save or send that message.')),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }


  Future<void> _sendFile() async {
    final peer = _activePeer;
    if (_sendingFile || _sending || peer == null) return;
    final selection = await FilePicker.platform.pickFiles(allowMultiple: false, withData: true);
    if (selection == null || !mounted) return;
    final file = selection.files.single;
    final bytes = file.bytes;
    if (bytes == null || bytes.isEmpty || bytes.length > 10 * 1024 * 1024) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Choose a readable file no larger than 10 MB.'),
      ));
      return;
    }
    setState(() { _sendingFile = true; _fileProgress = 0; });
    try {
      final message = await widget.controller.sendFile(
        peer: peer,
        fileName: file.name,
        bytes: bytes,
        localPath: file.path ?? '',
        onProgress: (value) {
          if (mounted) setState(() => _fileProgress = value);
        },
      );
      if (!mounted) return;
      setState(() => _messages.add(message));
      if (message.deliveryStatus == 'failed') {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('File transfer failed. Check the Wi-Fi connection.'),
        ));
      }
      _scrollToLatest();
    } on Object catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not send file: $error')));
    } finally {
      if (mounted) setState(() { _sendingFile = false; _fileProgress = 0; });
    }
  }

  void _scrollToLatest() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final isOnline = _activePeer != null;
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.peerName,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
            Text(
              isOnline ? 'Nearby · same Wi-Fi' : 'History · currently offline',
              style: const TextStyle(
                color: Color(0xFF718078),
                fontSize: 12,
                fontWeight: FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _messages.isEmpty
                  ? _ChatEmptyState(peerOnline: isOnline)
                  : ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.fromLTRB(16, 18, 16, 20),
                      itemCount: _messages.length,
                      itemBuilder: (context, index) {
                        return _MessageBubble(message: _messages[index]);
                      },
                    ),
            ),
            _Composer(
              controller: _textController,
              enabled: isOnline && !_sending && !_sendingFile,
              sending: _sending || _sendingFile,
              fileProgress: _fileProgress,
              onAttach: _sendFile,
              onSend: _send,
            ),
          ],
        ),
      ),
    );
  }
}

class _ChatEmptyState extends StatelessWidget {
  const _ChatEmptyState({required this.peerOnline});

  final bool peerOnline;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 36),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 66,
              height: 66,
              decoration: BoxDecoration(
                color: const Color(0xFFE8F3EC),
                borderRadius: BorderRadius.circular(22),
              ),
              child: const Icon(
                Icons.chat_bubble_outline_rounded,
                color: Color(0xFF28674F),
                size: 29,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              peerOnline ? 'Say hello' : 'No messages yet',
              style: const TextStyle(
                color: Color(0xFF193B32),
                fontSize: 20,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 7),
            Text(
              peerOnline
                  ? 'Your messages go directly to this phone over the local network.'
                  : 'When this phone is nearby again, you can start a conversation.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xFF718078),
                fontSize: 14,
                height: 1.45,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message});

  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final outgoing = message.isOutgoing;
    final bubbleColor = outgoing ? const Color(0xFF176B55) : Colors.white;
    final textColor = outgoing ? Colors.white : const Color(0xFF193B32);

    return Align(
      alignment: outgoing ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.78,
        ),
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
        decoration: BoxDecoration(
          color: bubbleColor,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(18),
            topRight: const Radius.circular(18),
            bottomLeft: Radius.circular(outgoing ? 18 : 5),
            bottomRight: Radius.circular(outgoing ? 5 : 18),
          ),
          border: outgoing ? null : Border.all(color: const Color(0xFFE8ECE8)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            _MessageBody(message: message, textColor: textColor),
            const SizedBox(height: 5),
            Text(
              '${_clockTime(message.createdAt)}${outgoing ? ' · ${_statusLabel(message.deliveryStatus)}' : ''}',
              style: TextStyle(
                color: outgoing
                    ? Colors.white.withOpacity(0.76)
                    : const Color(0xFF87928B),
                fontSize: 10,
              ),
            ),
          ],
        ),
      ),
    );
  }
}


class _MessageBody extends StatelessWidget {
  const _MessageBody({required this.message, required this.textColor});
  final ChatMessage message;
  final Color textColor;

  @override
  Widget build(BuildContext context) {
    Map<String, dynamic>? attachment;
    try {
      final decoded = jsonDecode(message.body);
      if (decoded is Map<String, dynamic> && decoded['_locallink_file'] == 'v1') {
        attachment = decoded;
      }
    } on Object {
      // Ordinary text message.
    }
    if (attachment == null) {
      return Text(message.body, style: TextStyle(color: textColor, fontSize: 15, height: 1.35));
    }
    final name = attachment['name'] as String? ?? 'File';
    final path = attachment['path'] as String? ?? '';
    final size = attachment['size'] as int? ?? 0;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      const Icon(Icons.attach_file_rounded, size: 22),
      const SizedBox(width: 8),
      Flexible(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(name, style: TextStyle(color: textColor, fontWeight: FontWeight.w600)),
        Text(_formatFileSize(size), style: TextStyle(color: textColor.withValues(alpha: 0.75), fontSize: 11)),
      ])),
      if (path.isNotEmpty)
        IconButton(
          tooltip: 'Share or save file',
          onPressed: () async {
            try {
              await Share.shareXFiles([XFile(path)], text: 'Shared from LocalLink: $name');
            } on Object catch (error) {
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not share file: $error')));
            }
          },
          icon: Icon(Icons.ios_share_rounded, color: textColor),
        ),
    ]);
  }
}

String _formatFileSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.enabled,
    required this.sending,
    required this.fileProgress,
    required this.onAttach,
    required this.onSend,
  });

  final TextEditingController controller;
  final bool enabled;
  final bool sending;
  final double fileProgress;
  final VoidCallback onAttach;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
      decoration: const BoxDecoration(
        color: Color(0xFFF8F8F4),
        border: Border(top: BorderSide(color: Color(0xFFE8ECE8))),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          IconButton(
            tooltip: 'Attach file (max 10 MB)',
            onPressed: enabled ? onAttach : null,
            icon: const Icon(Icons.attach_file_rounded),
          ),
          Expanded(
            child: TextField(
              controller: controller,
              enabled: enabled,
              minLines: 1,
              maxLines: 5,
              maxLength: 4000,
              textCapitalization: TextCapitalization.sentences,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => onSend(),
              decoration: InputDecoration(
                hintText: enabled ? 'Write a message…' : 'Phone is offline',
                counterText: '',
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 17,
                  vertical: 12,
                ),
              ),
            ),
          ),
          if (sending && fileProgress > 0)
            SizedBox(width: 32, child: LinearProgressIndicator(value: fileProgress)),
          const SizedBox(width: 9),
          Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: IconButton.filled(
              tooltip: 'Send message',
              onPressed: enabled ? onSend : null,
              icon: sending
                  ? const SizedBox(
                      width: 19,
                      height: 19,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.arrow_upward_rounded),
            ),
          ),
        ],
      ),
    );
  }
}

String _clockTime(DateTime dateTime) {
  final hour = dateTime.hour % 12 == 0 ? 12 : dateTime.hour % 12;
  final minute = dateTime.minute.toString().padLeft(2, '0');
  return '$hour:$minute ${dateTime.hour >= 12 ? 'PM' : 'AM'}';
}

String _statusLabel(String status) {
  return switch (status) {
    'sending' => 'Sending',
    'sent' => 'Sent',
    'failed' => 'Not delivered',
    _ => status,
  };
}
