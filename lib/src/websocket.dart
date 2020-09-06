import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:flutterjanus/flutterjanus.dart';

class WebSocketWrapper {
  String url;
  List<String> protocols;
  int keepAlivePeriod;

  Function() onOpen;
  Function(dynamic) onMessage;
  Function(int, String) onError;
  Function(int, String) onClose;

  WebSocketChannel webSocketChannel;

  // Constructor
  WebSocketWrapper(this.url, this.protocols, this.keepAlivePeriod);

  void connect() {
    webSocketChannel = IOWebSocketChannel.connect(url, protocols: protocols);
    // this?.onOpen();
    webSocketChannel.stream.listen((message) {
      this.onMessage(message);
    }, onError: (error) {
      this.onError(100, error);
    }, onDone: () {
      this.onClose(0, "Websocket closed.");
    });
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
