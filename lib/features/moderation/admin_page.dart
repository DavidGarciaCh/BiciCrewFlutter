import 'package:flutter/material.dart';
import '../../core/utils.dart';
import 'admin_report_page.dart';
import 'admin_support_page.dart';
import 'moderation_models.dart';
import 'moderation_repository.dart';

class AdminPage extends StatelessWidget {
  const AdminPage({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Administración'),
          bottom: const TabBar(tabs: [
            Tab(text: 'Reportes'),
            Tab(text: 'PQRS'),
            Tab(text: 'Registro'),
          ]),
        ),
        body: const TabBarView(children: [
          _ReportsTab(),
          _SupportTab(),
          _LogTab(),
        ]),
      ),
    );
  }
}

// Selector "Pendientes / Resueltos" que comparten las dos primeras pestañas
Widget _filterBar(String value, ValueChanged<String> onChanged,
    String closedLabel) {
  return Padding(
    padding: const EdgeInsets.all(12),
    child: SegmentedButton<String>(
      segments: [
        const ButtonSegment(value: 'open', label: Text('Pendientes')),
        ButtonSegment(value: 'closed', label: Text(closedLabel)),
      ],
      selected: {value},
      onSelectionChanged: (s) => onChanged(s.first),
    ),
  );
}

Widget _empty(String text, Future<void> Function() onRefresh) => RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(children: [
        const SizedBox(height: 100),
        Padding(
          padding: const EdgeInsets.all(24),
          child: Text(text, textAlign: TextAlign.center),
        ),
      ]),
    );

// ===================== Reportes =====================
class _ReportsTab extends StatefulWidget {
  const _ReportsTab();

  @override
  State<_ReportsTab> createState() => _ReportsTabState();
}

class _ReportsTabState extends State<_ReportsTab> {
  final _repo = ModerationRepository.instance;
  String _filter = 'open';
  List<AdminReport> _items = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final list = await _repo.adminReports(_filter);
      if (!mounted) return;
      setState(() {
        _items = list;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = errorText(e);
      });
    }
  }

  String _resolution(AdminReport r) => switch (r.action) {
        'post_hidden' => 'Publicación ocultada',
        'user_suspended' => 'Cuenta suspendida',
        _ => 'Descartado',
      };

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _filterBar(_filter, (v) {
          setState(() {
            _filter = v;
            _loading = true;
          });
          _load();
        }, 'Resueltos'),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? Center(child: Text(_error!))
                  : _items.isEmpty
                      ? _empty(
                          _filter == 'open'
                              ? 'No hay reportes pendientes.'
                              : 'Aún no hay reportes resueltos.',
                          _load)
                      : RefreshIndicator(
                          onRefresh: _load,
                          child: ListView.separated(
                            itemCount: _items.length,
                            separatorBuilder: (_, __) => const Divider(height: 1),
                            itemBuilder: (_, i) {
                              final r = _items[i];
                              return ListTile(
                                leading: CircleAvatar(
                                  child: Icon(r.isPost
                                      ? Icons.article_outlined
                                      : Icons.person_outline),
                                ),
                                title: Text(reportReasons[r.reason] ?? r.reason),
                                subtitle: Text(
                                  '${r.isPost ? 'Publicación de' : 'Usuario'} ${r.targetUserName}\n'
                                  'Reportó ${r.reporterName} · ${timeAgo(r.createdAt)}'
                                  '${r.sameTarget > 0 ? ' · +${r.sameTarget} reportes más' : ''}',
                                ),
                                isThreeLine: true,
                                trailing: r.status == 'open'
                                    ? const Icon(Icons.chevron_right)
                                    : Text(_resolution(r),
                                        style: Theme.of(context).textTheme.bodySmall),
                                onTap: () async {
                                  final changed = await Navigator.push<bool>(
                                    context,
                                    MaterialPageRoute(
                                        builder: (_) =>
                                            AdminReportPage(report: r)),
                                  );
                                  if (changed == true) _load();
                                },
                              );
                            },
                          ),
                        ),
        ),
      ],
    );
  }
}

// ===================== PQRS =====================
class _SupportTab extends StatefulWidget {
  const _SupportTab();

  @override
  State<_SupportTab> createState() => _SupportTabState();
}

class _SupportTabState extends State<_SupportTab> {
  final _repo = ModerationRepository.instance;
  String _filter = 'open';
  List<SupportRequest> _items = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final list = await _repo.adminSupport(_filter);
      if (!mounted) return;
      setState(() {
        _items = list;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = errorText(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _filterBar(_filter, (v) {
          setState(() {
            _filter = v;
            _loading = true;
          });
          _load();
        }, 'Atendidas'),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? Center(child: Text(_error!))
                  : _items.isEmpty
                      ? _empty('No hay solicitudes en esta lista.', _load)
                      : RefreshIndicator(
                          onRefresh: _load,
                          child: ListView.separated(
                            itemCount: _items.length,
                            separatorBuilder: (_, __) => const Divider(height: 1),
                            itemBuilder: (_, i) {
                              final s = _items[i];
                              return ListTile(
                                leading: const CircleAvatar(
                                    child: Icon(Icons.support_agent)),
                                title: Text(s.reason),
                                subtitle: Text(
                                  '${supportKinds[s.kind]} · ${s.userName ?? ''}\n'
                                  '${supportStatusLabels[s.status]} · ${timeAgo(s.createdAt)}',
                                ),
                                isThreeLine: true,
                                trailing: const Icon(Icons.chevron_right),
                                onTap: () async {
                                  final changed = await Navigator.push<bool>(
                                    context,
                                    MaterialPageRoute(
                                        builder: (_) =>
                                            AdminSupportPage(request: s)),
                                  );
                                  if (changed == true) _load();
                                },
                              );
                            },
                          ),
                        ),
        ),
      ],
    );
  }
}

// ===================== Registro (bitácora) =====================
class _LogTab extends StatefulWidget {
  const _LogTab();

  @override
  State<_LogTab> createState() => _LogTabState();
}

class _LogTabState extends State<_LogTab> {
  List<ModerationLogEntry> _items = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final list = await ModerationRepository.instance.adminLog();
      if (!mounted) return;
      setState(() {
        _items = list;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = errorText(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return Center(child: Text(_error!));
    if (_items.isEmpty) {
      return _empty('Todavía no hay acciones registradas.', _load);
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        itemCount: _items.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (_, i) {
          final e = _items[i];
          return ListTile(
            leading: const Icon(Icons.history),
            title: Text(moderationActionLabels[e.action] ?? e.action),
            subtitle: Text(
              '${e.targetName.isEmpty ? '' : 'Sobre ${e.targetName} · '}'
              'por ${e.adminName} · ${timeAgo(e.createdAt)}'
              '${e.note == null ? '' : '\n“${e.note}”'}',
            ),
            isThreeLine: e.note != null,
          );
        },
      ),
    );
  }
}