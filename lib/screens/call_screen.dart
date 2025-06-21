import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:async';
import 'dual_video_layout.dart';
import '../signaling.dart';

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

class _CallScreenState extends State<CallScreen> with WidgetsBindingObserver {
  final _localRenderer = RTCVideoRenderer();
  final _remoteRenderer = RTCVideoRenderer();
  final _signaling = DirectSignaling(host: 'ws://10.0.2.2:8080');

  RTCPeerConnection? _peerConnection;
  MediaStream? _localStream;

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  bool _isCaller = false;
  bool _isConnected = false;
  bool _isMicMuted = false;
  bool _isCameraOff = false;
  bool _isSpeakerOn = true;
  bool _isCallAccepted = false;
  bool _isCallEnded = false;
  bool _isVideoCall = false;
  bool _isDisconnecting = false; // Prevent multiple disconnect calls

  StreamSubscription? _callStatusSubscription;
  StreamSubscription? _iceCandidatesSubscription;
  StreamSubscription? _answerSubscription;
  StreamSubscription? _connectionMonitorSubscription;

  String _callStatus = 'Initializing...';
  String? _peerName;
  RTCSessionDescription? _remoteOffer;
  Timer? _callTimer;
  Duration _callDuration = Duration.zero;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _isVideoCall = widget.isVideoCall;

    _fetchCallData();
    _fetchPeerName();
  }

  Future<void> _fetchCallData() async {
    if (!mounted) return;

    try {
      final callDoc =
          await FirebaseFirestore.instance
              .collection('calls')
              .doc(widget.conversationId)
              .get();

      if (!mounted) return;

      if (callDoc.exists && callDoc.data() != null) {
        final callData = callDoc.data()!;
        final firestoreIsVideo = callData['isVideoCall'] ?? widget.isVideoCall;
        final currentUserId = _auth.currentUser?.uid;
        _isCaller = widget.callerId == currentUserId;

        if (_isCaller) {
          _isVideoCall = widget.isVideoCall;
          await FirebaseFirestore.instance
              .collection('calls')
              .doc(widget.conversationId)
              .update({'isVideoCall': _isVideoCall});
        } else {
          _isVideoCall = firestoreIsVideo;
        }

        print('Call type set to: ${_isVideoCall ? "video" : "voice"}');
      } else {
        _isVideoCall = widget.isVideoCall;
      }

      _setupCall();
    } catch (error) {
      print('Error getting call data: $error');
      _isVideoCall = widget.isVideoCall;
      _setupCall();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached ||
        state == AppLifecycleState.paused) {
      _endCall(userInitiated: false);
    }
  }

  Future<void> _fetchPeerName() async {
    if (!mounted) return;

    try {
      final currentUserId = _auth.currentUser?.uid;
      _isCaller = widget.callerId == currentUserId;

      final peerId = _isCaller ? widget.receiverId : widget.callerId;

      final userDoc = await _firestore.collection('users').doc(peerId).get();

      if (userDoc.exists && userDoc.data() != null && mounted) {
        setState(() {
          _peerName = userDoc.data()!['displayName'] ?? 'Unknown';
        });
      }
    } catch (e) {
      debugPrint('Error fetching peer name: $e');
    }
  }

  Future<void> _setupCall() async {
    if (!mounted) return;

    setState(() {
      _callStatus = 'Setting up call...';
    });

    final currentUserId = _auth.currentUser?.uid;
    if (currentUserId == null) {
      _handleError('User not authenticated');
      return;
    }

    _isCaller = widget.callerId == currentUserId;

    try {
      await _initRenderers();
      await _initCallFlow();
    } catch (e) {
      _handleError('Failed to initialize call: $e');
    }
  }

    Future<void> _initRenderers() async {
    await _localRenderer.initialize();
    await _remoteRenderer.initialize();
    await _signaling.initalize(
        onLocalStreamAvailable: _localStreamAvailable,
        onRemoteStreamAvailable: _remoteStreamAvailable,
        onConnectionState: _onConnectionState);
  }

  void _localStreamAvailable(MediaStream stream) // display local stream
  {
    setState(() {
      _localRenderer.srcObject = stream;
    });
  }

  void _remoteStreamAvailable(MediaStream stream) // display remote stream
  {
    setState(() {
      _remoteRenderer.srcObject = stream;
    });
  }

  void _onConnectionState(RTCPeerConnectionState state) {
    print(state);
    if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected ||
        state == RTCPeerConnectionState.RTCPeerConnectionStateDisconnected ||
        state == RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
      _isConnected = true;
    }
    setState(() {
      _callStatus = state.toString();
    });
  }

  Future<void> _initCallFlow() async {
    if (!mounted) return;

    final hasPermissions = await _requestCallPermissions();
    if (!hasPermissions || !mounted) return;

    if (_isCaller) {
      // Caller: Create call document first
      await _firestore.collection('calls').doc(widget.conversationId).set({
        'callerId': widget.callerId,
        'receiverId': widget.receiverId,
        'isVideoCall': _isVideoCall,
        'status': 'ringing',
        'startedAt': FieldValue.serverTimestamp(),
      });
    }

    _startCallStatusListener();

    try {
      await _initMediaDevices();
      if (!mounted) return;

      // IMPORTANT: Initialize signaling BEFORE peer connection
      await _signaling.initalize(
        onLocalStreamAvailable: (stream) {
          if (mounted) {
            setState(() {
              _localRenderer.srcObject = stream;
              _localStream = stream; // Store the stream reference
            });
          }
        },
        onRemoteStreamAvailable: (stream) {
          if (mounted) {
            setState(() {
              _remoteRenderer.srcObject = stream;
              _isConnected = true;
            });
          }
        },
        onConnectionState: (state) {
          debugPrint('Connection state changed: $state');
          if (mounted) {
            setState(() {
              _callStatus = state.toString();
            });
          }
        },
      );

      // Get peer connection from signaling
      _peerConnection = _signaling.localPeer;

      // Set up additional peer connection handlers
      _setupPeerConnectionHandlers();

      if (_isCaller) {
        if (mounted) {
          setState(() {
            _callStatus = 'Calling...';
          });
        }
        await _createOffer();
      } else {
        if (mounted) {
          setState(() {
            _callStatus = 'Incoming call...';
          });
        }
        await _acceptCall();
      }
    } catch (e) {
      _handleError('Failed to establish call: $e');
    }
  }

  // New method to set up additional peer connection handlers
  void _setupPeerConnectionHandlers() {
    if (_peerConnection == null) return;

    _peerConnection?.onIceCandidate = (candidate) async {
      if (candidate.candidate != null && !_isCallEnded) {
        await _firestore
            .collection('calls')
            .doc(widget.conversationId)
            .collection('iceCandidates')
            .add({
              'candidate': candidate.candidate,
              'sdpMid': candidate.sdpMid,
              'sdpMLineIndex': candidate.sdpMLineIndex,
              'fromCaller': _isCaller,
            });
      }
    };

    _peerConnection?.onConnectionState = (state) {
      debugPrint('Connection state changed: $state');
      if (_shouldRestartIce(state)) {
        _attemptIceRestart();
      }
    };

    _peerConnection?.onIceConnectionState = (state) {
      debugPrint('ICE connection state changed: $state');
      if (state == RTCIceConnectionState.RTCIceConnectionStateConnected &&
          mounted) {
        setState(() {
          _isConnected = true;
          _callStatus = 'Connected';
        });
      }
    };

    _listenForIceCandidates();
  }

  void _startCallStatusListener() {
    _callStatusSubscription = _firestore
        .collection('calls')
        .doc(widget.conversationId)
        .snapshots()
        .listen(
          _handleCallStatusChange,
          onError: (error) {
            _handleError('Error monitoring call: $error');
          },
        );
  }

  Future<bool> _requestCallPermissions() async {
    if (!mounted) return false;

    setState(() {
      _callStatus = 'Checking permissions...';
    });

    bool microphoneGranted = false;
    bool cameraGranted = true;

    microphoneGranted = await Permission.microphone.request().isGranted;

    if (_isVideoCall) {
      cameraGranted = await Permission.camera.request().isGranted;
    }

    final hasRequiredPermissions =
        _isVideoCall ? (cameraGranted && microphoneGranted) : microphoneGranted;

    if (!hasRequiredPermissions && mounted) {
      _handleError('Required permissions were not granted');
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) {
          Navigator.pop(context);
        }
      });
    }

    return hasRequiredPermissions;
  }

  void _handleCallStatusChange(DocumentSnapshot snapshot) {
    if (!mounted) return;

    if (!snapshot.exists || snapshot.data() == null) {
      if (!_isCallEnded) {
        _endCall(userInitiated: false);
      }
      return;
    }

    final data = snapshot.data() as Map<String, dynamic>;
    final status = data['status'];

    if (status == 'accepted' && !_isCallAccepted && mounted) {
      setState(() {
        _isCallAccepted = true;
        _callStatus = 'Connected';
      });

      _startCallTimer();
      _addCallToHistory();
    } else if (status == 'declined' && !_isCallEnded && mounted) {
      setState(() {
        _callStatus = 'Call declined';
      });

      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) {
          _endCall(userInitiated: false);
        }
      });
    } else if (status == 'ended' && !_isCallEnded) {
      _endCall(userInitiated: false);
    }
  }

  void _startCallTimer() {
    _callTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {
          _callDuration += const Duration(seconds: 1);
        });
      } else {
        timer.cancel();
      }
    });
  }

  void _addCallToHistory() {
    _firestore
        .collection('conversations')
        .doc(widget.conversationId)
        .collection('messages')
        .add({
          'senderId': widget.callerId,
          'text': '${_isVideoCall ? 'Video' : 'Audio'} call',
          'timestamp': FieldValue.serverTimestamp(),
          'isCallHistory': true,
          'callType': _isVideoCall ? 'video' : 'audio',
        });
  }

  Future<void> _initMediaDevices() async {
    if (!mounted) return;

    try {
      final mediaConstraints =
          _isVideoCall
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

      _localStream = await navigator.mediaDevices.getUserMedia(
        mediaConstraints,
      );

      if (mounted) {
        setState(() {
          _localRenderer.srcObject = _localStream;
        });
      }
    } catch (e) {
      _handleError('Error accessing media devices: $e');
      rethrow;
    }
  }

  Future<void> _initPeerConnection() async {
    if (!mounted) return;

    final config = {
      'iceServers': [
        {'urls': 'stun:stun.l.google.com:19302'},
        {'urls': 'stun:stun1.l.google.com:19302'},
        {'urls': 'stun:stun2.l.google.com:19302'},
        {
          'urls': 'turn:openrelay.metered.ca:80',
          'username': 'openrelayproject',
          'credential': 'openrelayproject',
        },
        {
          'urls': 'turn:openrelay.metered.ca:443',
          'username': 'openrelayproject',
          'credential': 'openrelayproject',
        },
      ],
      'iceTransportPolicy': 'all',
      'bundlePolicy': 'max-bundle',
      'rtcpMuxPolicy': 'require',
    };

    try {
      _peerConnection = await createPeerConnection(config);

      // Add local stream tracks
      if (_localStream != null) {
        for (var track in _localStream!.getTracks()) {
          await _peerConnection?.addTrack(track, _localStream!);
        }
      }

      _peerConnection?.onTrack = (event) {
        if (event.streams.isNotEmpty && mounted) {
          setState(() {
            _remoteRenderer.srcObject = event.streams[0];
            _isConnected = true;
          });
        }
      };

      _peerConnection?.onIceCandidate = (candidate) async {
        if (candidate.candidate != null && !_isCallEnded) {
          await _firestore
              .collection('calls')
              .doc(widget.conversationId)
              .collection('iceCandidates')
              .add({
                'candidate': candidate.candidate,
                'sdpMid': candidate.sdpMid,
                'sdpMLineIndex': candidate.sdpMLineIndex,
                'fromCaller': _isCaller,
              });
        }
      };

      _peerConnection?.onConnectionState = (state) {
        debugPrint('Connection state changed: $state');
        if (_shouldRestartIce(state)) {
          _attemptIceRestart();
        }
      };

      _peerConnection?.onIceConnectionState = (state) {
        debugPrint('ICE connection state changed: $state');
        if (state == RTCIceConnectionState.RTCIceConnectionStateConnected &&
            mounted) {
          setState(() {
            _isConnected = true;
            _callStatus = 'Connected';
          });
        } else if (_shouldRestartIce(state)) {
          _attemptIceRestart();
        }
      };

      _listenForIceCandidates();
    } catch (e) {
      debugPrint('Error initializing peer connection: $e');
      _handleError('Failed to establish peer connection.');
    }
  }

  bool _shouldRestartIce(dynamic state) {
    return (state == RTCIceConnectionState.RTCIceConnectionStateFailed ||
            state == RTCIceConnectionState.RTCIceConnectionStateDisconnected ||
            state == RTCIceConnectionState.RTCIceConnectionStateClosed) &&
        !_isCallEnded;
  }

  Future<void> _attemptIceRestart() async {
    if (_isCallEnded || _peerConnection == null) return;

    try {
      debugPrint('Attempting ICE restart...');

      if (_isCaller) {
        // Caller creates new offer with ICE restart
        final offer = await _peerConnection!.createOffer({
          'offerToReceiveAudio': 1,
          'offerToReceiveVideo': _isVideoCall ? 1 : 0,
          'iceRestart': true, // CRITICAL: Enable ICE restart
        });

        await _peerConnection!.setLocalDescription(offer);

        await _firestore.collection('calls').doc(widget.conversationId).update({
          'type': 'offer',
          'sdp': offer.sdp,
          'iceRestart': true,
        });
      }

      // Set status to reconnecting
      if (mounted) {
        setState(() {
          _callStatus = 'Reconnecting...';
        });
      }
    } catch (e) {
      debugPrint('ICE restart failed: $e');
      // If restart fails, end the call
      _endCall(userInitiated: false);
    }
  }

  Future<void> _createOffer() async {
    if (!mounted || _isCallEnded || _peerConnection == null) return;

    try {
      final offerOptions = {
        'offerToReceiveAudio': 1,
        'offerToReceiveVideo': _isVideoCall ? 1 : 0,
        'iceRestart': false,
        'voiceActivityDetection': true,
      };

      final offer = await _peerConnection!.createOffer(offerOptions);
      if (_isCallEnded || !mounted) return;

      await _peerConnection!.setLocalDescription(offer);
      if (_isCallEnded || !mounted) return;

      // Use the signaling call method
      await _signaling.call(
        conversationId: widget.conversationId,
        callerId: widget.callerId,
        receiverId: widget.receiverId,
        isVideoCall: _isVideoCall,
        offer: offer,
      );

      _listenForAnswerWithTimeout();
    } catch (e) {
      _handleError('Error creating offer: $e');
    }
  }

  // Modified _acceptCall method
  Future<void> _acceptCall() async {
    if (!mounted || _isCallEnded || _peerConnection == null) return;

    try {
      setState(() {
        _callStatus = 'Connecting...';
      });

      // Wait for offer to arrive via WebSocket (handled by DirectSignaling)
      // The DirectSignaling class will handle the offer and create answer automatically

      if (mounted) {
        setState(() {
          _isCallAccepted = true;
        });
      }

      debugPrint('Call accepted successfully');
    } catch (e) {
      debugPrint('Error in _acceptCall: $e');
      _handleError('Failed to accept call: $e');
    }
  }

  // Remove redundant _initPeerConnection since it's handled by DirectSignaling
  // Keep other methods as they are...

  void _listenForAnswerWithTimeout() {
    Timer? answerTimeout = Timer(Duration(seconds: 30), () {
      if (!_isCallAccepted && !_isCallEnded) {
        debugPrint('Answer timeout - ending call');
        _endCall(userInitiated: false);
      }
    });

    _answerSubscription = _firestore
        .collection('calls')
        .doc(widget.conversationId)
        .snapshots()
        .listen((snapshot) async {
          if (!mounted || _isCallEnded) {
            answerTimeout.cancel();
            return;
          }

          final data = snapshot.data();
          if (data?['type'] == 'answer' && data?['sdp'] != null) {
            answerTimeout.cancel();

            try {
              final answer = RTCSessionDescription(data!['sdp'], data['type']);
              await _peerConnection?.setRemoteDescription(answer);
            } catch (e) {
              debugPrint('Error setting remote description: $e');
            }
          }
        });
  }

  void _listenForIceCandidates() {
    _iceCandidatesSubscription = _firestore
        .collection('calls')
        .doc(widget.conversationId)
        .collection('iceCandidates')
        .where('fromCaller', isEqualTo: !_isCaller)
        .snapshots()
        .listen(
          (snapshot) {
            if (!mounted || _isCallEnded || _peerConnection == null) {
              _iceCandidatesSubscription?.cancel();
              return;
            }

            for (var change in snapshot.docChanges) {
              if (change.type == DocumentChangeType.added) {
                final data = change.doc.data();
                if (data != null && data['candidate'] != null) {
                  try {
                    final candidate = RTCIceCandidate(
                      data['candidate'],
                      data['sdpMid'],
                      data['sdpMLineIndex'],
                    );
                    _peerConnection?.addCandidate(candidate);
                  } catch (e) {
                    debugPrint('Error adding ICE candidate: $e');
                  }
                }
              }
            }
          },
          onError: (e) {
            debugPrint('Error listening for ICE candidates: $e');
          },
        );
  }

  Future<void> _endCall({bool userInitiated = true}) async {
    if (_isDisconnecting || _isCallEnded) return;

    _isDisconnecting = true;
    _isCallEnded = true;

    debugPrint('Ending call - userInitiated: $userInitiated');

    if (mounted) {
      setState(() {
        _callStatus = 'Call ended';
      });
    }

    // Cancel all timers
    _callTimer?.cancel();

    // Cancel all subscriptions
    _callStatusSubscription?.cancel();
    _iceCandidatesSubscription?.cancel();
    _answerSubscription?.cancel();
    _connectionMonitorSubscription?.cancel();

    // Update Firestore to notify peer
    if (userInitiated) {
      try {
        await _firestore.collection('calls').doc(widget.conversationId).update({
          'status': 'ended',
          'endedAt': FieldValue.serverTimestamp(),
        });
      } catch (e) {
        debugPrint('Error updating call status: $e');
      }
    }

    // Clean up WebRTC resources
    try {
      _localStream?.getTracks().forEach((track) {
        track.stop();
      });
      await _localStream?.dispose();
      await _peerConnection?.close();
      await _peerConnection?.dispose();
    } catch (e) {
      debugPrint('Error cleaning up WebRTC: $e');
    }

    // Clean up Firestore data after a delay
    Future.delayed(const Duration(seconds: 3), () async {
      try {
        final candidatesSnapshot =
            await _firestore
                .collection('calls')
                .doc(widget.conversationId)
                .collection('iceCandidates')
                .get();

        for (var doc in candidatesSnapshot.docs) {
          await doc.reference.delete();
        }

        // Delete the call document
        await _firestore
            .collection('calls')
            .doc(widget.conversationId)
            .delete();
      } catch (e) {
        debugPrint('Error cleaning up Firestore: $e');
      }
    });

    if (mounted) {
      Navigator.pop(context);
    }
  }

  void _toggleMute() {
    if (_localStream != null && mounted) {
      final audioTrack = _localStream!.getAudioTracks().firstOrNull;
      if (audioTrack != null) {
        setState(() {
          _isMicMuted = !_isMicMuted;
          audioTrack.enabled = !_isMicMuted;
        });
      }
    }
  }

  void _toggleCamera() {
    if (_localStream != null && _isVideoCall && mounted) {
      final videoTrack = _localStream!.getVideoTracks().firstOrNull;
      if (videoTrack != null) {
        setState(() {
          _isCameraOff = !_isCameraOff;
          videoTrack.enabled = !_isCameraOff;
        });
      }
    }
  }

  void _switchCamera() async {
    if (_localStream != null && _isVideoCall) {
      final videoTrack = _localStream!.getVideoTracks().firstOrNull;
      if (videoTrack != null) {
        await Helper.switchCamera(videoTrack);
      }
    }
  }

  void _toggleSpeaker() {
    if (mounted) {
      setState(() {
        _isSpeakerOn = !_isSpeakerOn;
      });
    }
  }

  void _handleError(String message) {
    debugPrint('Call error: $message');
    if (mounted && !_isCallEnded) {
      setState(() {
        _callStatus = 'Error: $message';
      });

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));

      Future.delayed(const Duration(seconds: 2), () {
        if (mounted && !_isCallEnded) {
          _endCall(userInitiated: false);
        }
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _callTimer?.cancel();
    _callStatusSubscription?.cancel();
    _iceCandidatesSubscription?.cancel();
    _answerSubscription?.cancel();
    _connectionMonitorSubscription?.cancel();
    _localRenderer.dispose();
    _remoteRenderer.dispose();
    _localStream?.dispose();
    _peerConnection?.close();
    _signaling.channel.sink.close();
    super.dispose();
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final hours = twoDigits(duration.inHours);
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return hours == '00' ? '$minutes:$seconds' : '$hours:$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        _endCall();
        return false;
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: Stack(
            children: [
              // Video Streams - use _isVideoCall instead of widget.isVideoCall
              if (_isVideoCall) ...[
                if (_localRenderer.srcObject != null &&
                    _remoteRenderer.srcObject != null)
                  Positioned.fill(
                    child: DualVideoLayout(
                      local: _localRenderer,
                      remote: _remoteRenderer,
                    ),
                  )
                else if (_localRenderer.srcObject != null)
                  // Show only local video when remote is not available
                  Positioned.fill(
                    child: RTCVideoView(
                      _localRenderer,
                      mirror: true,
                      objectFit:
                          RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                    ),
                  ),
              ] else ...[
                // Audio call UI
                Positioned.fill(
                  child: Container(
                    color: Colors.blueGrey.shade900,
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircleAvatar(
                            radius: 70,
                            backgroundColor: Colors.blueGrey.shade700,
                            child: Text(
                              _peerName?.isNotEmpty == true
                                  ? _peerName![0].toUpperCase()
                                  : '?',
                              style: const TextStyle(
                                fontSize: 50,
                                color: Colors.white,
                              ),
                            ),
                          ),
                          const SizedBox(height: 20),
                        ],
                      ),
                    ),
                  ),
                ),
              ],

              // Call information overlay
              Positioned(
                top: 20,
                left: 0,
                right: 0,
                child: Column(
                  children: [
                    Text(
                      _peerName ?? 'Connecting...',
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _isCallAccepted
                          ? _formatDuration(_callDuration)
                          : _callStatus,
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.white.withOpacity(0.8),
                      ),
                    ),
                  ],
                ),
              ),

              // Call controls
              Positioned(
                left: 0,
                right: 0,
                bottom: 40,
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 20.0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          // Mute button
                          CircleAvatar(
                            radius: 25,
                            backgroundColor:
                                _isMicMuted
                                    ? Colors.red.withOpacity(0.8)
                                    : Colors.white.withOpacity(0.3),
                            child: IconButton(
                              icon: Icon(
                                _isMicMuted ? Icons.mic_off : Icons.mic,
                                color: Colors.white,
                              ),
                              onPressed: _toggleMute,
                            ),
                          ),

                          // Video toggle (only for video calls)
                          if (_isVideoCall)
                            CircleAvatar(
                              radius: 25,
                              backgroundColor:
                                  _isCameraOff
                                      ? Colors.red.withOpacity(0.8)
                                      : Colors.white.withOpacity(0.3),
                              child: IconButton(
                                icon: Icon(
                                  _isCameraOff
                                      ? Icons.videocam_off
                                      : Icons.videocam,
                                  color: Colors.white,
                                ),
                                onPressed: _toggleCamera,
                              ),
                            ),

                          // End call button
                          CircleAvatar(
                            radius: 30,
                            backgroundColor: Colors.red,
                            child: IconButton(
                              icon: const Icon(
                                Icons.call_end,
                                color: Colors.white,
                              ),
                              onPressed: () => _endCall(),
                            ),
                          ),

                          // Speaker toggle
                          CircleAvatar(
                            radius: 25,
                            backgroundColor:
                                _isSpeakerOn
                                    ? Colors.blue.withOpacity(0.8)
                                    : Colors.white.withOpacity(0.3),
                            child: IconButton(
                              icon: Icon(
                                _isSpeakerOn
                                    ? Icons.volume_up
                                    : Icons.volume_down,
                                color: Colors.white,
                              ),
                              onPressed: _toggleSpeaker,
                            ),
                          ),

                          // Camera switch (only for video calls)
                          if (_isVideoCall)
                            CircleAvatar(
                              radius: 25,
                              backgroundColor: Colors.white.withOpacity(0.3),
                              child: IconButton(
                                icon: const Icon(
                                  Icons.switch_camera,
                                  color: Colors.white,
                                ),
                                onPressed: _switchCamera,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}