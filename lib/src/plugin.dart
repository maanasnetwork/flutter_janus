import 'dart:core';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:flutterjanus/flutterjanus.dart';

class Plugin {
  bool detached;
  bool started = false;
  MediaStream myStream;
  bool streamExternal;
  MediaStream remoteStream;
  var mySdp;
  var remoteSdp;
  bool sdpSent;
  Map<String, dynamic> mediaConstraints;
  RTCPeerConnection pc;
  Map<String, dynamic> dataChannels;
  RTCDTMFSender dtmfSender;
  bool trickle = true;
  bool iceDone = false;
  Map<String, dynamic> volume = {'value': null, 'timer': null};
  Map<String, dynamic> bitrate = {
    'value': '',
    'bsnow': null,
    'bsbefore': null,
    'tsnow': null,
    'tsbefore': null,
    'timer': null
  };
  List<RTCIceCandidate> candidates;
  var pendingData;

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
  onMessage(data, jsep) => callbacks.onMessage(data, jsep);
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
