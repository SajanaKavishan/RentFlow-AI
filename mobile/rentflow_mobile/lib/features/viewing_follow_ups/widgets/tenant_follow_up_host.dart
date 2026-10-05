import 'package:flutter/material.dart';
import '../../../shared/follow_up/follow_up_activity.dart';
import '../../properties/services/property_api_service.dart';
import '../../rental_applications/services/rental_application_api_service.dart';
import '../models/viewing_follow_up.dart';
import '../services/viewing_follow_up_api_service.dart';
import 'viewing_follow_up_dialog.dart';

class FollowUpNavigationObserver extends NavigatorObserver {
  final changes = ValueNotifier<int>(0);
  final List<Route<dynamic>> _routes = [];
  Route<dynamic>? get top => _routes.isEmpty ? null : _routes.last;
  bool get settled {
    final route = top;
    return route is PageRoute &&
        route.isCurrent &&
        (route.animation?.isCompleted ?? true) &&
        !(route.secondaryAnimation?.isAnimating ?? false);
  }

  void _notify([AnimationStatus? status]) {
    changes.value++;
  }

  void _watch(Route<dynamic> route) {
    if (route is! TransitionRoute) return;
    route.animation?.addStatusListener(_notify);
    route.secondaryAnimation?.addStatusListener(_notify);
  }

  void _unwatch(Route<dynamic> route) {
    if (route is! TransitionRoute) return;
    route.animation?.removeStatusListener(_notify);
    route.secondaryAnimation?.removeStatusListener(_notify);
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (previousRoute == null) {
      for (final previous in _routes) {
        _unwatch(previous);
      }
      _routes.clear();
    }
    _routes.add(route);
    _watch(route);
    _notify();
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _routes.remove(route);
    _unwatch(route);
    _notify();
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _routes.remove(route);
    _unwatch(route);
    _notify();
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    final index = oldRoute == null ? -1 : _routes.indexOf(oldRoute);
    if (oldRoute != null) {
      _routes.remove(oldRoute);
      _unwatch(oldRoute);
    }
    if (newRoute != null) {
      _routes.insert(index < 0 ? _routes.length : index, newRoute);
      _watch(newRoute);
    }
    _notify();
  }
}

/// Lives above the root Navigator, so resume on any tenant route is observed.
class TenantFollowUpHost extends StatefulWidget {
  const TenantFollowUpHost({
    super.key,
    required this.navigatorKey,
    required this.navigation,
    required this.apiService,
    required this.applicationApiService,
    required this.propertyApiService,
    required this.child,
  });
  final GlobalKey<NavigatorState> navigatorKey;
  final FollowUpNavigationObserver navigation;
  final ViewingFollowUpApiService apiService;
  final RentalApplicationApiService applicationApiService;
  final PropertyApiService propertyApiService;
  final Widget child;
  @override
  State<TenantFollowUpHost> createState() => _TenantFollowUpHostState();
}

class _TenantFollowUpHostState extends State<TenantFollowUpHost>
    with WidgetsBindingObserver {
  final _activity = FollowUpActivity();
  bool _pending = true, _checking = false, _showing = false, _scheduled = false;
  bool _foreground = true;
  ViewingFollowUp? _claimed;
  bool get _safe =>
      _foreground && !_activity.blocked && widget.navigation.settled;
  @override
  void initState() {
    super.initState();
    _foreground =
        WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    WidgetsBinding.instance.addObserver(this);
    widget.navigation.changes.addListener(_schedule);
    _activity.addListener(_schedule);
    _schedule();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.navigation.changes.removeListener(_schedule);
    _activity.removeListener(_schedule);
    _activity.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (_foreground && !_showing && !_checking) {
      _pending = true;
      _schedule();
    }
  }

  void _schedule() {
    if (!mounted ||
        _scheduled ||
        _checking ||
        _showing ||
        (!_pending && _claimed == null)) {
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
    if (_checking || _showing || !_safe || (!_pending && _claimed == null)) {
      return;
    }
    _checking = true;
    _pending = false;
    try {
      _claimed ??= await widget.apiService.claimNext();
      if (!mounted || _claimed == null || !_safe) return;
      final navigator = widget.navigatorKey.currentState;
      if (navigator == null) return;
      final prompt = _claimed!;
      _claimed = null;
      _showing = true;
      final destination = await showDialog<Widget>(
        context: navigator.context,
        barrierDismissible: false,
        builder: (_) => ViewingFollowUpDialog(
          followUp: prompt,
          apiService: widget.apiService,
          applicationApiService: widget.applicationApiService,
          propertyApiService: widget.propertyApiService,
        ),
      );
      if (mounted && destination != null) {
        await navigator.push<void>(
          MaterialPageRoute(builder: (_) => destination),
        );
      }
    } catch (_) {
      // A failed claim never blocks the app; retry on a later open/resume.
    } finally {
      _checking = false;
      _showing = false;
      // No chained claim after a response. A claimed response waiting for safety may be shown later.
      if (mounted && _claimed != null && _safe) _schedule();
    }
  }

  @override
  Widget build(BuildContext context) =>
      FollowUpActivityScope(activity: _activity, child: widget.child);
}
