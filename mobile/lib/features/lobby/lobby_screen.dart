import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/api/api_client.dart';
import '../../core/auth/auth_gate.dart';
import '../../core/auth/auth_repository.dart';

/// The authenticated landing screen.
///
/// P0-FE-03 replaces this with the real find-match lobby. For now it keeps
/// the connectivity smoke test (identity + `/health` + nginx distribution)
/// and the logout action.
class LobbyScreen extends ConsumerStatefulWidget {
  const LobbyScreen({super.key});

  static const path = '/lobby';

  @override
  ConsumerState<LobbyScreen> createState() => _LobbyScreenState();
}

class _LobbyScreenState extends ConsumerState<LobbyScreen> {
  Map<String, dynamic>? _health;
  Map<String, dynamic>? _me;
  bool _loading = false;
  String? _error;

  // Ping results
  List<Map<String, dynamic>>? _pingResults;
  Map<String, int>? _pingCounts;
  bool _pinging = false;

  // NOTE: no auto-load on mount — the identity + health checks run only
  // when the user taps the buttons. P0-FE-03 replaces this screen with the
  // real find-match lobby.

  Future<void> _check() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final api = ref.read(apiClientProvider);
      final results = await Future.wait([api.getHealth(), api.getMe()]);
      setState(() {
        _health = results[0];
        _me = results[1];
      });
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pingInstances() async {
    setState(() {
      _pinging = true;
      _pingResults = null;
      _pingCounts = null;
    });
    try {
      final results = await ref.read(apiClientProvider).pingInstances(12);
      final counts = <String, int>{};
      for (final r in results) {
        final inst = (r['instance'] as String?) ?? 'unknown';
        counts[inst] = (counts[inst] ?? 0) + 1;
      }
      setState(() {
        _pingResults = results;
        _pingCounts = counts;
      });
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _pinging = false);
    }
  }

  Future<void> _logout() async {
    await ref.read(authRepositoryProvider).logout();
    AuthGate.instance.signalSignedOut();
    if (!mounted) return;
    context.go('/login');
  }

  @override
  Widget build(BuildContext context) {
    final ok = _health?['status'] == 'ok';
    final distinct = _pingCounts?.length ?? 0;
    final pingOk = distinct >= 2;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Auto Chess — Connect'),
        actions: [
          IconButton(
            tooltip: 'Sign out',
            icon: const Icon(Icons.logout),
            onPressed: _logout,
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_me != null) _MeCard(me: _me!),
              if (_me != null) const SizedBox(height: 16),
              Icon(
                ok ? Icons.check_circle : Icons.health_and_safety_outlined,
                size: 64,
                color: ok ? Colors.green : Colors.indigo,
              ),
              const SizedBox(height: 16),
              const Text(
                'Connectivity smoke test',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              Text(
                'Two checks: (1) backend /health through nginx, '
                '(2) 12 concurrent /whoami pings to verify nginx '
                'least_conn actually distributes across all 3 Nest instances.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: _loading ? null : _check,
                icon: _loading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.network_check),
                label: const Text('GET /health + /user/me'),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _pinging ? null : _pingInstances,
                icon: _pinging
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(
                        pingOk ? Icons.verified : Icons.cyclone,
                        color: pingOk ? Colors.green : null,
                      ),
                label: Text(
                  distinct == 0
                      ? 'Ping 12 times (proves nginx distribution)'
                      : 'Ping again (last: $distinct distinct instances)',
                ),
              ),
              const SizedBox(height: 24),
              if (_health != null)
                _JsonBlock(title: 'GET /health', data: _health!),
              if (_pingCounts != null && _pingCounts!.isNotEmpty)
                _PingDistribution(counts: _pingCounts!, results: _pingResults!),
              if (_error != null) _ErrorBlock(error: _error!),
            ],
          ),
        ),
      ),
    );
  }
}

class _MeCard extends StatelessWidget {
  final Map<String, dynamic> me;
  const _MeCard({required this.me});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.indigo.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.indigo.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.person, color: Colors.indigo, size: 18),
              const SizedBox(width: 8),
              const Text(
                'Signed in',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.indigo.shade100,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  'rating ${me['rating']}',
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            me['username'] as String,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
          ),
          Text(
            me['email'] as String,
            style: TextStyle(color: Colors.grey.shade700),
          ),
          const SizedBox(height: 4),
          Text(
            'id: ${me['id']}',
            style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
          ),
        ],
      ),
    );
  }
}

class _JsonBlock extends StatelessWidget {
  final String title;
  final Map<String, dynamic> data;
  const _JsonBlock({required this.title, required this.data});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          ...data.entries.map(
            (e) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 120,
                    child: Text(
                      '${e.key}:',
                      style: const TextStyle(fontFamily: 'monospace'),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      e.value.toString(),
                      style: const TextStyle(fontFamily: 'monospace'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PingDistribution extends StatelessWidget {
  final Map<String, int> counts;
  final List<Map<String, dynamic>> results;
  const _PingDistribution({required this.counts, required this.results});

  @override
  Widget build(BuildContext context) {
    final total = results.length;
    final entries = counts.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    final maxCount =
        entries.map((e) => e.value).reduce((a, b) => a > b ? a : b);
    final distinct = entries.length;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.indigo.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.indigo.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.cyclone, color: Colors.indigo, size: 18),
              const SizedBox(width: 8),
              const Text(
                'Nginx distribution',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              Text(
                '$distinct distinct / $total total',
                style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 12),
          for (final entry in entries) ...[
            Row(
              children: [
                SizedBox(
                  width: 80,
                  child: Text(
                    entry.key,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: entry.value / maxCount,
                      minHeight: 14,
                      backgroundColor: Colors.indigo.shade100,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        Colors.indigo.shade400,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 40,
                  child: Text(
                    '${entry.value}',
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
          ],
          const SizedBox(height: 8),
          Text(
            distinct >= 2
                ? '✓ nginx is routing to multiple instances'
                : distinct == 1
                    ? '⚠ only 1 instance answered — connection may be keep-alive pinned'
                    : 'no responses',
            style: TextStyle(
              color: distinct >= 2
                  ? Colors.green.shade700
                  : Colors.orange.shade700,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorBlock extends StatelessWidget {
  final String error;
  const _ErrorBlock({required this.error});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.red.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Error',
              style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red)),
          const SizedBox(height: 8),
          Text(error, style: const TextStyle(fontFamily: 'monospace')),
        ],
      ),
    );
  }
}
