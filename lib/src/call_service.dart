import 'package:flutter_webrtc/flutter_webrtc.dart' as webrtc;

import 'socket_service.dart';

class CallService {
  CallService(this._socketService);

  final SocketService _socketService;
  webrtc.RTCPeerConnection? _peerConnection;
  webrtc.MediaStream? localStream;
  webrtc.MediaStream? remoteStream;
  final List<Map<String, dynamic>> _pendingIceCandidates = [];
  bool _renderersInitialized = false;
  bool _remoteDescriptionSet = false;

  final localRenderer = webrtc.RTCVideoRenderer();
  final remoteRenderer = webrtc.RTCVideoRenderer();

  static const _configuration = {
    'iceServers': [
      {'urls': 'stun:stun.l.google.com:19302'},
      {'urls': 'stun:stun1.l.google.com:19302'},
    ],
  };

  Future<void> initializeRenderers() async {
    if (_renderersInitialized) return;
    await localRenderer.initialize();
    await remoteRenderer.initialize();
    _renderersInitialized = true;
  }

  Future<void> startLocalMedia({required bool video}) async {
    localStream = await webrtc.navigator.mediaDevices.getUserMedia({
      'audio': true,
      'video': video
          ? {
              'facingMode': 'user',
            }
          : false,
    });
    localRenderer.srcObject = localStream;
  }

  Future<void> createPeerConnection({
    required String receiverId,
    required String callId,
  }) async {
    await _peerConnection?.close();
    _pendingIceCandidates.clear();
    _remoteDescriptionSet = false;
    _peerConnection = await webrtc.createPeerConnection(_configuration);
    for (final track
        in localStream?.getTracks() ?? <webrtc.MediaStreamTrack>[]) {
      await _peerConnection!.addTrack(track, localStream!);
    }

    _peerConnection!
      ..onIceCandidate = (candidate) {
        _socketService.sendIceCandidate(
          receiverId: receiverId,
          callId: callId,
          candidate: candidate.toMap(),
        );
      }
      ..onTrack = (event) {
        if (event.streams.isNotEmpty) {
          remoteStream = event.streams.first;
          remoteRenderer.srcObject = remoteStream;
        }
      };
  }

  Future<Map<String, dynamic>> createOffer() async {
    final offer = await _peerConnection!.createOffer();
    await _peerConnection!.setLocalDescription(offer);
    return offer.toMap();
  }

  Future<Map<String, dynamic>> createAnswer() async {
    final answer = await _peerConnection!.createAnswer();
    await _peerConnection!.setLocalDescription(answer);
    return answer.toMap();
  }

  Future<void> receiveOffer(Map<String, dynamic> offer) async {
    await _peerConnection!.setRemoteDescription(
      webrtc.RTCSessionDescription(
        offer['sdp'] as String?,
        offer['type'] as String?,
      ),
    );
    _remoteDescriptionSet = true;
    await _flushPendingIceCandidates();
  }

  Future<void> receiveAnswer(Map<String, dynamic> answer) async {
    await _peerConnection!.setRemoteDescription(
      webrtc.RTCSessionDescription(
        answer['sdp'] as String?,
        answer['type'] as String?,
      ),
    );
    _remoteDescriptionSet = true;
    await _flushPendingIceCandidates();
  }

  Future<void> addIceCandidate(Map<String, dynamic> candidate) async {
    if (_peerConnection == null || !_remoteDescriptionSet) {
      _pendingIceCandidates.add(candidate);
      return;
    }

    await _addIceCandidateNow(candidate);
  }

  Future<void> _flushPendingIceCandidates() async {
    final candidates = List<Map<String, dynamic>>.from(_pendingIceCandidates);
    _pendingIceCandidates.clear();
    for (final candidate in candidates) {
      await _addIceCandidateNow(candidate);
    }
  }

  Future<void> _addIceCandidateNow(Map<String, dynamic> candidate) async {
    await _peerConnection!.addCandidate(
      webrtc.RTCIceCandidate(
        candidate['candidate'] as String?,
        candidate['sdpMid'] as String?,
        candidate['sdpMLineIndex'] as int?,
      ),
    );
  }

  void toggleMicrophone(bool enabled) {
    for (final track
        in localStream?.getAudioTracks() ?? <webrtc.MediaStreamTrack>[]) {
      track.enabled = enabled;
    }
  }

  void toggleCamera(bool enabled) {
    for (final track
        in localStream?.getVideoTracks() ?? <webrtc.MediaStreamTrack>[]) {
      track.enabled = enabled;
    }
  }

  Future<void> end() async {
    await _peerConnection?.close();
    _peerConnection = null;
    _pendingIceCandidates.clear();
    _remoteDescriptionSet = false;
    for (final track
        in localStream?.getTracks() ?? <webrtc.MediaStreamTrack>[]) {
      await track.stop();
    }
    await localStream?.dispose();
    await remoteStream?.dispose();
    localStream = null;
    remoteStream = null;
    localRenderer.srcObject = null;
    remoteRenderer.srcObject = null;
  }

  Future<void> dispose() async {
    await end();
    await localRenderer.dispose();
    await remoteRenderer.dispose();
  }
}
