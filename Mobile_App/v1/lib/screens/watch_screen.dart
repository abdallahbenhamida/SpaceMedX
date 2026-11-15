import 'package:flutter/material.dart';

import '../core/settings.dart';
import '../l10n/l10n.dart';
import '../theme/app_theme.dart';
import '../watch/watch_link.dart';

/// Pairing of the Galaxy Watch, step by step. After pairing, START on the
/// Home screen reconnects to it by itself.
class WatchScreen extends StatefulWidget {
  const WatchScreen({super.key, WatchLink? link}) : _link = link;
  final WatchLink? _link;

  @override
  State<WatchScreen> createState() => _WatchScreenState();
}

class _WatchScreenState extends State<WatchScreen> {
  late final WatchLink _w = widget._link ?? WatchLink.instance;

  @override
  void initState() {
    super.initState();
    _w.load().then((_) {
      if (!mounted) return;
      if (_w.phase == WatchPhase.idle || _w.phase == WatchPhase.failed) {
        // a known watch: reconnect, otherwise search
        _w.savedAddress != null ? _w.connectSaved() : _w.startScan();
      }
    });
  }

  @override
  void dispose() {
    // leave the watch connected only if pairing worked; otherwise let go
    if (_w.phase != WatchPhase.ready) {
      _w.stopScan();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(title: Text(tr('Galaxy Watch'))),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: Listenable.merge([_w, AppSettings.instance]),
          builder: (context, _) => ListView(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
            children: _content(),
          ),
        ),
      ),
    );
  }

  List<Widget> _content() {
    switch (_w.phase) {
      case WatchPhase.scanning:
        return [
          _banner(Icons.search, 'Looking for your watch …', SpaceColors.cyan,
              'On the watch, open the health companion app and keep the screen on.'),
          const SizedBox(height: 16),
          for (final r in _w.found)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _bigChoice(
                Icons.watch,
                r.name.isEmpty ? 'Galaxy Watch' : r.name,
                'Tap to connect',
                () => _w.connect(r.address, name: r.name),
              ),
            ),
          const SizedBox(height: 8),
          const Center(child: CircularProgressIndicator()),
        ];
      case WatchPhase.connecting:
        return [
          _banner(Icons.sync, 'Connecting …', SpaceColors.cyan,
              _w.message.isEmpty ? 'Please wait.' : _w.message),
          const SizedBox(height: 24),
          const Center(child: CircularProgressIndicator()),
        ];
      case WatchPhase.needApproval:
        return [
          _banner(
            Icons.link,
            _w.pairingClosed ? 'Open the app on the watch' : 'Pair this watch',
            SpaceColors.warn,
            _w.message,
          ),
          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: _w.pairingClosed ? null : _w.requestPairing,
            icon: const Icon(Icons.link),
            label: Text(tr('Pair the watch')),
          ),
          const SizedBox(height: 12),
          OutlinedButton(onPressed: _w.startScan, child: Text(tr('Search again'))),
        ];
      case WatchPhase.waitingApproval:
        return [
          _banner(Icons.watch, 'Confirm on the watch', SpaceColors.cyan,
              'The watch must show this code. Tap the check mark on the watch.'),
          const SizedBox(height: 24),
          Center(
            child: Text(
              _w.pairCode ?? '------',
              style: const TextStyle(fontSize: 56, fontWeight: FontWeight.w900, letterSpacing: 8),
            ),
          ),
        ];
      case WatchPhase.ready:
        return [
          _banner(Icons.check_circle, 'Watch connected', SpaceColors.go,
              tr('{name} is ready. Press START on the home screen to collect data.',
                  {'name': _w.watchName.isEmpty ? tr('Your watch') : _w.watchName})),
          const SizedBox(height: 18),
          if (_w.params.isEmpty)
            Text(tr('The watch reports no usable sensor right now.'),
                style: const TextStyle(color: SpaceColors.muted, fontSize: 16))
          else ...[
            Text(tr('Data from the watch'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            for (final p in _w.params)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.favorite, color: SpaceColors.blue),
                title: Text(tr(p.name), style: const TextStyle(fontSize: 17)),
                trailing: const Icon(Icons.check, color: SpaceColors.go),
              ),
          ],
          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: () => Navigator.of(context).maybePop(),
            icon: const Icon(Icons.check),
            label: Text(tr('Done')),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () async {
              await _w.unpair();
              await _w.startScan();
            },
            icon: const Icon(Icons.link_off),
            label: Text(tr('Use a different watch')),
          ),
        ];
      case WatchPhase.failed:
        return [
          _banner(Icons.info_outline, 'No connection', SpaceColors.warn,
              _w.message.isEmpty ? 'The watch could not be reached.' : _w.message),
          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: _w.savedAddress != null ? _w.connectSaved : _w.startScan,
            icon: const Icon(Icons.refresh),
            label: Text(tr('Try again')),
          ),
          const SizedBox(height: 12),
          OutlinedButton(onPressed: _w.startScan, child: Text(tr('Search for the watch'))),
        ];
      case WatchPhase.idle:
        return [
          _banner(Icons.watch, 'Connect your watch', SpaceColors.blue,
              _w.message.isEmpty
                  ? 'On the watch, open the health companion app and keep the screen on.'
                  : _w.message),
          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: _w.startScan,
            icon: const Icon(Icons.search),
            label: Text(tr('Search for the watch')),
          ),
        ];
    }
  }

  Widget _banner(IconData icon, String title, Color color, String text) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 40),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(tr(title), style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: color)),
                  const SizedBox(height: 6),
                  Text(tr(text), style: const TextStyle(fontSize: 16, color: SpaceColors.muted)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _bigChoice(IconData icon, String title, String sub, VoidCallback onTap) {
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(icon, color: SpaceColors.blue, size: 32),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(tr(title), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                    Text(tr(sub), style: const TextStyle(fontSize: 14, color: SpaceColors.muted)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: SpaceColors.muted),
            ],
          ),
        ),
      ),
    );
  }
}
