import 'package:flutter/material.dart';

import '../core/server_client.dart';
import '../core/settings.dart';
import '../l10n/l10n.dart';
import '../theme/app_theme.dart';

/// Server address, user ID and a "test the connection" button. Both fields
/// may stay empty: the server is optional.
class ServerFields extends StatefulWidget {
  const ServerFields({super.key});

  @override
  State<ServerFields> createState() => _ServerFieldsState();
}

class _ServerFieldsState extends State<ServerFields> {
  final _s = AppSettings.instance;
  late final _server = TextEditingController(text: _s.serverUrl);
  late final _user = TextEditingController(text: _s.userId);

  bool _testing = false;
  ({bool ok, String message})? _test;

  @override
  void dispose() {
    _server.dispose();
    _user.dispose();
    super.dispose();
  }

  Future<void> _runTest() async {
    FocusScope.of(context).unfocus();
    setState(() {
      _testing = true;
      _test = null;
    });
    final r = await ServerClient.instance.testConnection(_server.text);
    if (!mounted) return;
    setState(() {
      _testing = false;
      _test = r;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _server,
          keyboardType: TextInputType.url,
          autocorrect: false,
          enableSuggestions: false,
          textInputAction: TextInputAction.next,
          textDirection: TextDirection.ltr,
          decoration: InputDecoration(
            labelText: tr('Server address'),
            hintText: 'https://your-server.org/measurement/save/',
            prefixIcon: const Icon(Icons.link),
          ),
          onChanged: (v) {
            _s.update(serverUrl: v);
            if (_test != null) setState(() => _test = null);
          },
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _user,
          autocorrect: false,
          enableSuggestions: false,
          textDirection: TextDirection.ltr,
          decoration: InputDecoration(
            labelText: tr('Your user ID'),
            hintText: tr('for example 1234'),
            prefixIcon: const Icon(Icons.badge_outlined),
          ),
          onChanged: (v) => _s.update(userId: v),
        ),
        const SizedBox(height: 14),
        OutlinedButton.icon(
          onPressed: _testing ? null : _runTest,
          icon: _testing
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.5))
              : const Icon(Icons.wifi_tethering),
          label: Text(_testing ? tr('Checking …') : tr('Test the connection')),
        ),
        if (_test != null) ...[
          const SizedBox(height: 10),
          Row(
            children: [
              Icon(_test!.ok ? Icons.check_circle : Icons.info_outline,
                  color: _test!.ok ? SpaceColors.go : SpaceColors.warn),
              const SizedBox(width: 8),
              Expanded(
                child: Text(_test!.message,
                    style: TextStyle(fontSize: 16, color: _test!.ok ? SpaceColors.go : SpaceColors.warn)),
              ),
            ],
          ),
        ],
      ],
    );
  }
}
