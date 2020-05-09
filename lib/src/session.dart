import 'dart:convert';
import 'dart:async';
import 'callbacks.dart';
import 'websocket.dart';
import 'janus.dart';
import 'plugin.dart';

class Session {
  bool websockets = false;
  var ws;
  var wsHandlers;
  Timer wsKeepaliveTimeoutId;
  List servers;
  int serversIndex = 0;
  var server;
  List<String> protocols = ['janus-protocol'];
  List iceServers = [
    {"urls": "stun:stun.l.google.com:19302"}
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
  String sessionId;
  Map<String, Map> pluginHandles;
  int retries = 0;
  Map<String, dynamic> transactions;

  final GatewayCallbacks gatewayCallbacks;

  Session(
      {this.server,
      this.iceServers,
      this.iceTransportPolicy,
      this.bundlePolicy,
      this.ipv6Support,
      this.withCredentials,
      this.maxPollEvents,
      this.token,
      this.apiSecret,
      this.destroyOnUnload,
      this.keepAlivePeriod,
      this.longPollTimeout,
      this.gatewayCallbacks}) {
    if (!Janus.initDone) {
      if (gatewayCallbacks.error is Function)
        gatewayCallbacks.error("Plugin not initialized");
    }
    Janus.log("Plugin initialized: " + Janus.initDone.toString());

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
      createSession(callbacks: gatewayCallbacks, reconnect: true);

  getSessionId() => this.sessionId;

  destroy(GatewayCallbacks callbacks) => destroySession(callbacks: callbacks);

  attach(Session session, Plugin plugin, Callbacks callbacks) =>
      plugin.attach(session: this, callbacks: callbacks);

  eventHandler() {
    if (this.sessionId == null) {
      return;
    }
    Janus.debug('Long poll...');
    if (this.connected) {
      Janus.warn("Is the server down? (connected=false)");
      return;
    }
    var longpoll = this.server +
        "/" +
        this.sessionId +
        "?rid=" +
        (new DateTime.now()).millisecondsSinceEpoch;
    Janus.log(longpoll);
    if (this.maxev > 0) longpoll = longpoll + "&maxev=" + this.maxev;
    if (this.token != null)
      longpoll = longpoll + "&token=" + Uri.encodeFull(token);
    if (this.apiSecret != null)
      longpoll = longpoll + "&apisecret=" + Uri.encodeFull(this.apiSecret);

    GatewayCallbacks httpCallbacks = GatewayCallbacks();
    httpCallbacks.success = handleEvent;
    httpCallbacks.error = (textStatus, errorThrown) {
      Janus.error(textStatus + ":" + errorThrown);
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
    if (this.websockets && this.sessionId != null && skipTimeout != true)
      eventHandler();
    if (this.websockets && Janus.isArray(json)) {
      // We got an array: it means we passed a maxev > 1, iterate on all objects
      for (var i = 0; i < json.length; i++) {
        handleEvent(json[i], true);
      }
      return;
    }
    if (json["janus"] == "keepalive") {
      // Nothing happened
      Janus.vdebug("Got a keepalive on session " + this.sessionId);
      return;
    } else if (json["janus"] == "ack") {
      // Just an ack, we can probably ignore
      Janus.debug("Got an ack on session " + sessionId);
      Janus.debug(json);
      var transaction = json["transaction"];
      if (transaction) {
        var reportSuccess = this.transactions[transaction];
        if (reportSuccess is Function) reportSuccess(json);
        this.transactions.remove(transaction);
      }
      return;
    } else if (json["janus"] == "success") {
      // Success!
      Janus.debug("Got a success on session " + sessionId);
      Janus.debug(json);
      // TODO Map transaction
      var transaction = json["transaction"];
      if (transaction) {
        // TODO Function reportSuccess
        var reportSuccess = this.transactions[transaction];
        if (reportSuccess is Function) reportSuccess(json);
        this.transactions.remove(transaction);
      }
      return;
    } else if (json["janus"] == "trickle") {
      // We got a trickle candidate from Janus
      var sender = json["sender"];
      if (sender == null) {
        Janus.warn("Missing sender...");
        return;
      }
      Map<String, dynamic> pluginHandle = this.pluginHandles[sender];
      if (pluginHandle == null) {
        Janus.debug("This handle is not attached to this session");
        return;
      }
      // TODO  RTCIceCandidate candidate
      var candidate = json["candidate"];
      Janus.debug("Got a trickled candidate on session " + this.sessionId);
      Janus.debug(candidate);
      var config = pluginHandle['webrtcStuff'];
      // TODO RTCPeerConnection config['pc']
      if (config['pc'] && config['remoteSdp']) {
        // Add candidate right now
        Janus.debug("Adding remote candidate:" + candidate);
        if (candidate == null) {
          // end-of-candidates
          config['pc'].addCandidate(Janus.endOfCandidates);
        } else {
          // New candidate
          config['pc'].addCandidate(candidate);
        }
      } else {
        // We didn't do setRemoteDescription (trickle got here before the offer?)
        Janus.debug(
            "We didn't do setRemoteDescription (trickle got here before the offer?), caching candidate");
        if (config.candidates == null) config.candidates = [];
        config['candidates'].add(candidate);
        Janus.debug(config.candidates);
      }
    } else if (json["janus"] == "webrtcup") {
      // The PeerConnection with the server is up! Notify this
      Janus.debug("Got a webrtcup event on session " + this.sessionId);
      Janus.debug(json);
      var sender = json["sender"];
      if (sender == null) {
        Janus.warn("Missing sender...");
        return;
      }
      Map<String, dynamic> pluginHandle = this.pluginHandles[sender];
      if (pluginHandle == null) {
        Janus.debug("This handle is not attached to this session");
        return;
      }
      pluginHandle['webrtcState'](true);
      return;
    } else if (json["janus"] == "hangup") {
      // A plugin asked the core to hangup a PeerConnection on one of our handles
      Janus.debug("Got a hangup event on session " + this.sessionId);
      Janus.debug(json);
      var sender = json["sender"];
      if (sender == null) {
        Janus.warn("Missing sender...");
        return;
      }
      Map<String, dynamic> pluginHandle = this.pluginHandles[sender];
      if (pluginHandle == null) {
        Janus.debug("This handle is not attached to this session");
        return;
      }
      pluginHandle['webrtcState'](false, json["reason"]);
      pluginHandle['hangup']();
    } else if (json["janus"] == "detached") {
      // A plugin asked the core to detach one of our handles
      Janus.debug("Got a detached event on session " + this.sessionId);
      Janus.debug(json);
      var sender = json["sender"];
      if (sender == null) {
        Janus.warn("Missing sender...");
        return;
      }
      Map<String, dynamic> pluginHandle = this.pluginHandles[sender];
      if (pluginHandle == null) {
        // Don't warn here because destroyHandle causes this situation.
        return;
      }
      pluginHandle['detached'] = true;
      pluginHandle['ondetached']();
      pluginHandle['detach']();
    } else if (json["janus"] == "media") {
      // Media started/stopped flowing
      Janus.debug("Got a media event on session " + this.sessionId);
      Janus.debug(json);
      var sender = json["sender"];
      if (sender == null) {
        Janus.warn("Missing sender...");
        return;
      }
      Map<String, dynamic> pluginHandle = this.pluginHandles[sender];
      if (pluginHandle == null) {
        Janus.debug("This handle is not attached to this session");
        return;
      }
      pluginHandle['mediaState'](json["type"], json["receiving"]);
    } else if (json["janus"] == "slowlink") {
      Janus.debug("Got a slowlink event on session " + this.sessionId);
      Janus.debug(json);
      // Trouble uplink or downlink
      var sender = json["sender"];
      if (sender == null) {
        Janus.warn("Missing sender...");
        return;
      }
      Map<String, dynamic> pluginHandle = this.pluginHandles[sender];
      if (pluginHandle == null) {
        Janus.debug("This handle is not attached to this session");
        return;
      }
      pluginHandle['slowLink'](json["uplink"], json["lost"]);
    } else if (json["janus"] == "error") {
      // Oops, something wrong happened
      Janus.error(
          "Ooops: " + json["error"].code + " " + json["error"].reason); // FIXME
      Janus.debug(json);
      var transaction = json["transaction"];
      if (transaction != null) {
        var reportSuccess = this.transactions[transaction];
        if (reportSuccess is Function) reportSuccess(json);
        this.transactions.remove(transaction);
      }
      return;
    } else if (json["janus"] == "event") {
      Janus.debug("Got a plugin event on session " + this.sessionId);
      Janus.debug(json);
      var sender = json["sender"];
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
          sender +
          " (" +
          plugindata["plugin"] +
          ")");
      var data = plugindata["data"];
      Janus.debug(data);
      Map<String, dynamic> pluginHandle = this.pluginHandles[sender];
      if (pluginHandle == null) {
        Janus.warn("This handle is not attached to this session");
        return;
      }
      var jsep = json["jsep"];
      if (jsep) {
        Janus.debug("Handling SDP as well...");
        Janus.debug(jsep);
      }
      var callback = pluginHandle['onmessage'];
      if (callback is Function) {
        Janus.debug("Notifying application...");
        // Send to callback specified when attaching plugin handle
        callback(data, jsep);
      } else {
        // Send to generic callback (?)
        Janus.debug("No provided notification callback");
      }
    } else if (json["janus"] == "timeout") {
      Janus.error("Timeout on session " + this.sessionId);
      Janus.debug(json);
      if (this.websockets) {
        this.ws.close(3504, "Gateway timeout");
      }
      return;
    } else {
      Janus.warn("Unknown message/event  '" +
          json["janus"] +
          "' on session " +
          this.sessionId);
      Janus.debug(json);
    }
  }

  // Private helper to send keep-alive messages on WebSockets
  keepAlive() {
    if (this.server == null || !this.websockets || !this.connected) return;
    this.wsKeepaliveTimeoutId =
        Timer(Duration(microseconds: this.keepAlivePeriod), this.keepAlive);
    Map<String, String> request = {
      "janus": "keepalive",
      "session_id": this.sessionId,
      "transaction": Janus.randomString(12)
    };
    if (this.token != null) request["token"] = token;
    if (this.apiSecret != null) request["apisecret"] = this.apiSecret;
    this.ws.send(jsonEncode(request));
  }

  createSession({GatewayCallbacks callbacks, bool reconnect = false}) {
    String transaction = Janus.randomString(12);
    Map<String, String> request = {
      "janus": "create",
      "transaction": transaction
    };
    if (reconnect) {
      // We're reconnecting, claim the session
      connected = false;
      request["janus"] = "claim";
      request["session_id"] = this.sessionId;
      // If we were using websockets, ignore the old connection
      if (this.websockets) {
        this.ws.onopen = null;
        this.ws.onerror = null;
        this.ws.onclose = null;
        if (this.wsKeepaliveTimeoutId != null) {
          this.wsKeepaliveTimeoutId.cancel();
          this.wsKeepaliveTimeoutId = null;
        }
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
      try {
        this.ws = SimpleWebSocket(this.server, this.protocols);
      } catch (e) {
        Janus.error(e.toString());
      }

      this.wsHandlers = {
        'error': () {
          Janus.error(
              "Error connecting to the Janus WebSockets server... " + server);
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
            Timer(Duration(microseconds: 200),
                createSession(callbacks: callbacks));
            return;
          }
          callbacks.error(
              "Error connecting to the Janus WebSockets server: Is the server down?");
        },
        'open': () {
          // We need to be notified about the success
          this.transactions[transaction] = (json) {
            Janus.debug(json);
            if (json["janus"] != "success") {
              Janus.error("Ooops: " +
                  json["error"].code +
                  " " +
                  json["error"].reason); // FIXME
              callbacks.error(json["error"].reason);
              return;
            }
            this.wsKeepaliveTimeoutId = Timer(
                Duration(microseconds: this.keepAlivePeriod), this.keepAlive);
            this.connected = true;
            transaction =
                json["session_id"] ? json["session_id"] : json.data["id"];
            if (reconnect) {
              Janus.log("Claimed session: " + this.sessionId);
            } else {
              Janus.log("Created session: " + this.sessionId);
            }
            // Janus.sessions[this.sessionId] = that;
            callbacks.success();
          };
          this.ws.send(jsonEncode(request));
        },
        'message': (event) => handleEvent(jsonDecode(event["data"])),
        'close': () {
          if (this.server == null || !this.connected) {
          } else {
            this.connected = false;
            // FIXME What if this is called when the page is closed?
            gatewayCallbacks
                .error("Lost connection to the server (is it down?)");
          }
        }
      };

      // Attach websocket handlers
      this.ws.onerror = this.wsHandlers['error'];
      this.ws.onopen = this.wsHandlers['open'];
      this.ws.onmessage = this.wsHandlers['message'];
      this.ws.onclose = this.wsHandlers['close'];
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
        callbacks.error(json["error"].reason);
        return;
      }
      this.connected = true;
      this.sessionId = json["session_id"] != null
          ? json["session_id"].toString()
          : json['data']["id"].toString();
      if (reconnect) {
        Janus.log("Claimed session: " + this.sessionId);
      } else {
        Janus.log("Created session: " + this.sessionId);
      }
      // Janus.sessions[this.sessionId] = that;
      eventHandler();
      callbacks.success();
    };
    httpCallbacks.error = (textStatus, errorThrown) {
      Janus.error(textStatus + ":" + errorThrown); // FIXME
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
        sessionId +
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
      this.pluginHandles.forEach((handleId, handle) {
        // TODO
        // Plugin.destroyHandle(sessionId, handleId, { 'noRequest': true }); // FIXME
      });
    }
    if (!this.connected) {
      Janus.warn("Is the server down? (connected=false)");
      this.sessionId = null;
      callbacks.success();
      return;
    }
    // No need to destroy all handles first, Janus will do that itself
    Map<String, String> request = {
      "janus": "destroy",
      "transaction": Janus.randomString(12)
    };
    if (this.token != null) request["token"] = token;
    if (this.apiSecret != null) request["apisecret"] = this.apiSecret;
    if (unload) {
      // We're unloading the page: use sendBeacon for HTTP instead,
      // or just close the WebSocket connection if we're using that
      if (this.websockets) {
        this.ws.onclose = null;
        this.ws.close();
        this.ws = null;
      } else {
        // navigator.sendBeacon(this.server + "/" + this.sessionId, jsonEncode(request));
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
        this.ws.onerror = null;
        this.ws.onopen = null;
        this.ws.onmessage = null;
        this.ws.onclose = null;

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

      this.ws.onmessage = onUnbindMessage;
      this.ws.onerror = onUnbindError;

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
        this.server + "/" + this.sessionId,
        {
          'verb': 'POST',
          'withCredentials': this.withCredentials,
          'body': request
        },
        callbacks);
  }
}
