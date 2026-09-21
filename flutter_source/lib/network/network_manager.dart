import 'package:http/http.dart' as http;

class NetworkManager {
  static final NetworkManager _instance = NetworkManager._internal();
  static NetworkManager get instance => _instance;

  // Every call below had no timeout at all - a dead/unreachable backend
  // hung the awaiting screen (login, dashboard, agent chat, everything)
  // indefinitely, with no way to recover short of killing the app. 30s
  // covers this app's normal API calls; a caller doing something
  // genuinely slower (LLM generation, OCR) passes its own `timeout`.
  static const Duration _defaultTimeout = Duration(seconds: 30);

  String? _token;
  String? get token => _token;

  NetworkManager._internal();

  void setToken(String token) {
    _token = token;
  }

  void clearToken() {
    _token = null;
  }

  Map<String, String> _getHeaders(Map<String, String>? customHeaders) {
    var headers = customHeaders ?? {};
    if (_token != null) {
      headers['Authorization'] = 'Bearer $_token';
    }
    return headers;
  }

  /// The bearer-auth header alone, for widgets that need to attach it
  /// themselves (e.g. `NetworkImage(url, headers: NetworkManager.instance.authHeaders())`
  /// for the authenticated /uploads mount) rather than going through
  /// get/post/put/delete above.
  Map<String, String> authHeaders() =>
      _token != null ? {'Authorization': 'Bearer $_token'} : {};

  Future<http.Response> get(String url,
      {Map<String, String>? headers, Duration? timeout}) async {
    return await http
        .get(Uri.parse(url), headers: _getHeaders(headers))
        .timeout(timeout ?? _defaultTimeout);
  }

  Future<http.Response> post(String url,
      {Map<String, String>? headers, Object? body, Duration? timeout}) async {
    return await http
        .post(Uri.parse(url), headers: _getHeaders(headers), body: body)
        .timeout(timeout ?? _defaultTimeout);
  }

  Future<http.Response> put(String url,
      {Map<String, String>? headers, Object? body, Duration? timeout}) async {
    return await http
        .put(Uri.parse(url), headers: _getHeaders(headers), body: body)
        .timeout(timeout ?? _defaultTimeout);
  }

  Future<http.Response> delete(String url,
      {Map<String, String>? headers, Duration? timeout}) async {
    return await http
        .delete(Uri.parse(url), headers: _getHeaders(headers))
        .timeout(timeout ?? _defaultTimeout);
  }

  http.MultipartRequest multipartRequest(String method, String url) {
    var request = http.MultipartRequest(method, Uri.parse(url));
    if (_token != null) {
      request.headers['Authorization'] = 'Bearer $_token';
    }
    return request;
  }
}
