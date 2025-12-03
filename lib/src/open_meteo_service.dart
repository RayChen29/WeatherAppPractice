import 'dart:convert';

import 'package:http/http.dart' as http;

/// Minimal Open-Meteo client.
///
/// Usage:
/// final svc = OpenMeteoService();
/// final json = await svc.fetchForecast(52.52, 13.41, hourly: 'temperature_2m');
class OpenMeteoService {
  final http.Client _client;

  OpenMeteoService([http.Client? client]) : _client = client ?? http.Client();

  /// Fetch forecast JSON from Open-Meteo.
  ///
  /// - latitude / longitude are required.
  /// - hourly / daily should be comma-separated variable names (e.g. 'temperature_2m').
  /// - currentWeather toggles the `current_weather` query param.
  /// - timezone defaults to 'auto' to return times in the location's timezone.
  ///
  /// Returns a decoded JSON map on success, throws on network / HTTP errors.
  Future<Map<String, dynamic>> fetchForecast(
    double latitude,
    double longitude, {
    String? hourly,
    String? daily,
    bool currentWeather = true,
    String timezone = 'auto',
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final query = <String, String>{
      'latitude': latitude.toString(),
      'longitude': longitude.toString(),
      'timezone': timezone,
    };

    if (hourly != null && hourly.isNotEmpty) query['hourly'] = hourly;
    if (daily != null && daily.isNotEmpty) query['daily'] = daily;
    if (currentWeather) query['current_weather'] = 'true';

    final uri = Uri.https('api.open-meteo.com', '/v1/forecast', query);

    final resp = await _client.get(uri).timeout(timeout);
    if (resp.statusCode != 200) {
      throw http.ClientException('OpenMeteo API error: ${resp.statusCode} ${resp.reasonPhrase}', uri);
    }

    final Map<String, dynamic> json = jsonDecode(resp.body) as Map<String, dynamic>;
    return json;
  }

  /// Close the internal client (useful in tests)
  void dispose() => _client.close();
}
