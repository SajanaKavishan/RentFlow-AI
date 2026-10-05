import 'package:flutter/material.dart';

/// Defers an automatic follow-up while a protected workflow is open.
class FollowUpActivity extends ChangeNotifier {
  int _holds = 0;
  bool _disposed = false;
  bool get blocked => _holds > 0;
  VoidCallback hold() {
    _holds++;
    notifyListeners();
    bool released = false;
    return () {
      if (released || _disposed) return;
      released = true;
      _holds--;
      notifyListeners();
    };
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

class FollowUpActivityScope extends InheritedWidget {
  const FollowUpActivityScope({
    super.key,
    required this.activity,
    required super.child,
  });
  final FollowUpActivity activity;
  @override
  bool updateShouldNotify(FollowUpActivityScope oldWidget) =>
      activity != oldWidget.activity;
  static FollowUpActivity? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<FollowUpActivityScope>()
      ?.activity;
}

/// The whole editing/upload workflow is protected, including native picker resumes.
class FollowUpPause extends StatefulWidget {
  const FollowUpPause({super.key, required this.child, this.active = true});
  final Widget child;
  final bool active;
  @override
  State<FollowUpPause> createState() => _FollowUpPauseState();
}

class _FollowUpPauseState extends State<FollowUpPause> {
  FollowUpActivity? _activity;
  VoidCallback? _release;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final activity = FollowUpActivityScope.maybeOf(context);
    if (activity == _activity) {
      _sync();
      return;
    }
    _release?.call();
    _release = null;
    _activity = activity;
    _sync();
  }

  void _sync() {
    if (widget.active) {
      _release ??= _activity?.hold();
    } else {
      _release?.call();
      _release = null;
    }
  }

  @override
  void didUpdateWidget(FollowUpPause oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  @override
  void dispose() {
    _release?.call();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
