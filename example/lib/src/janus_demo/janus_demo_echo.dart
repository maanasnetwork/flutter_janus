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
  String server = "http://fusion.minelytics.in:8088/janus";
  var janus;
  var echotest;
  String opaqueId = "echotest-" + Janus.randomString(12);
  var bitrateTimer;
  var spinner;

  bool audioenabled = false;
  bool videoenabled = false;

  bool doSimulcast = false;
  bool doSimulcast2 = false;
  String acodec = 'opus';
  String vcodec = 'vp8';

  Session _session;
  Plugin _plugin;

  List<dynamic> _peers;
  var _selfId;
  RTCVideoRenderer _localRenderer = new RTCVideoRenderer();
  RTCVideoRenderer _remoteRenderer = new RTCVideoRenderer();
  bool _inCalling = false;

  @override
  void initState() {
    // TODO: implement initState
    super.initState();
    Janus.init(
        options: {"debug": "vdebug"},
        callback: () => Janus.log("Janus Init Callback: Janus initialised."));

    GatewayCallbacks gatewayCallbacks = GatewayCallbacks();
    gatewayCallbacks.success = () => _attach();
    gatewayCallbacks.error = (error) => Janus.log(error.toString());
    gatewayCallbacks.destroyed = () => deactivate();
    _session = Session(server: server, gatewayCallbacks: gatewayCallbacks);
  }

  @override
  void deactivate() {
    // TODO: implement deactivate
    super.deactivate();
  }

  void _attach() {
    Callbacks callbacks = Callbacks();
    callbacks.plugin = "janus.plugin.echotest";
    callbacks.opaqueId = opaqueId;
    callbacks.success = () {};
  }

  _hangUp() {}

  _switchCamera() {}

  _muteMic() {}

  _buildRow(context, peer) {}

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
