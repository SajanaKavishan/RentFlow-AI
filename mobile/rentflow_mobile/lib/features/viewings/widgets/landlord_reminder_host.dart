import 'dart:async';
import 'package:flutter/material.dart';
import '../../../shared/home/landlord_workspace_service.dart';
import '../../properties/services/property_api_service.dart';
import '../../viewing_follow_ups/widgets/tenant_follow_up_host.dart';
import '../models/viewing.dart';
import '../screens/landlord_viewing_request_details_screen.dart';
import '../services/viewing_api_service.dart';
import '../services/viewing_reminders.dart';
import 'landlord_completion_dialog.dart';

/// Lives above the Navigator. Prompts wait for the root route to settle and
/// never interrupt details, forms, or other dialogs.
class LandlordReminderHost extends StatefulWidget {
  const LandlordReminderHost({
    super.key,
    required this.ownerId,
    required this.navigatorKey,
    required this.navigation,
    required this.service,
    required this.properties,
    required this.reminders,
    required this.child,
    this.now,
  });
  final String ownerId;
  final GlobalKey<NavigatorState> navigatorKey;
  final FollowUpNavigationObserver navigation;
  final ViewingApiService service;
  final PropertyApiService properties;
  final ViewingReminders reminders;
  final Widget child;
  final DateTime Function()? now;
  @override
  State<LandlordReminderHost> createState() => _LandlordReminderHostState();
}

class _LandlordReminderHostState extends State<LandlordReminderHost>
    with WidgetsBindingObserver {
  bool _foreground = true,
      _checking = false,
      _showing = false,
      _scheduled = false;
  bool _syncRequested = true, _promptRequested = true;
  bool _promptShownThisActivation = false;
  Timer? _timer;
  final Set<DateTime> _timerCheckedAt = {};
  final Map<String, DateTime> _lastPrompt = {};
  DateTime get _now => widget.now?.call() ?? DateTime.now();
  bool get _safe =>
      _foreground &&
      widget.navigation.settled &&
      widget.navigation.top?.settings.name == Navigator.defaultRouteName;

  @override
  void initState() {
    super.initState();
    _foreground =
        WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    WidgetsBinding.instance.addObserver(this);
    widget.navigation.changes.addListener(_schedule);
    widget.reminders.tappedPayload.addListener(_tapChanged);
    ViewingApiService.changes.addListener(_viewingChanged);
    _schedule();
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    widget.navigation.changes.removeListener(_schedule);
    widget.reminders.tappedPayload.removeListener(_tapChanged);
    ViewingApiService.changes.removeListener(_viewingChanged);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (!_foreground) {
      _timer?.cancel();
      return;
    }
    _syncRequested = true;
    _timerCheckedAt.clear();
    if (!_showing) {
      _promptRequested = true;
      _promptShownThisActivation = false;
    }
    _schedule();
  }

  void _viewingChanged() {
    _syncRequested = true;
    _schedule();
  }

  void _tapChanged() {
    if (widget.reminders.tappedPayload.value != null) {
      _syncRequested = true;
      _schedule();
    }
  }

  void _schedule() {
    if (!mounted || _scheduled || _checking || _showing || !_syncRequested) {
      return;
    }
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (mounted) _check();
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  Future<void> _check() async {
    if (!_foreground ||
        !widget.navigation.settled ||
        _checking ||
        _showing ||
        !_syncRequested) {
      return;
    }
    _checking = true;
    _syncRequested = false;
    try {
      await widget.reminders.setOwner(widget.ownerId);
      final viewings = await LandlordWorkspaceService(
        widget.properties,
      ).viewings(widget.service);
      if (!mounted) return;
      await widget.reminders.reconcile(widget.ownerId, viewings);
      if (!mounted) return;
      _scheduleTimer(viewings);
      if (!_safe) {
        _syncRequested = _promptRequested;
        return;
      }
      final tappedId = widget.reminders.consumeTap(widget.ownerId);
      if (tappedId != null) {
        final viewing = await widget.service.getViewingById(tappedId);
        if (!mounted || !_safe) return;
        _promptRequested = false;
        _promptShownThisActivation = true;
        _showing = true;
        await widget.navigatorKey.currentState!.push<void>(
          MaterialPageRoute(
            builder: (_) => LandlordViewingRequestDetailsScreen(
              viewing: viewing,
              viewingApiService: widget.service,
            ),
          ),
        );
        return;
      }
      if (!_promptRequested) return;
      _promptRequested = false;
      final eligible =
          viewings
              .where(
                (v) =>
                    v.status == ViewingStatus.approved &&
                    v.canMarkCompleted &&
                    v.completionEligibleAt != null &&
                    (_lastPrompt[v.id] == null ||
                        _now.difference(_lastPrompt[v.id]!) >=
                            const Duration(minutes: 10)),
              )
              .toList()
            ..sort(
              (a, b) =>
                  a.completionEligibleAt!.compareTo(b.completionEligibleAt!),
            );
      if (eligible.isEmpty) return;
      // A fresh detail response verifies identity and current server permission.
      final candidate = eligible.first;
      final viewing = await widget.service.getViewingById(candidate.id);
      if (!mounted ||
          !_safe ||
          viewing.id != candidate.id ||
          viewing.propertyId != candidate.propertyId ||
          viewing.tenantId != candidate.tenantId ||
          viewing.status != ViewingStatus.approved ||
          !viewing.canMarkCompleted) {
        return;
      }
      _lastPrompt[viewing.id] = _now;
      _promptShownThisActivation = true;
      _showing = true;
      await showDialog<bool>(
        context: widget.navigatorKey.currentState!.context,
        barrierDismissible: false,
        builder: (_) =>
            LandlordCompletionDialog(viewing: viewing, service: widget.service),
      );
      _syncRequested = true;
    } catch (_) {
      // Offline or denied device permission never blocks the app. Retry on resume.
    } finally {
      _checking = false;
      _showing = false;
      // Mutations may request reconciliation; they do not request another prompt.
      if (mounted && _syncRequested && _safe) _schedule();
    }
  }

  void _scheduleTimer(List<Viewing> viewings) {
    _timer?.cancel();
    final pending =
        viewings
            .where(
              (v) =>
                  v.status == ViewingStatus.approved &&
                  !v.canMarkCompleted &&
                  v.completionEligibleAt != null &&
                  !_timerCheckedAt.contains(v.completionEligibleAt),
            )
            .toList()
          ..sort(
            (a, b) =>
                a.completionEligibleAt!.compareTo(b.completionEligibleAt!),
          );
    if (!_foreground || pending.isEmpty) return;
    final at = pending.first.completionEligibleAt!;
    final delay = at.difference(_now) + const Duration(seconds: 1);
    _timer = Timer(
      delay > Duration.zero ? delay : const Duration(seconds: 1),
      () {
        _timerCheckedAt.add(at);
        _syncRequested = true;
        _promptRequested = !_promptShownThisActivation;
        _schedule();
      },
    );
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
