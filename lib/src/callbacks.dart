class GatewayCallbacks {
  var server;
  List iceServers = [
    {"urls": "stun:stun.l.google.com:19302"}
  ];
  var iceTransportPolicy;
  var bundlePolicy;
  bool ipv6Support = false;
  bool withCredentials = false;
  int maxPollEvents = 10;
  String token;
  String apiSecret;
  bool destroyOnUnload = true;
  int keepAlivePeriod = 25000;
  int longPollTimeout = 60000;

  Function success = () => {};
  Function error = () => {};
  Function destroyed = () => {};
}

class Callbacks {
  String plugin;
  String opaqueId;
  String token;
  String transaction;
  Map<String, String> request;

  Map<String, dynamic> message;
  dynamic jsep;
  dynamic text;
  dynamic data;
  dynamic label;
  dynamic dtmf;
  dynamic noRequest;
  dynamic rtcConstraints;
  dynamic simulcast2;

  Function success = () => {};
  Function error = () => {};
  Function consentDialog = () => {};
  Function iceState = () => {};
  Function mediaState = () => {};
  Function webrtcState = () => {};
  Function slowLink = () => {};
  Function onmessage = () => {};
  Function onlocalstream = () => {};
  Function onremotestream = () => {};
  Function ondata = () => {};
  Function ondataopen = () => {};
  Function oncleanup = () => {};
  Function ondetached = () => {};
}
