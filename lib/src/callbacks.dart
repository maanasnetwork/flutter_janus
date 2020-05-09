class GatewayCallbacks {
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

  dynamic message;
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
