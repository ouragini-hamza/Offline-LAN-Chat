import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../services/chat_controller.dart';

class IdentityQrScreen extends StatefulWidget {
  const IdentityQrScreen({required this.controller, super.key});
  final ChatController controller;
  @override
  State<IdentityQrScreen> createState() => _IdentityQrScreenState();
}
class _IdentityQrScreenState extends State<IdentityQrScreen> {
  bool _scanning = false;
  bool _handled = false;
  String? _status;
  String get _payload => jsonEncode({
    'protocol': 'locallink-identity-v1',
    'id': widget.controller.identity.id,
    'name': widget.controller.identity.name,
    'public_key': widget.controller.identity.publicKey,
  });
  Future<void> _handleCode(String raw) async {
    if (_handled) return;
    _handled = true;
    try {
      final data = jsonDecode(raw) as Map<String, dynamic>;
      if (data['protocol'] != 'locallink-identity-v1' || data['id'] is! String ||
          data['name'] is! String || data['public_key'] is! String ||
          data['id'] == widget.controller.identity.id) {
        throw const FormatException('Not a valid LocalLink identity QR.');
      }
      await widget.controller.trustPeer(id: data['id'] as String, name: data['name'] as String, publicKey: data['public_key'] as String);
      if (!mounted) return;
      setState(() { _scanning = false; _status = 'Trusted identity saved for ' + (data['name'] as String) + '.'; });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _status = 'Could not trust this QR: $error');
      _handled = false;
    }
  }
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Secure pairing')),
    body: ListView(padding: const EdgeInsets.all(20), children: [
      const Text('Show your identity QR to your friend. Your private key never appears in the QR.', style: TextStyle(fontSize: 15, height: 1.4)),
      const SizedBox(height: 18),
      Center(child: Container(color: Colors.white, padding: const EdgeInsets.all(12), child: QrImageView(data: _payload, size: 240))),
      const SizedBox(height: 8),
      SelectableText('Device: ' + widget.controller.identity.name + String.fromCharCode(10) + 'ID: ' + widget.controller.identity.id, textAlign: TextAlign.center),
      const SizedBox(height: 22),
      FilledButton.icon(onPressed: () => setState(() { _scanning = true; _handled = false; _status = null; }), icon: const Icon(Icons.qr_code_scanner), label: const Text('Scan friend’s QR')),
      if (_scanning) ...[
        const SizedBox(height: 16),
        SizedBox(height: 300, child: ClipRRect(borderRadius: BorderRadius.circular(16), child: MobileScanner(onDetect: (capture) { final raw = capture.barcodes.isNotEmpty ? capture.barcodes.first.rawValue : null; if (raw != null) _handleCode(raw); }))),
        TextButton(onPressed: () => setState(() => _scanning = false), child: const Text('Cancel scan')),
      ],
      if (_status != null) ...[const SizedBox(height: 12), Text(_status!, style: const TextStyle(height: 1.4))],
      const SizedBox(height: 16),
      const Text('Only scan a QR shown directly by the person you intend to trust. Pairing stores their public key; it does not use the internet.', style: TextStyle(color: Colors.black54, height: 1.4)),
    ]),
  );
}