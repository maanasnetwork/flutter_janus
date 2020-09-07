import 'dart:core';
import 'package:flutter_webrtc/webrtc.dart';
import 'package:flutter_webrtc/rtc_peerconnection.dart';
import 'package:flutterjanus/flutterjanus.dart';

class Plugin {
  Map<String, dynamic> webrtcStuff = {
    'started': false,
    'myStream': null,
    'streamExternal': false,
    'remoteStream': null,
    'mySdp': null,
    'mediaConstraints': null,
    'dtmfSender': null,
    'trickle': true,
    'iceDone': false,
    'volume': {'value': null, 'timer': null},
    'bitrate': {
      'value': '',
      'bsnow': null,
      'bsbefore': null,
      'tsnow': null,
      'tsbefore': null,
      'timer': null
    },
    'pendingData': null,
  };

  Map<String, RTCDataChannel> dataChannels;
  RTCPeerConnection pc;
  bool detached;

  final Session session;
  final Callbacks callbacks;
  final String plugin;
  final int handleId;
  final String handleToken;

  Plugin(
      {this.session,
      this.plugin,
      this.handleId,
      this.handleToken,
      this.callbacks});

  getId() => this.handleId;
  getPlugin() => this.plugin;
  getVolume() => this.session.getVolume(this.handleId, true);
  getRemoteVolume() => this.session.getVolume(this.handleId, true);
  getLocalVolume() => this.session.getVolume(this.handleId, false);
  isAudioMuted() => this.session.isMuted(this.handleId, false);
  muteAudio() => this.session.mute(this.handleId, false, true);
  unmuteAudio() => this.session.mute(this.handleId, false, false);
  isVideoMuted() => this.session.isMuted(this.handleId, true);
  muteVideo() => this.session.mute(this.handleId, true, true);
  unmuteVideo() => this.session.mute(this.handleId, true, false);
  getBitrate() => this.session.getBitrate(this.handleId);
  send(callbacks) => this.session.sendMessage(this.handleId, callbacks);
  data(callbacks) => this.session.sendData(this.handleId, callbacks);
  dtmf(callbacks) => this.session.sendDtmf(this.handleId, callbacks);

  consentDialog(bool state) => callbacks.consentDialog(state);
  iceState(RTCIceConnectionState state) => callbacks.iceState(state);
  mediaState(mediaType, mediaReciving) =>
      callbacks.mediaState(mediaType, mediaReciving);
  webrtcState(bool state, [reason]) => callbacks.webrtcState(state, [reason]);
  slowLink(uplink, lost) => callbacks.slowLink(uplink, lost);
  onmessage(data, jsep) => callbacks.onMessage(data, jsep);
  createOffer({Callbacks callbacks}) =>
      this.session.prepareWebrtc(this.handleId, true, callbacks);
  createAnswer(callbacks) =>
      this.session.prepareWebrtc(this.handleId, false, callbacks);
  handleRemoteJsep(callbacks) =>
      this.session.prepareWebrtcPeer(this.handleId, callbacks);
  onLocalStream(MediaStream stream) => callbacks.onLocalStream(stream);
  onRemoteStream(MediaStream stream) => callbacks.onRemoteStream(stream);
  onData(event, data) => callbacks.onData(event, data);
  onDataOpen(label) => callbacks.onDataOpen(label);
  onCleanup() => callbacks.onCleanup();
  onDetached() => callbacks.onDetached();
  hangup(sendRequest) =>
      this.session.cleanupWebrtc(this.handleId, sendRequest == true);
  detach(callbacks) => this.session.destroyHandle(this.handleId, callbacks);
}
