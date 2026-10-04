import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../core/auth/token_storage.dart';
import '../models/current_user.dart';
import '../models/profile_image_file.dart';
import '../services/auth_service.dart';

class AuthController extends ChangeNotifier {
  AuthController({required this.authService, required this.tokenStorage});
  final AuthService authService;
  final TokenStorage tokenStorage;
  CurrentUser? _currentUser;
  bool _isLoading = true;
  int _profileImageRevision = 0;
  Future<Uint8List?>? _profileImageRequest;
  bool _changingPassword = false;
  int _sessionRevision = 0;
  String? _signInNotice;

  CurrentUser? get currentUser => _currentUser;
  bool get isAuthenticated => _currentUser != null;
  bool get isLoading => _isLoading;
  int get profileImageRevision => _profileImageRevision;
  bool get isChangingPassword => _changingPassword;
  String? get signInNotice => _signInNotice;

  void _invalidateProfileImage() {
    _profileImageRevision++;
    _profileImageRequest = null;
  }

  // Share one authenticated fetch between mounted avatars. Failures stay local
  // to the photo; logout/replacement cannot reuse an earlier request's bytes.
  Future<Uint8List?> loadProfileImage() {
    if (_currentUser?.hasProfileImage != true) return Future.value(null);
    final revision = _profileImageRevision;
    return _profileImageRequest ??= authService
        .getProfileImage()
        .then<Uint8List?>(
          (bytes) => revision == _profileImageRevision ? bytes : null,
          onError: (Object error) => null,
        );
  }

  Future<void> restoreSession() async {
    _sessionRevision++;
    _invalidateProfileImage();
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
      authService.apiClient.resumeAuthentication();
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
    _sessionRevision++;
    _invalidateProfileImage();
    await tokenStorage
        .saveToken(result.accessToken)
        .timeout(authService.apiClient.requestTimeout);
    try {
      authService.apiClient.resumeAuthentication();
      _currentUser = await authService.getCurrentUser();
      _signInNotice = null;
      notifyListeners();
    } catch (_) {
      await logout();
      rethrow;
    }
  }

  Future<void> handleUnauthorized() async {
    _sessionRevision++;
    authService.apiClient.suspendAuthentication();
    _invalidateProfileImage();
    _currentUser = null;
    notifyListeners();
    await _deleteStoredToken();
  }

  Future<CurrentUser> updateProfile({
    required String fullName,
    required String phoneNumber,
  }) async {
    final userId = _currentUser?.id;
    final revision = _profileImageRevision;
    if (userId == null) {
      throw const AuthException('Sign in to update your profile.');
    }
    final updated = await authService.updateProfile(
      fullName: fullName,
      phoneNumber: phoneNumber,
    );
    if (_currentUser?.id == userId && revision == _profileImageRevision) {
      _currentUser = updated;
      notifyListeners();
    }
    return updated;
  }

  Future<CurrentUser> uploadProfileImage(ProfileImageFile image) async {
    final userId = _currentUser?.id;
    final revision = _profileImageRevision;
    if (userId == null) {
      throw const AuthException('Sign in to update your profile.');
    }
    final updated = await authService.uploadProfileImage(image);
    if (_currentUser?.id == userId && revision == _profileImageRevision) {
      _currentUser = updated;
      _invalidateProfileImage();
      notifyListeners();
    }
    return updated;
  }

  Future<CurrentUser> updatePublicContact(
    CurrentUser user,
    String phone,
    bool enabled,
  ) async {
    final updated = await authService.updatePublicContact(user, phone, enabled);
    _currentUser = updated;
    notifyListeners();
    return updated;
  }

  Future<void> logout() async {
    _sessionRevision++;
    authService.apiClient.suspendAuthentication();
    _invalidateProfileImage();
    _currentUser = null;
    notifyListeners();
    await _deleteStoredToken();
  }

  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
    required String newPasswordConfirmation,
  }) async {
    if (!isAuthenticated) throw const AuthException('Please sign in again.');
    if (_changingPassword) {
      throw const AuthException('Password change is already in progress.');
    }
    final revision = _sessionRevision;
    _changingPassword = true;
    notifyListeners();
    try {
      final previousToken = await tokenStorage.readToken().timeout(
        authService.apiClient.requestTimeout,
      );
      final result = await authService.changePassword(
        currentPassword: currentPassword,
        newPassword: newPassword,
        newPasswordConfirmation: newPasswordConfirmation,
      );
      if (revision != _sessionRevision) {
        throw const AuthException(
          'Your session changed. Please sign in again.',
        );
      }
      if (result.accessToken == previousToken) {
        throw const PasswordChangeSessionException(
          'Your password may have changed. Please sign in again.',
        );
      }
      authService.apiClient.beginTokenReplacement();
      final persistence = Future<void>.sync(
        () => tokenStorage.saveToken(result.accessToken),
      );
      try {
        await persistence.timeout(authService.apiClient.requestTimeout);
        final installed = await tokenStorage.readToken().timeout(
          authService.apiClient.requestTimeout,
        );
        if (installed != result.accessToken) throw const FormatException();
      } catch (_) {
        // A timed-out platform write cannot be cancelled. If it completes after
        // logout, remove that late token rather than restoring it on restart.
        unawaited(
          persistence
              .then<void>((_) async {
                if (!isAuthenticated &&
                    await tokenStorage.readToken().timeout(
                          authService.apiClient.requestTimeout,
                        ) ==
                        result.accessToken) {
                  await _deleteStoredToken();
                }
              }, onError: (Object _) {})
              .catchError((Object _) {}),
        );
        throw const PasswordChangeSessionException(
          'Your password was changed. Please sign in again.',
        );
      }
      if (revision != _sessionRevision) {
        if (!isAuthenticated) await _deleteStoredToken();
        throw const AuthException(
          'Your session changed. Please sign in again.',
        );
      }
      // ApiClient reads this same store on every call; there is no second token
      // cache to update. Resume only after durable replacement has completed.
      authService.apiClient.resumeAuthentication();
    } on PasswordChangeSessionException catch (error) {
      if (revision == _sessionRevision) {
        _signInNotice = error.message;
        await logout();
      }
      rethrow;
    } finally {
      _changingPassword = false;
      notifyListeners();
    }
  }
}

class AuthScope extends InheritedNotifier<AuthController> {
  const AuthScope({
    super.key,
    required AuthController controller,
    required super.child,
  }) : super(notifier: controller);

  static AuthController of(BuildContext context) {
    final controller = maybeOf(context);
    assert(controller != null, 'AuthScope was not found.');
    return controller!;
  }

  static AuthController? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AuthScope>()?.notifier;
}
