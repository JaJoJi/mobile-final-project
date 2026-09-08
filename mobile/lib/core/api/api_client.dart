import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../auth/auth_gate.dart';
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

  /// [dio] and [storage] are injectable for tests; production passes
  /// neither and gets the real HTTP client + secure storage.
  ApiClient({Dio? dio, FlutterSecureStorage? storage})
      : _dio = dio ?? _defaultDio(),
        _storage = storage ?? const FlutterSecureStorage() {
    _dio.interceptors.add(AuthInterceptor(_storage, _dio));
  }

  static Dio _defaultDio() => Dio(
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
      );

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

/// Dio interceptor that
///   1. injects `Authorization: Bearer <token>` on every non-`/auth/`
///      request, and
///   2. on a `401`, silently refreshes the access token with the stored
///      refresh token and retries the original request **once**.
///
/// If the refresh itself fails (refresh token expired / revoked) the
/// stored tokens are wiped and [AuthGate.signalSignedOut] fires, which the
/// router listens to and redirects to `/login`. The interceptor never
/// rethrows an unrelated exception — a failed refresh surfaces as the
/// original `401`.
///
/// Web fallback: flutter_secure_storage on web uses localStorage, which
/// is acceptable for MVP (real prod would use proper key exchange).
class AuthInterceptor extends QueuedInterceptor {
  AuthInterceptor(this._storage, Dio parentDio)
      : _refreshDio = Dio(BaseOptions(
          baseUrl: parentDio.options.baseUrl,
          connectTimeout: parentDio.options.connectTimeout,
          receiveTimeout: parentDio.options.receiveTimeout,
          headers: const {'Accept': 'application/json', 'Connection': 'close'},
        ))
          // Share the transport so tests' fake adapter also serves the
          // refresh + retry calls. No interceptors here → those requests
          // can't re-enter this queued interceptor and deadlock it.
          ..httpClientAdapter = parentDio.httpClientAdapter;

  final FlutterSecureStorage _storage;

  /// Interceptor-free client used for the token refresh and the one retry.
  final Dio _refreshDio;

  /// Marks a request that has already been retried after a refresh so a
  /// second `401` can't loop forever.
  static const _retriedKey = 'auth_retried';

  bool _isAuthPath(String path) => path.startsWith('/auth/');

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    if (!_isAuthPath(options.path)) {
      final token = await _storage.read(key: _kAccessTokenKey);
      if (token != null && token.isNotEmpty) {
        options.headers['Authorization'] = 'Bearer $token';
      }
    }
    handler.next(options);
  }

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    final res = err.response;
    final req = err.requestOptions;
    final canRetry = res?.statusCode == 401 &&
        !_isAuthPath(req.path) &&
        req.extra[_retriedKey] != true;

    if (!canRetry) {
      handler.next(err);
      return;
    }

    final newAccess = await _refresh();
    if (newAccess == null) {
      // Refresh failed → tokens already cleared → tell the router.
      AuthGate.instance.signalSignedOut();
      handler.next(err);
      return;
    }

    try {
      // Retry on the bare Dio (no interceptors) so a second failure can't
      // re-enter this queued interceptor and deadlock it.
      final retried = await _refreshDio.fetch<dynamic>(
        req
          ..headers['Authorization'] = 'Bearer $newAccess'
          ..extra[_retriedKey] = true,
      );
      handler.resolve(retried);
    } on DioException catch (e) {
      handler.next(e);
    }
  }

  /// Exchanges the stored refresh token for a new pair. Persists the new
  /// tokens and returns the fresh access token, or `null` (and clears
  /// storage) on any failure. Runs on [_refreshDio] (no interceptors) so
  /// it never re-enters this queued interceptor.
  Future<String?> _refresh() async {
    final refreshToken = await _storage.read(key: _kRefreshTokenKey);
    if (refreshToken == null || refreshToken.isEmpty) {
      await _clear();
      return null;
    }
    try {
      final res = await _refreshDio.post<Map<String, dynamic>>(
        '/auth/refresh',
        data: {'refreshToken': refreshToken},
      );
      final data = res.data!;
      final access = data['accessToken'] as String;
      await _storage.write(key: _kAccessTokenKey, value: access);
      await _storage.write(
          key: _kRefreshTokenKey, value: data['refreshToken'] as String);
      await _storage.write(key: _kUserIdKey, value: data['userId'] as String);
      return access;
    } catch (_) {
      await _clear();
      return null;
    }
  }

  Future<void> _clear() async {
    await _storage.delete(key: _kAccessTokenKey);
    await _storage.delete(key: _kRefreshTokenKey);
    await _storage.delete(key: _kUserIdKey);
  }
}
