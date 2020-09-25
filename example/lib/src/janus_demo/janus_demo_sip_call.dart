import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:flutterjanus/flutterjanus.dart';

class JanusSipCall extends StatefulWidget {
  JanusSipCall({Key key}) : super(key: key);

  @override
  _JanusSipCallState createState() => _JanusSipCallState();
}

class _JanusSipCallState extends State<JanusSipCall> {
  String server = "wss://janutter.tzty.net:7007";
  // String server = "https://janutter.tzty.net:8008/janus";
  var sipcall;
  String opaqueId = "siptest-" + Janus.randomString(12);

  String selectAppraoch;
  bool registered = false;
  var masterId;
  var helpers = {};
  int helpersCount;
  var incoming;

  Session session;
  Plugin sip;

  MediaStream _localStream;
  RTCVideoRenderer _localRenderer = new RTCVideoRenderer();
  RTCVideoRenderer _remoteRenderer = new RTCVideoRenderer();
  bool _inCalling = false;

  TextEditingController nameController = TextEditingController();

  _JanusSipCallState({Key key});

  @override
  void initState() {
    super.initState();
    Janus.init(options: {"debug": "all"}, callback: null);
    initRenderers();
  }

  initRenderers() async {
    await _localRenderer.initialize();
    await _remoteRenderer.initialize();
    _connect();
  }

  @override
  void deactivate() {
    super.deactivate();
    if (session != null) session.destroy();
    _localRenderer.dispose();
    _remoteRenderer.dispose();
  }

  registerDialog() {
    showDialog(
        context: context,
        barrierDismissible: false,
        child: AlertDialog(
          title: Text("Register as"),
          content: Column(
            mainAxisSize: MainAxisSize.max,
            children: [
              TextFormField(
                decoration: InputDecoration(labelText: "Username"),
                controller: nameController,
              ),
              RaisedButton(
                color: Colors.green,
                textColor: Colors.white,
                onPressed: () {
                  registerUsername(nameController.text);
                },
                child: Text("Proceed"),
              )
            ],
          ),
        ));
  }

  makeCallDialog() {
    showDialog(
        context: context,
        barrierDismissible: false,
        child: AlertDialog(
          title: Text("Call Registered User or wait for user to call you"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                decoration: InputDecoration(
                    labelText: "Name Of Registered User to call"),
                controller: nameController,
              ),
              RaisedButton(
                color: Colors.green,
                textColor: Colors.white,
                onPressed: () {
                  doCall(nameController.text, false, null);
                  Navigator.of(context).pop();
                },
                child: Text("Call"),
              )
            ],
          ),
        ));
  }

  registerUsername(username) {
    if (sipcall != null) {
      sipcall.send({
        "message": {"request": "register", "username": username}
      });
    }
  }

  doCall(uri, doVideo, referId) {
    if (sipcall != null) {
      Callbacks callbacks = Callbacks();
      callbacks.media = {
        "audioSend": true,
        "audioRecv": true,
        "videoSend": doVideo,
        "videoRecv": doVideo
      };
      callbacks.success = (RTCSessionDescription jsep) {
        Janus.debug("Got SDP!");
        Janus.debug(jsep.toMap());
        Map<String, dynamic> body = {"request": "call", "uri": uri};
        if (referId) body["refer_id"] = referId;
        callbacks.message = body;
        callbacks.jsep = jsep.toMap();
        sipcall.send(callbacks);
      };
      callbacks.error = (error) {
        Janus.error("WebRTC error:", error);
        Janus.log("WebRTC error... " + jsonEncode(error));
      };
      Janus.debug("Trying a createOffer too (audio/video sendrecv)");
      sipcall.createOffer(callbacks: callbacks);
    }
  }

  void _connect() async {
    GatewayCallbacks gatewayCallbacks = GatewayCallbacks();
    gatewayCallbacks.server = this.server;
    gatewayCallbacks.success = _attach;
    gatewayCallbacks.error = (error) => Janus.log(error.toString());
    gatewayCallbacks.destroyed = () => deactivate();
    Session(gatewayCallbacks); // async httpd call
    setState(() {
      _inCalling = true;
    });
  }

  void _attach(int sessionId) {
    session = Janus.sessions[sessionId.toString()];

    Callbacks callbacks = Callbacks();
    callbacks.plugin = "janus.plugin.videocall";
    callbacks.opaqueId = opaqueId;
    callbacks.success = _success;
    callbacks.error = _error;
    callbacks.consentDialog = _consentDialog;
    callbacks.iceState = _iceState;
    callbacks.mediaState = _mediaState;
    callbacks.webrtcState = _webrtcState;
    callbacks.slowLink = _slowLink;
    callbacks.onMessage = _onMessage;
    callbacks.onLocalStream = _onLocalStream;
    callbacks.onRemoteStream = _onRemoteStream;
    callbacks.onDataOpen = _onDataOpen;
    callbacks.onData = _onData;
    callbacks.onCleanup = _onCleanup;
    this.session.attach(callbacks: callbacks);
  }

  _success(Plugin pluginHandle) {
    sipcall = pluginHandle;
    Janus.log("Plugin attached! (" +
        this.sipcall.getPlugin() +
        ", id=" +
        sipcall.getId().toString() +
        ")");
    Map<String, dynamic> body = {"audio": true, "video": true};
    Janus.debug("Sending message (" + jsonEncode(body) + ")");
    // Create am empty callback for the message
    Callbacks callbacks = Callbacks();
    callbacks.message = body;
    sipcall.send(callbacks);
    // No media provided: by default, it's sendrecv for audio and video
  }

  _error(error) {
    Janus.log("  -- Error attaching plugin...", error.toString());
  }

  _consentDialog(bool on) {
    Janus.debug("Consent dialog should be " + (on ? "on" : "off") + " now");
  }

  _iceState(RTCIceConnectionState state) {
    Janus.log("ICE state changed to " + state.toString());
  }

  _mediaState(String medium, bool on) {
    Janus.log(
        "Janus " + (on ? "started" : "stopped") + " receiving our " + medium);
  }

  _webrtcState(bool on) {
    Janus.log("Janus says our WebRTC PeerConnection is " +
        (on ? "up" : "down") +
        " now");
  }

  _slowLink(bool uplink, lost) {
    Janus.warn("Janus reports problems " +
        (uplink ? "sending" : "receiving") +
        " packets on this PeerConnection (" +
        lost +
        " lost packets)");
  }

  _onMessage(msg, jsep) {
    Janus.debug(" ::: Got a message :::");
    Janus.debug(msg);
    if (jsep != null) {
      Janus.debug("Handling SDP as well...");
      Janus.debug(jsep);
      Callbacks callbacks = Callbacks();
      callbacks.jsep = jsep;
      sipcall.handleRemoteJsep(callbacks);
    }
    var result = msg["result"];
    Janus.log(result);
    if (result != null) {
      if (result == "done") {
        Janus.log("Echo Test is over");
      }

      var status = result["status"];
      if (status == "slow_link") {
        Janus.log(
            "Janus apparently missed many packets we sent, maybe we should reduce the bitrate",
            "Packet loss?");
      }
    }
  }

  _onLocalStream(MediaStream stream) {
    Janus.debug(" ::: Got a local stream :::");
    _localStream = stream;
    _localRenderer.srcObject = stream;
  }

  _onRemoteStream(MediaStream stream) {
    Janus.debug(" ::: Got a remote stream :::");
    _remoteRenderer.srcObject = stream;
  }

  _onDataOpen(data) {
    Janus.log("The DataChannel is available!");
  }

  _onData(data) {
    Janus.debug("We got data from the DataChannel! " + data);
  }

  _onCleanup() {
    Janus.log(" ::: Got a cleanup notification :::");
  }

  _hangUp() async {
    try {
      GatewayCallbacks gatewayCallbacks;
      session.destroy(gatewayCallbacks: gatewayCallbacks);
      _localRenderer.srcObject = null;
      _remoteRenderer.srcObject = null;
    } catch (e) {
      print(e.toString());
    }
    Janus.log('Hangup called');
    setState(() {
      _inCalling = false;
    });
  }

  _switchCamera() {
    Janus.log('Switching camera');
  }

  _muteMic() {}

  @override
  Widget build(BuildContext context) {
    return new Scaffold(
      appBar: new AppBar(
        title: new Text('Sipcall Test'),
        actions: <Widget>[
          Padding(
              padding: EdgeInsets.only(right: 20.0),
              child: GestureDetector(
                onTap: registerDialog,
                child: Icon(
                  Icons.settings,
                  size: 26.0,
                ),
              )),
        ],
      ),
      body: new OrientationBuilder(
        builder: (context, orientation) {
          return new Center(
            child: new Container(
              decoration: new BoxDecoration(color: Colors.white),
              child: new Stack(
                children: <Widget>[
                  new Align(
                    alignment: orientation == Orientation.portrait
                        ? const FractionalOffset(0.5, 0.1)
                        : const FractionalOffset(0.0, 0.5),
                    child: new Container(
                      margin: new EdgeInsets.fromLTRB(0.0, 0.0, 0.0, 0.0),
                      width: 320.0,
                      height: 240.0,
                      child: new RTCVideoView(_localRenderer),
                      decoration: new BoxDecoration(color: Colors.black54),
                    ),
                  ),
                  new Align(
                    alignment: orientation == Orientation.portrait
                        ? const FractionalOffset(0.5, 0.9)
                        : const FractionalOffset(1.0, 0.5),
                    child: new Container(
                      margin: new EdgeInsets.fromLTRB(0.0, 0.0, 0.0, 0.0),
                      width: 320.0,
                      height: 240.0,
                      child: new RTCVideoView(_remoteRenderer),
                      decoration: new BoxDecoration(color: Colors.black54),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
      floatingActionButton: new FloatingActionButton(
        onPressed: _inCalling ? _hangUp : doCall,
        tooltip: _inCalling ? 'Hangup' : 'Call',
        child: new Icon(_inCalling ? Icons.call_end : Icons.phone),
      ),
    );
  }
}