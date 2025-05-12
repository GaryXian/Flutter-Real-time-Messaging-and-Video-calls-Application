// call_screen.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

class CallScreen extends StatefulWidget {
  final String conversationId;
  final String callerId;
  final String receiverId;
  final bool isVideoCall;

  const CallScreen({
    super.key,
    required this.conversationId,
    required this.callerId,
    required this.receiverId,
    required this.isVideoCall,
  });

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  final _localRenderer = RTCVideoRenderer();
  final _remoteRenderer = RTCVideoRenderer();

  RTCPeerConnection? _peerConnection;
  MediaStream? _localStream;

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  bool _isCaller = false;

  @override
  void initState() {
    super.initState();
    _initRenderers();
    _initCall();
  }

  Future<void> _initRenderers() async {
    await _localRenderer.initialize();
    await _remoteRenderer.initialize();
  }

  Future<void> _initCall() async {
    final currentUserId = _auth.currentUser?.uid;
    if (currentUserId == null) return;

    _isCaller = widget.callerId == currentUserId;

    final mediaConstraints = widget.isVideoCall
        ? {'audio': true, 'video': true}
        : {'audio': true, 'video': false};

    final stream = await navigator.mediaDevices.getUserMedia(mediaConstraints);
    _localStream = stream;
    _localRenderer.srcObject = stream;

    final config = {
      'iceServers': [
        {'urls': 'stun:stun.l.google.com:19302'},
      ]
    };

    _peerConnection = await createPeerConnection(config);

    // Add local stream
    for (var track in stream.getTracks()) {
      await _peerConnection?.addTrack(track, stream);
    }

    // On remote stream
    _peerConnection?.onTrack = (event) {
      if (event.streams.isNotEmpty) {
        setState(() {
          _remoteRenderer.srcObject = event.streams[0];
        });
      }
    };

    // Handle ICE candidates (send only local)
    _peerConnection?.onIceCandidate = (candidate) {
      if (candidate.candidate != null) {
        _firestore
            .collection('calls')
            .doc(widget.conversationId)
            .collection('iceCandidates')
            .add({
          'candidate': candidate.candidate,
          'sdpMid': candidate.sdpMid,
          'sdpMLineIndex': candidate.sdpMLineIndex,
        });
      }
    };

    if (_isCaller) {
      await _createOffer();
    } else {
      await _listenForOffer();
    }

    _listenForIceCandidates();
  }

  Future<void> _createOffer() async {
    final offer = await _peerConnection!.createOffer();
    await _peerConnection!.setLocalDescription(offer);

    await _firestore.collection('calls').doc(widget.conversationId).set({
      'type': 'offer',
      'sdp': offer.sdp,
      'callerId': widget.callerId,
      'receiverId': widget.receiverId,
      'isVideo': widget.isVideoCall,
    });

    // Listen for answer
    _firestore.collection('calls').doc(widget.conversationId).snapshots().listen((snapshot) async {
      final data = snapshot.data();
      if (data == null) return;

      if (data['type'] == 'answer' && (await _peerConnection?.getRemoteDescription()) == null) {
        final answer = RTCSessionDescription(data['sdp'], data['type']);
        await _peerConnection?.setRemoteDescription(answer);
      }
    });
  }

  Future<void> _listenForOffer() async {
    final doc = await _firestore.collection('calls').doc(widget.conversationId).get();

    if (!doc.exists) return;
    final data = doc.data();
    if (data == null || data['type'] != 'offer') return;

    final offer = RTCSessionDescription(data['sdp'], data['type']);
    await _peerConnection?.setRemoteDescription(offer);

    final answer = await _peerConnection!.createAnswer();
    await _peerConnection!.setLocalDescription(answer);

    await _firestore.collection('calls').doc(widget.conversationId).update({
      'type': 'answer',
      'sdp': answer.sdp,
    });
  }

  void _listenForIceCandidates() {
    _firestore
        .collection('calls')
        .doc(widget.conversationId)
        .collection('iceCandidates')
        .snapshots()
        .listen((snapshot) {
      for (var doc in snapshot.docs) {
        final data = doc.data();
        if (data['candidate'] != null) {
          final candidate = RTCIceCandidate(
            data['candidate'],
            data['sdpMid'],
            data['sdpMLineIndex'],
          );
          _peerConnection?.addCandidate(candidate);
        }
      }
    });
  }

  Future<void> _endCall() async {
    await _localStream?.dispose();
    await _peerConnection?.close();

    // Cleanup Firestore call document and candidates
    await _firestore
        .collection('calls')
        .doc(widget.conversationId)
        .collection('iceCandidates')
        .get()
        .then((snapshot) {
      for (var doc in snapshot.docs) {
        doc.reference.delete();
      }
    });

    await _firestore.collection('calls').doc(widget.conversationId).delete();

    Navigator.pop(context);
  }

  @override
  void dispose() {
    _localRenderer.dispose();
    _remoteRenderer.dispose();
    _localStream?.dispose();
    _peerConnection?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isVideoCall ? 'Video Call' : 'Voice Call'),
        actions: [
          IconButton(
            icon: const Icon(Icons.call_end, color: Colors.red),
            onPressed: _endCall,
          ),
        ],
      ),
      body: Center(
        child: widget.isVideoCall
            ? Column(
                children: [
                  Expanded(child: RTCVideoView(_remoteRenderer)),
                  Expanded(child: RTCVideoView(_localRenderer, mirror: true)),
                ],
              )
            : const Icon(Icons.call, size: 100, color: Colors.green),
      ),
    );
  }
}
