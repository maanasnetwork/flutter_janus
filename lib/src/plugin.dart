import 'dart:convert';
import 'dart:async';
import 'dart:core';

import 'callbacks.dart';
import 'janus.dart';
import 'session.dart';
import 'package:flutter_webrtc/webrtc.dart';

class Plugin {
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

  bool detached;

  final Session session;
  final Callbacks callbacks;
  final String plugin;
  final String handleId;
  final String handleToken;

  Plugin(
      {this.session,
      this.plugin,
      this.handleId,
      this.handleToken,
      this.callbacks});

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

  consentDialog(bool state) => callbacks.consentDialog(state);
  iceState(bool state) => callbacks.iceState(state);
  mediaState(mediaType, mediaReciving) =>
      callbacks.mediaState(mediaType, mediaReciving);
  webrtcState(bool state, [reason]) => callbacks.webrtcState(state, [reason]);
  slowLink(uplink, lost) => callbacks.slowLink(uplink, lost);
  onmessage(data, jsep) => callbacks.onmessage(data, jsep);
  createOffer(callbacks) =>
      this.session.prepareWebrtc(handleId, true, callbacks);
  createAnswer(callbacks) =>
      this.session.prepareWebrtc(handleId, false, callbacks);
  handleRemoteJsep(callbacks) =>
      this.session.prepareWebrtcPeer(handleId, callbacks);
  onlocalstream(MediaStream stream) => callbacks.onlocalstream(stream);
  onremotestream(MediaStream stream) => callbacks.onremotestream(stream);
  ondata(event, data) => callbacks.ondata(event, data);
  ondataopen(label) => callbacks.ondataopen(label);
  oncleanup() => callbacks.oncleanup();
  ondetached() => callbacks.ondetached();
  hangup(sendRequest) =>
      this.session.cleanupWebrtc(handleId, sendRequest == true);
  detach(String handleId, callbacks) =>
      this.session.destroyHandle(handleId, callbacks);
}
