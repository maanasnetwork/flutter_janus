import 'dart:async';

import 'package:flutter/services.dart';

class Flutterjanus {
  static const MethodChannel _channel =
      const MethodChannel('flutterjanus');

  static Future<String> get platformVersion async {
    final String version = await _channel.invokeMethod('getPlatformVersion');
    return version;
  }
}
