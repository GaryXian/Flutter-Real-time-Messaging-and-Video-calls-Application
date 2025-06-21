import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

class DualVideoLayout extends StatefulWidget {
  final RTCVideoRenderer local;
  final RTCVideoRenderer remote;

  const DualVideoLayout({
    super.key,
    required this.local,
    required this.remote,
  });

  @override
  State<DualVideoLayout> createState() => _DualVideoLayoutState();
}

class _DualVideoLayoutState extends State<DualVideoLayout> {
  bool defaultView = true;
  MediaStreamTrack? _localVideoTrack;

  @override
  void initState() {
    super.initState();
    _extractLocalVideoTrack();
  }

  void _extractLocalVideoTrack() {
    if (widget.local.srcObject != null) {
      final videoTracks = widget.local.srcObject!.getVideoTracks();
      final videoTrack = videoTracks.isNotEmpty
          ? videoTracks.firstWhere((track) => track.kind == 'video', orElse: () => videoTracks.first)
          : null;

      if (videoTrack != null) {
        _localVideoTrack = videoTrack;
      }
    }
  }

  Future<void> _switchCamera() async {
    try {
      await _localVideoTrack?.switchCamera();
    } catch (e) {
      print('Error switching camera: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final mainRenderer = defaultView ? widget.local : widget.remote;
    final smallRenderer = defaultView ? widget.remote : widget.local;

    return Stack(
      children: [
        if (mainRenderer.textureId != null) // prevent render before init
          RTCVideoView(
            mainRenderer,
            objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
          ),
        Align(
          alignment: Alignment.bottomLeft,
          child: Padding(
            padding: const EdgeInsets.only(left: 20, bottom: 20),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: GestureDetector(
                onTap: () {
                  setState(() {
                    defaultView = !defaultView;
                  });
                },
                child: SizedBox(
                  width: 130,
                  height: 200,
                  child: smallRenderer.textureId != null
                      ? RTCVideoView(
                          smallRenderer,
                          objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                        )
                      : const ColoredBox(
                          color: Colors.black12,
                          child: Center(child: CircularProgressIndicator()),
                        ),
                ),
              ),
            ),
          ),
        ),
        Positioned(
          top: 40,
          right: 20,
          child: FloatingActionButton(
            mini: true,
            heroTag: 'switchCam',
            onPressed: _switchCamera,
            backgroundColor: Colors.white,
            child: const Icon(Icons.cameraswitch, color: Colors.black),
          ),
        )
      ],
    );
  }
}
