import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../models/viewing.dart';

abstract interface class ReminderDevice {
  Future<void> initialize();
  Future<void> requestPermissionOnce();
  Future<Map<int, String?>> pending();
  Future<void> schedule(int id, Viewing viewing, String payload);
  Future<void> cancel(int id);
  Future<String?> readState();
  Future<void> writeState(String state);
}

/// Serializes account changes and reconciliation. The persisted allocation avoids
/// hash collisions and survives restarts; only this feature's IDs are cancelled.
class ViewingReminders {
  ViewingReminders(this.device, {DateTime Function()? now})
    : now = now ?? DateTime.now;
  final ReminderDevice device;
  final DateTime Function() now;
  final tappedPayload = ValueNotifier<String?>(null);
  Future<void> _tail = Future.value();
  String? _owner;
  String? _storedOwner;
  bool _initialized = false;
  int _nextId = 10000;
  final Map<String, int> _ids = {};

  Future<void> _run(Future<void> Function() action) {
    final result = _tail.then((_) => action());
    // Device failures must never suppress the server-driven in-app experience.
    _tail = result.catchError((Object _) {});
    return _tail;
  }

  Future<void> _initialize() async {
    if (_initialized) return;
    await device.initialize();
    final raw = await device.readState();
    if (raw != null) {
      final data = jsonDecode(raw) as Map<String, dynamic>;
      _storedOwner = data['owner'] as String?;
      _nextId = data['nextId'] as int;
      _ids.addAll((data['ids'] as Map<String, dynamic>).cast<String, int>());
    }
    _initialized = true;
  }

  Future<void> _save() => device.writeState(
    jsonEncode({'owner': _storedOwner, 'nextId': _nextId, 'ids': _ids}),
  );

  Future<void> setOwner(String? owner) {
    _owner = owner;
    return _run(() async {
      await _initialize();
      if (_storedOwner == owner) return;
      for (final id in _ids.values) {
        await device.cancel(id);
      }
      _ids.clear();
      _storedOwner = owner;
      await _save();
    });
  }

  Future<void> reconcile(
    String owner,
    List<Viewing> authoritative,
  ) => _run(() async {
    await _initialize();
    if (_owner != owner || _storedOwner != owner) return;
    final qualifying = {
      for (final v in authoritative)
        if (v.status == ViewingStatus.approved &&
            v.completionEligibleAt != null)
          v.id: v,
    };
    for (final key in _ids.keys.toList()) {
      if (!qualifying.containsKey(key)) {
        await device.cancel(_ids[key]!);
        _ids.remove(key);
      }
    }
    await _save();
    final future =
        qualifying.values
            .where((v) => v.completionEligibleAt!.isAfter(now()))
            .toList()
          ..sort(
            (a, b) =>
                a.completionEligibleAt!.compareTo(b.completionEligibleAt!),
          );
    // Leave headroom below iOS's 64 pending notification limit.
    final scheduled = future.take(60).toList();
    final pending = await device.pending();
    final futureIds = scheduled.map((v) => v.id).toSet();
    for (final entry in _ids.entries) {
      if (pending.containsKey(entry.value) && !futureIds.contains(entry.key)) {
        await device.cancel(entry.value);
      }
    }
    if (scheduled.isEmpty || _owner != owner) return;
    await device.requestPermissionOnce();
    for (final viewing in scheduled) {
      if (_owner != owner) return;
      final id = _ids.putIfAbsent(viewing.id, () => _nextId++);
      // Persist before OS scheduling so a crash cannot orphan a notification.
      await _save();
      final payload = jsonEncode({
        'owner': owner,
        'viewing': viewing.id,
        'at': viewing.completionEligibleAt!.toUtc().toIso8601String(),
      });
      if (pending[id] == payload) continue;
      await device.cancel(id);
      await device.schedule(id, viewing, payload);
    }
  });

  String? consumeTap(String owner) {
    final payload = tappedPayload.value;
    if (payload == null) return null;
    tappedPayload.value = null;
    try {
      final data = jsonDecode(payload) as Map<String, dynamic>;
      return data['owner'] == owner ? data['viewing'] as String? : null;
    } catch (_) {
      return null;
    }
  }
}
