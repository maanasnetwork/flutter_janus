import 'dart:convert';
import 'dart:async';
import 'dart:core';

import 'callbacks.dart';
import 'janus.dart';
import 'session.dart';
import 'package:flutter_webrtc/webrtc.dart';

class Plugin {
  String plugin;
  String handleId;
  String token;
  bool detached;

  Map<String, dynamic> webrtcStuff = {
    'started': false,
    'myStream': null,
    'streamExternal': false,
    'remoteStream': null,
    'mySdp': null,
    'mediaConstraints': null,
    'pc': null,
    'dataChannel': {},
    'dtmfSender': null,
    'trickle': true,
    'iceDone': false,
    'volume': {'value': null, 'timer': null},
    'bitrate': {
      'value': null,
      'bsnow': null,
      'bsbefore': null,
      'tsnow': null,
      'tsbefore': null,
      'timer': null
    }
  };

  final Session session;
  final Callbacks callbacks;

  Plugin(this.session, this.callbacks);

  getId() => handleId;
  getPlugin() => plugin;
  getVolume() => this.session.getVolume(handleId, true);
  getRemoteVolume() => this.session.getVolume(handleId, true);
  getLocalVolume() => this.session.getVolume(handleId, false);
  isAudioMuted() => this.session.isMuted(handleId, false);
  muteAudio() => this.session.mute(handleId, false, true);
  unmuteAudio() => this.session.mute(handleId, false, false);
  isVideoMuted() => this.session.isMuted(handleId, true);
  muteVideo() => this.session.mute(handleId, true, true);
  unmuteVideo() => this.session.mute(handleId, true, false);
  getBitrate() => this.session.getBitrate(handleId);
  send(callbacks) => this.session.sendMessage(handleId, callbacks);
  data(callbacks) => this.session.sendData(handleId, callbacks);
  dtmf(callbacks) => this.session.sendDtmf(handleId, callbacks);

  consentDialog() => callbacks.consentDialog();
  iceState() => callbacks.iceState();
  mediaState() => callbacks.mediaState();
  webrtcState() => callbacks.webrtcState();
  slowLink() => callbacks.slowLink();
  onmessage() => callbacks.onmessage();
  createOffer(callbacks) =>
      this.session.prepareWebrtc(handleId, true, callbacks);
  createAnswer(callbacks) =>
      this.session.prepareWebrtc(handleId, false, callbacks);
  handleRemoteJsep(callbacks) =>
      this.session.prepareWebrtcPeer(handleId, callbacks);
  onlocalstream() => callbacks.onlocalstream();
  onremotestream() => callbacks.onremotestream();
  ondata() => callbacks.ondata();
  ondataopen() => callbacks.ondataopen();
  oncleanup() => callbacks.oncleanup();
  ondetached() => callbacks.ondetached();
  hangup(sendRequest) =>
      this.session.cleanupWebrtc(handleId, sendRequest == true);
  detach(callbacks) => this.session.destroyHandle(handleId, callbacks);
}
