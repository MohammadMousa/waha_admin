import 'dart:convert';
import 'package:http/http.dart' as http;

class AppConfig {
  static String apiBaseUrl = '';

  static Future<void> init() async {
    try {
      // Relative URL resolves against <base href>; the ?t= param avoids cached copies
      final res = await http.get(
        Uri.parse('config.json?t=${DateTime.now().millisecondsSinceEpoch}'),
      );
      if (res.statusCode == 200) {
        final data = json.decode(utf8.decode(res.bodyBytes));
        apiBaseUrl = (data['apiBaseUrl'] as String?) ?? '';
      }
    } catch (_) {
      apiBaseUrl = '';
    }
  }
}
