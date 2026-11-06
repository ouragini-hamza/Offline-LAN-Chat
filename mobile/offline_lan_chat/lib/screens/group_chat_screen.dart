import 'dart:async';

import 'package:flutter/material.dart';

import '../models/chat_message.dart';
import '../services/chat_controller.dart';
import '../services/group_store.dart';

class GroupChatScreen extends StatefulWidget {
  const GroupChatScreen({required this.controller, required this.group, super.key});
  final ChatController controller;
  final LocalGroup group;
  @override
  State<GroupChatScreen> createState() => _GroupChatScreenState();
}

class _GroupChatScreenState extends State<GroupChatScreen> {
  final _textController = TextEditingController();
  final _scrollController = ScrollController();
  final List<ChatMessage> _messages = [];
  StreamSubscription<ChatMessage>? _subscription;
  bool _loading = true;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _loadHistory();
    _subscription = widget.controller.incomingMessages.listen((message) {
      if (!mounted || message.peerId != 'group:${widget.group.id}') return;
      setState(() => _messages.add(message));
      _scrollToEnd();
    });
  }

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadHistory() async {
    final history = await widget.controller.loadMessages('group:${widget.group.id}');
    if (!mounted) return;
    setState(() { _messages..clear()..addAll(history); _loading = false; });
    _scrollToEnd();
  }

  Future<void> _send() async {
    final text = _textController.text.trim();
    if (_sending || text.isEmpty) return;
    _textController.clear();
    setState(() => _sending = true);
    try {
      final message = await widget.controller.sendGroupText(widget.group, text);
      if (!mounted) return;
      setState(() => _messages.add(message));
      if (message.deliveryStatus == 'failed') {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('No group member is currently reachable, or delivery failed.'),
        ));
      }
      _scrollToEnd();
    } on Object catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not send group message: $error')));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(_scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(widget.group.name, style: const TextStyle(fontWeight: FontWeight.w700)),
      Text('${widget.group.memberIds.length} members · LAN only',
        style: const TextStyle(fontSize: 12, color: Color(0xFF718078))),
    ])),
    body: SafeArea(child: Column(children: [
      Expanded(child: _loading
        ? const Center(child: CircularProgressIndicator())
        : _messages.isEmpty
          ? const Center(child: Padding(padding: EdgeInsets.all(24), child: Text(
              'Messages go directly to online group members on the same Wi-Fi.', textAlign: TextAlign.center)))
          : ListView.builder(
              controller: _scrollController, padding: const EdgeInsets.all(16), itemCount: _messages.length,
              itemBuilder: (context, index) {
                final message = _messages[index];
                final outgoing = message.isOutgoing;
                return Align(
                  alignment: outgoing ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * .8),
                    margin: const EdgeInsets.only(bottom: 9), padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: outgoing ? const Color(0xFF176B55) : Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: outgoing ? null : Border.all(color: const Color(0xFFE8ECE8)),
                    ),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                      Text(message.body, style: TextStyle(color: outgoing ? Colors.white : const Color(0xFF193B32))),
                      const SizedBox(height: 4),
                      Text(message.deliveryStatus, style: TextStyle(fontSize: 10, color: outgoing ? Colors.white70 : Colors.black45)),
                    ]),
                  ),
                );
              },
            )),
      Container(padding: const EdgeInsets.all(12), child: Row(children: [
        Expanded(child: TextField(
          controller: _textController, enabled: !_sending, maxLength: 3500, maxLines: 4, minLines: 1,
          decoration: const InputDecoration(hintText: 'Message the group', counterText: ''),
          onSubmitted: (_) => _send(),
        )),
        const SizedBox(width: 8),
        IconButton.filled(onPressed: _sending ? null : _send, icon: _sending
          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
          : const Icon(Icons.send_rounded)),
      ])),
    ])),
  );
}
