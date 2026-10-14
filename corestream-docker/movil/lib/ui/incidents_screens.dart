import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/i18n.dart';
import '../core/theme.dart';
import '../models/models.dart';
import '../models/api_domain_models.dart';
import '../providers.dart';
import 'ticket_sheets.dart';
import 'widgets.dart';

// -------------------------------------------------------------------- lista

final incidentFilterProvider = StateProvider<IncidentStatus?>((ref) { ref.watch(authProvider); return null; });

class IncidentsScreen extends ConsumerWidget {
  const IncidentsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final filter = ref.watch(incidentFilterProvider);
    final incidents = ref.watch(incidentsProvider);

    final filters = ref.watch(apiModeProvider) ? <(IncidentStatus?, String)>[
      (null, s('all')), for (final status in apiIncidentStatuses) (status, s('is_${status.wire}')),
    ] : <(IncidentStatus?, String)>[
      (null, s('all')),
      (IncidentStatus.open, s('is_OPEN')),
      (IncidentStatus.inProgress, s('is_IN_PROGRESS')),
      (IncidentStatus.underReview, s('is_UNDER_REVIEW')),
      (IncidentStatus.resolved, s('is_RESOLVED')),
    ];

    return Column(
      children: [
        SizedBox(
          height: 52,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
            itemCount: filters.length,
            separatorBuilder: (_, __) => const SizedBox(width: 7),
            itemBuilder: (_, i) {
              final (value, label) = filters[i];
              final selected = filter == value;
              return FilterChip(
                selected: selected,
                showCheckmark: false,
                label: Text(label),
                onSelected: (_) =>
                    ref.read(incidentFilterProvider.notifier).state = value,
              );
            },
          ),
        ),
        Expanded(
          child: AsyncView<List<Incident>>(
            value: incidents,
            builder: (list) {
              final visible = filter == null
                  ? list
                  : list
                      .where((i) =>
                          i.status == filter ||
                          (filter == IncidentStatus.open &&
                              i.status == IncidentStatus.reopened))
                      .toList();
              if (visible.isEmpty) {
                return EmptyState(s('no_incidents'), icon: Icons.folder_open_outlined);
              }
              return RefreshIndicator(
                onRefresh: () { refreshApiData(ref); return ref.refresh(incidentsProvider.future); },
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                  itemCount: visible.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (_, i) => IncidentRow(
                    visible[i],
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) =>
                            IncidentDetailScreen(incidentId: visible[i].id))),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class IncidentRow extends ConsumerWidget {
  const IncidentRow(this.incident, {super.key, this.projectName, required this.onTap});

  final Incident incident;
  final String? projectName;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = cs(context);
    final s = ref.watch(stringsProvider);
    final repo = ref.watch(repositoryProvider);
    final assignee = repo.userById(incident.assigneeId);

    return CsCard(
      onTap: onTap,
      padding: EdgeInsets.zero,
      child: IntrinsicHeight(
        child: Row(
          children: [
            Container(
              width: 4,
              decoration: BoxDecoration(
                color: severityColor(context, incident.severity),
                borderRadius:
                    const BorderRadius.horizontal(left: Radius.circular(16)),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(13),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(incident.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 13.5, fontWeight: FontWeight.w600, height: 1.3)),
                    const SizedBox(height: 4),
                    Text(
                      [
                        if (incident.number > 0) 'INC-${incident.number}',
                        if (projectName != null) projectName!,
                        relativeTime(s, incident.createdAt),
                      ].join(' · '),
                      style: TextStyle(fontSize: 11.5, color: c.mut),
                    ),
                    const SizedBox(height: 7),
                    Wrap(spacing: 6, children: [
                      IncidentStatusChip(incident.status),
                      SeverityChip(incident.severity),
                    ]),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: UserAvatar(assignee, size: 26),
            ),
          ],
        ),
      ),
    );
  }
}

// ------------------------------------------------------------------- detalle

class IncidentDetailScreen extends ConsumerWidget {
  const IncidentDetailScreen({super.key, required this.incidentId});
  final String incidentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final c = cs(context);
    final incidentAsync = ref.watch(incidentProvider(incidentId));
    final me = ref.watch(authProvider)!;
    final repo = ref.read(repositoryProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(incidentAsync.valueOrNull != null &&
                incidentAsync.valueOrNull!.number > 0
            ? 'INC-${incidentAsync.valueOrNull!.number}'
            : s('incident')),
      ),
      body: AsyncView<Incident>(
        value: incidentAsync,
        builder: (i) {
          final reporter = repo.userById(i.reporterId);
          final assignee = repo.userById(i.assigneeId);
          final mine = i.assigneeId == me.id;

          Widget? actions;
          if (i.status == IncidentStatus.open || i.status == IncidentStatus.reopened) {
            actions = me.isLead
                ? FilledButton.icon(
                    icon: const Icon(Icons.people_outline),
                    label: Text(s('assign')),
                    onPressed: () => _showIncidentAssign(context, ref, i),
                  )
                : FilledButton.icon(
                    icon: const Icon(Icons.play_arrow),
                    label: Text(s('take')),
                    onPressed: () => repo.takeIncident(i.id),
                  );
          } else if (i.status == IncidentStatus.inProgress && (mine || me.isLead)) {
            actions = FilledButton.icon(
              icon: const Icon(Icons.visibility_outlined),
              label: Text(s('to_review')),
              onPressed: () =>
                  repo.setIncidentStatus(i.id, IncidentStatus.underReview),
            );
          } else if (i.status == IncidentStatus.underReview && me.isLead) {
            actions = FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: c.green),
              icon: const Icon(Icons.check),
              label: Text(s('resolve_inc')),
              onPressed: () => repo.setIncidentStatus(i.id, IncidentStatus.resolved),
            );
          } else if (i.status == IncidentStatus.resolved && me.isLead) {
            actions = Row(children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () =>
                      repo.setIncidentStatus(i.id, IncidentStatus.reopened),
                  child: Text(s('reopen')),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton(
                  onPressed: () =>
                      repo.setIncidentStatus(i.id, IncidentStatus.closed),
                  child: Text(s('close_inc')),
                ),
              ),
            ]);
          }

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 30),
            children: [
              Text(
                relativeTime(s, i.createdAt),
                style: TextStyle(fontSize: 11.5, color: c.faint, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 6),
              Text(i.title,
                  style: const TextStyle(
                      fontSize: 20, fontWeight: FontWeight.w700, height: 1.3)),
              const SizedBox(height: 10),
              Wrap(spacing: 7, runSpacing: 6, children: [
                IncidentStatusChip(i.status),
                SeverityChip(i.severity),
                if (i.category != null)
                  CsChip(label: s('cat_${i.category!.wire}'), color: c.gray, dot: false),
              ]),
              const SizedBox(height: 14),
              CsCard(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                child: Column(children: [
                  _row(context, s('reported_by'), reporter, s, unavailable: i.reporterId != null),
                  _row(context, s('assignee'), assignee, s, unavailable: i.assigneeId != null),
                  if (i.environment != null)
                    DetailRow(s('environment'), child: Text(i.environment!, textAlign: TextAlign.right,
                      style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600))),
                ]),
              ),
              SectionLabel(s('description')),
              CsCard(
                child: Text(i.description.isEmpty ? s('no_description') : i.description,
                    style: TextStyle(fontSize: 13.5, height: 1.55, color: c.mut)),
              ),
              if (i.mitigation != null && i.mitigation!.isNotEmpty) ...[
                SectionLabel(s('mitigation')), CsCard(child: Text(i.mitigation!,
                    style: TextStyle(fontSize: 13.5, height: 1.55, color: c.mut))),
              ],
              if (i.comments.isNotEmpty) ...[
                SectionLabel(s('comments')),
                CsCard(
                  child: Column(children: [
                    for (final cm in i.comments)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            UserAvatar(repo.userById(cm.userId), size: 28),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(repo.userById(cm.userId)?.fullName ?? '',
                                      style: const TextStyle(
                                          fontSize: 13, fontWeight: FontWeight.w600)),
                                  const SizedBox(height: 2),
                                  Text('“${cm.text}”',
                                      style: TextStyle(
                                          fontSize: 12.5, color: c.mut, height: 1.45)),
                                  const SizedBox(height: 2),
                                  Text(relativeTime(s, cm.ts),
                                      style:
                                          TextStyle(fontSize: 11, color: c.faint)),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                  ]),
                ),
              ],
              const SizedBox(height: 18),
              if (ref.watch(apiModeProvider))
                _ApiIncidentActions(incident: i)
              else if (actions != null)
                actions
              else if (!me.isLead && !mine)
                EmptyState(s('view_only'), icon: Icons.visibility_outlined),
              if (ref.watch(apiModeProvider)) ResourceIdentity(i.id),
            ],
          );
        },
      ),
    );
  }

  Widget _row(BuildContext context, String label, User? user, S s, {bool unavailable = false}) {
    final c = cs(context);
    return DetailRow(label, child: Row(mainAxisSize: MainAxisSize.min, children: [
        UserAvatar(user, size: 22),
        const SizedBox(width: 7),
        Flexible(child: Text(user?.fullName ?? s(unavailable ? 'user_unavailable' : 'unassigned'),
            textAlign: TextAlign.right,
            style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                color: user == null ? c.faint : c.ink))),
      ]));
  }
}

Future<void> _showIncidentAssign(BuildContext context, WidgetRef ref, Incident i) {
  final s = ref.read(stringsProvider);
  String? picked;
  return showCsSheet(
    context,
    StatefulBuilder(
      builder: (ctx, setState) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SheetTitle(i.number > 0 ? '${s('assign')} · INC-${i.number}' : s('assign'), subtitle: '“${i.title}”'),
          UserPicker(selected: picked, onSelect: (id) => setState(() => picked = id)),
          const SizedBox(height: 14),
          CsMutationButton(
            enabled: picked != null,
            onPressed: () async {
                    await ref.read(repositoryProvider).assignIncident(i.id, picked!);
                    if (ctx.mounted) Navigator.pop(ctx);
                  },
            child: Text(s('confirm')),
          ),
        ],
      ),
    ),
  );
}

class _ApiIncidentActions extends ConsumerStatefulWidget {
  const _ApiIncidentActions({required this.incident});
  final Incident incident;
  @override
  ConsumerState<_ApiIncidentActions> createState() => _ApiIncidentActionsState();
}

class _ApiIncidentActionsState extends ConsumerState<_ApiIncidentActions> {
  late IncidentStatus _status = widget.incident.status;
  @override
  void didUpdateWidget(covariant _ApiIncidentActions oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.incident.status != widget.incident.status) _status = widget.incident.status;
  }
  @override
  Widget build(BuildContext context) {
    final s = ref.watch(stringsProvider);
    final i = widget.incident;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (ref.watch(authProvider)?.isLead == true) ...[
        FilledButton.icon(onPressed: () => _showIncidentAssign(context, ref, i),
            icon: const Icon(Icons.people_outline), label: Text(s('assign'))),
        const SizedBox(height: 12),
      ],
      DropdownButtonFormField<IncidentStatus>(key: ValueKey(i.status), initialValue: _status,
          decoration: InputDecoration(labelText: s('incident_state')),
          items: [for (final status in apiIncidentStatuses)
            DropdownMenuItem(value: status, child: Text(s('is_${status.wire}')))],
          onChanged: (value) { if (value != null) setState(() => _status = value); }),
      const SizedBox(height: 12),
      CsMutationButton(enabled: _status != i.status, icon: Icons.save_outlined,
          onPressed: () => ref.read(repositoryProvider).setIncidentStatus(i.id, _status), child: Text(s('save'))),
      const SizedBox(height: 12),
      CsCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [Icon(Icons.info_outline, size: 16, color: cs(context).faint),
          const SizedBox(width: 8), Expanded(child: Text(s('backend_limits'),
            style: TextStyle(color: cs(context).mut, fontSize: 12, fontWeight: FontWeight.w600)))]),
        const SizedBox(height: 6),
        Text(s('incident_limits'), style: TextStyle(color: cs(context).mut, fontSize: 12, height: 1.5)),
      ])),
    ]);
  }
}
