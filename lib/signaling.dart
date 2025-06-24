import 'dart:async';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

// Key modifications for DirectSignaling class
class DirectSignaling {
  DirectSignaling({required this.host});

  final String host;
  String? socketId;
  final Completer<void> _socketReady = Completer<void>();
  late List<Map<String, dynamic>> _pendingCandidates = [];
  late RTCPeerConnection localPeer;
  late WebSocketChannel channel;
  void Function(MediaStream stream)? onLocalStreamAvailable;
  void Function(MediaStream stream)? onRemoteStreamAvailable;
  void Function(RTCPeerConnectionState state)? onConnectionState;

  // Add these fields for call context
  String? _currentConversationId;
  bool _isVideoCall = true;

  Future<void> initalize({
    onLocalStreamAvailable,
    onRemoteStreamAvailable,
    onConnectionState,
  }) async {
    this.onLocalStreamAvailable = onLocalStreamAvailable;
    this.onRemoteStreamAvailable = onRemoteStreamAvailable;
    this.onConnectionState = onConnectionState;

    channel = IOWebSocketChannel.connect(host);
    channel.stream.listen(_handleWebsocketMessages);
    await initWebRTC();
  }

  void _handleWebsocketMessages(msg) async {
    Map<String, dynamic> message = jsonDecode(msg);

    if (message['type'] == 'id') {
      socketId = message['data'];
      if (!_socketReady.isCompleted) {
        _socketReady.complete();
      }
    } else if (message['type'] == 'answer') {
      var response = message['data'];
      print('Received answer');
      await handleResponse(response);
    } else if (message['type'] == 'offer') {
      var response = message['data'];
      print('Received offer');
      // Store conversation context
      _currentConversationId = message['conversationId'];
      _isVideoCall = message['isVideoCall'] ?? true;
      await handleOffer(response);
    } else if (message['type'] == 'candidate') {
      var candidate = message['data'];
      await handleRemoteCandidates(candidate);
    }
  }

  Future<void> waitForSocketReady() async {
    await _socketReady.future;
  }

  // Modified initWebRTC to accept call type parameter
  Future<void> initWebRTC({bool isVideoCall = true}) async {
    _isVideoCall = isVideoCall;
    var localStream = await getUserMedia(isVideoCall: isVideoCall);
    onLocalStreamAvailable?.call(localStream);

    localPeer = await createPeerConnection(
      {
        'iceServers': [
          {'urls': 'stun:stun.l.google.com:19302'},
          {'urls': 'stun:stun1.l.google.com:19302'},
          {
            'urls': 'turn:openrelay.metered.ca:80',
            'username': 'openrelayproject',
            'credential': 'openrelayproject',
          },
        ],
      },
      {
        "mandatory": {
          "OfferToReceiveAudio": true,
          "OfferToReceiveVideo": isVideoCall,
        },
        "optional": [],
      },
    );

    // ICE candidates will be handled by CallScreen
    localPeer.onIceCandidate = (RTCIceCandidate candidate) {
      // Let CallScreen handle Firestore updates
      channel.sink.add(
        jsonEncode({
          'type': 'candidate',
          'data': candidate.toMap(),
          'from': socketId,
          'conversationId': _currentConversationId,
        }),
      );
    };

    if (onConnectionState != null) {
      localPeer.onConnectionState = onConnectionState;
    }

    // Handle incoming tracks
    localPeer.onTrack = (RTCTrackEvent event) {
      if (event.streams.isNotEmpty) {
        onRemoteStreamAvailable?.call(event.streams[0]);
      }
    };

    // Add local stream tracks
    localStream.getTracks().forEach((track) async {
      await localPeer.addTrack(track, localStream);
    });
  }

  Future<void> handleRemoteCandidates(Map<String, dynamic> candidateMap) async {
    var candidate = RTCIceCandidate(
      candidateMap['candidate'],
      candidateMap['sdpMid'],
      candidateMap['sdpMLineIndex'],
    );

    if (localPeer.signalingState == RTCSignalingState.RTCSignalingStateStable ||
        localPeer.signalingState ==
            RTCSignalingState.RTCSignalingStateHaveRemoteOffer ||
        localPeer.signalingState ==
            RTCSignalingState.RTCSignalingStateHaveLocalPrAnswer) {
      print('Adding ICE candidate directly.');
      await localPeer.addCandidate(candidate);
    } else {
      // Store temporarily if not ready yet
      print('Storing ICE candidate for later.');
      _pendingCandidates.add(candidateMap);
    }
  }

  Future<void> handleResponse(Map<String, dynamic> description) async {
    var desc = RTCSessionDescription(description['sdp'], description['type']);
    await localPeer.setRemoteDescription(desc);

    // Process any pending candidates after setting remote description
    for (var candidateMap in _pendingCandidates) {
      await handleRemoteCandidates(candidateMap);
    }
    _pendingCandidates.clear();
  }

  Future<void> handleOffer(Map<String, dynamic> description) async {
    try {
      var desc = RTCSessionDescription(description['sdp'], description['type']);
      await localPeer.setRemoteDescription(desc);

      if (localPeer.signalingState !=
          RTCSignalingState.RTCSignalingStateHaveRemoteOffer) {
        print(
          'Peer is not in a valid state to create an answer: ${localPeer.signalingState}',
        );
        return;
      }
      _pendingCandidates.clear(); // Clear any pending candidates
      var answer = await localPeer.createAnswer({
        'offerToReceiveAudio': 1,
        'offerToReceiveVideo': _isVideoCall ? 1 : 0,
      });
      await localPeer.setLocalDescription(answer);

      // Update Firestore with answer
      if (_currentConversationId != null) {
        await FirebaseFirestore.instance
            .collection('calls')
            .doc(_currentConversationId!)
            .update({
              'type': 'answer',
              'sdp': answer.sdp,
              'isVideoCall': _isVideoCall,
              'timestamp': FieldValue.serverTimestamp(),
              'status': 'accepted',
            });
      }

      // Send answer via WebSocket
      String msg = jsonEncode({
        'type': 'answer',
        'data': answer.toMap(),
        'from': socketId,
        'conversationId': _currentConversationId,
      });
      channel.sink.add(msg);
    } catch (e) {
      print('Error handling offer: $e');
    }
  }

  // Modified getUserMedia to accept call type
  Future<MediaStream> getUserMedia({bool isVideoCall = true}) async {
    final constraints =
        isVideoCall
            ? {
              'audio': {
                'echoCancellation': true,
                'noiseSuppression': true,
                'autoGainControl': true,
              },
              'video': {
                'facingMode': 'user',
                'width': {'min': 320, 'ideal': 640, 'max': 1280},
                'height': {'min': 240, 'ideal': 480, 'max': 720},
                'frameRate': {'min': 15, 'ideal': 24, 'max': 30},
              },
            }
            : {
              'audio': {
                'echoCancellation': true,
                'noiseSuppression': true,
                'autoGainControl': true,
              },
              'video': false,
            };

    MediaStream stream = await navigator.mediaDevices.getUserMedia(constraints);
    return stream;
  }

  Future<void> call({
    required String conversationId,
    required String callerId,
    required String receiverId,
    required bool isVideoCall,
    required RTCSessionDescription offer,
  }) async {
    await waitForSocketReady();

    _currentConversationId = conversationId;
    _isVideoCall = isVideoCall;

    // Store offer in Firestore
    await FirebaseFirestore.instance
        .collection('calls')
        .doc(conversationId)
        .update({
          'type': 'offer',
          'sdp': offer.sdp,
          'isVideoCall': isVideoCall,
          'timestamp': FieldValue.serverTimestamp(),
        });

    // Send via WebSocket for real-time signaling
    String msg = jsonEncode({
      'type': 'offer',
      'data': offer.toMap(),
      'from': socketId,
      'conversationId': conversationId,
      'callerId': callerId,
      'receiverId': receiverId,
      'isVideoCall': isVideoCall,
    });
    channel.sink.add(msg);
  }

  Future<void> close() async {
    await localPeer.close();
    await localPeer.dispose();
    await channel.sink.close();
  }
}
