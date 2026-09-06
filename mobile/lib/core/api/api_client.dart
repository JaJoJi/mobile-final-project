import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../config/app_config.dart';

/// Provider exposing a singleton [ApiClient] for the rest of the app.
final apiClientProvider = Provider<ApiClient>((ref) => ApiClient());

/// Storage keys for the auth interceptor to read the access token.
const _kAccessTokenKey = 'access_token';
const _kRefreshTokenKey = 'refresh_token';
const _kUserIdKey = 'user_id';

class ApiClient {
  final Dio _dio;
  final FlutterSecureStorage _storage;

  ApiClient()
      : _dio = Dio(
          BaseOptions(
            baseUrl: AppConfig.apiBaseUrl,
            connectTimeout: AppConfig.requestTimeout,
            receiveTimeout: AppConfig.requestTimeout,
            sendTimeout: AppConfig.requestTimeout,
            headers: {
              'Accept': 'application/json',
              // Force a new TCP connection per request so nginx's
              // `least_conn` actually round-robins across the 3 Nest
              // instances. Without this, HTTP/1.1 keep-alive pins us to
              // whatever Nest instance answered first.
              'Connection': 'close',
            },
          ),
        ),
        _storage = const FlutterSecureStorage() {
    _dio.interceptors.add(_AuthHeaderInterceptor(_storage));
  }

  // ─── connectivity / smoke ────────────────────────────────────────

  Future<Map<String, dynamic>> getHealth() async {
    final res = await _dio.get('/health');
    return Map<String, dynamic>.from(res.data as Map);
  }

  Future<Map<String, dynamic>> whoami() async {
    final res = await _dio.get('/health/whoami');
    return Map<String, dynamic>.from(res.data as Map);
  }

  Future<List<Map<String, dynamic>>> pingInstances(int times) async {
    final futures = List.generate(times, (_) => whoami());
    return Future.wait(futures);
  }

  // ─── auth ─────────────────────────────────────────────────────────

  Future<AuthResult> register({
    required String email,
    required String username,
    required String password,
  }) async {
    final res = await _dio.post('/auth/register', data: {
      'email': email,
      'username': username,
      'password': password,
    });
    return _parseAuth(res);
  }

  Future<AuthResult> login({
    required String email,
    required String password,
  }) async {
    final res = await _dio.post('/auth/login', data: {
      'email': email,
      'password': password,
    });
    return _parseAuth(res);
  }

  Future<AuthResult> refresh(String refreshToken) async {
    final res = await _dio.post('/auth/refresh', data: {
      'refreshToken': refreshToken,
    });
    return _parseAuth(res);
  }

  // ─── user ─────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> getMe() async {
    final res = await _dio.get('/user/me');
    return Map<String, dynamic>.from(res.data as Map);
  }

  Future<Map<String, dynamic>> updateMe({required String username}) async {
    final res = await _dio.patch('/user/me', data: {'username': username});
    return Map<String, dynamic>.from(res.data as Map);
  }

  // ─── helpers ──────────────────────────────────────────────────────

  AuthResult _parseAuth(Response res) {
    final data = res.data as Map<String, dynamic>;
    return AuthResult(
      userId: data['userId'] as String,
      accessToken: data['accessToken'] as String,
      refreshToken: data['refreshToken'] as String,
    );
  }
}

class AuthResult {
  final String userId;
  final String accessToken;
  final String refreshToken;
  AuthResult({
    required this.userId,
    required this.accessToken,
    required this.refreshToken,
  });
}

/// Dio interceptor that injects `Authorization: Bearer <token>` on every
/// request, reading the token from secure storage.
///
/// Web fallback: flutter_secure_storage on web uses localStorage, which
/// is acceptable for MVP (real prod would use proper key exchange).
class _AuthHeaderInterceptor extends Interceptor {
  final FlutterSecureStorage _storage;
  _AuthHeaderInterceptor(this._storage);

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    // Skip auth header for /auth/* endpoints (they issue tokens)
    // and the public /health endpoints.
    if (!options.path.startsWith('/auth/')) {
      final token = await _storage.read(key: _kAccessTokenKey);
      if (token != null && token.isNotEmpty) {
        options.headers['Authorization'] = 'Bearer $token';
      }
    }
    handler.next(options);
  }
}
