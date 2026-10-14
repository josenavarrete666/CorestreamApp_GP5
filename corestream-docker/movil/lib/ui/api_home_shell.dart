import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/api_models.dart';
import '../providers.dart';
import '../services/api_websocket_service.dart';
import 'settings_sheet.dart';

class ApiHomeShell extends ConsumerStatefulWidget {
  const ApiHomeShell({super.key});
  @override
  ConsumerState<ApiHomeShell> createState() => _ApiHomeShellState();
}

class _ApiHomeShellState extends ConsumerState<ApiHomeShell> {
  int _index = 0;
  bool _mutating = false;
  Future<void> _action(Future<void> Function() operation) async {
    if (_mutating) return;
    setState(() => _mutating = true);
    try { await operation(); } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$error')));
    } finally { if (mounted) setState(() => _mutating = false); }
  }
  void _refresh() {
    ref.invalidate(applicationsProvider);
    ref.invalidate(apiNotificationsProvider);
    ref.invalidate(unreadCountProvider);
  }
  @override
  Widget build(BuildContext context) {
    final s = ref.watch(stringsProvider);
    final session = ref.watch(authControllerProvider);
    final ws = ref.watch(apiWebsocketProvider);
    final status = ref.watch(websocketStatusProvider).valueOrNull ?? ws?.status ?? WsStatus.connecting;
    final unread = ref.watch(unreadCountProvider);
    ref.listen(liveApiNotificationProvider, (_, next) {
      next.whenData((notification) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(notification.message)));
      });
    });
    return Listener(onPointerDown: (_) => ws?.activity(), onPointerSignal: (_) => ws?.activity(),
      child: Scaffold(
        appBar: AppBar(title: const Text('CoreStream'), actions: [
          IconButton(tooltip: s('refresh'), onPressed: _refresh, icon: const Icon(Icons.refresh)),
          IconButton(tooltip: s('settings'), onPressed: () => showSettingsSheet(context, ref), icon: const Icon(Icons.settings_outlined)),
          IconButton(tooltip: s('logout'), onPressed: () => ref.read(authControllerProvider.notifier).logout(), icon: const Icon(Icons.logout)),
        ]),
        body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(padding: const EdgeInsets.fromLTRB(16, 12, 16, 8), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(session.user!.fullName, style: Theme.of(context).textTheme.titleLarge),
            Text('${session.profile!.email} · ${s('role_${session.profile!.role}')}'),
            Row(children: [
              Flexible(child: Text(s('ws_${status.name}'), style: Theme.of(context).textTheme.bodySmall)),
              if (status == WsStatus.idle || status == WsStatus.failed) TextButton(onPressed: () => ws?.activity(), child: Text(s('resume_ws'))),
              const Spacer(),
              unread.when(data: (value) => Text('${s('unread')}: $value'), loading: () => const Text('…'),
                error: (error, _) => Tooltip(message: '$error', child: const Icon(Icons.error_outline))),
            ]),
          ])),
          Expanded(child: _index == 0 ? _applications() : _notifications()),
        ]),
        bottomNavigationBar: NavigationBar(selectedIndex: _index, onDestinationSelected: (i) => setState(() => _index = i), destinations: [
          NavigationDestination(icon: const Icon(Icons.apps_outlined), label: s('applications')),
          NavigationDestination(icon: const Icon(Icons.notifications_outlined), label: s('notifications')),
        ]),
      ));
  }
  Widget _error(Object error, VoidCallback retry) {
    final s = ref.read(stringsProvider);
    return Center(child: Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, children: [
      Text('$error', textAlign: TextAlign.center),
      const SizedBox(height: 12),
      FilledButton(onPressed: retry, child: Text(s('retry'))),
    ])));
  }
  Widget _applications() {
    final s = ref.watch(stringsProvider);
    return ref.watch(applicationsProvider).when(loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => _error(error, _refresh), data: (items) {
        if (items.isEmpty) return Center(child: Text(s('empty_applications')));
        return RefreshIndicator(onRefresh: () async => _refresh(), child: ListView.builder(
          padding: const EdgeInsets.all(16), itemCount: items.length, itemBuilder: (_, i) {
            final app = items[i];
            return Semantics(container: true,
              label: '${app.name}. ${s('epics')}: ${app.epicCount}. ${s('pending_todo')}: ${app.pendingCount}. ${s('delayed')}: ${app.delayedCount}. ${app.id}',
              child: Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(app.name, style: Theme.of(context).textTheme.titleMedium),
              Text(s(app.active ? 'active' : 'inactive')),
              const SizedBox(height: 12),
              Wrap(spacing: 16, runSpacing: 8, children: [
                Text('${s('epics')}: ${app.epicCount}'),
                Text('${s('pending_todo')}: ${app.pendingCount}'),
                Text('${s('delayed')}: ${app.delayedCount}'),
              ]),
              const SizedBox(height: 8),
              SelectableText(app.id, style: Theme.of(context).textTheme.bodySmall),
            ]))));
          }));
      });
  }
  Widget _notifications() {
    final s = ref.watch(stringsProvider);
    return ref.watch(apiNotificationsProvider).when(loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => _error(error, _refresh), data: (items) {
        if (items.isEmpty) return Center(child: Text(s('empty_notifications')));
        return Column(children: [
          Align(alignment: Alignment.centerRight, child: TextButton(onPressed: _mutating || items.every((n) => n.read) ? null
              : () => _action(ref.read(apiResourcesProvider).markAllNotificationsRead), child: Text(s('mark_all')))),
          Expanded(child: ListView.builder(padding: const EdgeInsets.all(16), itemCount: items.length,
            itemBuilder: (_, i) => _notification(items[i]))),
        ]);
      });
  }
  Widget _notification(ApiNotification n) {
    final s = ref.watch(stringsProvider);
    return Semantics(container: true, label: '${n.title}. ${n.message}. ${n.id}. ${n.read ? s('read') : s('unread')}',
      child: Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(n.title, style: Theme.of(context).textTheme.titleMedium),
      Text(n.message),
      const SizedBox(height: 8),
      Text(n.createdAt.toLocal().toString(), style: Theme.of(context).textTheme.bodySmall),
      SelectableText(n.id, style: Theme.of(context).textTheme.bodySmall),
      if (n.read) Text(s('read')) else TextButton(onPressed: _mutating ? null
          : () => _action(() => ref.read(apiResourcesProvider).markNotificationRead(n.id)), child: Text(s('mark_read'))),
    ]))));
  }
}
