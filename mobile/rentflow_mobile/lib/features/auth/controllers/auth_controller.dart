import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/auth/token_storage.dart';
import '../models/current_user.dart';
import '../services/auth_service.dart';

class AuthController extends ChangeNotifier {
  AuthController({required this.authService, required this.tokenStorage});
  final AuthService authService;
  final TokenStorage tokenStorage;
  CurrentUser? _currentUser;
  bool _isLoading = true;

  CurrentUser? get currentUser => _currentUser;
  bool get isAuthenticated => _currentUser != null;
  bool get isLoading => _isLoading;

  Future<void> restoreSession() async {
    _isLoading = true;
    notifyListeners();
    try {
      final token = await tokenStorage.readToken().timeout(
        authService.apiClient.requestTimeout,
      );
      if (token == null || token.isEmpty) {
        _currentUser = null;
        return;
      }
      _currentUser = await authService.getCurrentUser();
    } catch (error) {
      if (_shouldClearRestoredToken(error)) {
        await _deleteStoredToken();
      }
      _currentUser = null;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  bool _shouldClearRestoredToken(Object error) {
    if (error is TimeoutException) return false;
    if (error is! AuthException) return true;
    if (error.isConnectionFailure) return false;
    final statusCode = error.statusCode;
    return statusCode == null ||
        (statusCode < 500 && statusCode != 408 && statusCode != 429);
  }

  Future<void> _deleteStoredToken() async {
    try {
      await tokenStorage.deleteToken().timeout(
        authService.apiClient.requestTimeout,
      );
    } catch (_) {
      // Session state can still recover if secure storage is temporarily slow.
    }
  }

  Future<void> login({required String email, required String password}) async {
    final result = await authService.login(email: email, password: password);
    await _accept(result);
  }

  Future<void> register({
    required String fullName,
    required String email,
    required String phoneNumber,
    required String password,
    required UserRole role,
  }) async {
    final result = await authService.register(
      fullName: fullName,
      email: email,
      phoneNumber: phoneNumber,
      password: password,
      role: role,
    );
    await _accept(result);
  }

  Future<void> _accept(AuthResult result) async {
    await tokenStorage
        .saveToken(result.accessToken)
        .timeout(authService.apiClient.requestTimeout);
    try {
      _currentUser = await authService.getCurrentUser();
      notifyListeners();
    } catch (_) {
      await logout();
      rethrow;
    }
  }

  Future<void> handleUnauthorized() async {
    _currentUser = null;
    notifyListeners();
    await _deleteStoredToken();
  }

  Future<void> logout() async {
    _currentUser = null;
    notifyListeners();
    await _deleteStoredToken();
  }
}

class AuthScope extends InheritedNotifier<AuthController> {
  const AuthScope({
    super.key,
    required AuthController controller,
    required super.child,
  }) : super(notifier: controller);

  static AuthController of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AuthScope>();
    assert(scope != null, 'AuthScope was not found.');
    return scope!.notifier!;
  }
}
