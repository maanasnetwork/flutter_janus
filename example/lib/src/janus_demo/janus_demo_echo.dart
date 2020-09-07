import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutterjanus/src/callbacks.dart';
import 'dart:core';
import 'package:flutter_webrtc/webrtc.dart';
import 'package:flutterjanus/src/janus.dart';
import 'package:flutterjanus/src/session.dart';
import 'package:flutterjanus/src/plugin.dart';

class JanusEcho extends StatefulWidget {
  static String tag = 'janus_demo_echo';

  JanusEcho({Key key}) : super(key: key);

  @override
  _JanusEchoState createState() => _JanusEchoState();
}

class _JanusEchoState extends State<JanusEcho> {
  String server = "wss://janutter.tzty.net:7007";
  // String server = "https://janutter.tzty.net:8008/janus";
  var janus;
  var echotest;
  String opaqueId = "echotest-" + Janus.randomString(12);
  var bitrateTimer;
  var spinner;

  bool audioenabled = false;
  bool videoenabled = false;

  bool doSimulcast = false;
  bool doSimulcast2 = false;
  String acodec;
  String vcodec;
  bool simulcastStarted = false;

  Session _session;
  Plugin _plugin;
  Map<String, dynamic> _handle;

  List<dynamic> _peers;
  var _selfId;
  RTCVideoRenderer _localRenderer = new RTCVideoRenderer();
  RTCVideoRenderer _remoteRenderer = new RTCVideoRenderer();
  bool _inCalling = false;

  @override
  void initState() {
    super.initState();
    Janus.init(options: {"debug": "all"}, callback: null);
    initRenderers();
    _connect();
  }

  initRenderers() async {
    await _localRenderer.initialize();
    await _remoteRenderer.initialize();
  }

  @override
  void deactivate() {
    super.deactivate();
    _localRenderer.dispose();
    _remoteRenderer.dispose();
  }

  void _connect() async {
    GatewayCallbacks gatewayCallbacks = GatewayCallbacks();
    gatewayCallbacks.server = this.server;
    gatewayCallbacks.success = _attach;
    gatewayCallbacks.error = (error) => Janus.log(error.toString());
    gatewayCallbacks.destroyed = () => deactivate();
    Session(gatewayCallbacks); // async httpd call
  }

  void _attach(int sessionId) {
    this._session = Janus.sessions[sessionId.toString()];

    Callbacks callbacks = Callbacks();
    callbacks.plugin = "janus.plugin.echotest";
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
    this._session.attach(callbacks: callbacks);
  }

  _success(Plugin pluginHandle) {
    Plugin echotest = pluginHandle;
    Janus.log("Plugin attached! (" +
        echotest.getPlugin() +
        ", id=" +
        echotest.getId() +
        ")");
    Map<String, dynamic> body = {"audio": true, "video": true};
    if (this.acodec != null) body['audiocodec'] = this.acodec;
    if (this.vcodec != null) body['videocodec'] = this.vcodec;
    Janus.debug("Sending message (" + jsonEncode(body) + ")");
    // Create am empty callback for the message
    Callbacks callbacks = Callbacks();
    callbacks.success = null;
    callbacks.message = body;
    Janus.log(callbacks.success.runtimeType);
    echotest.send(callbacks);
    // No media provided: by default, it's sendrecv for audio and video

    // Let's negotiate data channels as well
    callbacks.media["data"] = false;
    callbacks.simulcast = doSimulcast;
    callbacks.simulcast2 = doSimulcast2;
    callbacks.success = (RTCSessionDescription jsep) {
      Janus.debug("Got SDP!");
      Janus.debug(jsep.toMap());
      callbacks.message = body;
      callbacks.jsep = jsep.toMap();
      echotest.send(callbacks);
    };
    callbacks.error = (error) {
      Janus.error("WebRTC error:", error);
      Janus.log("WebRTC error... " + jsonEncode(error));
    };
    Janus.debug("Trying a createOffer too (audio/video sendrecv)");

    echotest.createOffer(callbacks: callbacks);
  }

  _error(error) {
    Janus.log("  -- Error attaching plugin...", error.toString());
  }

  _consentDialog(bool on) {
    Janus.debug("Consent dialog should be " + (on ? "on" : "off") + " now");
  }

  _iceState(String state) {
    Janus.log("ICE state changed to " + state);
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

  _onMessage(msg, jsep) {}

  _onLocalStream(MediaStream stream) {
    Janus.log('Local Stream available');
    _localRenderer.srcObject = stream;
  }

  _onRemoteStream(MediaStream stream) {
    Janus.log('Remote Stream available');
    _remoteRenderer.srcObject = stream;
  }

  _onDataOpen(data) {
    Janus.log('Data Channel opened');
  }

  _onData(data) {
    Janus.log('Data received');
  }

  _onCleanup() {
    Janus.log(" ::: Got a cleanup notification :::");
  }

  _hangUp() {
    Janus.log('Hangup called');
  }

  _switchCamera() {
    Janus.log('Switching camera');
  }

  _muteMic() {}

  _buildRow(context, peer) {
    var self = (peer['id'] == _selfId);
    return ListBody(children: <Widget>[
      ListTile(
        title: Text(self
            ? peer['name'] + '[Your self]'
            : peer['name'] + '[' + peer['user_agent'] + ']'),
        onTap: null,
        trailing: new SizedBox(
            width: 100.0,
            child: new Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: <Widget>[
                  IconButton(
                    icon: const Icon(Icons.videocam),
                    onPressed: () => {},
                    tooltip: 'Echo Test',
                  ),
                ])),
        subtitle: Text('id: ' + peer['id']),
      ),
      Divider()
    ]);
  }

  @override
  Widget build(BuildContext context) {
    return new Scaffold(
      appBar: new AppBar(
        title: new Text('Janus Echo Test'),
        actions: <Widget>[
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: null,
            tooltip: 'setup',
          ),
        ],
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: _inCalling
          ? new SizedBox(
              width: 200.0,
              child: new Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: <Widget>[
                    FloatingActionButton(
                      child: const Icon(Icons.switch_camera),
                      onPressed: _switchCamera,
                    ),
                    FloatingActionButton(
                      onPressed: _hangUp,
                      tooltip: 'Hangup',
                      child: new Icon(Icons.call_end),
                      backgroundColor: Colors.pink,
                    ),
                    FloatingActionButton(
                      child: const Icon(Icons.mic_off),
                      onPressed: _muteMic,
                    )
                  ]))
          : null,
      body: _inCalling
          ? OrientationBuilder(builder: (context, orientation) {
              return new Container(
                child: new Stack(children: <Widget>[
                  new Positioned(
                      left: 0.0,
                      right: 0.0,
                      top: 0.0,
                      bottom: 0.0,
                      child: new Container(
                        margin: new EdgeInsets.fromLTRB(0.0, 0.0, 0.0, 0.0),
                        width: MediaQuery.of(context).size.width,
                        height: MediaQuery.of(context).size.height,
                        child: new RTCVideoView(_remoteRenderer),
                        decoration: new BoxDecoration(color: Colors.black54),
                      )),
                  new Positioned(
                    left: 20.0,
                    top: 20.0,
                    child: new Container(
                      width: orientation == Orientation.portrait ? 90.0 : 120.0,
                      height:
                          orientation == Orientation.portrait ? 120.0 : 90.0,
                      child: new RTCVideoView(_localRenderer),
                      decoration: new BoxDecoration(color: Colors.black54),
                    ),
                  ),
                ]),
              );
            })
          : new ListView.builder(
              shrinkWrap: true,
              padding: const EdgeInsets.all(0.0),
              itemCount: (_peers != null ? _peers.length : 0),
              itemBuilder: (context, i) {
                return _buildRow(context, _peers[i]);
              }),
    );
  }
}
