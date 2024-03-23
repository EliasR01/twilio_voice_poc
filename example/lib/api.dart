import 'dart:convert';

import 'package:http/http.dart' as http;

import 'utils.dart';

class Result {
  final String identity;
  final String accessToken;

  Result(this.identity, this.accessToken);
}

/// Register with a local token generator using URL http://localhost:3000/token. This is a function to generate token for twilio voice.
/// [generateLocalAccessToken] is the default method for registering
///
/// Returned data should contained the following format:
/// {
///  "identity": "user123",
///  "token": "ey...",
/// }
Future<dynamic> generateLocalAccessToken() async {
  try {
    final uri = Uri.http("192.168.0.162:8000", "/token");
    final result = await http.get(uri);
    if (result.statusCode >= 300 && result.statusCode < 500) {
      printDebug("Error requesting token from server [${uri.toString()}]");
      printDebug(result.body);
      return null;
    }
    final res = result.body;

    return res;
  } catch (err) {
    printDebug("Got error requesting API: $err");
  }
  return null;
}

Future<void> streamCall(String callSid) async {
  try {
    final uri = Uri.http("192.168.0.162:8000", "/start-streaming");
    final result = await http.post(
      uri,
      body: json.encode(
        <String, dynamic>{"callSid": callSid},
      ),
    );
    if (result.statusCode >= 300 && result.statusCode < 500) {
      printDebug("Error requesting token from server [${uri.toString()}]");
    }
  } catch (err) {
    printDebug("Got error requesting API: $err");
  }
}
