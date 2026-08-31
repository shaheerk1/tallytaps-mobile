import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/sync_config_service.dart';
import '../models/mobile_bill.dart';
import '../services/sync_diagnostics_service.dart';
import '../services/sync_service.dart';
import '../state/tally_store.dart';
import '../theme/app_colors.dart';
import 'qr_scanner_screen.dart';

/// A dedicated one-time configuration screen, intentionally reached from
/// History so recording can remain an uninterrupted offline-first workflow.
class SyncSetupScreen extends StatefulWidget {
  const SyncSetupScreen({super.key});

  @override
  State<SyncSetupScreen> createState() => _SyncSetupScreenState();
}

class _SyncSetupScreenState extends State<SyncSetupScreen> {
  final _serverController = TextEditingController();
  final _hostController = TextEditingController();
  Timer? _pollTimer;
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final connection = context.read<TallyStore>().connection;
    if (connection != null) {
      _serverController.text = connection.serverUrl;
      _hostController.text = connection.hostCode;
      if (connection.status == ConnectionStatus.pending) _beginPolling();
    }
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _serverController.dispose();
    _hostController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<TallyStore>();
    final connection = store.connection;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Server connection'),
        leading: IconButton(
          onPressed: () => Navigator.of(context).maybePop(),
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
        ),
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
          children: [
            const _IntroCard(),
            const SizedBox(height: 20),
            if (connection?.isConnected ?? false)
              _ConnectedCard(connection: connection!, store: store, onForget: _forget)
            else if (connection?.status == ConnectionStatus.pending)
              _PendingCard(
                hostCode: connection!.hostCode,
                error: _error,
                checking: _submitting,
                onCheck: _checkNow,
                onStartOver: _forget,
              )
            else
              _setupForm(),
            const SizedBox(height: 18),
            TextButton.icon(
              onPressed: _showDiagnostics,
              icon: const Icon(Icons.bug_report_outlined),
              label: const Text('View sync diagnostics'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _setupForm() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        'Connect this device',
        style: Theme.of(context).textTheme.headlineSmall?.copyWith(
          fontWeight: FontWeight.w800,
          color: AppColors.ink,
        ),
      ),
      const SizedBox(height: 6),
      const Text(
        'Scan the ticket shared by your TallyTaps host, or enter the details below.',
        style: TextStyle(color: AppColors.inkSoft, fontWeight: FontWeight.w600),
      ),
      const SizedBox(height: 18),
      OutlinedButton.icon(
        onPressed: _scanTicket,
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 17),
          side: const BorderSide(color: AppColors.brand, width: 1.5),
          foregroundColor: AppColors.brand,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        ),
        icon: const Icon(Icons.qr_code_scanner_rounded),
        label: const Text('Scan connection ticket', style: TextStyle(fontWeight: FontWeight.w800)),
      ),
      const SizedBox(height: 22),
      _label('SERVER ADDRESS'),
      const SizedBox(height: 7),
      TextField(
        controller: _serverController,
        keyboardType: TextInputType.url,
        autocorrect: false,
        enableSuggestions: false,
        decoration: const InputDecoration(
          hintText: 'https://sync.yourbusiness.com',
          prefixIcon: Icon(Icons.dns_outlined),
        ),
      ),
      const SizedBox(height: 16),
      _label('HOST ID'),
      const SizedBox(height: 7),
      TextField(
        controller: _hostController,
        textCapitalization: TextCapitalization.characters,
        autocorrect: false,
        enableSuggestions: false,
        decoration: const InputDecoration(
          hintText: 'TH-XXXXXX',
          prefixIcon: Icon(Icons.hub_outlined),
        ),
      ),
      if (_error != null) ...[
        const SizedBox(height: 12),
        _ErrorText(_error!),
      ],
      const SizedBox(height: 20),
      FilledButton.icon(
        onPressed: _submitting ? null : _requestConnection,
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.brand,
          padding: const EdgeInsets.symmetric(vertical: 17),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        ),
        icon: _submitting
            ? const SizedBox(width: 19, height: 19, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            : const Icon(Icons.link_rounded),
        label: const Text('Request connection', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
      ),
    ],
  );

  Widget _label(String value) => Text(
    value,
    style: const TextStyle(
      color: AppColors.inkFaint,
      fontSize: 12,
      letterSpacing: 0.7,
      fontWeight: FontWeight.w800,
    ),
  );

  Future<void> _scanTicket() async {
    final ticket = await Navigator.of(context).push<PairingTicket>(
      MaterialPageRoute<PairingTicket>(builder: (_) => const QrScannerScreen()),
    );
    if (ticket == null) return;
    setState(() {
      _serverController.text = ticket.serverUrl;
      _hostController.text = ticket.hostCode;
      _error = null;
    });
  }

  Future<void> _requestConnection() async {
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await context.read<TallyStore>().startPairing(
        serverUrl: _serverController.text,
        hostCode: _hostController.text,
      );
      if (mounted) _beginPolling();
    } catch (error) {
      if (mounted) setState(() => _error = _friendlyError(error));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _beginPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 3), (_) => _checkNow(silent: true));
  }

  Future<void> _checkNow({bool silent = false}) async {
    if (_submitting) return;
    if (!silent) setState(() => _submitting = true);
    try {
      await context.read<TallyStore>().checkPairing();
      if (mounted && context.read<TallyStore>().isConnected) _pollTimer?.cancel();
      if (mounted) setState(() => _error = null);
    } catch (error) {
      if (mounted && !silent) setState(() => _error = _friendlyError(error));
    } finally {
      if (mounted && !silent) setState(() => _submitting = false);
    }
  }

  Future<void> _forget() async {
    _pollTimer?.cancel();
    await context.read<TallyStore>().forgetConnection();
    if (mounted) setState(() => _error = null);
  }

  Future<void> _showDiagnostics() async {
    final diagnostics = SyncDiagnosticsService();
    final contents = await diagnostics.read();
    final location = await diagnostics.location();
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
          child: SizedBox(
            height: MediaQuery.sizeOf(context).height * 0.72,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Sync diagnostics',
                  style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 6),
                const Text(
                  'This local log omits tokens, notes, and file contents.',
                  style: TextStyle(color: AppColors.inkSoft),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF10232B),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: SingleChildScrollView(
                      child: SelectableText(
                        contents,
                        style: const TextStyle(
                          color: Color(0xFFD7EBF0),
                          fontFamily: 'monospace',
                          fontSize: 12,
                          height: 1.45,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'Local file: $location',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: AppColors.inkFaint, fontSize: 11),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _friendlyError(Object error) => error is SyncFailure
      ? error.message
      : 'Could not reach the server. Check the address and your connection.';
}

class _IntroCard extends StatelessWidget {
  const _IntroCard();

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: AppColors.brand.withValues(alpha: 0.09),
      borderRadius: BorderRadius.circular(20),
    ),
    child: const Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.offline_bolt_rounded, color: AppColors.brand, size: 26),
        SizedBox(width: 12),
        Expanded(
          child: Text(
            'Recording always works offline. Once connected, saved entries and attachments are sent quietly when the server is available.',
            style: TextStyle(color: AppColors.ink, fontWeight: FontWeight.w700, height: 1.35),
          ),
        ),
      ],
    ),
  );
}

class _PendingCard extends StatelessWidget {
  const _PendingCard({
    required this.hostCode,
    required this.error,
    required this.checking,
    required this.onCheck,
    required this.onStartOver,
  });

  final String hostCode;
  final String? error;
  final bool checking;
  final Future<void> Function() onCheck;
  final Future<void> Function() onStartOver;

  @override
  Widget build(BuildContext context) => _Card(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.hourglass_top_rounded, color: AppColors.stock, size: 34),
        const SizedBox(height: 14),
        const Text('Waiting for approval', style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        Text('A manager of $hostCode needs to approve this device. This screen checks automatically.', style: const TextStyle(color: AppColors.inkSoft, height: 1.35, fontWeight: FontWeight.w600)),
        if (error != null) ...[const SizedBox(height: 12), _ErrorText(error!)],
        const SizedBox(height: 18),
        FilledButton.icon(
          onPressed: checking ? null : onCheck,
          icon: checking ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.refresh_rounded),
          label: const Text('Check now'),
        ),
        TextButton(onPressed: onStartOver, child: const Text('Use a different host')),
      ],
    ),
  );
}

class _ConnectedCard extends StatefulWidget {
  const _ConnectedCard({required this.connection, required this.store, required this.onForget});
  final SyncConnection connection;
  final TallyStore store;
  final Future<void> Function() onForget;

  @override
  State<_ConnectedCard> createState() => _ConnectedCardState();
}

class _ConnectedCardState extends State<_ConnectedCard> {
  List<PosCatalogNode> _nodes = const [];
  bool _loadingNodes = true;
  bool _saving = false;
  String? _routingError;

  @override
  void initState() {
    super.initState();
    _loadNodes();
  }

  Future<void> _loadNodes() async {
    try {
      final nodes = await widget.store.loadPosNodes();
      if (mounted) setState(() => _nodes = nodes);
    } catch (_) {
      if (mounted) setState(() => _routingError = 'Could not refresh POS destinations.');
    } finally {
      if (mounted) setState(() => _loadingNodes = false);
    }
  }

  Future<void> _setDestination(String? value) async {
    if (value == null || _saving) return;
    setState(() { _saving = true; _routingError = null; });
    try {
      await widget.store.updateRecordRouting(
        deliveryScope: value == '__all__' ? 'all' : 'selected',
        targetPosNodeId: value == '__all__' ? null : value,
      );
    } catch (_) {
      if (mounted) setState(() => _routingError = 'Could not save the destination.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => _Card(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(children: [Icon(Icons.verified_rounded, color: AppColors.positive, size: 30), SizedBox(width: 10), Text('Connected', style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800))]),
        const SizedBox(height: 14),
        _DetailRow(label: 'HOST ID', value: widget.connection.hostCode),
        const SizedBox(height: 9),
        _DetailRow(label: 'SERVER', value: widget.connection.serverUrl),
        const SizedBox(height: 20),
        const Text('QUICK RECORD DESTINATION', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: AppColors.inkFaint, letterSpacing: 0.5)),
        const SizedBox(height: 7),
        if (_loadingNodes)
          const LinearProgressIndicator(minHeight: 3)
        else
          DropdownButtonFormField<String>(
            key: ValueKey('${widget.connection.deliveryScope}-${widget.connection.targetPosNodeIds.join(',')}'),
            initialValue: widget.connection.deliveryScope == 'selected' &&
                    widget.connection.targetPosNodeIds.isNotEmpty &&
                    _nodes.any((node) => node.id == widget.connection.targetPosNodeIds.first)
                ? widget.connection.targetPosNodeIds.first
                : '__all__',
            decoration: const InputDecoration(prefixIcon: Icon(Icons.route_rounded)),
            items: [
              const DropdownMenuItem(value: '__all__', child: Text('All connected POS systems')),
              ..._nodes.map((node) => DropdownMenuItem(value: node.id, child: Text(node.nickname))),
            ],
            onChanged: _saving ? null : _setDestination,
          ),
        const SizedBox(height: 7),
        const Text('Used automatically for cash, card, stock, and note records. Bills choose their destination during checkout.', style: TextStyle(color: AppColors.inkSoft, fontSize: 12, height: 1.35)),
        if (_routingError != null) ...[const SizedBox(height: 8), _ErrorText(_routingError!)],
        if (widget.store.unsynced.isNotEmpty) ...[
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: widget.store.syncing ? null : () => widget.store.syncPending(),
            icon: widget.store.syncing ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.sync_rounded),
            label: Text('Sync ${widget.store.unsynced.length} waiting ${widget.store.unsynced.length == 1 ? 'entry' : 'entries'}'),
          ),
        ],
        const SizedBox(height: 12),
        TextButton.icon(onPressed: widget.onForget, icon: const Icon(Icons.link_off_rounded), label: const Text('Disconnect this device')),
      ],
    ),
  );
}

class _Card extends StatelessWidget {
  const _Card({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(22), boxShadow: const [BoxShadow(color: Color(0x120D1E16), blurRadius: 18, offset: Offset(0, 8))]),
    child: child,
  );
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => Row(children: [SizedBox(width: 62, child: Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: AppColors.inkFaint))), Expanded(child: Text(value, style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.ink)))]);
}

class _ErrorText extends StatelessWidget {
  const _ErrorText(this.value);
  final String value;
  @override
  Widget build(BuildContext context) => Text(value, style: const TextStyle(color: AppColors.negative, fontWeight: FontWeight.w700));
}
