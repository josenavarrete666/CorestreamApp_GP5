import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/api_repository.dart';
import '../data/api_error.dart';
import '../models/models.dart';
import '../providers.dart';
import 'incidents_screens.dart';
import 'ticket_detail_screen.dart';

Future<void> openNotification(BuildContext context, WidgetRef ref, AppNotification notification,
    {bool markRead = false}) async {
  final repo = ref.read(repositoryProvider);
  final userId = ref.read(authProvider)?.id;
  try {
    if (markRead && !notification.read) await repo.markNotificationRead(notification.id);
    if (!context.mounted || ref.read(authProvider)?.id != userId) return;
    if (notification.ticketId != null) {
      if (repo is ApiRepository && !await repo.isDevelopmentTicket(notification.ticketId!)) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(ref.read(stringsProvider)('unsupported_ticket'))));
        }
        return;
      }
      if (!context.mounted || ref.read(authProvider)?.id != userId) return;
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => TicketDetailScreen(ticketId: notification.ticketId!)));
    } else if (notification.incidentId != null) {
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => IncidentDetailScreen(incidentId: notification.incidentId!)));
    }
  } catch (error) {
    if (context.mounted && !(error is ApiError && error.kind == ApiErrorKind.superseded)) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$error')));
    }
  }
}
