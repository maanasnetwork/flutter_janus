import 'dart:convert';
import 'dart:async';
import 'package:sdp_transform/sdp_transform.dart';
import 'package:flutter_webrtc/webrtc.dart';
import 'package:flutterjanus/flutterjanus.dart';

class Session {
  bool websockets = false;
  WebSocketWrapper ws;
  var wsHandlers;
  Timer wsKeepaliveTimeoutId;
  List servers;
  int serversIndex = 0;
  var server;
  List<String> protocols = ['janus-protocol'];
  List iceServers = [
    {"url": "stun:stun.l.google.com:19302"},
  ];

  var iceTransportPolicy;
  var bundlePolicy;
  bool ipv6Support = false;
  bool withCredentials = false;
  int maxPollEvents = 10;
  int maxev = 10;
  String token;
  String apiSecret;
  bool destroyOnUnload = true;
  int keepAlivePeriod = 25000;
  int longPollTimeout = 60000;

  bool connected = false;
  int sessionId;
  Map<String, Plugin> pluginHandles = {};
  int retries = 0;
  Map<String, dynamic> transactions = {};

  final GatewayCallbacks gatewayCallbacks;

  Session(this.gatewayCallbacks) {
    this.server =
        gatewayCallbacks.server != null ? gatewayCallbacks.server : null;
    this.iceServers = gatewayCallbacks.iceServers != null
        ? gatewayCallbacks.iceServers
        : this.iceServers;
    this.iceTransportPolicy = gatewayCallbacks.iceTransportPolicy != null
        ? gatewayCallbacks.iceTransportPolicy
        : null;
    this.bundlePolicy = gatewayCallbacks.bundlePolicy != null
        ? gatewayCallbacks.bundlePolicy
        : null;
    this.ipv6Support = gatewayCallbacks.ipv6Support != null
        ? gatewayCallbacks.ipv6Support
        : null;
    this.withCredentials = gatewayCallbacks.withCredentials != null
        ? gatewayCallbacks.withCredentials
        : null;
    this.maxPollEvents = gatewayCallbacks.maxPollEvents != null
        ? gatewayCallbacks.maxPollEvents
        : this.maxPollEvents;
    this.token = gatewayCallbacks.token != null ? gatewayCallbacks.token : null;
    this.apiSecret =
        gatewayCallbacks.apiSecret != null ? gatewayCallbacks.apiSecret : null;
    this.destroyOnUnload = gatewayCallbacks.destroyOnUnload != null
        ? gatewayCallbacks.destroyOnUnload
        : this.destroyOnUnload;
    this.keepAlivePeriod = gatewayCallbacks.keepAlivePeriod != null
        ? gatewayCallbacks.keepAlivePeriod
        : null;
    this.longPollTimeout = gatewayCallbacks.longPollTimeout != null
        ? gatewayCallbacks.longPollTimeout
        : null;

    if (!Janus.initDone) {
      if (gatewayCallbacks.error is Function)
        gatewayCallbacks.error("Plugin not initialized");
      return;
    }
    Janus.log("Plugin initialized: " + Janus.initDone.toString());

    if (gatewayCallbacks.server == null) {
      gatewayCallbacks.error("Invalid server url");
      return;
    }
    if (Janus.isArray(this.server)) {
      Janus.log("Multiple servers provided (" +
          this.server.length +
          "), will use the first that works");
      this.servers = this.server;
      this.server = null;
    }

    if (this.server.indexOf("ws") == 0) {
      this.websockets = true;
      Janus.log("Using WebSockets to contact Janus: " + this.server);
    } else {
      Janus.log("Using REST API to contact Janus: " + server);
    }

    if (this.maxPollEvents != null && this.maxPollEvents > 1)
      this.maxev = this.maxPollEvents;
    else
      this.maxev = 1;

    createSession(callbacks: gatewayCallbacks);
  }

  getServer() => this.server;

  isConnected() => this.connected;

  reconnect(GatewayCallbacks callbacks) =>
      this.createSession(callbacks: gatewayCallbacks, reconnect: true);

  getSessionId() => this.sessionId;

  destroy({GatewayCallbacks callbacks}) =>
      this.destroySession(callbacks: callbacks);

  attach({Callbacks callbacks}) => this.createHandle(callbacks: callbacks);

  eventHandler() {
    if (this.sessionId == null) {
      return;
    }
    Janus.debug('Long poll...');
    if (!this.connected) {
      Janus.warn("Is the server down? (connected=false)");
      return;
    }
    String longpoll = this.server +
        "/" +
        this.sessionId.toString() +
        "?rid=" +
        (new DateTime.now()).millisecondsSinceEpoch.toString();
    Janus.log(longpoll);
    if (this.maxev > 0) longpoll = longpoll + "&maxev=" + this.maxev.toString();
    if (this.token != null)
      longpoll = longpoll + "&token=" + Uri.encodeFull(token);
    if (this.apiSecret != null)
      longpoll = longpoll + "&apisecret=" + Uri.encodeFull(this.apiSecret);

    GatewayCallbacks httpCallbacks = GatewayCallbacks();
    httpCallbacks.success = handleEvent;
    httpCallbacks.error = (textStatus, errorThrown) {
      Janus.error(textStatus + ":", errorThrown);
      retries++;
      if (retries > 3) {
        // Did we just lose the server? :-(
        connected = false;
        gatewayCallbacks.error("Lost connection to the server (is it down?)");
        return;
      }
      eventHandler();
    };
    Janus.httpAPICall(longpoll,
        {'verb': 'GET', 'withCredentials': withCredentials}, httpCallbacks);
  }

  // Private event handler: this will trigger plugin callbacks, if set
  handleEvent(json, [skipTimeout]) {
    retries = 0;
    if (!this.websockets && this.sessionId != null && skipTimeout != true)
      eventHandler();
    if (!this.websockets && Janus.isArray(json)) {
      // We got an array: it means we passed a maxev > 1, iterate on all objects
      for (var i = 0; i < json.length; i++) {
        handleEvent(json[i], true);
      }
      return;
    }
    if (json["janus"] == "keepalive") {
      // Nothing happened
      Janus.debug("Got a keepalive on session " + this.sessionId.toString());
      return;
    } else if (json["janus"] == "ack") {
      // Just an ack, we can probably ignore
      Janus.debug("Got an ack on session " + this.sessionId.toString());
      Janus.debug(json);
      String transaction = json["transaction"];
      if (transaction != null) {
        Function reportSuccess = this.transactions[transaction];
        if (reportSuccess is Function) reportSuccess(json);
        this.transactions.remove(transaction);
      }
      return;
    } else if (json["janus"] == "success") {
      // Success!
      if (this.sessionId != null)
        Janus.debug("Got a success on session " + this.sessionId.toString());
      Janus.debug(json);
      String transaction = json["transaction"];
      if (transaction != null) {
        Function reportSuccess = this.transactions[transaction];
        if (reportSuccess is Function) reportSuccess(json);
        this.transactions.remove(transaction);
      }
      return;
    } else if (json["janus"] == "trickle") {
      // We got a trickle candidate from Janus
      String sender = json["sender"].toString();
      if (sender == null) {
        Janus.warn("Missing sender...");
        return;
      }
      Plugin pluginHandle = this.pluginHandles[sender.toString()];
      if (pluginHandle == null) {
        Janus.debug("This handle is not attached to this session");
        return;
      }

      Map<String, dynamic> candidateMap = json["candidate"];
      Janus.debug(candidateMap.toString());
      RTCIceCandidate candidate = RTCIceCandidate(candidateMap['candidate'],
          candidateMap['sdpMid'], candidateMap['sdpMlineIndex']);
      Janus.debug(
          "Got a trickled candidate on session " + this.sessionId.toString());
      Janus.debug(candidate.toMap());
      if (pluginHandle.pc != null && pluginHandle.remoteSdp != null) {
        // Add candidate right now
        Janus.debug("Adding remote candidate:" + candidate.toString());
        if (candidate == null ||
            candidateMap['candidate']['completed'] == true) {
          // end-of-candidates
          pluginHandle.pc.addCandidate(Janus.endOfCandidates);
        } else {
          // New candidate
          pluginHandle.pc.addCandidate(candidate);
        }
      } else {
        // We didn't do setRemoteDescription (trickle got here before the offer?)
        Janus.debug(
            "We didn't do setRemoteDescription (trickle got here before the offer?), caching candidate");
        pluginHandle.candidates.add(candidate);
        Janus.debug(pluginHandle.candidates.toString());
      }
    } else if (json["janus"] == "webrtcup") {
      // The PeerConnection with the server is up! Notify this
      Janus.debug(
          "Got a webrtcup event on session " + this.sessionId.toString());
      Janus.debug(json);
      String sender = json["sender"].toString();
      if (sender == null) {
        Janus.warn("Missing sender...");
        return;
      }
      Plugin pluginHandle = this.pluginHandles[sender.toString()];
      if (pluginHandle == null) {
        Janus.debug("This handle is not attached to this session");
        return;
      }
      pluginHandle.webrtcState(true);
      return;
    } else if (json["janus"] == "hangup") {
      // A plugin asked the core to hangup a PeerConnection on one of our handles
      Janus.debug("Got a hangup event on session " + this.sessionId.toString());
      Janus.debug(json);
      String sender = json["sender"].toString();
      if (sender == null) {
        Janus.warn("Missing sender...");
        return;
      }
      Plugin pluginHandle = this.pluginHandles[sender.toString()];
      if (pluginHandle == null) {
        Janus.debug("This handle is not attached to this session");
        return;
      }
      pluginHandle.webrtcState(false, json["reason"]);
      pluginHandle.hangup({});
    } else if (json["janus"] == "detached") {
      // A plugin asked the core to detach one of our handles
      Janus.debug(
          "Got a detached event on session " + this.sessionId.toString());
      Janus.debug(json);
      String sender = json["sender"].toString();
      if (sender == null) {
        Janus.warn("Missing sender...");
        return;
      }
      Plugin pluginHandle = this.pluginHandles[sender.toString()];
      if (pluginHandle == null) {
        // Don't warn here because destroyHandle causes this situation.
        return;
      }
      pluginHandle.detached = true;
      pluginHandle.onDetached();
      pluginHandle.detach(null);
    } else if (json["janus"] == "media") {
      // Media started/stopped flowing
      Janus.debug("Got a media event on session " + this.sessionId.toString());
      Janus.debug(json);
      String sender = json["sender"].toString();
      if (sender == null) {
        Janus.warn("Missing sender...");
        return;
      }
      Plugin pluginHandle = this.pluginHandles[sender.toString()];
      if (pluginHandle == null) {
        Janus.debug("This handle is not attached to this session");
        return;
      }
      pluginHandle.mediaState(json["type"], json["receiving"]);
    } else if (json["janus"] == "slowlink") {
      Janus.debug(
          "Got a slowlink event on session " + this.sessionId.toString());
      Janus.debug(json);
      // Trouble uplink or downlink
      String sender = json["sender"].toString();
      if (sender == null) {
        Janus.warn("Missing sender...");
        return;
      }
      Plugin pluginHandle = this.pluginHandles[sender.toString()];
      if (pluginHandle == null) {
        Janus.debug("This handle is not attached to this session");
        return;
      }
      pluginHandle.slowLink(json["uplink"], json["lost"]);
    } else if (json["janus"] == "error") {
      // Oops, something wrong happened
      Janus.error(
          "Ooops: " + json["error"].code + " " + json["error"].reason); // FIXME
      Janus.debug(json);
      String transaction = json["transaction"];
      if (transaction != null) {
        Function reportSuccess = this.transactions[transaction];
        if (reportSuccess is Function) reportSuccess(json);
        this.transactions.remove(transaction);
      }
      return;
    } else if (json["janus"] == "event") {
      Janus.debug("Got a plugin event on session " + this.sessionId.toString());
      Janus.debug(json);
      String sender = json["sender"].toString();
      if (sender == null) {
        Janus.warn("Missing sender...");
        return;
      }
      var plugindata = json["plugindata"];
      if (plugindata == null) {
        Janus.warn("Missing plugindata...");
        return;
      }
      Janus.debug("  -- Event is coming from " +
          sender.toString() +
          " (" +
          plugindata["plugin"] +
          ")");
      var data = plugindata["data"];
      Janus.debug(data);
      Plugin pluginHandle = this.pluginHandles[sender.toString()];
      if (pluginHandle == null) {
        Janus.warn("This handle is not attached to this session");
        return;
      }

      var jsep = json["jsep"];
      if (jsep != null) {
        Janus.debug("Handling SDP as well...");
        Janus.debug(jsep);
      }
      var callback = pluginHandle.onMessage;
      if (callback is Function) {
        Janus.debug("Notifying application...");
        // Send to callback specified when attaching plugin handle
        Janus.log(data);
        callback(data, jsep);
      } else {
        // Send to generic callback (?)
        Janus.debug("No provided notification callback");
      }
    } else if (json["janus"] == "timeout") {
      Janus.error("Timeout on session " + this.sessionId.toString());
      Janus.debug(json);
      if (this.websockets) {
        this.ws.close();
      }
      return;
    } else {
      Janus.warn("Unknown message/event  '" +
          json["janus"] +
          "' on session " +
          this.sessionId.toString());
      Janus.debug(json);
    }
  }

  // Private helper to send keep-alive messages on WebSockets
  keepAlive() {
    if (this.server == null || !this.websockets || !this.connected) return;
    Timer.periodic(Duration(milliseconds: this.keepAlivePeriod), (Timer t) {
      this.wsKeepaliveTimeoutId = t;
      Map<String, dynamic> request = {
        "janus": "keepalive",
        "session_id": this.sessionId,
        "transaction": Janus.randomString(12)
      };
      if (this.token != null) request["token"] = token;
      if (this.apiSecret != null) request["apisecret"] = this.apiSecret;
      Janus.log(request.toString());
      this.ws.send(jsonEncode(request));
    });
  }

  createSession({GatewayCallbacks callbacks, bool reconnect = false}) {
    String transaction = Janus.randomString(12);
    Map<String, dynamic> request = {
      "janus": "create",
      "transaction": transaction
    };
    if (reconnect) {
      // We're reconnecting, claim the session
      connected = false;
      request["janus"] = "claim";
      request["session_id"] = this.sessionId;
      // If we were using websockets, ignore the old connection
      if (this.ws != null) {
        this.ws.onMessage = null;
        this.ws.onError = null;
        this.ws.onClose = null;
      }
    }

    if (this.token != null) request["token"] = token;
    if (this.apiSecret != null) request["apisecret"] = apiSecret;

    if (this.server != null && Janus.isArray(this.servers)) {
      // We still need to find a working server from the list we were given
      this.server = this.servers[this.serversIndex];
      if (this.server.indexOf("ws") == 0) {
        this.websockets = true;
        Janus.log("Server #" +
            (this.serversIndex + 1).toString() +
            ": trying WebSockets to contact Janus (" +
            this.server +
            ")");
      } else {
        this.websockets = false;
        Janus.log("Server #" +
            (this.serversIndex + 1).toString() +
            ": trying REST API to contact Janus (" +
            server +
            ")");
      }
    }
    if (this.websockets) {
      this.ws =
          WebSocketWrapper(this.server, this.protocols, this.keepAlivePeriod);

      // Attach websocket handlers
      this.ws.onError = (int code, String reason) {
        Janus.error(
            "Error connecting to the Janus WebSockets server... " + server);
        Janus.error(reason.toString());
        if (Janus.isArray(this.servers) && !reconnect) {
          this.serversIndex++;
          if (this.serversIndex == this.servers.length) {
            // We tried all the servers the user gave us and they all failed
            callbacks.error(
                "Error connecting to any of the provided Janus servers: Is the server down?");
            return;
          }
          // Let's try the next server
          this.server = null;
          Timer(
              Duration(microseconds: 200), createSession(callbacks: callbacks));
          return;
        }
        callbacks.error(
            "Error connecting to the Janus WebSockets server: Is the server down?");
      };

      this.ws.onMessage = (message) {
        handleEvent(jsonDecode(message));
      };

      this.ws.onClose = (int code, String reason) {
        if (this.server == null || !this.connected) {
        } else {
          this.connected = false;
          // FIXME What if this is called when the page is closed?
          gatewayCallbacks.error("Lost connection to the server (is it down?)");
        }
      };

      // All set, now try to connect websocket
      try {
        this.ws.connect();
        this.transactions[transaction] = (json) {
          Janus.debug(json);
          if (json["janus"] != "success") {
            Janus.error("Ooops: " +
                json["error"].code +
                " " +
                json["error"].reason); // FIXME
            callbacks.error(json["error"]["reason"]);
            return;
          }
          this.connected = true;
          if (json["session_id"] != null) {
            this.sessionId = json["session_id"];
          } else {
            this.sessionId = json["data"]["id"];
          }
          if (reconnect) {
            Janus.log("Claimed session: " + this.sessionId.toString());
          } else {
            Janus.log("Created session: " + this.sessionId.toString());
          }
          Janus.sessions[this.sessionId.toString()] = this;
          keepAlive();
          callbacks.success(this.sessionId);
        };

        Janus.debug(request.toString());
        this.ws.send(jsonEncode(request));
      } catch (error) {
        Janus.error(error.toString());
      }

      return;
    }

    GatewayCallbacks httpCallbacks = GatewayCallbacks();
    httpCallbacks.success = (json) {
      Janus.debug(json.toString());
      if (json["janus"] != "success") {
        Janus.error("Ooops: " +
            json["error"]["code"] +
            " " +
            json["error"]["reason"]); // FIXME
        callbacks.error(json["error"]["reason"]);
        return;
      }
      this.connected = true;
      if (json["session_id"] != null) {
        this.sessionId = json["session_id"];
      } else {
        this.sessionId = json["data"]["id"];
      }

      if (reconnect) {
        Janus.log("Claimed session: " + this.sessionId.toString());
      } else {
        Janus.log("Created session: " + this.sessionId.toString());
      }
      Janus.sessions[this.sessionId.toString()] = this;
      eventHandler();
      callbacks
          .success(this.sessionId); // return session to the success callback
    };
    httpCallbacks.error = (textStatus, errorThrown) {
      Janus.error(textStatus + ":", errorThrown); // FIXME
      if (Janus.isArray(this.servers) && !reconnect) {
        this.serversIndex++;
        if (this.serversIndex == servers.length) {
          // We tried all the servers the user gave us and they all failed
          callbacks.error(
              "Error connecting to any of the provided Janus servers: Is the server down?");
          return;
        }
        // Let's try the next server
        this.apiSecret = null;
        Timer(Duration(microseconds: 200), createSession(callbacks: callbacks));
        return;
      }
      if (errorThrown == "")
        callbacks.error(textStatus + ": Is the server down?");
      else
        callbacks.error(textStatus + ": " + errorThrown);
    };
    Janus.httpAPICall(
        server,
        {
          'verb': 'POST',
          'withCredentials': this.withCredentials,
          'body': request,
        },
        httpCallbacks);
  }

  destroySession(
      {GatewayCallbacks callbacks,
      bool unload = true,
      bool notifyDestroyed = true,
      bool cleanupHandles = true}) {
    // FIXME This method triggers a success even when we fail
    Janus.log("Destroying session " +
        sessionId.toString() +
        " (unload=" +
        unload.toString() +
        ")");
    if (this.sessionId == null) {
      Janus.warn("No session to destroy");
      if (callbacks.success is Function) callbacks.success();
      if (notifyDestroyed) if (callbacks.destroyed is Function)
        callbacks.destroyed();
      return;
    }
    if (cleanupHandles) {
      this.pluginHandles.forEach((handleId, Plugin handle) {
        handle.detach({'noRequest': true}); // FIXME
      });
    }
    if (!this.connected) {
      Janus.warn("Is the server down? (connected=false)");
      this.sessionId = null;
      callbacks.success();
      return;
    }
    // No need to destroy all handles first, Janus will do that itself
    Map<String, dynamic> request = {
      "janus": "destroy",
      "transaction": Janus.randomString(12)
    };
    if (this.token != null) request["token"] = token;
    if (this.apiSecret != null) request["apisecret"] = this.apiSecret;
    if (unload) {
      // We're unloading the page: use sendBeacon for HTTP instead,
      // or just close the WebSocket connection if we're using that
      if (this.websockets) {
        this.ws.onClose = null;
        this.ws.close();
        this.ws = null;
      } else {
        // navigator.sendBeacon(this.server + "/" + this.sessionId, jsonEncode(request));
        GatewayCallbacks httpCallbacks = GatewayCallbacks();
        Janus.httpAPICall(
            this.server + "/" + this.sessionId.toString(),
            {
              'verb': 'POST',
              'withCredentials': this.withCredentials,
              'body': request
            },
            httpCallbacks);
      }
      Janus.log("Destroyed session:");
      this.sessionId = null;
      this.connected = false;
      if (callbacks.success is Function) callbacks.success();
      if (notifyDestroyed) if (callbacks.destroyed is Function)
        callbacks.destroyed();
      return;
    }
    if (this.websockets) {
      request["session_id"] = this.sessionId;
      var onUnbindMessage;
      var onUnbindError;
      var unbindWebSocket = () {
        // Detach websocket handlers
        this.ws.onError = null;
        this.ws.onOpen = null;
        this.ws.onMessage = null;
        this.ws.onClose = null;

        // TODO connect these calls
        // ws.removeEventListener('message', onUnbindMessage);
        // ws.removeEventListener('error', onUnbindError);

        if (this.wsKeepaliveTimeoutId != null) {
          this.wsKeepaliveTimeoutId.cancel();
        }
        this.ws.close();
      };

      onUnbindMessage = (event) {
        var data = jsonDecode(event.data);
        if (data['session_id'] == request['session_id'] &&
            data['transaction'] == request['transaction']) {
          unbindWebSocket();
          callbacks.success();
          if (notifyDestroyed) gatewayCallbacks.destroyed();
        }
      };

      onUnbindError = (event) {
        unbindWebSocket();
        callbacks.error("Failed to destroy the server: Is the server down?");
        if (notifyDestroyed) gatewayCallbacks.destroyed();
      };

      this.ws.onMessage = onUnbindMessage;
      this.ws.onError = onUnbindError;

      this.ws.send(jsonEncode(request));
      return;
    }

    GatewayCallbacks httpCallbacks = GatewayCallbacks();
    httpCallbacks.success = (json) {
      Janus.log("Destroyed session:");
      Janus.debug(json);
      this.sessionId = null;
      this.connected = false;
      if (json["janus"] != "success") {
        Janus.error("Ooops: " +
            json["error"].code +
            " " +
            json["error"].reason); // FIXME
      }
      callbacks.success();
      if (notifyDestroyed) if (callbacks.destroyed is Function)
        callbacks.destroyed();
    };
    httpCallbacks.error = (textStatus, errorThrown) {
      Janus.error(textStatus + ":" + errorThrown); // FIXME
      // Reset everything anyway
      this.sessionId = null;
      this.connected = false;
      callbacks.success();
      if (notifyDestroyed) if (callbacks.destroyed is Function)
        callbacks.destroyed();
    };
    Janus.httpAPICall(
        this.server + "/" + this.sessionId.toString(),
        {
          'verb': 'POST',
          'withCredentials': this.withCredentials,
          'body': request
        },
        httpCallbacks);
  }

  createHandle({Callbacks callbacks}) {
    if (!this.connected) {
      Janus.warn("Is the server down? (connected=false)");
      this.gatewayCallbacks.error("Is the server down? (connected=false)");
      return;
    }

    String plugin = callbacks.plugin;
    if (plugin == null) {
      Janus.error("Invalid plugin");
      callbacks.error("Invalid plugin");
      return;
    }

    String opaqueId = callbacks.opaqueId;
    String handleToken = callbacks.token != null ? callbacks.token : this.token;
    String transaction = Janus.randomString(12);
    Map<String, dynamic> request = {
      "janus": "attach",
      "plugin": plugin,
      "opaque_id": opaqueId,
      "transaction": transaction
    };
    if (handleToken != null) request["token"] = handleToken;
    if (this.apiSecret != null) request["apisecret"] = this.apiSecret;

    if (this.websockets) {
      this.transactions[transaction] = (json) {
        Janus.debug(json);
        if (json["janus"] != "success") {
          Janus.error("Ooops: " +
              json["error"].code +
              " " +
              json["error"].reason); // FIXME
          callbacks.error(
              "Ooops: " + json["error"].code + " " + json["error"].reason);
          return;
        }
        int handleId = json["data"]["id"];
        Janus.log("Created handle: " + handleId.toString());
        // Initialise plugin
        Plugin pluginHandle = Plugin(
            session: this,
            plugin: plugin,
            handleId: handleId,
            handleToken: handleToken,
            callbacks: callbacks);

        this.pluginHandles[handleId.toString()] = pluginHandle;
        callbacks.success(pluginHandle);
      };

      request["session_id"] = this.sessionId;
      this.ws.send(jsonEncode(request));
      return;
    }

    GatewayCallbacks httpCallbacks = GatewayCallbacks();
    httpCallbacks.success = (json) {
      Janus.debug(json);
      if (json["janus"] != "success") {
        Janus.error("Ooops: " +
            json["error"].code +
            " " +
            json["error"].reason); // FIXME
        callbacks
            .error("Ooops: " + json["error"].code + " " + json["error"].reason);
        return;
      }
      int handleId = json["data"]["id"];
      Janus.log("Created handle: " + handleId.toString());

      // Initialise plugin
      Plugin pluginHandle = Plugin(
          session: this,
          plugin: plugin,
          handleId: handleId,
          handleToken: handleToken,
          callbacks: callbacks);

      this.pluginHandles[handleId.toString()] = pluginHandle;
      callbacks.success(pluginHandle);
    };

    httpCallbacks.error = (textStatus, errorThrown) {
      Janus.error(textStatus + ":" + errorThrown); // FIXME
      if (errorThrown == "")
        callbacks.error(textStatus + ": Is the server down?");
      else
        callbacks.error(textStatus + ": " + errorThrown);
    };

    Janus.httpAPICall(
        this.server + "/" + this.sessionId.toString(),
        {
          'verb': 'POST',
          'withCredentials': this.withCredentials,
          'body': request
        },
        httpCallbacks);
  }

  // Private method to send a message
  sendMessage(int handleId, Callbacks callbacks) {
    if (!this.connected) {
      Janus.warn("Is the server down? (connected=false)");
      callbacks.error("Is the server down? (connected=false)");
      return;
    }
    Plugin pluginHandle = this.pluginHandles[handleId.toString()];
    if (pluginHandle == null) {
      Janus.warn("Invalid handle");
      callbacks.error("Invalid handle");
      return;
    }

    Map<String, dynamic> message = callbacks.message;
    var jsep = callbacks.jsep;
    String transaction = Janus.randomString(12);
    Map<String, dynamic> request = {
      "janus": "message",
      "body": message,
      "transaction": transaction
    };
    if (pluginHandle.handleToken != null)
      request["token"] = pluginHandle.handleToken;
    if (this.apiSecret != null) request["apisecret"] = this.apiSecret;
    if (jsep != null) request["jsep"] = jsep;
    Janus.debug(
        "Sending message to plugin (handle=" + handleId.toString() + "):");
    Janus.debug(request);
    if (this.websockets) {
      request["session_id"] = this.sessionId;
      request["handle_id"] = handleId;
      this.transactions[transaction] = (json) {
        Janus.debug("Message sent!");
        Janus.debug(json);
        if (json["janus"] == "success") {
          // We got a success, must have been a synchronous transaction
          var plugindata = json["plugindata"];
          if (!plugindata) {
            Janus.warn("Request succeeded, but missing plugindata...");
            callbacks.success();
            return;
          }
          Janus.log("Synchronous transaction successful (" +
              plugindata["plugin"] +
              ")");
          var data = plugindata["data"];
          Janus.debug(data);
          if (callbacks.success != null) callbacks.success(data);
          return;
        } else if (json["janus"] != "ack") {
          // Not a success and not an ack, must be an error
          if (json["error"]) {
            Janus.error("Ooops: " +
                json["error"].code +
                " " +
                json["error"].reason); // FIXME
            callbacks.error(json["error"].code + " " + json["error"].reason);
          } else {
            Janus.error("Unknown error"); // FIXME
            callbacks.error("Unknown error");
          }
          return;
        }
        // If we got here, the plugin decided to handle the request asynchronously
        callbacks.success();
      };
      this.ws.send(jsonEncode(request));
      return;
    }

    GatewayCallbacks httpCallbacks = GatewayCallbacks();

    httpCallbacks.success = (json) {
      Janus.debug("Message sent!");
      Janus.debug(json);
      if (json["janus"] == "success") {
        // We got a success, must have been a synchronous transaction
        var plugindata = json["plugindata"];
        if (plugindata == null) {
          Janus.warn("Request succeeded, but missing plugindata...");
          callbacks.success();
          return;
        }
        Janus.log("Synchronous transaction successful (" +
            plugindata["plugin"] +
            ")");
        var data = plugindata["data"];
        Janus.debug(data);
        callbacks.success(data);
        return;
      } else if (json["janus"] != "ack") {
        // Not a success and not an ack, must be an error
        if (json["error"]) {
          Janus.error("Ooops: " +
              json["error"].code +
              " " +
              json["error"].reason); // FIXME
          callbacks.error(json["error"].code + " " + json["error"].reason);
        } else {
          Janus.error("Unknown error"); // FIXME
          callbacks.error("Unknown error");
        }
        return;
      }
      // If we got here, the plugin decided to handle the request asynchronously
      if (callbacks.success is Function) callbacks.success();
    };

    httpCallbacks.error = (textStatus, errorThrown) {
      Janus.error(textStatus + ":" + errorThrown); // FIXME
      callbacks.error(textStatus + ": " + errorThrown);
    };

    Janus.httpAPICall(
        this.server +
            "/" +
            this.sessionId.toString() +
            "/" +
            handleId.toString(),
        {
          'verb': 'POST',
          'withCredentials': this.withCredentials,
          'body': request
        },
        httpCallbacks);
  }

  // Private method to send a trickle candidate
  sendTrickleCandidate(int handleId, Map<String, dynamic> candidate) {
    if (!this.connected) {
      Janus.warn("Is the server down? (connected=false)");
      return;
    }
    Plugin pluginHandle = this.pluginHandles[handleId.toString()];
    if (pluginHandle == null) {
      Janus.warn("Invalid handle");
      return;
    }
    Map<String, dynamic> request = {
      "janus": "trickle",
      "candidate": candidate,
      "transaction": Janus.randomString(12)
    };
    if (pluginHandle.handleToken != null)
      request["token"] = pluginHandle.handleToken;
    if (this.apiSecret != null) request["apisecret"] = this.apiSecret;
    Janus.vdebug(
        "Sending trickle candidate (handle=" + handleId.toString() + "):");
    Janus.vdebug(request);
    if (this.websockets) {
      request["session_id"] = this.sessionId;
      request["handle_id"] = handleId;
      this.ws.send(jsonEncode(request));
      return;
    }

    GatewayCallbacks httpCallbacks = GatewayCallbacks();
    httpCallbacks.success = (json) {
      Janus.vdebug("Candidate sent!");
      Janus.vdebug(json);
      if (json["janus"] != "ack") {
        Janus.error("Ooops: " +
            json["error"].code +
            " " +
            json["error"].reason); // FIXME
        return;
      }
    };

    httpCallbacks.error = (textStatus, errorThrown) {
      Janus.error(textStatus + ":" + errorThrown); // FIXME
    };

    Janus.httpAPICall(
        this.server +
            "/" +
            this.sessionId.toString() +
            "/" +
            handleId.toString(),
        {
          'verb': 'POST',
          'withCredentials': this.withCredentials,
          'body': request
        },
        httpCallbacks);
  }

  // Private method to create a data channel
  createDataChannel(int handleId, label, incoming, pendingData) {
    Plugin pluginHandle = this.pluginHandles[handleId.toString()];
    if (pluginHandle == null) {
      Janus.warn("Invalid handle");
      return;
    }
    Map<String, RTCDataChannel> dataChannels = pluginHandle.dataChannels;

    var onDataChannelMessage = (event) {
      Janus.log('Received message on data channel:' + event.toString());
      var label = event.target.label;
      pluginHandle.onData(event.data, label);
    };
    var onDataChannelStateChange = (state) {
      Janus.log('Received state change on data channel:' + state.toString());
      var label = state.label;
      var dcState =
          (dataChannels[label] != null) ? dataChannels[label].state : "null";
      Janus.log('State change on <' + label + '> data channel: ' + dcState);
      if (dcState == 'open') {
        // FIX ME no params pending in RTCDataChannel to store pending message in flutter_webrtc
        // Any pending messages to send?
        // if (dataChannels[label].pending &&
        //     pluginHandle.dataChannels[label]['pending'].length > 0) {
        //   Janus.log("Sending pending messages on <" +
        //       label +
        //       ">:" +
        //       pluginHandle.dataChannels[label]['pending'].length.toString());
        //   for (var data in pluginHandle.dataChannels[label]['pending']) {
        //     Janus.log("Sending data on data channel <" + label + ">");
        //     Janus.debug(data);
        //     pluginHandle.dataChannels[label].send(data);
        //   }
        //   pluginHandle.dataChannels[label]['pending'] = [];
        // }
        // Notify the open data channel
        pluginHandle.onDataOpen(label);
      }
    };
    var onDataChannelError = (error) => {
          Janus.error('Got error on data channel:' + error)
          // TODO
        };
    if (incoming == null) {
      Janus.log("Creating a data channel with label" + label);
      // Add options (ordered, maxRetransmits, etc.)
      RTCDataChannelInit rtcDataChannel = RTCDataChannelInit();
      pluginHandle.pc
          .createDataChannel(label, rtcDataChannel)
          .then((RTCDataChannel channel) {
        dataChannels[label] = channel;
      }).catchError((error, StackTrace trace) {
        Janus.error(error.toString());
      });
    } else {
      // The channel was created by Janus
      dataChannels[label] = incoming;
    }
    dataChannels[label].onMessage = onDataChannelMessage;
    dataChannels[label].onDataChannelState = onDataChannelStateChange;
    // FIX me these calls do not exists, need to implement these in onDataChannelStateChange
    // dataChannels[label].onclose = onDataChannelStateChange;
    // dataChannels[label].onerror = onDataChannelError;
    // dataChannels[label].pending = [];
    // if (pendingData != null)
    //   pluginHandle.dataChannels[label]['pending'].add(pendingData);
  }

  // Private method to send a data channel message
  sendData(int handleId, Callbacks callbacks) {
    Plugin pluginHandle = this.pluginHandles[handleId.toString()];
    if (pluginHandle == null) {
      Janus.warn("Invalid handle");
      callbacks.error("Invalid handle");
      return;
    }
    var data = callbacks.text || callbacks.data;
    if (!data) {
      Janus.warn("Invalid data");
      callbacks.error("Invalid data");
      return;
    }
    var label = callbacks.label ? callbacks.label : Janus.dataChanDefaultLabel;
    if (pluginHandle.dataChannels[label] == null) {
      // Create new data channel and wait for it to open
      createDataChannel(handleId, label, null, data);
      callbacks.success();
      return;
    }
    if (pluginHandle.dataChannels[label]['readyState'] != "open") {
      pluginHandle.dataChannels[label]['pending'].add(data);
      callbacks.success();
      return;
    }
    Janus.log("Sending data on data channel <" + label + ">");
    Janus.debug(data);
    // TODO attach send
    pluginHandle.dataChannels[label].send(data);
    callbacks.success();
  }

  // Private method to send a DTMF tone
  sendDtmf(int handleId, Callbacks callbacks) {
    Plugin pluginHandle = this.pluginHandles[handleId.toString()];
    if (pluginHandle == null) {
      Janus.warn("Invalid handle");
      callbacks.error("Invalid handle");
      return;
    }
    if (pluginHandle.dtmfSender == null) {
      // Create the DTMF sender the proper way, if possible
      if (pluginHandle.pc != null) {
        // FIX ME
        // var senders = pc.getSenders();
        // var audioSender = senders.find((sender) {
        //   sender.track && sender.track.kind == 'audio';
        // });
        var audioSender = {'dtmf': null};
        if (audioSender != null) {
          Janus.warn("Invalid DTMF configuration (no audio track)");
          callbacks.error("Invalid DTMF configuration (no audio track)");
          return;
        }
        pluginHandle.dtmfSender = audioSender['dtmf'];
        if (pluginHandle.dtmfSender != null) {
          Janus.log("Created DTMF Sender");
          pluginHandle.dtmfSender['ontonechange'] = (tone) =>
              Janus.debug("Sent DTMF tone: " + tone['tone'].toString());
        }
      }
      if (pluginHandle.dtmfSender == null) {
        Janus.warn("Invalid DTMF configuration");
        callbacks.error("Invalid DTMF configuration");
        return;
      }
    }
    var dtmf = callbacks.dtmf;
    if (dtmf == null) {
      Janus.warn("Invalid DTMF parameters");
      callbacks.error("Invalid DTMF parameters");
      return;
    }
    var tones = dtmf['tones'];
    if (tones == null) {
      Janus.warn("Invalid DTMF string");
      callbacks.error("Invalid DTMF string");
      return;
    }
    var duration = (dtmf['duration'] is int)
        ? dtmf['duration']
        : 500; // We choose 500ms as the default duration for a tone
    var gap = (dtmf['gap'] is int)
        ? dtmf['gap']
        : 50; // We choose 50ms as the default gap between tones
    Janus.debug("Sending DTMF string " +
        tones +
        " (duration " +
        duration.toString() +
        "ms, gap " +
        gap.toString() +
        "ms)");
    pluginHandle.dtmfSender.insertDTMF(tones, duration, gap);
    callbacks.success();
  }

  // Private method to destroy a plugin handle
  destroyHandle(int handleId, Callbacks callbacks) {
    var noRequest = (callbacks.noRequest == true);
    Janus.log("Destroying handle " +
        handleId.toString() +
        " (only-locally=" +
        noRequest.toString() +
        ")");
    cleanupWebrtc(handleId, false);
    Plugin pluginHandle = this.pluginHandles[handleId.toString()];
    if (pluginHandle == null) {
      // Plugin was already detached by Janus, calling detach again will return a handle not found error, so just exit here
      this.pluginHandles.remove(handleId.toString());
      callbacks.success();
      return;
    }
    if (noRequest) {
      // We're only removing the handle locally
      this.pluginHandles.remove(handleId.toString());
      callbacks.success();
      return;
    }
    if (!this.connected) {
      Janus.warn("Is the server down? (connected=false)");
      callbacks.error("Is the server down? (connected=false)");
      return;
    }
    Map<String, dynamic> request = {
      "janus": "detach",
      "transaction": Janus.randomString(12)
    };
    if (pluginHandle.handleToken != null)
      request["token"] = pluginHandle.handleToken;
    if (this.apiSecret != null) request["apisecret"] = this.apiSecret;
    if (this.websockets != null) {
      request["session_id"] = this.sessionId;
      request["handle_id"] = handleId;
      this.ws.send(jsonEncode(request)); // FIX ME
      this.pluginHandles.remove(handleId.toString());
      callbacks.success();
      return;
    }

    GatewayCallbacks httpCallbacks = GatewayCallbacks();
    httpCallbacks.success = (json) {
      Janus.log("Destroyed handle:");
      Janus.debug(json);
      if (json["janus"] != "success") {
        Janus.error("Ooops: " +
            json["error"].code.toString() +
            " " +
            json["error"].reason.toString()); // FIXME
      }
      this.pluginHandles.remove(handleId.toString());
      callbacks.success();
    };
    httpCallbacks.error = (textStatus, errorThrown) {
      Janus.error(textStatus + ":" + errorThrown); // FIXME
      // We cleanup anyway
      this.pluginHandles.remove(handleId.toString());
      callbacks.success();
    };
    Janus.httpAPICall(
        this.server +
            "/" +
            this.sessionId.toString() +
            "/" +
            handleId.toString(),
        {
          'verb': 'POST',
          'withCredentials': this.withCredentials,
          'body': request
        },
        httpCallbacks);
  }

  // WebRTC stuff
  streamsDone(int handleId, RTCSessionDescription jsep, Map media, callbacks,
      MediaStream stream) async {
    Plugin pluginHandle = this.pluginHandles[handleId.toString()];
    if (pluginHandle == null) {
      Janus.warn("Invalid handle");
      callbacks.error("Invalid handle");
      return;
    }
    Janus.debug("streamsDone:" + stream.toString());
    if (stream != null) {
      Janus.debug("  -- Audio tracks:" + stream.getAudioTracks().toString());
      Janus.debug("  -- Video tracks:" + stream.getVideoTracks().toString());
    }
    // We're now capturing the new stream: check if we're updating or if it's a new thing
    bool addTracks = false;
    if (pluginHandle.myStream == null ||
        !media['update'] ||
        pluginHandle.streamExternal) {
      pluginHandle.myStream = stream;
      addTracks = true;
    } else {
      // We only need to update the existing stream
      if (((!media['update'] && isAudioSendEnabled(media)) ||
              (media['update'] &&
                  (media['addAudio'] || media['replaceAudio']))) &&
          stream.getAudioTracks() != null &&
          stream.getAudioTracks().length > 0) {
        pluginHandle.myStream.addTrack(stream.getAudioTracks()[0]);
        if (Janus.unifiedPlan) {
          // Use Transceivers
          Janus.log((media['replaceAudio'] ? "Replacing" : "Adding") +
              " audio track:" +
              stream.getAudioTracks()[0].toString());
          Map<String, dynamic> audioTransceiver;
          // FIX ME
          // List transceivers = pc.getTransceivers();
          List transceivers = [];
          if (transceivers != null && transceivers.length > 0) {
            for (var t in transceivers) {
              // TODO sender is MediaStreamTrack
              if ((t['sender'] &&
                      t['sender'].track &&
                      t['sender'].track.kind == "audio") ||
                  (t['receiver'] &&
                      t['receiver'].track &&
                      t['receiver'].track.kind == "audio")) {
                audioTransceiver = t;
                break;
              }
            }
          }
          if (audioTransceiver != null && audioTransceiver['sender'] != null) {
            // Todo implement replaceTrack
            audioTransceiver['sender'].replaceTrack(stream.getAudioTracks()[0]);
          } else {
            // FIX ME
            // pc.addTrack(stream.getAudioTracks()[0], stream);
            pluginHandle.pc.addStream(stream);
          }
        } else {
          Janus.log((media['replaceAudio'] ? "Replacing" : "Adding") +
              " audio track:" +
              stream.getAudioTracks()[0].toString());
          // FIX ME
          // pc.addTrack(stream.getAudioTracks()[0], stream);
          pluginHandle.pc.addStream(stream);
        }
      }
      if (((!media['update'] && isVideoSendEnabled(media)) ||
              (media['update'] &&
                  (media['addVideo'] || media['replaceVideo']))) &&
          stream.getVideoTracks() != null &&
          stream.getVideoTracks().length > 0) {
        pluginHandle.myStream.addTrack(stream.getVideoTracks()[0]);
        if (Janus.unifiedPlan) {
          // Use Transceivers
          Janus.log((media['replaceVideo'] ? "Replacing" : "Adding") +
              " video track:" +
              stream.getVideoTracks()[0].toString());
          Map<String, dynamic> videoTransceiver;
          // List transceivers = pc.getTransceivers();
          List transceivers = [];
          if (transceivers != null && transceivers.length > 0) {
            for (var t in transceivers) {
              // TODO sender is MediaStreamTrack
              if ((t['sender'] &&
                      t['sender'].track &&
                      t['sender'].track.kind == "video") ||
                  (t['receiver'] &&
                      t['receiver'].track &&
                      t['receiver'].track.kind == "video")) {
                videoTransceiver = t;
                break;
              }
            }
          }
          if (videoTransceiver != null && videoTransceiver['sender'] != null) {
            // Todo implement replaceTrack
            videoTransceiver['sender'].replaceTrack(stream.getVideoTracks()[0]);
          } else {
            // FIX ME
            // pc.addTrack(stream.getVideoTracks()[0], stream);
            pluginHandle.pc.addStream(stream);
          }
        } else {
          Janus.log((media['replaceVideo'] ? "Replacing" : "Adding") +
              " video track:" +
              stream.getVideoTracks()[0].toString());
          // FIX ME
          // pc.addTrack(stream.getVideoTracks()[0], stream);
          pluginHandle.pc.addStream(stream);
        }
      }
    }
    // If we still need to create a PeerConnection, let's do that
    if (pluginHandle.pc == null) {
      Map<String, dynamic> pcConfig = {"iceServers": this.iceServers};
      if (this.iceTransportPolicy != null)
        pcConfig["iceTransportPolicy"] = this.iceTransportPolicy;
      if (this.bundlePolicy != null)
        pcConfig["bundlePolicy"] = this.bundlePolicy;
      if (Janus.webRTCAdapter['browserDetails']['browser'] == "chrome") {
        // For Chrome versions before 72, we force a plan-b semantic, and unified-plan otherwise
        pcConfig["sdpSemantics"] =
            (Janus.webRTCAdapter['browserDetails']['version'] < 72)
                ? "plan-b"
                : "unified-plan";
      }
      Map<String, dynamic> pcConstraints = {
        "mandatory": {},
        "optional": [
          {"DtlsSrtpKeyAgreement": true}
        ]
      };
      if (this.ipv6Support) {
        pcConstraints['optional'].add({"googIPv6": true});
      }
      // Any custom constraint to add?
      if (callbacks.rtcConstraints != null) {
        Janus.debug("Adding custom PeerConnection constraints:" +
            callbacks.rtcConstraints.toString()); // FIX ME
        for (var i in callbacks.rtcConstraints) {
          pcConstraints['optional'].add(callbacks.rtcConstraints[i]);
        }
      }
      if (Janus.webRTCAdapter['browserDetails']['browser'] == "edge") {
        // This is Edge, enable BUNDLE explicitly
        pcConfig['bundlePolicy'] = "max-bundle";
      }
      Janus.log("Creating PeerConnection");
      Janus.debug(pcConstraints.toString());
      Janus.debug(pcConfig.toString());
      // From webrtc
      pluginHandle.pc = await createPeerConnection(pcConfig, pcConstraints);
      Janus.debug("Peer Connection is ready");
      Janus.debug(pluginHandle.pc.toString());
      // FIXME

      // pluginHandle.pc.getStats().then((List<StatsReport> stats) {
      //   if (stats != null) {
      //     Janus.log(
      //         "PC Stats: " + stats[1].type + stats[1].values.toString());
      //     pluginHandle.volume = {};
      //     pluginHandle.bitrate['value'] = "0 kbits/sec";
      //   }
      // }).catchError((error, StackTrace stackTrace) {
      //   Janus.error(error.toString());
      // });

      Janus.log("Preparing local SDP and gathering candidates (trickle=" +
          pluginHandle.trickle.toString() +
          ")");

      pluginHandle.pc.onIceConnectionState = (RTCIceConnectionState state) {
        if (pluginHandle.pc != null) pluginHandle.iceState(state);
      };

      pluginHandle.pc.onIceCandidate = (RTCIceCandidate candidate) {
        if (candidate == null ||
            (Janus.webRTCAdapter['browserDetails']['browser'] == 'edge' &&
                candidate.candidate.indexOf('endOfCandidates') > 0)) {
          Janus.log("End of candidates.");
          pluginHandle.iceDone = true;
          Janus.log(pluginHandle.trickle);
          if (pluginHandle.trickle == true) {
            // Notify end of candidates
            sendTrickleCandidate(handleId, {"completed": true});
          } else {
            // No trickle, time to send the complete SDP (including all candidates)
            sendSDP(handleId, callbacks);
          }
        } else {
          // JSON.stringify doesn't work on some WebRTC objects anymore
          // See https://code.google.com/p/chromium/issues/detail?id=467366
          // RTCIceCandidate candidate = RTCIceCandidate(iceCandidate.candidate,
          //     iceCandidate.sdpMid, iceCandidate.sdpMlineIndex);
          if (pluginHandle.trickle == true) {
            // Send candidate
            sendTrickleCandidate(handleId, candidate.toMap());
            Janus.debug(candidate.toMap());
          }
        }
      };

      pluginHandle.pc.onAddStream = (MediaStream stream) {
        Janus.log('onAddStream event call');
        Janus.log(stream.toString());
      };

      pluginHandle.pc.onRemoveStream = (MediaStream stream) {
        Janus.log('onRemoveStream event call');
        Janus.log(stream.toString());
      };

      pluginHandle.pc.onAddTrack =
          (MediaStream stream, MediaStreamTrack track) {
        Janus.log("Handling Remote Track");
        Janus.debug(stream);
        if (stream == null) return;
        pluginHandle.remoteStream = stream;
        pluginHandle.onRemoteStream(stream);

        // FIX ME no equivalent call exists in flutter_webrtc
        // if (event.track.onended) return;
        // Janus.log("Adding onended callback to track:" + event.track);
        // event.track.onended = (ev) {
        //   Janus.log("Remote track muted/removed:" + ev);
        //   if (pluginHandle.remoteStream) {
        //     pluginHandle.remoteStream.removeTrack(ev.target);
        //     pluginHandle.onremotestream(pluginHandle.remoteStream);
        //   }
        // };

        // FIX ME no equivalent call exists in flutter_webrtc
        // event.track.onmute = event.track.onended;
        // event.track.onunmute = (ev) {
        //   Janus.log("Remote track flowing again:" + ev);
        //   try {
        //     pluginHandle.remoteStream.addTrack(ev.target);
        //     pluginHandle.onremotestream(pluginHandle.remoteStream);
        //   } catch (e) {
        //     Janus.error(e);
        //   }
        //   ;
        // };
      };

      // TODO connect addTrack
      if (addTracks && stream != null) {
        // var simulcast2 = (callbacks.simulcast2 == true);
        // FIX ME: janus.js  find out all the track from the stream and then add to the PC
        // There is no equivalnet call in flutter_webrtc. We will add the stream to PC
        pluginHandle.pc.addStream(stream).then((void v) {
          Janus.log("Stream added to PC");
        }).catchError((error, StackTrace stackTrace) {
          Janus.log(stackTrace);
          Janus.error(error.toString());
        });
        // // Get a list of audio and video tracks
        // List<MediaStreamTrack> tracks =
        //     stream.getAudioTracks() + stream.getVideoTracks();
        // tracks.forEach((MediaStreamTrack track) {
        //   Janus.log('Adding local track:' + track.toString());
        //   if (!simulcast2) {
        //     Janus.log('here i am');
        //     pluginHandle.pc.addTrack(track, stream);
        //   } else {
        //     if (track.kind == "audio") {
        //       pluginHandle.pc.addTrack(track, stream);
        //     } else {
        //       Janus.log(
        //           'Enabling rid-based simulcasting:' + track.toString());
        //       var maxBitrates =
        //           getMaxBitrates(callbacks.simulcastMaxBitrates);
        //       pc.addTransceiver(track, {
        //         'direction': "sendrecv",
        //         'streams': [stream],
        //         'sendEncodings': [
        //           {
        //             'rid': "h",
        //             'active': true,
        //             'maxBitrate': maxBitrates['high']
        //           },
        //           {
        //             'rid': "m",
        //             'active': true,
        //             'maxBitrate': maxBitrates['medium'],
        //             'scaleResolutionDownBy': 2
        //           },
        //           {
        //             'rid': "l",
        //             'active': true,
        //             'maxBitrate': maxBitrates['low'],
        //             'scaleResolutionDownBy': 4
        //           }
        //         ]
        //       });
        //     }
        //   }
        // });
      }

      // Any data channel to create?
      if (isDataEnabled(media) &&
          pluginHandle.dataChannels[Janus.dataChanDefaultLabel] == null) {
        Janus.log("Creating data channel");
        createDataChannel(handleId, Janus.dataChanDefaultLabel, null, null);
        Janus.log('failing here');
        pluginHandle.pc.onDataChannel = (var channel) {
          Janus.log(
              "Data channel created by Janus:" + channel.toString()); // FIX ME
          createDataChannel(handleId, "label", channel, null);
        };
      }

      // If there's a new local stream, let's notify the application
      if (pluginHandle.myStream != null) {
        pluginHandle.onLocalStream(pluginHandle.myStream);
      }

      // Create offer/answer now
      if (jsep == null) {
        createOffer(handleId, media, callbacks);
      } else {
        pluginHandle.pc.setRemoteDescription(jsep).then((void v) {
          Janus.log("Remote description accepted!");
          pluginHandle.remoteSdp = jsep.sdp;
          // Any trickle candidate we cached?
          if (pluginHandle.candidates != null &&
              pluginHandle.candidates.length > 0) {
            for (var i = 0; i < pluginHandle.candidates.length; i++) {
              RTCIceCandidate candidate = pluginHandle.candidates[i];
              Janus.debug("Adding remote candidate:" + candidate.toString());
              if (candidate == null) {
                // end-of-candidates
                pluginHandle.pc.addCandidate(Janus.endOfCandidates);
              } else {
                // New candidate
                pluginHandle.pc.addCandidate(candidate);
              }
            }
            pluginHandle.candidates = [];
          }
          // Create the answer now
          createAnswer(handleId, media, callbacks, null);
        }).catchError((error, StackTrace stackTrade) {
          callbacks.error(error);
        });
      }
    }
  }

  prepareWebrtc(int handleId, bool offer, Callbacks callbacks) {
    var jsep = callbacks.jsep;

    if (offer && jsep != null) {
      Janus.error("Provided a JSEP to a createOffer");
      callbacks.error("Provided a JSEP to a createOffer");
      return;
    } else if (!offer &&
        (jsep == null || jsep.type == null || jsep.sdp == null)) {
      Janus.error("A valid JSEP is required for createAnswer");
      callbacks.error("A valid JSEP is required for createAnswer");
      return;
    }

    /* Check that callbacks.media is a (not null) Object */
    callbacks.media = (callbacks.media != null)
        ? callbacks.media
        : {'audio': true, 'video': true};
    Map<String, dynamic> media = callbacks.media;
    Plugin pluginHandle = this.pluginHandles[handleId.toString()];
    if (pluginHandle == null) {
      Janus.warn("Invalid handle");
      callbacks.error("Invalid handle");
      return;
    }
    pluginHandle.trickle = isTrickleEnabled(callbacks.trickle);
    // Are we updating a session?
    if (pluginHandle.pc == null) {
      // Nope, new PeerConnection
      media['update'] = false;
      media['keepAudio'] = false;
      media['keepVideo'] = false;
    } else {
      Janus.log("Updating existing media session");
      media['update'] = true;
      // Check if there's anything to add/remove/replace, or if we
      // can go directly to preparing the new SDP offer or answer
      if (callbacks.stream != null) {
        // External stream: is this the same as the one we were using before?
        if (callbacks.stream != pluginHandle.myStream) {
          Janus.log("Renegotiation involves a new external stream");
        }
      } else {
        // Check if there are changes on audio
        if (media['addAudio']) {
          media['keepAudio'] = false;
          media['replaceAudio'] = false;
          media['removeAudio'] = false;
          media['audioSend'] = true;
          if (pluginHandle.myStream != null &&
              pluginHandle.myStream.getAudioTracks() != null &&
              pluginHandle.myStream.getAudioTracks().length > 0) {
            Janus.error("Can't add audio stream, there already is one");
            callbacks.error("Can't add audio stream, there already is one");
            return;
          }
        } else if (media['removeAudio']) {
          media['keepAudio'] = false;
          media['replaceAudio'] = false;
          media['addAudio'] = false;
          media['audioSend'] = false;
        } else if (media['replaceAudio']) {
          media['keepAudio'] = false;
          media['addAudio'] = false;
          media['removeAudio'] = false;
          media['audioSend'] = true;
        }

        if (pluginHandle.myStream == null) {
          // No media stream: if we were asked to replace, it's actually an "add"
          if (media['replaceAudio']) {
            media['keepAudio'] = false;
            media['replaceAudio'] = false;
            media['addAudio'] = true;
            media['audioSend'] = true;
          }
          if (isAudioSendEnabled(media)) {
            media['keepAudio'] = false;
            media['addAudio'] = true;
          }
        } else {
          if (pluginHandle.myStream.getAudioTracks() == null ||
              pluginHandle.myStream.getAudioTracks().length == 0) {
            // No audio track: if we were asked to replace, it's actually an "add"
            if (media['replaceAudio']) {
              media['keepAudio'] = false;
              media['replaceAudio'] = false;
              media['addAudio'] = true;
              media['audioSend'] = true;
            }
            if (isAudioSendEnabled(media)) {
              media['keepAudio'] = false;
              media['addAudio'] = true;
            }
          } else {
            // We have an audio track: should we keep it as it is?
            if (isAudioSendEnabled(media) &&
                !media['removeAudio'] &&
                !media['replaceAudio']) {
              media['keepAudio'] = true;
            }
          }
        }
        // Check if there are changes on video
        if (media['addVideo']) {
          media['keepVideo'] = false;
          media['replaceVideo'] = false;
          media['removeVideo'] = false;
          media['videoSend'] = true;
          if (pluginHandle.myStream != null &&
              pluginHandle.myStream.getVideoTracks() != null &&
              pluginHandle.myStream.getVideoTracks().length > 0) {
            Janus.error("Can't add video stream, there already is one");
            callbacks.error("Can't add video stream, there already is one");
            return;
          }
        } else if (media['removeVideo']) {
          media['keepVideo'] = false;
          media['replaceVideo'] = false;
          media['addVideo'] = false;
          media['videoSend'] = false;
        } else if (media['replaceVideo']) {
          media['keepVideo'] = false;
          media['addVideo'] = false;
          media['removeVideo'] = false;
          media['videoSend'] = true;
        }
        if (pluginHandle.myStream == null) {
          // No media stream: if we were asked to replace, it's actually an "add"
          if (media['replaceVideo']) {
            media['keepVideo'] = false;
            media['replaceVideo'] = false;
            media['addVideo'] = true;
            media['videoSend'] = true;
          }
          if (isVideoSendEnabled(media)) {
            media['keepVideo'] = false;
            media['addVideo'] = true;
          }
        } else {
          if (pluginHandle.myStream.getVideoTracks() == null ||
              pluginHandle.myStream.getVideoTracks().length == 0) {
            // No video track: if we were asked to replace, it's actually an "add"
            if (media['replaceVideo']) {
              media['keepVideo'] = false;
              media['replaceVideo'] = false;
              media['addVideo'] = true;
              media['videoSend'] = true;
            }
            if (isVideoSendEnabled(media)) {
              media['keepVideo'] = false;
              media['addVideo'] = true;
            }
          } else {
            // We have a video track: should we keep it as it is?
            if (isVideoSendEnabled(media) &&
                !media['removeVideo'] &&
                !media['replaceVideo']) {
              media['keepVideo'] = true;
            }
          }
        }
        // Data channels can only be added
        if (media['addData']) {
          media['data'] = true;
        }
      }
      // If we're updating and keeping all tracks, let's skip the getUserMedia part
      if ((isAudioSendEnabled(media) && media['keepAudio']) &&
          (isVideoSendEnabled(media) && media['keepVideo'])) {
        // pluginHandle.consentDialog(false);
        streamsDone(handleId, jsep, media, callbacks, pluginHandle.myStream);
        return;
      }
    }

    // If we're updating, check if we need to remove/replace one of the tracks
    if (media['update'] && pluginHandle.streamExternal) {
      if (media['removeAudio'] || media['replaceAudio']) {
        if (pluginHandle.myStream != null &&
            pluginHandle.myStream.getAudioTracks() != null &&
            pluginHandle.myStream.getAudioTracks().length > 0) {
          var at = pluginHandle.myStream.getAudioTracks()[0];
          Janus.log("Removing audio track:" + at.toString());
          pluginHandle.myStream.removeTrack(at);
          try {
            // at.stop();
          } catch (e) {}
        }
        // FIX ME
        // if (pluginHandle.pc.getSenders() && pluginHandle.pc.getSenders().length) {
        //   var ra = true;
        //   if (media['replaceAudio'] && Janus.unifiedPlan) {
        //     // We can use replaceTrack
        //     ra = false;
        //   }
        //   if (ra) {
        //     for (var asnd in pluginHandle.pc.getSenders()) {
        //       if (asnd != null &&
        //           asnd.track != null &&
        //           asnd.track.kind == "audio") {
        //         Janus.log("Removing audio sender:" + asnd.toString());
        //         pluginHandle.pc.removeTrack(asnd);
        //       }
        //     }
        //   }
        // }
      }
      if (media['removeVideo'] || media['replaceVideo']) {
        if (pluginHandle.myStream != null &&
            pluginHandle.myStream.getVideoTracks() != null &&
            pluginHandle.myStream.getVideoTracks().length > 0) {
          var vt = pluginHandle.myStream.getVideoTracks()[0];
          Janus.log("Removing video track:", vt);
          pluginHandle.myStream.removeTrack(vt);
          try {
            // vt.stop();
          } catch (e) {}
        }
        // FIX ME
        // if (pluginHandle.pc.getSenders() && pluginHandle.pc.getSenders().length) {
        //   var rv = true;
        //   if (media['replaceVideo'] && Janus.unifiedPlan) {
        //     // We can use replaceTrack
        //     rv = false;
        //   }
        //   if (rv) {
        //     for (var vsnd in pc.getSenders()) {
        //       if (vsnd != null &&
        //           vsnd.track != null &&
        //           vsnd.track.kind == "video") {
        //         Janus.log("Removing video sender:", vsnd);
        //         pluginHandle.pc.removeTrack(vsnd);
        //       }
        //     }
        //   }
        // }
      }
    }

    // Was a MediaStream object passed, or do we need to take care of that?
    if (callbacks.stream != null) {
      MediaStream stream = callbacks.stream;
      Janus.log("MediaStream provided by the application");
      Janus.debug(stream);
      // If this is an update, let's check if we need to release the previous stream
      if (media['update']) {
        if (pluginHandle.myStream != null &&
            pluginHandle.myStream != callbacks.stream &&
            pluginHandle.streamExternal) {
          // We're replacing a stream we captured ourselves with an external one
          try {
            // Try a MediaStreamTrack.stop() for each track
            // List tracks = pluginHandle.myStream.getTracks();
            // for (MediaStreamTrack mst in tracks) {
            //   Janus.log(mst);
            //   if (mst != null) mst.dispose();
            // }
          } catch (e) {
            // Do nothing if this fails
          }
          pluginHandle.myStream = null;
        }
      }
      // Skip the getUserMedia part
      pluginHandle.streamExternal = true;
      // pluginHandle.consentDialog(false);
      streamsDone(handleId, jsep, media, callbacks, stream);
      return;
    }

    if (isAudioSendEnabled(media) || isVideoSendEnabled(media)) {
      if (!Janus.isGetUserMediaAvailable()) {
        callbacks.error("getUserMedia not available");
        return;
      }
      Map<String, dynamic> constraints = {
        'mandatory': {},
        'optional': [
          {'DtlsSrtpKeyAgreement': true},
        ]
      };
      // pluginHandle.consentDialog(true);
      bool audioSupport = isAudioSendEnabled(media);
      if (audioSupport && media != null && media['audio'] is bool)
        bool audioSupport = media['audio'];

      bool videoSupport = isVideoSendEnabled(media);
      if (videoSupport && media != null) {
        bool simulcast = (callbacks.simulcast == true);
        bool simulcast2 = (callbacks.simulcast2 == true);
        if ((simulcast || simulcast2) && !jsep && !media['video'])
          media['video'] = "hires";
        if (media['video'] &&
            media['video'] != 'screen' &&
            media['video'] != 'window') {
          if (media['video'] is String) {
            videoSupport = media['video'];
          } else {
            int width = 0;
            int height = 0;
            int maxHeight = 0;
            if (media['video'] == 'lowres') {
              // Small resolution, 4:3
              height = 240;
              maxHeight = 240;
              width = 320;
            } else if (media['video'] == 'lowres-16:9') {
              // Small resolution, 16:9
              height = 180;
              maxHeight = 180;
              width = 320;
            } else if (media['video'] == 'hires' ||
                media['video'] == 'hires-16:9' ||
                media['video'] == 'hdres') {
              // High(HD) resolution is only 16:9
              height = 720;
              maxHeight = 720;
              width = 1280;
            } else if (media['video'] == 'fhdres') {
              // Full HD resolution is only 16:9
              height = 1080;
              maxHeight = 1080;
              width = 1920;
            } else if (media['video'] == '4kres') {
              // 4K resolution is only 16:9
              height = 2160;
              maxHeight = 2160;
              width = 3840;
            } else if (media['video'] == 'stdres') {
              // Normal resolution, 4:3
              height = 480;
              maxHeight = 480;
              width = 640;
            } else if (media['video'] == 'stdres-16:9') {
              // Normal resolution, 16:9
              height = 360;
              maxHeight = 360;
              width = 640;
            } else {
              Janus.log("Default video setting is stdres 4:3");
              height = 480;
              maxHeight = 480;
              width = 640;
            }
            Janus.log("Adding media constraint:", media['video'].toString());
            Map videoSupport = {
              'height': {'ideal': height},
              'width': {'ideal': width}
            };
            Janus.log("Adding video constraint:", videoSupport);
          }
        } else if (media['video'] == 'screen' || media['video'] == 'window') {
          if (navigator != null && navigator.getDisplayMedia != null) {
            // The new experimental getDisplayMedia API is available, let's use that
            // https://groups.google.com/forum/#!topic/discuss-webrtc/Uf0SrR4uxzk
            // https://webrtchacks.com/chrome-screensharing-getdisplaymedia/
            constraints['video'] = {};
            if (media['screenshareFrameRate'] != null) {
              constraints['video']['frameRate'] = media['screenshareFrameRate'];
            }
            if (media['screenshareHeight'] != null) {
              constraints['video']['height'] = media['screenshareHeight'];
            }
            if (media['screenshareWidth']) {
              constraints['video']['width'] = media['screenshareWidth'];
            }
            constraints['audio'] = media['captureDesktopAudio'];
            navigator.getDisplayMedia(constraints).then((MediaStream stream) {
              //pluginHandle.consentDialog(false);
              if (isAudioSendEnabled(media) && !media['keepAudio']) {
                navigator.getUserMedia({'audio': true, 'video': false}).then(
                    (MediaStream stream) {
                  // stream.addTrack(stream.getAudioTracks()[0]);
                  streamsDone(handleId, jsep, media, callbacks, stream);
                });
              } else {
                streamsDone(handleId, jsep, media, callbacks, stream);
              }
            }).catchError((error, StackTrace stackTrace) {
              // pluginHandle.consentDialog(false);
              callbacks.error(error);
            });
            return;
          }
          // We're going to try and use the extension for Chrome 34+, the old approach
          // for older versions of Chrome, or the experimental support in Firefox 33+
          callbackUserMedia(error, stream) {
            // pluginHandle.consentDialog(false);
            if (error) {
              callbacks.error(error);
            } else {
              streamsDone(handleId, jsep, media, callbacks, stream);
            }
          }

          getScreenMedia(constraints, gsmCallback, useAudio) {
            Janus.log("Adding media constraint (screen capture)");
            Janus.debug(constraints);
            navigator.getUserMedia(constraints).then((MediaStream stream) {
              if (useAudio) {
                navigator.getUserMedia({'audio': true, 'video': false}).then(
                    (audioStream) {
                  stream.addTrack(audioStream.getAudioTracks()[0]);
                  gsmCallback(null, stream);
                });
              } else {
                gsmCallback(null, stream);
              }
            }).catchError((error, StackTrace stackTrace) {
              // pluginHandle.consentDialog(false);
              gsmCallback(error);
            });
          }

          if (Janus.webRTCAdapter['browserDetails']['browser'] == 'chrome') {
            var chromever = Janus.webRTCAdapter['browserDetails']['version'];
            var maxver = 33;
            Map<String, dynamic> window;
            // if (navigator.userAgent.match('Linux'))
            //   maxver = 35; // "known" crash in chrome 34 and 35 on linux
            if (chromever >= 26 && chromever <= maxver) {
              // Chrome 26->33 requires some awkward chrome://flags manipulation
              constraints = {
                'video': {
                  'mandatory': {
                    'googLeakyBucket': true,
                    'maxWidth': window['screen']['width'],
                    'maxHeight': window['screen']['height'],
                    'minFrameRate': media['screenshareFrameRate'],
                    'maxFrameRate': media['screenshareFrameRate'],
                    'chromeMediaSource': 'screen'
                  }
                },
                'audio': isAudioSendEnabled(media) && !media['keepAudio']
              };
              getScreenMedia(constraints, callbackUserMedia,
                  isAudioSendEnabled(media) && !media['keepAudio']);
            } else {
              // Chrome 34+ requires an extension
              // Janus.extension.getScreen((error, sourceId) {
              //   if (error) {
              //     pluginHandle.consentDialog(false);
              //     return callbacks.error(error);
              //   }
              //   constraints = {
              //     'audio': false,
              //     'video': {
              //       'mandatory': {
              //         'chromeMediaSource': 'desktop',
              //         'maxWidth': window['screen']['width'],
              //         'maxHeight': window['screen']['height'],
              //         'minFrameRate': media['screenshareFrameRate'],
              //         'maxFrameRate': media['screenshareFrameRate'],
              //       },
              //       'optional': [
              //         {'googLeakyBucket': true},
              //         {'googTemporalLayeredScreencast': true}
              //       ]
              //     }
              //   };
              //   constraints['video']['mandatory']['chromeMediaSourceId'] =
              //       sourceId;
              //   getScreenMedia(constraints, callbackUserMedia,
              //       isAudioSendEnabled(media) && !media['keepAudio']);
              // });
            }
          } else if (Janus.webRTCAdapter['browserDetails']['browser'] ==
              'firefox') {
            if (Janus.webRTCAdapter['browserDetails']['version'] >= 33) {
              // Firefox 33+ has experimental support for screen sharing
              constraints = {
                'video': {
                  'mozMediaSource': media['video'],
                  'mediaSource': media['video']
                },
                'audio': isAudioSendEnabled(media) && !media['keepAudio']
              };
              getScreenMedia(constraints, (err, stream) {
                callbackUserMedia(err, stream);
                // Workaround for https://bugzilla.mozilla.org/show_bug.cgi?id=1045810
                if (!err) {
                  var lastTime = stream.currentTime;
                  Timer polly = Timer(Duration(milliseconds: 500), () {});
                  if (!stream) polly.cancel();
                  if (stream.currentTime == lastTime) {
                    polly.cancel();
                    if (stream.onended) {
                      stream.onended();
                    }
                  }
                  lastTime = stream.currentTime;
                }
              }, isAudioSendEnabled(media) && !media['keepAudio']);
            } else {
              Map<String, String> error = {'type': 'NavigatorUserMediaError'};
              error['name'] =
                  'Your version of Firefox does not support screen sharing, please install Firefox 33 (or more recent versions)';
              // pluginHandle.consentDialog(false);
              callbacks.error(error);
              return;
            }
          }
          return;
        }
      }

      // If we got here, we're not screensharing
      if (media == null || media['video'] != 'screen') {
        // Check whether all media sources are actually available or not
        navigator.getSources().then((devices) {
          Janus.debug(devices.toString());
          bool audioExist = devices.any((device) {
            return device['kind'] == 'audioinput';
          });

          bool videoExist = isScreenSendEnabled(media) ||
              devices.any((device) {
                return device['kind'] == 'videoinput';
              });

          // Check whether a missing device is really a problem
          bool audioSend = isAudioSendEnabled(media);
          bool videoSend = isVideoSendEnabled(media);
          bool needAudioDevice = isAudioSendRequired(media);
          bool needVideoDevice = isVideoSendRequired(media);

          if (audioSend || videoSend || needAudioDevice || needVideoDevice) {
            // We need to send either audio or video
            var haveAudioDevice = audioSend ? audioExist : false;
            var haveVideoDevice = videoSend ? videoExist : false;
            if (!haveAudioDevice && !haveVideoDevice) {
              // FIXME Should we really give up, or just assume recvonly for both?
              // pluginHandle.consentDialog(false);
              callbacks.error('No capture device found');
              return false;
            } else if (!haveAudioDevice && needAudioDevice) {
              // pluginHandle.consentDialog(false);
              callbacks.error(
                  'Audio capture is required, but no capture device found');
              return false;
            } else if (!haveVideoDevice && needVideoDevice) {
              // pluginHandle.consentDialog(false);
              callbacks.error(
                  'Video capture is required, but no capture device found');
              return false;
            }
          }

          Map<String, dynamic> gumConstraints = {
            'audio': (audioExist && !media['keepAudio']) ? audioSupport : false,
            'video': (videoExist && !media['keepVideo']) ? videoSupport : false
          };
          Janus.debug("getUserMedia constraints", gumConstraints.toString());
          if (!gumConstraints['audio'] && !gumConstraints['video']) {
            // pluginHandle.consentDialog(false);
            streamsDone(handleId, jsep, media, callbacks, callbacks.stream);
          } else {
            // Override mediaConstraints
            if (gumConstraints['video']) {
              gumConstraints['video'] = {
                "mandatory": {
                  "minWidth":
                      '640', // Provide your own width, height and frame rate here
                  "minHeight": '480',
                  "minFrameRate": '30',
                },
                "facingMode": "user",
                "optional": [],
              };
            }
            Janus.debug(gumConstraints);
            navigator.getUserMedia(gumConstraints).then((MediaStream stream) {
              // pluginHandle.consentDialog(false);
              streamsDone(handleId, jsep, media, callbacks, stream);
            }).catchError((error, StackTrace stackTrace) {
              Janus.log(error);
              // pluginHandle.consentDialog(false);
              callbacks.error({
                'code': error.code,
                'name': error.name,
                'message': error.message
              });
            });
          }
        }).catchError((error, StackTrace stackTrace) {
          // pluginHandle.consentDialog(false);
          Janus.log(error);
          callbacks.error('enumerateDevices error', error);
        });
      }
    } else {
      // No need to do a getUserMedia, create offer/answer right away
      streamsDone(handleId, jsep, media, callbacks, null);
    }
  }

  prepareWebrtcPeer(int handleId, callbacks) {
    RTCSessionDescription jsep =
        RTCSessionDescription(callbacks.jsep["sdp"], callbacks.jsep["type"]);
    Plugin pluginHandle = this.pluginHandles[handleId.toString()];
    if (pluginHandle == null) {
      Janus.warn("Invalid handle");
      callbacks.error("Invalid handle");
      return;
    }
    if (jsep != null) {
      if (pluginHandle.pc == null) {
        Janus.warn(
            "Wait, no PeerConnection?? if this is an answer, use createAnswer and not handleRemoteJsep");
        callbacks.error(
            "No PeerConnection: if this is an answer, use createAnswer and not handleRemoteJsep");
        return;
      }

      pluginHandle.pc.setRemoteDescription(jsep).then((void v) {
        Janus.log("Remote description accepted!");
        pluginHandle.remoteSdp = callbacks.jsep["sdp"];
        // Any trickle candidate we cached?
        if (pluginHandle.candidates != null &&
            pluginHandle.candidates.length > 0) {
          for (var i = 0; i < pluginHandle.candidates.length; i++) {
            RTCIceCandidate candidate = pluginHandle.candidates[i];
            Janus.debug("Adding remote candidate:", candidate);
            if (candidate == null) {
              // end-of-candidates
              pluginHandle.pc.addCandidate(Janus.endOfCandidates);
            } else {
              // New candidate
              pluginHandle.pc.addCandidate(candidate);
            }
          }
          pluginHandle.candidates = [];
        }
        // Done
        callbacks.success();
      }).catchError((error, StackTrace stackTrace) {
        callbacks.error(error);
      });
    } else {
      callbacks.error("Invalid JSEP");
    }
  }

  createOffer(int handleId, Map<String, dynamic> media, Callbacks callbacks) {
    Plugin pluginHandle = this.pluginHandles[handleId.toString()];
    if (pluginHandle == null) {
      Janus.warn("Invalid handle");
      callbacks.error("Invalid handle");
      return;
    }
    bool simulcast = (callbacks.simulcast == true);
    if (!simulcast) {
      Janus.log(
          "Creating offer (iceDone=" + pluginHandle.iceDone.toString() + ")");
    } else {
      Janus.log("Creating offer (iceDone=" +
          pluginHandle.iceDone.toString() +
          ", simulcast=" +
          simulcast.toString() +
          ")");
    }
    // https://code.google.com/p/webrtc/issues/detail?id=3508
    Map<String, dynamic> mediaConstraints = {};
    if (Janus.unifiedPlan) {
      // We can use Transceivers
      var audioTransceiver;
      var videoTransceiver;
      // FIX ME
      // var transceivers = pc.getTransceivers();
      var transceivers = [];
      if (transceivers != null && transceivers.length > 0) {
        for (var t in transceivers) {
          if ((t['sender'] &&
                  t['sender'].track &&
                  t['sender'].track.kind == "audio") ||
              (t['receiver'] &&
                  t['receiver'].track &&
                  t['receiver'].track.kind == "audio")) {
            if (audioTransceiver == null) {
              audioTransceiver = t;
            }
            continue;
          }
          if ((t['sender'] &&
                  t['sender'].track &&
                  t['sender'].track.kind == "video") ||
              (t['receiver'] &&
                  t['receiver'].track &&
                  t['receiver'].track.kind == "video")) {
            if (videoTransceiver == null) {
              videoTransceiver = t;
            }
            continue;
          }
        }
      }
      // Handle audio (and related changes, if any)
      var audioSend = isAudioSendEnabled(media);
      var audioRecv = isAudioRecvEnabled(media);
      if (!audioSend && !audioRecv) {
        // Audio disabled: have we removed it?
        if (media['removeAudio'] && audioTransceiver) {
          if (audioTransceiver.setDirection != null) {
            audioTransceiver.setDirection("inactive");
          } else {
            audioTransceiver.direction = "inactive";
          }
          Janus.log("Setting audio transceiver to inactive:", audioTransceiver);
        }
      } else {
        // Take care of audio m-line
        if (audioSend && audioRecv) {
          if (audioTransceiver != null) {
            if (audioTransceiver.setDirection != null) {
              audioTransceiver.setDirection("sendrecv");
            } else {
              audioTransceiver.direction = "sendrecv";
            }
            Janus.log(
                "Setting audio transceiver to sendrecv:", audioTransceiver);
          }
        } else if (audioSend && !audioRecv) {
          if (audioTransceiver != null) {
            if (audioTransceiver.setDirection != null) {
              audioTransceiver.setDirection("sendonly");
            } else {
              audioTransceiver.direction = "sendonly";
            }
            Janus.log(
                "Setting audio transceiver to sendonly:", audioTransceiver);
          }
        } else if (!audioSend && audioRecv) {
          if (audioTransceiver != null) {
            if (audioTransceiver.setDirection != null) {
              audioTransceiver.setDirection("recvonly");
            } else {
              audioTransceiver.direction = "recvonly";
            }
            Janus.log(
                "Setting audio transceiver to recvonly:", audioTransceiver);
          } else {
            // FIX ME
            // // In theory, this is the only case where we might not have a transceiver yet
            // audioTransceiver =
            //     pc.addTransceiver("audio", {'direction': "recvonly"});
            // Janus.log("Adding recvonly audio transceiver:", audioTransceiver);
            Janus.log("addTransceiver is not supported");
          }
        }
      }
      // Handle video (and related changes, if any)
      var videoSend = isVideoSendEnabled(media);
      var videoRecv = isVideoRecvEnabled(media);
      if (!videoSend && !videoRecv) {
        // Video disabled: have we removed it?
        if (media['removeVideo'] && videoTransceiver != null) {
          if (videoTransceiver.setDirection != null) {
            videoTransceiver.setDirection("inactive");
          } else {
            videoTransceiver.direction = "inactive";
          }
          Janus.log("Setting video transceiver to inactive:", videoTransceiver);
        }
      } else {
        // Take care of video m-line
        if (videoSend && videoRecv) {
          if (videoTransceiver != null) {
            if (videoTransceiver.setDirection != null) {
              videoTransceiver.setDirection("sendrecv");
            } else {
              videoTransceiver.direction = "sendrecv";
            }
            Janus.log(
                "Setting video transceiver to sendrecv:", videoTransceiver);
          }
        } else if (videoSend && !videoRecv) {
          if (videoTransceiver != null) {
            if (videoTransceiver.setDirection != null) {
              videoTransceiver.setDirection("sendonly");
            } else {
              videoTransceiver.direction = "sendonly";
            }
            Janus.log(
                "Setting video transceiver to sendonly:", videoTransceiver);
          }
        } else if (!videoSend && videoRecv) {
          if (videoTransceiver != null) {
            if (videoTransceiver.setDirection != null) {
              videoTransceiver.setDirection("recvonly");
            } else {
              videoTransceiver.direction = "recvonly";
            }
            Janus.log(
                "Setting video transceiver to recvonly:", videoTransceiver);
          } else {
            // FIX ME
            // In theory, this is the only case where we might not have a transceiver yet
            // videoTransceiver =
            //     pc.addTransceiver("video", {'direction': "recvonly"});
            // Janus.log("Adding recvonly video transceiver:", videoTransceiver);
            Janus.log("addTransceiver is not supported");
          }
        }
      }
    } else {
      mediaConstraints["offerToReceiveAudio"] = isAudioRecvEnabled(media);
      mediaConstraints["offerToReceiveVideo"] = isVideoRecvEnabled(media);
    }
    bool iceRestart = (callbacks.iceRestart == true);
    if (iceRestart) {
      mediaConstraints["iceRestart"] = true;
    }
    Janus.debug(mediaConstraints);
    // Check if this is Firefox and we've been asked to do simulcasting
    bool sendVideo = isVideoSendEnabled(media);
    if (sendVideo &&
        simulcast &&
        Janus.webRTCAdapter['browserDetails']['browser'] == "firefox") {
      // FIXME Based on https://gist.github.com/voluntas/088bc3cc62094730647b
      Janus.log("Enabling Simulcasting for Firefox (RID)");
      // FIX ME No equivalent call
      // var sender = pc.getSenders().find((s) {
      //   return s.track.kind == "video";
      // });
      // if (sender) {
      //   var parameters = sender.getParameters();
      //   if (!parameters) {
      //     parameters = {};
      //   }
      //   var maxBitrates = getMaxBitrates(callbacks.simulcastMaxBitrates);
      //   parameters.encodings = [
      //     {'rid': "h", 'active': true, 'maxBitrate': maxBitrates['high']},
      //     {
      //       'rid': "m",
      //       'active': true,
      //       'maxBitrate': maxBitrates['medium'],
      //       'scaleResolutionDownBy': 2
      //     },
      //     {
      //       'rid': "l",
      //       'active': true,
      //       'maxBitrate': maxBitrates['low'],
      //       'scaleResolutionDownBy': 4
      //     }
      //   ];
      //   sender.setParameters(parameters);
      // }
    }

    pluginHandle.pc
        .createOffer(mediaConstraints)
        .then((RTCSessionDescription offer) {
      Janus.debug(offer.toString());
      // JSON.stringify doesn't work on some WebRTC objects anymore
      // See https://code.google.com/p/chromium/issues/detail?id=467366
      // RTCSessionDescription jsep = RTCSessionDescription(offer.sdp, offer.type);
      // FIX ME
      // callbacks.customizeSdp(jsep);
      // offer.sdp = offer.sdp;
      Janus.log("Setting local description");
      if (sendVideo && simulcast) {
        // This SDP munging only works with Chrome (Safari STP may support it too)
        if (Janus.webRTCAdapter['browserDetails']['browser'] == "chrome" ||
            Janus.webRTCAdapter['browserDetails']['browser'] == "safari") {
          Janus.log("Enabling Simulcasting for Chrome (SDP munging)");
          offer.sdp = mungeSdpForSimulcasting(offer.sdp);
        } else if (Janus.webRTCAdapter['browserDetails']['browser'] !=
            "firefox") {
          Janus.warn(
              "simulcast=true, but this is not Chrome nor Firefox, ignoring");
        }
      }
      pluginHandle.mySdp = offer.sdp;
      pluginHandle.pc.setLocalDescription(offer);
      pluginHandle.mediaConstraints = mediaConstraints;
      if (pluginHandle.iceDone == false && pluginHandle.trickle == false) {
        // Don't do anything until we have all candidates
        Janus.log("Waiting for all candidates...");
        return;
      }
      Janus.log("Offer ready");
      callbacks.success(offer);
    }).catchError((error, StackTrace stackTrace) {
      callbacks.error(error);
    });
  }

  createAnswer(int handleId, media, callbacks, customizedSdp) {
    Plugin pluginHandle = this.pluginHandles[handleId.toString()];
    if (pluginHandle == null) {
      Janus.warn("Invalid handle");
      callbacks.error("Invalid handle");
      return;
    }
    var simulcast = (callbacks['simulcast'] == true);
    if (!simulcast) {
      Janus.log(
          "Creating answer (iceDone=" + pluginHandle.iceDone.toString() + ")");
    } else {
      Janus.log("Creating answer (iceDone=" +
          pluginHandle.iceDone.toString() +
          ", simulcast=" +
          simulcast.toString() +
          ")");
    }
    var mediaConstraints;
    if (Janus.unifiedPlan) {
      // We can use Transceivers
      mediaConstraints = {};
      var audioTransceiver;
      var videoTransceiver;
      // FIX ME no equivalent call
      // var transceivers = pluginHandle.pc.getTransceivers();
      // if (transceivers != null && transceivers.length > 0) {
      //   for (var t in transceivers) {
      //     if ((t['sender'] &&
      //             t['sender'].track &&
      //             t['sender'].track.kind == "audio") ||
      //         (t['receiver'] &&
      //             t['receiver'].track &&
      //             t['receiver'].track.kind == "audio")) {
      //       if (!audioTransceiver) audioTransceiver = t;
      //       continue;
      //     }
      //     if ((t['sender'] &&
      //             t['sender'].track &&
      //             t['sender'].track.kind == "video") ||
      //         (t['receiver'] &&
      //             t['receiver'].track &&
      //             t['receiver'].track.kind == "video")) {
      //       if (!videoTransceiver) videoTransceiver = t;
      //       continue;
      //     }
      //   }
      // }
      // Handle audio (and related changes, if any)
      var audioSend = isAudioSendEnabled(media);
      var audioRecv = isAudioRecvEnabled(media);
      if (!audioSend && !audioRecv) {
        // Audio disabled: have we removed it?
        if (media['removeAudio'] && audioTransceiver) {
          try {
            if (audioTransceiver.setDirection != null) {
              audioTransceiver.setDirection("inactive");
            } else {
              audioTransceiver.direction = "inactive";
            }
            Janus.log(
                "Setting audio transceiver to inactive:", audioTransceiver);
          } catch (e) {
            Janus.error(e);
          }
        }
      } else {
        // Take care of audio m-line
        if (audioSend && audioRecv) {
          if (audioTransceiver != null) {
            try {
              if (audioTransceiver.setDirection != null) {
                audioTransceiver.setDirection("sendrecv");
              } else {
                audioTransceiver.direction = "sendrecv";
              }
              Janus.log(
                  "Setting audio transceiver to sendrecv:", audioTransceiver);
            } catch (e) {
              Janus.error(e);
            }
          }
        } else if (audioSend && !audioRecv) {
          try {
            if (audioTransceiver != null) {
              if (audioTransceiver.setDirection != null) {
                audioTransceiver.setDirection("sendonly");
              } else {
                audioTransceiver.direction = "sendonly";
              }
              Janus.log(
                  "Setting audio transceiver to sendonly:", audioTransceiver);
            }
          } catch (e) {
            Janus.error(e);
          }
        } else if (!audioSend && audioRecv) {
          if (audioTransceiver != null) {
            try {
              if (audioTransceiver.setDirection != null) {
                audioTransceiver.setDirection("recvonly");
              } else {
                audioTransceiver.direction = "recvonly";
              }
              Janus.log(
                  "Setting audio transceiver to recvonly:", audioTransceiver);
            } catch (e) {
              Janus.error(e);
            }
          } else {
            // In theory, this is the only case where we might not have a transceiver yet
            // FIX ME no addTransceiver call
            // audioTransceiver =
            //     pc.addTransceiver("audio", {'direction': "recvonly"});
            // Janus.log("Adding recvonly audio transceiver:", audioTransceiver);
            Janus.log("No addTransceiver call");
          }
        }
      }
      // Handle video (and related changes, if any)
      var videoSend = isVideoSendEnabled(media);
      var videoRecv = isVideoRecvEnabled(media);
      if (!videoSend && !videoRecv) {
        // Video disabled: have we removed it?
        if (media['removeVideo'] && videoTransceiver != null) {
          try {
            if (videoTransceiver.setDirection != null) {
              videoTransceiver.setDirection("inactive");
            } else {
              videoTransceiver.direction = "inactive";
            }
            Janus.log(
                "Setting video transceiver to inactive:", videoTransceiver);
          } catch (e) {
            Janus.error(e);
          }
        }
      } else {
        // Take care of video m-line
        if (videoSend && videoRecv) {
          if (videoTransceiver != null) {
            try {
              if (videoTransceiver.setDirection != null) {
                videoTransceiver.setDirection("sendrecv");
              } else {
                videoTransceiver.direction = "sendrecv";
              }
              Janus.log(
                  "Setting video transceiver to sendrecv:", videoTransceiver);
            } catch (e) {
              Janus.error(e);
            }
          }
        } else if (videoSend && !videoRecv) {
          if (videoTransceiver != null) {
            try {
              if (videoTransceiver.setDirection != null) {
                videoTransceiver.setDirection("sendonly");
              } else {
                videoTransceiver.direction = "sendonly";
              }
              Janus.log(
                  "Setting video transceiver to sendonly:", videoTransceiver);
            } catch (e) {
              Janus.error(e);
            }
          }
        } else if (!videoSend && videoRecv) {
          if (videoTransceiver != null) {
            try {
              if (videoTransceiver.setDirection != null) {
                videoTransceiver.setDirection("recvonly");
              } else {
                videoTransceiver.direction = "recvonly";
              }
              Janus.log(
                  "Setting video transceiver to recvonly:", videoTransceiver);
            } catch (e) {
              Janus.error(e);
            }
          } else {
            // In theory, this is the only case where we might not have a transceiver yet
            // FIX ME
            // videoTransceiver =
            //     pc.addTransceiver("video", {'direction': "recvonly"});
            // Janus.log("Adding recvonly video transceiver:", videoTransceiver);
            Janus.log("No addTransciever call");
          }
        }
      }
    } else {
      if (Janus.webRTCAdapter['browserDetails']['browser'] == "firefox" ||
          Janus.webRTCAdapter['browserDetails']['browser'] == "edge") {
        mediaConstraints = {
          'offerToReceiveAudio': isAudioRecvEnabled(media),
          'offerToReceiveVideo': isVideoRecvEnabled(media)
        };
      } else {
        mediaConstraints = {
          'mandatory': {
            'OfferToReceiveAudio': isAudioRecvEnabled(media),
            'OfferToReceiveVideo': isVideoRecvEnabled(media)
          }
        };
      }
    }
    Janus.debug(mediaConstraints);
    // Check if this is Firefox and we've been asked to do simulcasting
    var sendVideo = isVideoSendEnabled(media);
    if (sendVideo &&
        simulcast &&
        Janus.webRTCAdapter['browserDetails']['browser'] == "firefox") {
      // FIXME Based on https://gist.github.com/voluntas/088bc3cc62094730647b
      Janus.log("Enabling Simulcasting for Firefox (RID)");
      // FIX ME no equivalent call
      // var sender = pc.getSenders()[1];
      // Janus.log(sender);
      // var parameters = sender.getParameters();
      // Janus.log(parameters);

      // var maxBitrates = getMaxBitrates(callbacks.simulcastMaxBitrates);
      // sender.setParameters({
      //   'encodings': [
      //     {
      //       'rid': "high",
      //       'active': true,
      //       'priority': "high",
      //       'maxBitrate': maxBitrates['high']
      //     },
      //     {
      //       'rid': "medium",
      //       'active': true,
      //       'priority': "medium",
      //       'maxBitrate': maxBitrates['medium']
      //     },
      //     {
      //       'rid': "low",
      //       'active': true,
      //       'priority': "low",
      //       'maxBitrate': maxBitrates['low']
      //     }
      //   ]
      // });
    }
    pluginHandle.pc
        .createAnswer(mediaConstraints)
        .then((RTCSessionDescription answer) {
      Janus.debug(answer.toString());
      // JSON.stringify doesn't work on some WebRTC objects anymore
      // See https://code.google.com/p/chromium/issues/detail?id=467366
      RTCSessionDescription jsep =
          RTCSessionDescription(answer.sdp, answer.type);
      callbacks.customizeSdp(jsep);
      answer.sdp = jsep.sdp;
      Janus.log("Setting local description");
      if (sendVideo && simulcast) {
        // This SDP munging only works with Chrome
        if (Janus.webRTCAdapter['browserDetails']['browser'] == "chrome") {
          // FIXME Apparently trying to simulcast when answering breaks video in Chrome...
          //~ Janus.log("Enabling Simulcasting for Chrome (SDP munging)");
          //~ answer.sdp = mungeSdpForSimulcasting(answer.sdp);
          Janus.warn(
              "simulcast=true, but this is an answer, and video breaks in Chrome if we enable it");
        } else if (Janus.webRTCAdapter['browserDetails']['browser'] !=
            "firefox") {
          Janus.warn(
              "simulcast=true, but this is not Chrome nor Firefox, ignoring");
        }
      }
      pluginHandle.mySdp = answer.sdp;
      pluginHandle.pc.setLocalDescription(answer).catchError(callbacks.error);
      pluginHandle.mediaConstraints = mediaConstraints;
      if (pluginHandle.iceDone == null && pluginHandle.trickle == null) {
        // Don't do anything until we have all candidates
        Janus.log("Waiting for all candidates...");
        return;
      }
      callbacks.success(answer);
    }).catchError((error, StackTrace stackTrace) {
      callbacks.error(error);
    });
  }

  sendSDP(int handleId, callbacks) {
    var pluginHandle = this.pluginHandles[handleId.toString()];
    if (pluginHandle == null) {
      Janus.warn("Invalid handle, not sending anything");
      return;
    }

    Janus.log("Sending offer/answer SDP...");
    if (pluginHandle.mySdp == null) {
      Janus.warn("Local SDP instance is invalid, not sending anything...");
      return;
    }
    pluginHandle.pc
        .getLocalDescription()
        .then((RTCSessionDescription rtcSessionDescription) {
      pluginHandle.mySdp = {
        "type": rtcSessionDescription.type,
        "sdp": rtcSessionDescription.sdp,
      };
    }).catchError((error, StackTrace stackTrace) {
      Janus.log(error);
    });

    if (pluginHandle.trickle == false) pluginHandle.mySdp["trickle"] = false;
    Janus.debug(callbacks);
    pluginHandle.sdpSent = true;
    callbacks.success(pluginHandle.mySdp);
  }

  getVolume(int handleId, remote) {
    Plugin pluginHandle = this.pluginHandles[handleId.toString()];
    if (pluginHandle == null) {
      Janus.warn("Invalid handle");
      return 0;
    }
    var stream = remote ? "remote" : "local";

    if (!pluginHandle.volume[stream])
      pluginHandle.volume[stream] = {'value': 0};
    // Start getting the volume, if audioLevel in getStats is supported (apparently
    // they're only available in Chrome/Safari right now: https://webrtc-stats.callstats.io/)
    if (pluginHandle.pc.getStats() != null &&
        (Janus.webRTCAdapter['browserDetails']['browser'] == "chrome" ||
            Janus.webRTCAdapter['browserDetails']['browser'] == "safari")) {
      if (remote && pluginHandle.remoteStream == null) {
        Janus.warn("Remote stream unavailable");
        return 0;
      } else if (remote == null && pluginHandle.myStream == null) {
        Janus.warn("Local stream unavailable");
        return 0;
      }
      if (pluginHandle.volume[stream]['timer'] == null) {
        Janus.log("Starting " + stream + " volume monitor");
        pluginHandle.volume[stream]['timer'] =
            Timer(Duration(microseconds: 200), () {
          pluginHandle.pc.getStats().then((List<StatsReport> stats) {
            stats.forEach((res) {
              if (res == null || res.type != "audio") return;
              if ((remote != null && !res.values['remoteSource']) ||
                  (remote != null && res.type != "media-source")) return;
              pluginHandle.volume[stream]['value'] =
                  (res.values['audioLevel'] ? res.values['audioLevel'] : 0);
            });
          });
        });
        return 0; // We don't have a volume to return yet
      }
      return pluginHandle.volume[stream]['value'];
    } else {
      // audioInputLevel and audioOutputLevel seem only available in Chrome? audioLevel
      // seems to be available on Chrome and Firefox, but they don't seem to work
      Janus.warn("Getting the " + stream + " volume unsupported by browser");
      return 0;
    }
  }

  isMuted(int handleId, video) {
    Plugin pluginHandle = this.pluginHandles[handleId.toString()];
    if (pluginHandle == null) {
      Janus.warn("Invalid handle");
      return true;
    }

    if (pluginHandle.pc == null) {
      Janus.warn("Invalid PeerConnection");
      return true;
    }
    if (pluginHandle.myStream == null) {
      Janus.warn("Invalid local MediaStream");
      return true;
    }
    if (video) {
      // Check video track
      if (pluginHandle.myStream.getVideoTracks() == null ||
          pluginHandle.myStream.getVideoTracks().length == 0) {
        Janus.warn("No video track");
        return true;
      }
      return !pluginHandle.myStream.getVideoTracks()[0].enabled;
    } else {
      // Check audio track
      if (pluginHandle.myStream.getAudioTracks() == null ||
          pluginHandle.myStream.getAudioTracks().length == 0) {
        Janus.warn("No audio track");
        return true;
      }
      return !pluginHandle.myStream.getAudioTracks()[0].enabled;
    }
  }

  mute(int handleId, video, mute) {
    Plugin pluginHandle = this.pluginHandles[handleId.toString()];
    if (pluginHandle == null) {
      Janus.warn("Invalid handle");
      return false;
    }

    if (pluginHandle.pc == null) {
      Janus.warn("Invalid PeerConnection");
      return false;
    }
    if (pluginHandle.myStream != null) {
      Janus.warn("Invalid local MediaStream");
      return false;
    }
    if (video) {
      // Mute/unmute video track
      if (pluginHandle.myStream.getVideoTracks() == null ||
          pluginHandle.myStream.getVideoTracks().length == 0) {
        Janus.warn("No video track");
        return false;
      }
      pluginHandle.myStream.getVideoTracks()[0].enabled = !mute;
      return true;
    } else {
      // Mute/unmute audio track
      if (pluginHandle.myStream.getAudioTracks() == null ||
          pluginHandle.myStream.getAudioTracks().length == 0) {
        Janus.warn("No audio track");
        return false;
      }
      pluginHandle.myStream.getAudioTracks()[0].enabled = !mute;
      return true;
    }
  }

  getBitrate(int handleId) {
    Plugin pluginHandle = this.pluginHandles[handleId.toString()];
    if (pluginHandle == null) {
      Janus.warn("Invalid handle");
      return "Invalid handle";
    }

    if (pluginHandle.pc == null) return "Invalid PeerConnection";
    // Start getting the bitrate, if getStats is supported
    if (pluginHandle.pc.getStats() != null) {
      if (pluginHandle.bitrate['timer'] != null) {
        Janus.log("Starting bitrate timer (via getStats)");
        pluginHandle.bitrate['timer'] = Timer(Duration(microseconds: 1000), () {
          pluginHandle.pc.getStats().then((List<StatsReport> stats) {
            stats.forEach((res) {
              if (res == null) return;
              bool inStats = false;
              // Check if these are statistics on incoming media
              if ((res.type == "video" ||
                      res.id.toLowerCase().indexOf("video") > -1) &&
                  res.type == "inbound-rtp" &&
                  res.id.indexOf("rtcp") < 0) {
                // New stats
                inStats = true;
              } else if (res.type == 'ssrc') {
                // Older Chromer versions
                inStats = true;
              }
              // Parse stats now
              if (inStats) {
                pluginHandle.bitrate['bsnow'] = res.values['bytesReceived'];
                pluginHandle.bitrate['tsnow'] = res.timestamp;
                if (pluginHandle.bitrate['bsbefore'] == null ||
                    pluginHandle.bitrate['tsbefore'] == null) {
                  // Skip this round
                  pluginHandle.bitrate['bsbefore'] =
                      pluginHandle.bitrate['bsnow'];
                  pluginHandle.bitrate['tsbefore'] =
                      pluginHandle.bitrate['tsnow'];
                } else {
                  // Calculate bitrate
                  var timePassed = pluginHandle.bitrate['tsnow'] -
                      pluginHandle.bitrate['tsbefore'];
                  if (Janus.webRTCAdapter['browserDetails']['browser'] ==
                      "safari")
                    timePassed = timePassed /
                        1000; // Apparently the timestamp is in microseconds, in Safari
                  var bitRate = ((pluginHandle.bitrate['bsnow'] -
                              pluginHandle.bitrate['bsbefore']) *
                          8 /
                          timePassed)
                      .round();
                  if (Janus.webRTCAdapter['browserDetails']['browser'] ==
                      "safari") bitRate = int.parse(bitRate / 1000);
                  pluginHandle.bitrate['value'] = bitRate + ' kbits/sec';
                  Janus.log(
                      "Estimated bitrate is " + pluginHandle.bitrate['value']);
                  pluginHandle.bitrate['bsbefore'] =
                      pluginHandle.bitrate['bsnow'];
                  pluginHandle.bitrate['tsbefore'] =
                      pluginHandle.bitrate['tsnow'];
                }
              }
            });
          });
        });
        return "0 kbits/sec"; // We don't have a bitrate value yet
      }
      return pluginHandle.bitrate['value'];
    } else {
      Janus.warn("Getting the video bitrate unsupported by browser");
      return "Feature unsupported by browser";
    }
  }

  webrtcError(error) {
    Janus.error("WebRTC error:", error);
  }

  cleanupWebrtc(int handleId, hangupRequest) {
    Janus.log("Cleaning WebRTC stuff");
    Plugin pluginHandle = this.pluginHandles[handleId.toString()];
    if (pluginHandle == null) {
      // Nothing to clean
      return;
    }

    if (hangupRequest == true) {
      // Send a hangup request (we don't really care about the response)
      var request = {"janus": "hangup", "transaction": Janus.randomString(12)};
      if (pluginHandle.handleToken != null)
        request["token"] = pluginHandle.handleToken;
      if (this.apiSecret != null) request["apisecret"] = this.apiSecret;
      Janus.debug(
          "Sending hangup request (handle=" + handleId.toString() + "):");
      Janus.debug(request);
      if (this.websockets) {
        request["session_id"] = this.sessionId;
        request["handle_id"] = handleId;
        this.ws.send(jsonEncode(request));
      } else {
        GatewayCallbacks httpCallbacks = GatewayCallbacks();
        Janus.httpAPICall(
            this.server +
                "/" +
                this.sessionId.toString() +
                "/" +
                handleId.toString(),
            {
              'verb': 'POST',
              'withCredentials': this.withCredentials,
              'body': request,
            },
            httpCallbacks);
      }
    }
    // Cleanup stack
    pluginHandle.remoteStream = null;
    if (pluginHandle.volume != null) {
      if (pluginHandle.volume['local'] != null &&
          pluginHandle.volume['local']['timer'] != null)
        pluginHandle.volume['local']['timer'].cancel();
      if (pluginHandle.volume['remote'] &&
          pluginHandle.volume['remote']['timer'] != null)
        pluginHandle.volume['remote']['timer'].cancel();
    }
    pluginHandle.volume = {};
    if (pluginHandle.bitrate['timer'] != null)
      pluginHandle.bitrate['timer'].cancel();
    pluginHandle.bitrate['timer'] = null;
    pluginHandle.bitrate['bsnow'] = null;
    pluginHandle.bitrate['bsbefore'] = null;
    pluginHandle.bitrate['tsnow'] = null;
    pluginHandle.bitrate['tsbefore'] = null;
    pluginHandle.bitrate['value'] = null;
    try {
      // Try a MediaStreamTrack.stop() for each track
      if (pluginHandle.streamExternal && pluginHandle.myStream != null) {
        Janus.log("Stopping local stream tracks");
        // var tracks = pluginHandle.myStream.getTracks();
        // for (var mst in tracks) {
        //   Janus.log(mst);
        //   if (mst) mst.stop();
        // }
      }
    } catch (e) {
      // Do nothing if this fails
    }
    pluginHandle.streamExternal = false;
    pluginHandle.myStream = null;
    // Close PeerConnection
    try {
      pluginHandle.pc.dispose();
    } catch (e) {
      // Do nothing
    }
    pluginHandle.pc = null;
    pluginHandle.candidates = [];
    pluginHandle.mySdp = null;
    pluginHandle.remoteSdp = null;
    pluginHandle.iceDone = false;
    pluginHandle.dataChannels = {};
    pluginHandle.dtmfSender = null;

    pluginHandle.onCleanup();
  }

  // Helper method to munge an SDP to enable simulcasting (Chrome only)
  mungeSdpForSimulcasting(sdp) {
    // Let's munge the SDP to add the attributes for enabling simulcasting
    // (based on https://gist.github.com/ggarber/a19b4c33510028b9c657)

    var sdpSession = parse(sdp);
    // TODO
    // Need to be ported for dart
    return write(sdpSession, null);
  }

  // Helper methods to parse a media object
  isAudioSendEnabled(Map<String, dynamic> media) {
    Janus.debug("isAudioSendEnabled:", media.toString());
    if (media == null) return true; // Default
    if (media['audio'] == false) return false; // Generic audio has precedence
    if (media['audioSend'] == null) return true; // Default
    return (media['audioSend'] == true);
  }

  isAudioSendRequired(Map<String, dynamic> media) {
    Janus.debug("isAudioSendRequired:", media.toString());
    if (media == null) return false; // Default
    if (media['audio'] == false || media['audioSend'] == false)
      return false; // If we're not asking to capture audio, it's not required
    if (media['failIfNoAudio'] == null) return false; // Default
    return (media['failIfNoAudio'] == true);
  }

  isAudioRecvEnabled(Map<String, dynamic> media) {
    Janus.debug("isAudioRecvEnabled:", media.toString());
    if (media == null) return true; // Default
    if (media['audio'] == false) return false; // Generic audio has precedence
    if (media['audioRecv'] == null) return true; // Default
    return (media['audioRecv'] == true);
  }

  isVideoSendEnabled(Map<String, dynamic> media) {
    Janus.debug("isVideoSendEnabled:", media.toString());
    if (media == null) return true; // Default
    if (media['video'] == false) return false; // Generic video has precedence
    if (media['videoSend'] == null) return true; // Default
    return (media['videoSend'] == true);
  }

  isVideoSendRequired(Map<String, dynamic> media) {
    Janus.debug("isVideoSendRequired:", media.toString());
    if (media == null) return false; // Default
    if (media['video'] == false || media['videoSend'] == false)
      return false; // If we're not asking to capture video, it's not required
    if (media['failIfNoVideo'] == null) return false; // Default
    return (media['failIfNoVideo'] == true);
  }

  isVideoRecvEnabled(Map<String, dynamic> media) {
    Janus.debug("isVideoRecvEnabled:", media.toString());
    if (media == null) return true; // Default
    if (media['video'] == false) return false; // Generic video has precedence
    if (media['videoRecv'] == null) return true; // Default
    return (media['videoRecv'] == true);
  }

  isScreenSendEnabled(Map<String, dynamic> media) {
    Janus.debug("isScreenSendEnabled:", media);
    if (media == null) return false;
    if (media['video'] is bool)
      return false;
    else {
      var constraints = media['video']['mandatory'];
      if (constraints['chromeMediaSource'])
        return constraints['chromeMediaSource'] == 'desktop' ||
            constraints['chromeMediaSource'] == 'screen';
      else if (constraints.mozMediaSource)
        return constraints['mozMediaSource'] == 'window' ||
            constraints['mozMediaSource'] == 'screen';
      else if (constraints.mediaSource)
        return constraints['mediaSource'] == 'window' ||
            constraints['mediaSource'] == 'screen';
      return false;
    }
  }

  isDataEnabled(Map<String, dynamic> media) {
    Janus.debug("isDataEnabled:", media.toString());
    if (Janus.webRTCAdapter['browserDetails']['browser'] == "edge") {
      Janus.warn("Edge doesn't support data channels yet");
      return false;
    }
    if (media == null) return false; // Default
    return (media['data'] == true);
  }

  isTrickleEnabled(bool trickle) {
    Janus.debug("isTrickleEnabled:" + trickle.toString());
    return (trickle == false) ? false : true;
  }

  getMaxBitrates(Map<String, dynamic> simulcastMaxBitrates) {
    Map<String, dynamic> maxBitrates = {
      "high": 900000,
      "medium": 300000,
      "low": 100000,
    };

    if (simulcastMaxBitrates != null) {
      maxBitrates["high"] = simulcastMaxBitrates["high"];
      maxBitrates["medium"] = simulcastMaxBitrates["medium"];
      maxBitrates["low"] = simulcastMaxBitrates["low"];
    }
    return maxBitrates;
  }
}
