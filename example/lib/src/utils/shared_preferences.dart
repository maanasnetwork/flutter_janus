import 'package:shared_preferences/shared_preferences.dart';

class JanusSharedPreferences {
  static final String _kJanusServer = "wss://janutter.tzty.net:7007";
  static final String _kApiKey = null;
  static final String _kSipSettings = null;

  static Future<String> getJanusServer() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();

    return prefs.getString(_kJanusServer) ?? "wss://janutter.tzty.net:7007";
  }

  static Future<bool> setJanusServer(String value) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();

    return prefs.setString(_kJanusServer, value);
  }

  static Future<String> getApiKey() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();

    return prefs.getString(_kApiKey) ?? null;
  }

  static Future<bool> setApiKey(String value) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();

    return prefs.setString(_kApiKey, value);
  }

  static Future<String> getSipSettings() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();

    return prefs.getString(_kSipSettings) ?? null;
  }

  static Future<bool> setSipSettings(String value) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();

    return prefs.setString(_kSipSettings, value);
  }
}
