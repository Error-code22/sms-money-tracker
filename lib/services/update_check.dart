import 'dart:convert';

import 'package:http/http.dart' as http;

class UpdateCheck {
  /// Returns the latest GitHub release (tag, html_url), or null when there
  /// is no release (404) or the request fails (offline). Never throws.
  static Future<({String tag, String url})?> latestRelease() async {
    try {
      final res = await http
          .get(
            Uri.parse(
              'https://api.github.com/repos/Error-code22/sms-money-tracker/releases/latest',
            ),
          )
          .timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) return null;
      final json = jsonDecode(res.body) as Map<String, dynamic>;
      final tag = json['tag_name'] as String?;
      if (tag == null || tag.isEmpty) return null;
      return (tag: tag, url: json['html_url'] as String? ?? '');
    } catch (_) {
      return null;
    }
  }
}
