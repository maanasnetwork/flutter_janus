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
  String opaqueId = "siptest-" + Janus.randomString(12);

  bool audioEnabled = false;
  bool videoEnabled = false;

  String myUsername;
  String yourUsername;
  Map<String, dynamic> peers;

  bool doSimulcast = false;
  bool doSimulcast2 = false;
  bool simulcastStarted = false;

  Session session;
  Plugin sipcall;

  MediaStream _localStream;
  RTCVideoRenderer _localRenderer = new RTCVideoRenderer();
  RTCVideoRenderer _remoteRenderer = new RTCVideoRenderer();
  bool _inCalling = false;
  bool _registered = false;
  var selectedApproach;
  var masterId;
  var helpers = {};
  int helpersCount = 0;

  TextEditingController textController = TextEditingController();

  _JanusSipCallState({Key key});

  @override
  void initState() {
    super.initState();
    Janus.init(options: {"debug": "all"}, callback: _connect);
    initRenderers();
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
    if (session != null) session.destroy();
  }

  registerDialog() {
    showDialog(
        context: context,
        builder: (BuildContext context) {
          return Dialog(
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20.0)), //this right here
            child: Container(
              height: 200,
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      decoration: InputDecoration(
                          border: InputBorder.none,
                          hintText: 'Register as username ...'),
                      controller: textController,
                    ),
                    SizedBox(
                      width: 320.0,
                      child: RaisedButton(
                        onPressed: () {
                          registerUsername(textController.text);
                          Navigator.of(context).pop();
                        },
                        child: Text(
                          "Register",
                          style: TextStyle(color: Colors.white),
                        ),
                        color: Colors.green,
                      ),
                    )
                  ],
                ),
              ),
            ),
          );
        });
  }

  showAlert(String title, String text) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        // return object of type Dialog
        return AlertDialog(
          title: new Text(title),
          content: new Text(text),
          actions: <Widget>[
            // usually buttons at the bottom of the dialog
            new FlatButton(
              child: new Text("Close"),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
          ],
        );
      },
    );
  }

  makeCallDialog() {
    showDialog(
        context: context,
        barrierDismissible: false,
        child: AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20.0)),
          title: Text("Call"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text("Wait for user to call you."),
              TextFormField(
                decoration: InputDecoration(labelText: "or Call user"),
                controller: textController,
              ),
              RaisedButton(
                color: Colors.green,
                textColor: Colors.white,
                onPressed: () {
                  doCall(textController.text);
                  Navigator.of(context).pop();
                },
                child: Text("Call"),
              ),
              new FlatButton(
                child: new Text("Close"),
                onPressed: () {
                  Navigator.of(context).pop();
                },
              ),
            ],
          ),
        ));
  }

  answerCallDialog(jsep) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Incoming call'),
          content: Text("Incoming call from " + yourUsername + "!"),
          actions: <Widget>[
            FlatButton(
              child: Text("Accept"),
              onPressed: () {
                answerCall(jsep);
                Navigator.of(context).pop();
              },
            ),
            FlatButton(
              child: Text("Decline"),
              onPressed: () {
                declineCall();
                Navigator.of(context).pop();
              },
            ),
          ],
        );
      },
    );
  }

  registerUsername(username) {
    if (sipcall != null) {
      Callbacks callbacks = Callbacks();
      callbacks.message = {"request": "register", "username": username};
      sipcall.send(callbacks);
    }
  }

  doCall(String username) {
    if (sipcall != null) {
      Callbacks callbacks = Callbacks();
      callbacks.media["data"] = false;
      callbacks.simulcast = doSimulcast;
      callbacks.simulcast2 = doSimulcast2;
      callbacks.success = (RTCSessionDescription jsep) {
        Janus.debug("Got SDP!");
        Janus.debug(jsep.toMap());
        Map<String, dynamic> body = {"request": "call", "username": username};
        callbacks.message = body;
        callbacks.jsep = jsep.toMap();
        sipcall.send(callbacks);
        setState(() {
          _inCalling = true;
        });
      };
      callbacks.error = (error) {
        Janus.error("WebRTC error:", error);
        Janus.log("WebRTC error... " + jsonEncode(error));
      };
      Janus.debug("Trying a createOffer too (audio/video sendrecv)");
      sipcall.createOffer(callbacks: callbacks);
    }
  }

  answerCall(jsep) {
    Janus.debug(jsep.toString());
    Callbacks callbacks = Callbacks();
    callbacks.jsep = jsep;
    callbacks.media["data"] = false;
    callbacks.media["video"] = false;
    callbacks.simulcast = doSimulcast;
    callbacks.simulcast2 = doSimulcast2;
    callbacks.success = (RTCSessionDescription jsep) {
      Janus.debug("Got SDP!");
      Janus.debug(jsep.toMap());
      callbacks.message = {"request": "accept"};
      callbacks.jsep = jsep.toMap();
      sipcall.send(callbacks);
      setState(() {
        _inCalling = true;
      });
    };
    callbacks.error = (error) {
      Janus.error("WebRTC error:", error);
      Janus.log("WebRTC error... " + jsonEncode(error));
    };
    sipcall.createAnswer(callbacks);
  }

  declineCall() {
    Janus.log("Decline call pressed");
  }

  updateCall(jsep) {
    Callbacks callbacks = Callbacks();
    callbacks.jsep = jsep;
    if (jsep.type == 'answer') {
      sipcall.handleRemoteJsep(callbacks);
    } else {
      callbacks.media["data"] = false;
      callbacks.simulcast = doSimulcast;
      callbacks.simulcast2 = doSimulcast2;
      callbacks.success = (RTCSessionDescription jsep) {
        Janus.debug("Got SDP!");
        Janus.debug(jsep.toMap());
        callbacks.message = {"request": "set"};
        callbacks.jsep = jsep.toMap();
        sipcall.send(callbacks);
      };
      callbacks.error = (error) {
        Janus.error("WebRTC error:", error);
        Janus.log("WebRTC error... " + jsonEncode(error));
      };
      sipcall.createAnswer(callbacks);
    }
  }

  _onMessage(msg, jsep) {
    Janus.debug(" ::: Got a message :::");
    Janus.debug(msg);
    Map<String, dynamic> result = msg["result"];
    if (result != null) {
      if (result["list"] != null) {
        peers = result["list"];
        Janus.debug("Got a list of registered peers:");
        Janus.debug(peers.toString());
      } else if (result["event"] != null) {
        String event = result["event"];
        if (event == 'registered') {
          setState(() {
            _registered = true;
          });

          myUsername = result["username"];
          Janus.log("Successfully registered as " + myUsername + "!");
          showAlert(
              "Registered", "Successfully registered as " + myUsername + "!");
          // Get a list of available peers, just for fun
          // TODO Enable buttons to call now
        } else if (event == 'calling') {
          Janus.log("Waiting for the peer to answer...");
          // TODO Any ringtone?
          showAlert('Calling', "Waiting for the peer to answer...");
        } else if (event == 'incomingcall') {
          Janus.log("Incoming call from " + result["username"] + "!");
          yourUsername = result["username"];
          // Notify user
          answerCallDialog(jsep);
        } else if (event == 'accepted') {
          if (result["username"] == null) {
            Janus.log("Call started!");
          } else {
            yourUsername = result["username"];
            Janus.log(yourUsername + " accepted the call!");
          }
          // Video call can start
          if (jsep != null) {
            Callbacks callbacks = Callbacks();
            callbacks.jsep = jsep;
            sipcall.handleRemoteJsep(callbacks);
          }
        } else if (event == 'update') {
          if (jsep != null) {
            updateCall(jsep);
          }
        } else if (event == 'hangup') {
          Janus.log("Call hung up by " +
              result["username"] +
              " (" +
              result["reason"] +
              ")!");
          sipcall.hangup(false);
          _hangUp();
        }
      }
    } else {
      var error = msg["error"];
      showAlert("Error", error.toString());
      _hangUp();
    }
  }

  @override
  Widget build(BuildContext context) {
    return new Scaffold(
      appBar: new AppBar(
        title: new Text('Videocall Test'),
        actions: <Widget>[],
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
        onPressed: _registered
            ? (_inCalling ? _hangUp : makeCallDialog)
            : registerDialog,
        tooltip: _registered ? (_inCalling ? 'Hangup' : 'Call') : 'Register',
        child: new Icon(_registered
            ? (_inCalling ? Icons.call_end : Icons.phone)
            : Icons.verified_user),
      ),
    );
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
    session = Janus.sessions[sessionId.toString()];

    Callbacks callbacks = Callbacks();
    callbacks.plugin = "janus.plugin.sip";
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

  _muteMic() {
    Janus.log('Mute mic.');
  }
}
