import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'dart:io';

typedef void OnMessageCallback(dynamic msg);
typedef void OnErrorCallback(int code, String reason);
typedef void OnCloseCallback(int code, String reason);
typedef void OnOpenCallback();

class SimpleWebSocket {
  String url;
  List<String> protocols;
  int keepAlivePeriod;
  WebSocketChannel webSocketChannel;

  // Webscoket Callbacks
  OnOpenCallback onOpen;
  OnMessageCallback onMessage;
  OnErrorCallback onError;
  OnCloseCallback onClose;

  // Constructor
  SimpleWebSocket(this.url, this.protocols, this.keepAlivePeriod);

  connect() {
    Duration pingInterval = Duration(seconds: (keepAlivePeriod ~/ 1000));
    webSocketChannel = IOWebSocketChannel.connect(url,
        protocols: protocols, pingInterval: pingInterval);

    // this?.onOpen();
    // webSocketChannel.listen((data) {
    //   this?.onMessage(data);
    // }, onDone: () {
    //   this?.onClose(webSocketChannel.closeCode, webSocketChannel.closeReason);
    // });
  }

  send(data) {
    if (webSocketChannel != null) {
      webSocketChannel.sink.add(data);
    }
  }

  close() {
    if (webSocketChannel != null) webSocketChannel.sink.close();
  }
}
