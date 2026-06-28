import 'package:http/http.dart' as http;

class NetworkManager {
  static final NetworkManager _instance = NetworkManager._internal();
  static NetworkManager get instance => _instance;
  
  String? _token;
  
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

  Future<http.Response> get(String url, {Map<String, String>? headers}) async {
    return await http.get(Uri.parse(url), headers: _getHeaders(headers));
  }

  Future<http.Response> post(String url, {Map<String, String>? headers, Object? body}) async {
    return await http.post(Uri.parse(url), headers: _getHeaders(headers), body: body);
  }

  Future<http.Response> put(String url, {Map<String, String>? headers, Object? body}) async {
    return await http.put(Uri.parse(url), headers: _getHeaders(headers), body: body);
  }

  Future<http.Response> delete(String url, {Map<String, String>? headers}) async {
    return await http.delete(Uri.parse(url), headers: _getHeaders(headers));
  }

  http.MultipartRequest multipartRequest(String method, String url) {
    var request = http.MultipartRequest(method, Uri.parse(url));
    if (_token != null) {
      request.headers['Authorization'] = 'Bearer $_token';
    }
    return request;
  }
}
