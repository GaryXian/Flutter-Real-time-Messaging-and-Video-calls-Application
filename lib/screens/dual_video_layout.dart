import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

class DualVideoLayout extends StatefulWidget {
  final RTCVideoRenderer local;
  final RTCVideoRenderer remote;
  final bool isFrontCamera; // Add this parameter
  final VoidCallback? onCameraSwitch; // Add callback for camera switch

  const DualVideoLayout({
    super.key,
    required this.local,
    required this.remote,
    this.isFrontCamera = true,
    this.onCameraSwitch,
  });

  @override
  State<DualVideoLayout> createState() => _DualVideoLayoutState();
}

class _DualVideoLayoutState extends State<DualVideoLayout> {
  bool defaultView = true; // true = local main, false = remote main

  @override
  Widget build(BuildContext context) {
    final mainRenderer = defaultView ? widget.local : widget.remote;
    final smallRenderer = defaultView ? widget.remote : widget.local;
    
    // Only mirror local video when it's front camera
    final shouldMirrorMain = defaultView && widget.isFrontCamera;
    final shouldMirrorSmall = !defaultView && widget.isFrontCamera;

    return Stack(
      children: [
        // Main video view
        if (mainRenderer.textureId != null)
          RTCVideoView(
            mainRenderer,
            objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
            mirror: shouldMirrorMain,
          ),
        
        // Small video view (bottom left)
        Positioned(
          bottom: 20,
          left: 20,
          child: GestureDetector(
            onTap: () {
              setState(() {
                defaultView = !defaultView;
              });
            },
            child: Container(
              width: 130,
              height: 200,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white, width: 2),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: smallRenderer.textureId != null
                    ? RTCVideoView(
                        smallRenderer,
                        objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                        mirror: shouldMirrorSmall,
                      )
                    : Container(
                        color: Colors.black54,
                        child: const Center(
                          child: CircularProgressIndicator(
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                            strokeWidth: 2,
                          ),
                        ),
                      ),
              ),
            ),
          ),
        ),
        
        // Camera switch button (only show when local video is main)
        if (defaultView && widget.onCameraSwitch != null)
          Positioned(
            top: 50,
            right: 20,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.5),
                shape: BoxShape.circle,
              ),
              child: IconButton(
                onPressed: widget.onCameraSwitch,
                icon: const Icon(
                  Icons.cameraswitch,
                  color: Colors.white,
                  size: 24,
                ),
                padding: const EdgeInsets.all(12),
              ),
            ),
          ),
        
        // View switch indicator
        Positioned(
          bottom: 230,
          left: 20,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.6),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              'Tap to switch',
              style: TextStyle(
                color: Colors.white.withOpacity(0.8),
                fontSize: 12,
              ),
            ),
          ),
        ),
      ],
    );
  }
}