import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../api/api_client.dart';

/// Riverpod provider for the singleton [AuthRepository].
final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => AuthRepository(ref.read(apiClientProvider)),
);

/// Owns the auth side-effects: calls the API, persists / clears
/// tokens in secure storage. Pure logic, no UI.
class AuthRepository {
  final ApiClient _api;
  static const _storage = FlutterSecureStorage();

  static const _kAccessTokenKey = 'access_token';
  static const _kRefreshTokenKey = 'refresh_token';
  static const _kUserIdKey = 'user_id';

  AuthRepository(this._api);

  // ─── high-level operations ────────────────────────────────────────

  Future<AuthResult> register({
    required String email,
    required String username,
    required String password,
  }) async {
    try {
      final res = await _api.register(
        email: email,
        username: username,
        password: password,
      );
      await _persist(res);
      return res;
    } on DioException catch (e) {
      throw _mapError(e);
    }
  }

  Future<AuthResult> login({
    required String email,
    required String password,
  }) async {
    try {
      final res = await _api.login(email: email, password: password);
      await _persist(res);
      return res;
    } on DioException catch (e) {
      throw _mapError(e);
    }
  }

  Future<void> logout() async {
    await _storage.delete(key: _kAccessTokenKey);
    await _storage.delete(key: _kRefreshTokenKey);
    await _storage.delete(key: _kUserIdKey);
  }

  // ─── token / identity queries ──────────────────────────────────────

  Future<String?> getAccessToken() => _storage.read(key: _kAccessTokenKey);
  Future<String?> getRefreshToken() => _storage.read(key: _kRefreshTokenKey);
  Future<String?> getUserId() => _storage.read(key: _kUserIdKey);
  Future<bool> isAuthenticated() async => (await getAccessToken()) != null;

  /// Tries to refresh the access token using the stored refresh token.
  /// Returns null if there's no refresh token or it has expired.
  Future<AuthResult?> tryRefresh() async {
    final refresh = await getRefreshToken();
    if (refresh == null) return null;
    try {
      final res = await _api.refresh(refresh);
      await _persist(res);
      return res;
    } catch (_) {
      // Refresh failed — wipe stored tokens so the user gets sent to login.
      await logout();
      return null;
    }
  }

  // ─── internal ─────────────────────────────────────────────────────

  Future<void> _persist(AuthResult r) async {
    await _storage.write(key: _kAccessTokenKey, value: r.accessToken);
    await _storage.write(key: _kRefreshTokenKey, value: r.refreshToken);
    await _storage.write(key: _kUserIdKey, value: r.userId);
  }

  AuthException _mapError(DioException e) {
    final code = e.response?.statusCode;
    final body = e.response?.data;
    String? serverMessage;
    if (body is Map) {
      final m = body['message'];
      if (m is String) {
        serverMessage = m;
      } else if (m is List && m.isNotEmpty) {
        serverMessage = m.first.toString();
      }
    }

    if (code == 401) return AuthException('invalid email or password');
    if (code == 409) return AuthException(serverMessage ?? 'already in use');
    if (code == 400) return AuthException(serverMessage ?? 'invalid input');
    if (code == null) return AuthException('cannot reach server');
    return AuthException(serverMessage ?? 'server error ($code)');
  }
}

class AuthException implements Exception {
  final String message;
  AuthException(this.message);
  @override
  String toString() => message;
}
