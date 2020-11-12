import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:flutterjanus/flutterjanus.dart';

class JanusVideoRoom extends StatefulWidget {
  JanusVideoRoom({Key key}) : super(key: key);

  @override
  _JanusVideoRoomState createState() => _JanusVideoRoomState();
}

class _JanusVideoRoomState extends State<JanusVideoRoom> {
  String server = "wss://janutter.tzty.net:7007";
  // String server = "https://janutter.tzty.net:8008/janus";

  String opaqueId = "videoroomtest-" + Janus.randomString(12);

  bool audioEnabled = false;
  bool videoEnabled = false;

  int myRoom = 1234; // Demo room
  String myUsername;
  int myId;
  MediaStream myStream;
  int myPvtId; // We use this other ID just to map our subscriptions to us
  List<Plugin> feeds = [];
  List<dynamic> list = [];
  Map<String, dynamic> bitrateTimer;

  bool doSimulcast = false;
  bool doSimulcast2 = false;
  bool simulcastStarted = false;

  Session session;
  Plugin sfutest;

  RTCVideoRenderer localRenderer = new RTCVideoRenderer();
  Future<String> hasInitRenderers;
  List<RTCVideoRenderer> remoteRenderer = [];

  bool _inCalling = false;
  bool _registered = false;

  TextEditingController textController = TextEditingController();

  _JanusVideoRoomState({Key key});

  @override
  void initState() {
    super.initState();
    Janus.init(options: {"debug": "all"}, callback: null);
    hasInitRenderers = initRenderers();
  }

  Future<String> initRenderers() async {
    await localRenderer.initialize();
    for (int i = 0; i < 5; i++) {
      RTCVideoRenderer rend = new RTCVideoRenderer();
      remoteRenderer.add(rend);
      await rend.initialize();
    }
    _connect();
  }

  @override
  void deactivate() {
    super.deactivate();
    localRenderer.dispose();
    for (int i = 0; i < 5; i++) {
      remoteRenderer[i].dispose();
    }
    if (session != null) session.destroy();
  }

  registerUsername(username) {
    if (sfutest != null) {
      Callbacks callbacks = Callbacks();
      callbacks.message = {
        "request": "join",
        "room": myRoom,
        "ptype": "publisher",
        "display": username
      };
      myUsername = username;
      sfutest.send(callbacks);
    }
  }

  publishOwnFeed({bool useAudio = true}) {
    if (sfutest != null) {
      Callbacks callbacks = Callbacks();
      callbacks.media = {
        "audioRecv": false,
        "videoRecv": false,
        "audioSend": useAudio,
        "videoSend": true
      };
      callbacks.simulcast = doSimulcast;
      callbacks.simulcast2 = doSimulcast2;
      callbacks.success = (RTCSessionDescription jsep) {
        Janus.debug("Got publisher SDP!");
        Janus.debug(jsep.toMap());
        Map<String, dynamic> publish = {
          "request": "configure",
          "audio": useAudio,
          "video": true
        };
        // You can force a specific codec to use when publishing by using the
        // audiocodec and videocodec properties, for instance:
        // 		publish["audiocodec"] = "opus"
        // to force Opus as the audio codec to use, or:
        // 		publish["videocodec"] = "vp9"
        callbacks.message = publish;
        callbacks.jsep = jsep.toMap();
        sfutest.send(callbacks);
        setState(() {
          _inCalling = true;
        });
      };
      callbacks.error = (error) {
        Janus.error("WebRTC error:", error);
        Janus.log("WebRTC error... " + jsonEncode(error));
      };
      Janus.debug("Trying a createOffer too (audio/video sendrecv)");
      sfutest.createOffer(callbacks: callbacks);
    }
  }

  unpublishOwnFeed() {
    if (sfutest != null) {
      Callbacks callbacks = Callbacks();
      callbacks.message = {
        "request": "unpublish",
      };
      sfutest.send(callbacks);
    }
  }

  newRemoteFeed(id, display, audio, video) {
    // A new feed has been published, create a new plugin handle and attach to it as a subscriber
    Plugin remoteFeed;
    Callbacks callbacks = Callbacks();
    callbacks.plugin = "janus.plugin.videoroom";
    callbacks.opaqueId = opaqueId;
    callbacks.success = (Plugin pluginHandle) {
      remoteFeed = pluginHandle;
      Janus.log("Plugin attached! (" +
          remoteFeed.getPlugin().toString() +
          ", id=" +
          remoteFeed.getId().toString() +
          ")");
      Janus.log("  -- This is a subscriber");
      Map<String, dynamic> subscribe = {
        "request": "join",
        "room": myRoom,
        "ptype": "subscriber",
        "feed": id,
        "private_id": myPvtId
      };
      // You can force a specific codec to use when publishing by using the
      // audiocodec and videocodec properties, for instance:
      // 		publish["audiocodec"] = "opus"
      // to force Opus as the audio codec to use, or:
      // 		publish["videocodec"] = "vp9"
      callbacks.message = subscribe;
      remoteFeed.send(callbacks);
    };
    callbacks.error = _error;
    callbacks.consentDialog = _consentDialog;
    callbacks.iceState = _iceState;
    callbacks.mediaState = _mediaState;
    callbacks.webrtcState = _webrtcState;
    callbacks.slowLink = _slowLink;
    callbacks.onMessage = (Map<String, dynamic> msg, jsep) {
      Janus.debug(" ::: Got a message (subscriber) :::");
      Janus.debug(msg);
      String event = msg["videoroom"];
      Janus.debug("Event: " + event.toString());
      if (msg["error"] != null) {
        Janus.error(msg["error"]);
      } else if (event != null) {
        if (event == "attached") {
          // Subscriber created and attached
          if (feeds.length < 5) {
            feeds.add(remoteFeed);
            remoteFeed.remoteFeedIndex = feeds.length - 1;
          }
          remoteFeed.remoteFeedId = msg["id"];
          remoteFeed.remoteFeedDisplay = msg["display"];
          Janus.log("Successfully attached to feed " +
              remoteFeed.remoteFeedId.toString() +
              " (" +
              remoteFeed.remoteFeedDisplay +
              ") in room " +
              msg["room"].toString());
        } else if (event == "event") {
          // Check if we got an event on a simulcast-related event from this publisher
          var substream = msg["substream"];
          var temporal = msg["temporal"];
          if (substream != null || temporal != null) {
            Janus.log("Feed supports simulcast");
          }
        }
      }
      if (jsep != null) {
        Janus.debug("Handling SDP as well...");
        Janus.debug(jsep);
        Callbacks callbacks = Callbacks();
        callbacks.jsep = jsep;
        callbacks.media = {"audioSend": false, "videoSend": false};
        callbacks.success = (RTCSessionDescription jsep) {
          Janus.debug("Got SDP!");
          Janus.debug(jsep.toMap());
          callbacks.message = {"request": "start", "room": myRoom};
          callbacks.jsep = jsep.toMap();
          remoteFeed.send(callbacks);
        };
        callbacks.error = (error) {
          Janus.error("WebRTC error:", error);
          Janus.log("WebRTC error... " + jsonEncode(error));
        };
        remoteFeed.createAnswer(callbacks);
      }
    };
    callbacks.onLocalStream = () {
      // The subscriber stream is recvonly, we don't expect anything here
      Janus.log("The subscriber stream is receive only.");
    };
    callbacks.onRemoteStream = (MediaStream stream) {
      Janus.debug("Remote feed #" + remoteFeed.remoteFeedId.toString());
      remoteRenderer[remoteFeed.remoteFeedIndex].srcObject = stream;
    };
    callbacks.onDataOpen = _onDataOpen;
    callbacks.onData = _onData;
    callbacks.onCleanup = () {
      Janus.log(" ::: Got a cleanup notification (remote feed " +
          remoteFeed.remoteFeedId.toString() +
          ") :::");
      remoteRenderer[remoteFeed.remoteFeedIndex].srcObject = null;
    };
    this.session.attach(callbacks: callbacks);
  }

  updateCall(jsep) {
    Callbacks callbacks = Callbacks();
    callbacks.jsep = jsep;
    if (jsep.type == 'answer') {
      sfutest.handleRemoteJsep(callbacks);
    } else {
      callbacks.media["data"] = false;
      callbacks.simulcast = doSimulcast;
      callbacks.simulcast2 = doSimulcast2;
      callbacks.success = (RTCSessionDescription jsep) {
        Janus.debug("Got SDP!");
        Janus.debug(jsep.toMap());
        callbacks.message = {"request": "set"};
        callbacks.jsep = jsep.toMap();
        sfutest.send(callbacks);
      };
      callbacks.error = (error) {
        Janus.error("WebRTC error:", error);
        Janus.log("WebRTC error... " + jsonEncode(error));
      };
      sfutest.createAnswer(callbacks);
    }
  }

  getRegisteredUsers() {
    Callbacks callbacks = Callbacks();
    callbacks.message = {"request": "list"};
    sfutest.send(callbacks);
  }

  void _connect() async {
    GatewayCallbacks gatewayCallbacks = GatewayCallbacks();
    gatewayCallbacks.server = this.server;
    gatewayCallbacks.success = _attach;
    gatewayCallbacks.error = (error) => Janus.error(error.toString());
    gatewayCallbacks.destroyed = () => deactivate();
    Session(gatewayCallbacks); // async httpd call
  }

  void _attach(int sessionId) {
    session = Janus.sessions[sessionId.toString()];

    Callbacks callbacks = Callbacks();
    callbacks.plugin = "janus.plugin.videoroom";
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
    sfutest = pluginHandle;
    Janus.log("Plugin attached! (" +
        this.sfutest.getPlugin() +
        ", id=" +
        sfutest.getId().toString() +
        ")");
    Janus.log("  -- This is a publisher/manager");
    // Prepare the username registration
    // registerDialog();
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

  _webrtcState(bool on, [List<dynamic> extra]) {
    //sometimes we get extra here? an error?
    Janus.log("Janus says our WebRTC PeerConnection is " +
        (on ? "up" : "down") +
        " now");
    Janus.debug('WebRTC state message, had extra: ${extra.toString()}');
  }

  // onMessage is main application flow control
  _onMessage(Map<String, dynamic> msg, jsep) {
    Janus.debug(" ::: Got a message (publisher) :::");
    Janus.debug(msg);
    String event = msg["videoroom"];
    Janus.debug("Event: " + event.toString());

    if (event != null) {
      if (event == "joined") {
        // Publisher/manager created, negotiate WebRTC and attach to existing feeds, if any
        myId = msg["id"];
        myPvtId = msg["private_id"];
        Janus.log("Successfully joined room " +
            msg["room"].toString() +
            " with ID " +
            myId.toString());
        publishOwnFeed(useAudio: true);
        // Any new feed to attach to?
        if (msg["publishers"] != null) {
          list = msg["publishers"];
          Janus.debug("Got a list of available publishers/feeds:");
          Janus.debug(list.toString());
          list.forEach((value) {
            var id = value["id"];
            var display = value["display"];
            var audio = value["audio_codec"];
            var video = value["video_coded"];
            Janus.debug("  >> [" +
                id.toString() +
                "] " +
                display.toString() +
                " (audio: " +
                audio.toString() +
                ", video: " +
                video.toString() +
                ")");
            newRemoteFeed(id, display, audio, video);
          });
        }
      } else if (event == 'destroyed') {
        // The room has been destroyed
        Janus.warn("The room has been destroyed!");
      } else if (event == "event") {
        // Any new feed to attach to?
        if (msg["publishers"] != null) {
          list = msg["publishers"];
          Janus.debug("Got a list of available publishers/feeds:");
          Janus.debug(list.toString());
          list.forEach((value) {
            var id = value["id"];
            var display = value["display"];
            var audio = value["audio_codec"];
            var video = value["video_coded"];
            Janus.debug("  >> [" +
                id.toString() +
                "] " +
                display.toString() +
                " (audio: " +
                audio.toString() +
                ", video: " +
                video.toString() +
                ")");
            newRemoteFeed(id, display, audio, video);
          });
        } else if (msg["leaving"] != null) {
          var leaving = msg["leaving"];
          Janus.log("Publisher left: " + leaving.toString());
          Plugin remoteFeed;

          feeds.forEach((element) {
            if (element.getId() == leaving) {
              remoteFeed = element;
            }
          });
          if (remoteFeed != null) {
            Janus.debug("Feed " +
                remoteFeed.remoteFeedId.toString() +
                " (" +
                remoteFeed.remoteFeedDisplay +
                ") has left the room, detaching");
            feeds.remove(remoteFeed);
            remoteFeed.getPlugin().detach({});
          }
        } else if (msg["unpublished"] != null) {
          var unpublished = msg["unpublished"];
          Janus.log("Publisher left: " + unpublished.toString());
          if (unpublished == 'ok') {
            // That's us
            sfutest.hangup(false);
            return;
          }
          Plugin remoteFeed;
          feeds.forEach((element) {
            if (element.getId() == unpublished) {
              remoteFeed = element;
            }
          });
          if (remoteFeed != null) {
            Janus.debug("Feed " +
                remoteFeed.remoteFeedId.toString() +
                " (" +
                remoteFeed.remoteFeedDisplay +
                ") has left the room, detaching");
            feeds.remove(remoteFeed);
            remoteFeed.getPlugin().detach({});
          }
        } else if (msg["error"] != null) {
          if (msg["error_code"] == 426) {
            // This is a "no such room" error: give a more meaningful description
            Janus.error("No such room exists");
          } else {
            Janus.error("Unknown Error: " + msg["error"].toString());
          }
        }
      }
    }

    if (jsep != null) {
      Janus.debug("Handling SDP as well...");
      Janus.debug(jsep);
      Callbacks callbacks = Callbacks();
      callbacks.jsep = jsep;
      sfutest.handleRemoteJsep(callbacks);
      var audio = msg["audio_codec"];
      if (myStream != null &&
          myStream.getAudioTracks().length > 0 &&
          audio == null) {
        Janus.log("Our audio stream has been rejected, viewers won't hear us");
      }
      var video = msg["audio_codec"];
      if (myStream != null &&
          myStream.getVideoTracks().length > 0 &&
          video == null) {
        Janus.log("Our video stream has been rejected, viewers won't see us");
      }
    }
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
    myStream = stream;
    localRenderer.srcObject = myStream;
  }

  _onRemoteStream(MediaStream stream) {
    // The publisher stream is sendonly, we don't expect anything here
    Janus.debug(" ::: Got a remote stream :::");
  }

  _onDataOpen(data) {
    Janus.log("The DataChannel is available!");
  }

  _onData(data) {
    Janus.debug("We got data from the DataChannel! " + data);
  }

  _onCleanup() {
    Janus.log(" ::: Got a cleanup notification :::");
    myStream = null;
    localRenderer.srcObject = null;
  }

  _hangUp() async {
    try {
      GatewayCallbacks gatewayCallbacks;
      session.destroy(gatewayCallbacks: gatewayCallbacks);
      localRenderer.srcObject = null;
      for (int i = 0; i < 5; i++) {
        remoteRenderer[i].srcObject = null;
      }
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

  @override
  Widget build(BuildContext context) {
    return new Scaffold(
      appBar: new AppBar(
        title: new Text('Videoroom Test'),
        actions: <Widget>[],
      ),
      body: new FutureBuilder(
          future: hasInitRenderers,
          builder: (BuildContext context, AsyncSnapshot<String> snapshot) {
            switch (snapshot.connectionState) {
              case ConnectionState.none:
              case ConnectionState.waiting:
                return new Text('loading...');
              default:
                if (snapshot.hasError)
                  return new Text('Error: ${snapshot.error}');
                else
                  return new OrientationBuilder(
                    builder: (context, orientation) {
                      return Container(
                        decoration: BoxDecoration(color: Colors.white),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            Column(
                              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                              children: [
                                Container(
                                  decoration:
                                      new BoxDecoration(color: Colors.black54),
                                  child: new RTCVideoView(localRenderer),
                                  width:
                                      MediaQuery.of(context).size.width / 2.1,
                                  height:
                                      MediaQuery.of(context).size.height / 4.1,
                                ),
                                Container(
                                  decoration:
                                      new BoxDecoration(color: Colors.black54),
                                  child: new RTCVideoView(remoteRenderer[0]),
                                  width:
                                      MediaQuery.of(context).size.width / 2.1,
                                  height:
                                      MediaQuery.of(context).size.height / 4.1,
                                ),
                                Container(
                                  decoration:
                                      new BoxDecoration(color: Colors.black54),
                                  child: new RTCVideoView(remoteRenderer[1]),
                                  width:
                                      MediaQuery.of(context).size.width / 2.1,
                                  height:
                                      MediaQuery.of(context).size.height / 4.1,
                                ),
                              ],
                            ),
                            Column(
                              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                              children: [
                                Container(
                                  decoration:
                                      new BoxDecoration(color: Colors.black54),
                                  child: new RTCVideoView(remoteRenderer[2]),
                                  width:
                                      MediaQuery.of(context).size.width / 2.1,
                                  height:
                                      MediaQuery.of(context).size.height / 4.1,
                                ),
                                Container(
                                  decoration:
                                      new BoxDecoration(color: Colors.black54),
                                  child: new RTCVideoView(remoteRenderer[3]),
                                  width:
                                      MediaQuery.of(context).size.width / 2.1,
                                  height:
                                      MediaQuery.of(context).size.height / 4.1,
                                ),
                                Container(
                                  decoration:
                                      new BoxDecoration(color: Colors.black54),
                                  child: new RTCVideoView(remoteRenderer[4]),
                                  width:
                                      MediaQuery.of(context).size.width / 2.1,
                                  height:
                                      MediaQuery.of(context).size.height / 4.1,
                                ),
                              ],
                            )
                          ],
                        ),
                      );
                    },
                  );
            }
          }),
      floatingActionButton: new FloatingActionButton(
        onPressed: _registered ? _hangUp : registerDialog,
        tooltip: _registered ? 'Hangup' : 'Register',
        child: new Icon(_registered ? Icons.call_end : Icons.phone),
      ),
    );
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
}
