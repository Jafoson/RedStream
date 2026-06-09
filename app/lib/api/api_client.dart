import 'package:dio/dio.dart';

/// Creates a configured Dio instance for the given server URL.
/// If [profileId] is supplied, every request carries an X-Profile-ID header.
/// If [authToken] is supplied, every request carries an Authorization: Bearer header.
Dio buildDio(String serverUrl, {int? profileId, String? authToken}) {
  final base = serverUrl.endsWith('/') ? serverUrl.substring(0, serverUrl.length - 1) : serverUrl;
  final headers = <String, dynamic>{'Content-Type': 'application/json'};
  if (profileId != null) headers['X-Profile-ID'] = profileId.toString();
  if (authToken != null && authToken.isNotEmpty) {
    headers['Authorization'] = 'Bearer $authToken';
  }
  return Dio(
    BaseOptions(
      baseUrl: base,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 30),
      headers: headers,
    ),
  );
}
