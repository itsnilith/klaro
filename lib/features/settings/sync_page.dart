import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/db.dart';
import '../../core/state.dart';
import '../../design/smooth_scroll.dart';
import '../../design/tokens.dart';
import '../../design/widgets.dart';
import '../../services/sync.dart';

class SyncSettings extends StatefulWidget {
  const SyncSettings({super.key});

  @override
  State<SyncSettings> createState() => _SyncSettingsState();
}

class _SyncSettingsState extends State<SyncSettings> {
  SyncHost? _host;
  List<Map<String, Object?>> _devices = const [];
  final _code = TextEditingController();
  bool _busy = false;
  String? _message;
  bool _messageIsError = false;

  @override
  void initState() {
    super.initState();
    _host = SyncHost.running;
    _load();
  }

  Future<void> _load() async {
    if (_host == null && AppState.i.syncActive) {
      try {
        _host = await SyncHost.start(port: AppState.i.syncPort);
      } catch (_) {}
    }
    final devices = await Store.i.devices();
    if (!mounted) return;
    setState(() {
      _devices = devices;
    });
  }

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return MSmoothScrollView(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Device sync', style: MType.h1.copyWith(color: c.ink, fontSize: 26)),
          const SizedBox(height: 4),
          Text(
            'Move your notes, courses and cards between your own devices. Directly, over your network.',
            style: MType.small.copyWith(color: c.inkMuted),
          ),
          const SizedBox(height: 18),
          _EncryptionBanner(),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth > 720;
              final share = _ShareCard(
                host: _host,
                busy: _busy,
                onToggle: _toggleHost,
              );
              final join = _JoinCard(
                code: _code,
                busy: _busy,
                onPair: _pair,
              );
              if (!wide) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [share, const SizedBox(height: 14), join],
                );
              }
              return IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(flex: 11, child: share),
                    const SizedBox(width: 14),
                    Expanded(flex: 9, child: join),
                  ],
                ),
              );
            },
          ),
          if (_message != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: _messageIsError ? c.dangerSoft : c.surfaceAlt,
                borderRadius: BorderRadius.circular(MRadius.md),
                border: Border.all(color: _messageIsError ? c.danger : c.line),
              ),
              child: Row(
                children: [
                  Icon(
                    _messageIsError ? Icons.error_outline_rounded : Icons.check_circle_outline_rounded,
                    size: 16,
                    color: _messageIsError ? c.danger : c.success,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _message!,
                      style: MType.small.copyWith(
                        color: _messageIsError ? c.danger : c.ink,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 22),
          Row(
            children: [
              Text('Paired devices', style: MType.h3.copyWith(color: c.ink, fontSize: 15)),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: c.surfaceSunken,
                  borderRadius: BorderRadius.circular(MRadius.pill),
                ),
                child: Text(
                  '${_devices.where((d) => (d['revoked'] as int? ?? 0) == 0).length}',
                  style: MType.small.copyWith(color: c.inkMuted, fontSize: 10.5),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (_devices.isEmpty)
            MCard(
              padding: const EdgeInsets.all(18),
              child: Row(
                children: [
                  Icon(Icons.devices_other_rounded, size: 20, color: c.inkFaint),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'No device paired yet. Start sharing on this computer, then scan the QR code or enter the 6-digit code on the other device.',
                      style: MType.small.copyWith(color: c.inkMuted, fontSize: 12, height: 1.45),
                    ),
                  ),
                ],
              ),
            )
          else
            for (final d in _devices) ...[
              _DeviceRow(
                device: d,
                onSync: () => _syncNow(d),
                onRevoke: () async {
                  await Store.i.revokeDevice(d['id'] as String);
                  _load();
                },
              ),
              const SizedBox(height: 8),
            ],
        ],
      ),
    );
  }

  Future<void> _toggleHost() async {
    setState(() => _busy = true);
    try {
      if (_host == null) {
        final host = await SyncHost.start(port: AppState.i.syncPort);
        setState(() {
          _host = host;
          _message = 'Sharing is active. Your QR code and 6-digit code stay persistent across restarts until you stop sharing.';
          _messageIsError = false;
        });
      } else {
        await SyncHost.stop(clearPersisted: true);
        setState(() {
          _host = null;
          _message = 'Sharing stopped manually.';
          _messageIsError = false;
        });
      }
    } catch (e) {
      setState(() {
        _message = 'Could not start sharing: $e';
        _messageIsError = true;
      });
    } finally {
      setState(() => _busy = false);
    }
  }

  Future<void> _pair() async {
    final input = _code.text.trim();
    if (input.isEmpty) return;
    setState(() {
      _busy = true;
      _message = 'Searching for device on your local network…';
      _messageIsError = false;
    });
    try {
      await SyncClient.pairByCodeOrToken(
        input: input,
        defaultPort: AppState.i.syncPort,
        myName: AppState.i.deviceName,
      );
      _code.clear();
      setState(() {
        _message = 'Device paired over E2EE.';
        _messageIsError = false;
      });
      _load();
    } catch (e) {
      setState(() {
        _message = 'Pairing failed: $e';
        _messageIsError = true;
      });
    } finally {
      setState(() => _busy = false);
    }
  }

  Future<void> _syncNow(Map<String, Object?> device) async {
    final address = await Store.i.metaGet('sync_host') ?? '';
    if (address.isEmpty) {
      setState(() {
        _message = 'Pair the device first so klaro. knows its local route.';
        _messageIsError = true;
      });
      return;
    }
    setState(() {
      _busy = true;
      _message = 'Syncing over E2EE…';
      _messageIsError = false;
    });
    try {
      final result = await SyncClient.pull(address: address, port: AppState.i.syncPort);
      setState(() {
        _message =
            'Synced ${result.notes} notes, ${result.courses} courses, ${result.cards} cards.';
        _messageIsError = false;
      });
      AppState.i.bump();
      _load();
    } catch (e) {
      setState(() {
        _message = 'Sync failed: $e';
        _messageIsError = true;
      });
    } finally {
      setState(() => _busy = false);
    }
  }
}

class _EncryptionBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return MCard(
      padding: const EdgeInsets.all(18),
      radius: MRadius.xl,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: c.surfaceSunken,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(Icons.lock_outline_rounded, size: 20, color: c.ink),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'End-to-end encrypted',
                  style: MType.h3.copyWith(color: c.ink, fontSize: 15),
                ),
                const SizedBox(height: 4),
                Text(
                  'Your devices agree on a secret key when you pair. Everything after that is sealed with AES-256-GCM, '
                  'and nothing passes through any external server.',
                  style: MType.small.copyWith(
                    color: c.inkMuted,
                    fontSize: 11.5,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 14,
                  runSpacing: 6,
                  children: const [
                    _Fact(label: 'X25519 key exchange'),
                    _Fact(label: 'AES-256-GCM'),
                    _Fact(label: 'No cloud relay'),
                    _Fact(label: 'Persistent until stopped'),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ShareCard extends StatelessWidget {
  const _ShareCard({
    required this.host,
    required this.busy,
    required this.onToggle,
  });

  final SyncHost? host;
  final bool busy;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final active = host != null;
    final qrPayload = active
        ? 'klaro://pair?host=${host!.addresses.firstOrNull ?? '127.0.0.1'}&port=${host!.port}&code=${host!.pairingCode}'
        : '';

    return MCard(
      padding: const EdgeInsets.all(18),
      radius: MRadius.xl,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Share this device', style: MType.h3.copyWith(color: c.ink, fontSize: 15)),
              const Spacer(),
              MButton(
                label: active ? 'Stop sharing' : 'Start sharing',
                icon: active ? Icons.stop_rounded : Icons.wifi_tethering_rounded,
                kind: active ? MButtonKind.secondary : MButtonKind.primary,
                dense: true,
                onPressed: busy ? null : onToggle,
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            active
                ? 'Active across restarts with the same code until you click Stop sharing.'
                : 'Turn on sharing to get a persistent QR code and 6-digit pairing code.',
            style: MType.small.copyWith(color: c.inkMuted, fontSize: 11.5),
          ),
          const SizedBox(height: 16),
          if (!active)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 34),
              decoration: BoxDecoration(
                color: c.surfaceAlt,
                borderRadius: BorderRadius.circular(MRadius.lg),
                border: Border.all(color: c.line),
              ),
              child: Column(
                children: [
                  Icon(Icons.qr_code_2_rounded, size: 46, color: c.inkFaint),
                  const SizedBox(height: 10),
                  Text(
                    'Click Start sharing to display your QR code and 6-digit code.',
                    style: MType.small.copyWith(color: c.inkMuted, fontSize: 11.5),
                  ),
                ],
              ),
            )
          else
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(MRadius.md),
                    border: Border.all(color: c.line),
                  ),
                  child: QrImageView(
                    data: qrPayload,
                    size: 136,
                    backgroundColor: Colors.white,
                    padding: EdgeInsets.zero,
                    eyeStyle: const QrEyeStyle(
                      eyeShape: QrEyeShape.square,
                      color: Color(0xFF18181B),
                    ),
                    dataModuleStyle: const QrDataModuleStyle(
                      dataModuleShape: QrDataModuleShape.square,
                      color: Color(0xFF18181B),
                    ),
                  ),
                ),
                const SizedBox(width: 18),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('PERSISTENT PAIRING CODE',
                          style: MType.label.copyWith(color: c.inkFaint, fontSize: 9)),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Text(
                            host!.pairingCode,
                            style: MType.h1.copyWith(
                              color: c.ink,
                              fontSize: 30,
                              letterSpacing: 4,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(width: 4),
                          MIconButton(
                            icon: Icons.copy_rounded,
                            size: 30,
                            tooltip: 'Copy 6-digit code',
                            onPressed: () {
                              Clipboard.setData(ClipboardData(text: host!.pairingCode));
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      MButton(
                        label: 'Copy QR pairing link',
                        icon: Icons.qr_code_rounded,
                        dense: true,
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: qrPayload));
                        },
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Scan the QR code with your phone or enter the 6-digit code on another computer. Both methods work simultaneously.',
                        style: MType.small.copyWith(
                          color: c.inkMuted,
                          fontSize: 11,
                          height: 1.45,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

/// Join card with both QR scan/paste and 6-digit code available at the same time — NO IP address field.
class _JoinCard extends StatelessWidget {
  const _JoinCard({
    required this.code,
    required this.busy,
    required this.onPair,
  });

  final TextEditingController code;
  final bool busy;
  final VoidCallback onPair;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return MCard(
      padding: const EdgeInsets.all(18),
      radius: MRadius.xl,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Connect to another device', style: MType.h3.copyWith(color: c.ink, fontSize: 15)),
          const SizedBox(height: 4),
          Text(
            'Use either the 6-digit pairing code or the QR code — Klaro discovers the device automatically on your network.',
            style: MType.small.copyWith(color: c.inkMuted, fontSize: 11.5),
          ),
          const SizedBox(height: 16),
          Text('OPTION 1 · 6-DIGIT PAIRING CODE',
              style: MType.label.copyWith(color: c.inkFaint, fontSize: 9)),
          const SizedBox(height: 6),
          TextField(
            controller: code,
            style: MType.bodyStrong.copyWith(color: c.ink, fontSize: 14, letterSpacing: 2),
            decoration: const InputDecoration(
              hintText: 'Enter other device code',
              isDense: true,
              prefixIcon: Icon(Icons.password_rounded, size: 17),
            ),
            onSubmitted: (_) => onPair(),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              MButton(
                label: busy ? 'Connecting…' : 'Pair with code',
                icon: Icons.link_rounded,
                kind: MButtonKind.primary,
                onPressed: busy ? null : onPair,
              ),
              MButton(
                label: 'Paste QR link',
                icon: Icons.qr_code_scanner_rounded,
                onPressed: busy
                    ? null
                    : () async {
                        final clip = await Clipboard.getData(Clipboard.kTextPlain);
                        final txt = clip?.text?.trim() ?? '';
                        if (txt.isNotEmpty) {
                          code.text = txt;
                          onPair();
                        }
                      },
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: c.surfaceAlt,
              borderRadius: BorderRadius.circular(MRadius.md),
              border: Border.all(color: c.line),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.phone_iphone_rounded, size: 16, color: c.inkMuted),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Option 2 · Mobile QR: point the klaro. mobile app camera at the QR code on the left to pair instantly without typing.',
                    style: MType.small.copyWith(
                      color: c.inkMuted,
                      fontSize: 11,
                      height: 1.45,
                    ),
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

class _DeviceRow extends StatelessWidget {
  const _DeviceRow({
    required this.device,
    required this.onSync,
    required this.onRevoke,
  });

  final Map<String, Object?> device;
  final VoidCallback onSync;
  final VoidCallback onRevoke;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final revoked = (device['revoked'] as int? ?? 0) == 1;
    return MCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: c.surfaceSunken,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              Icons.devices_rounded,
              size: 17,
              color: revoked ? c.inkFaint : c.ink,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  device['name'] as String? ?? 'Device',
                  style: MType.bodyStrong.copyWith(
                    color: revoked ? c.inkFaint : c.ink,
                    fontSize: 12.5,
                  ),
                ),
                Text(
                  revoked
                      ? 'Revoked'
                      : 'Paired ${relativeDate(DateTime.fromMillisecondsSinceEpoch(device['paired_at'] as int))}',
                  style: MType.small.copyWith(color: c.inkFaint, fontSize: 10.5),
                ),
              ],
            ),
          ),
          if (!revoked) ...[
            MButton(label: 'Sync now', dense: true, onPressed: onSync),
            const SizedBox(width: 4),
          ],
          MIconButton(
            icon: Icons.link_off_rounded,
            size: 30,
            tooltip: 'Revoke',
            onPressed: revoked ? null : onRevoke,
          ),
        ],
      ),
    );
  }
}
/// A plain fact, not a control: a quiet dot and a label, no pill or border.
class _Fact extends StatelessWidget {
  const _Fact({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 5,
          height: 5,
          decoration: BoxDecoration(color: c.inkFaint, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: MType.small.copyWith(color: c.inkMuted, fontSize: 10.5),
        ),
      ],
    );
  }
}