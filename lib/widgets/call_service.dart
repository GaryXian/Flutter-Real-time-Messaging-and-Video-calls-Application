import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../screens/call_screen.dart';
import 'package:audioplayers/audioplayers.dart';

class CallListenerService {
  static StreamSubscription<DocumentSnapshot>? _subscription;
  static StreamSubscription<QuerySnapshot>? _globalSubscription;
  static final Set<String> _handledCallIds = {}; // Track handled calls
  static final AudioPlayer _audioPlayer = AudioPlayer();
  static Timer? _calloutTimer; // Timer to handle call timeout
  static StreamSubscription<DocumentSnapshot>?
  _activeCallSubscription; // Track active call dialog
  static bool _isDialogShowing = false; // Flag to prevent multiple dialogs
  static DateTime? _lastCallEndTime; // Track when the last call ended
  static String? _currentCallId; // Track the current call ID
  static const Duration _callTimeoutDuration = Duration(seconds: 30);


  // Reset the service state completely
  static void resetServiceState() {
    _handledCallIds.clear();
    _isDialogShowing = false;
    //_activeCallSubscription?.cancel();
    _activeCallSubscription = null;
    _currentCallId = null;
    _stopRingtone();
    _cancelCallTimeout();
  }

  static void _startCallTimeout(String conversationId, BuildContext context) {
  _calloutTimer?.cancel(); // Cancel any existing timer
  
  _calloutTimer = Timer(_callTimeoutDuration, () {
    // Auto-decline the call after timeout
    FirebaseFirestore.instance
        .collection('calls')
        .doc(conversationId)
        .update({'status': 'declined'}) // or 'declined' if you prefer
        .catchError((error) {
          print('Error auto-ending call: $error');
        });
    
    // Dismiss dialog if it's still showing
    if (_isDialogShowing && _currentCallId == conversationId && context.mounted) {
      _dismissCurrentCallDialog(context);
      
    }
  });
}

// Add this method to cancel the timeout timer
static void _cancelCallTimeout() {
  _calloutTimer?.cancel();
  _calloutTimer = null;
}


  static void startGlobalListening(BuildContext context, String currentUserId) {
    _globalSubscription?.cancel();

    _globalSubscription = FirebaseFirestore.instance
        .collection('calls')
        .where('receiverId', isEqualTo: currentUserId)
        .snapshots()
        .listen(
          (querySnapshot) async {
            // CRITICAL: Process document changes instead of current state
            for (var change in querySnapshot.docChanges) {
              if (change.type == DocumentChangeType.added || 
                  change.type == DocumentChangeType.modified) {
                
                final doc = change.doc;
                final data = doc.data()!;
                final callerId = data['callerId'];
                final conversationId = doc.id;
                final isVideoCall = data['isVideoCall'] ?? false;
                final callStatus = data['status'] ?? 'ended';

                // Skip if user is the caller
                if (callerId == currentUserId) continue;

                // CRITICAL: Only clean up if this specific call ended
                if ((callStatus == 'cancelled' || callStatus == 'ended' || callStatus == 'declined') 
                    && _currentCallId == conversationId) {
                  _handledCallIds.remove(conversationId);
                  if (_isDialogShowing) {
                    _lastCallEndTime = DateTime.now();
                    _dismissCurrentCallDialog(context);
                  }
                  continue;
                }

                // CRITICAL: Remove the delay logic that blocks immediate calls
                if (callStatus == 'ringing' &&
                    !_handledCallIds.contains(conversationId) &&
                    !_isDialogShowing) {
                  
                  await _showIncomingCallDialog(
                    context,
                    conversationId,
                    callerId,
                    currentUserId,
                    isVideoCall,
                  );
                }
              } else if (change.type == DocumentChangeType.removed) {
                // CRITICAL: Clean up when document is deleted
                final conversationId = change.doc.id;
                _handledCallIds.remove(conversationId);
                if (_currentCallId == conversationId && _isDialogShowing) {
                  _dismissCurrentCallDialog(context);
                }
              }
            }
          },
          onError: (error) {
            print('Global call listener error: $error');
            resetServiceState();
            Future.delayed(const Duration(seconds: 2), () {
              if (context.mounted) {
                startGlobalListening(context, currentUserId);
              }
            });
          },
        );
  }


  static Future<void> _playRingtone() async {
    try {
      await _audioPlayer.play(AssetSource('ringtone.mp3'), volume: 1.0);
    } catch (e) {
      print('Error playing ringtone: $e');
    }
  }

  static Future<void> _stopRingtone() async {
    try {
      await _audioPlayer.stop();
    } catch (e) {
      print('Error stopping ringtone: $e');
    }
  }

  static void stopGlobalListening() {
    _globalSubscription?.cancel();
    _globalSubscription = null;
    resetServiceState();
  }

  static void startListening(
    BuildContext context,
    String conversationId,
    String currentUserId,
  ) {
    // Cancel existing subscription
    _subscription?.cancel();

    final callDocRef = FirebaseFirestore.instance
        .collection('calls')
        .doc(conversationId);

    _subscription = callDocRef.snapshots().listen(
      (doc) async {
        if (!doc.exists) return;

        final data = doc.data() as Map<String, dynamic>;
        final callerId = data['callerId'];
        final isVideoCall =
            data['isVideoCall'] ?? false; // Always respect the caller's choice
        final callStatus = data['status'] ?? 'ended';

        // Reset handled status when call is cancelled or ended
        if (callStatus == 'cancelled' ||
            callStatus == 'ended' ||
            callStatus == 'declined') {
          _handledCallIds.remove(conversationId);
          if (_isDialogShowing && _currentCallId == conversationId) {
            _lastCallEndTime = DateTime.now();
            _dismissCurrentCallDialog(context);
          }
          return;
        }

        if (callStatus != 'ringing') return;
        if (callerId == currentUserId) return;
        if (_handledCallIds.contains(conversationId))
          return; // Prevent duplicate
        if (_isDialogShowing) return; // Prevent multiple dialogs

        await _showIncomingCallDialog(
          context,
          conversationId,
          callerId,
          currentUserId,
          isVideoCall,
        );
      },
      onError: (error) {
        print('Call listener error: $error');
        // Reset state on error
        resetServiceState();

        // Attempt to restart listening
        Future.delayed(const Duration(seconds: 5), () {
          if (context.mounted) {
            startListening(context, conversationId, currentUserId);
          }
        });
      },
    );
  }

  static void stopListening() {
    _subscription?.cancel();
    _subscription = null;
  }

  static Future<void> _showIncomingCallDialog(
    BuildContext context,
    String conversationId,
    String callerId,
    String currentUserId,
    bool isVideoCall,
  ) async {
    if (_isDialogShowing) return; // Prevent multiple dialogs

    _isDialogShowing = true;
    _currentCallId = conversationId;
    _handledCallIds.add(conversationId); // Mark this call as handled
    try {
      // Get caller information
      final userDoc =
          await FirebaseFirestore.instance
              .collection('users')
              .doc(callerId)
              .get();

      // Check if context is still valid
      if (!context.mounted) {
        _cleanupCallState();
        return;
      }

      // Extract caller information with null safety
      final callerName =
          userDoc.exists
              ? (userDoc.data() != null
                  ? (userDoc.data()!['displayName'] ?? 'Unknown')
                  : 'Unknown')
              : 'Unknown';
      final callerPhotoUrl =
          userDoc.exists
              ? (userDoc.data() != null ? userDoc.data()!['photoUrl'] : null)
              : null;

      await _playRingtone();
      // Start call timeout timer
      _startCallTimeout(conversationId, context);
      // Cancel any active call subscription before creating a new one
      _activeCallSubscription?.cancel();

      // Setup a subscription to monitor this specific call for status changes
      _activeCallSubscription = FirebaseFirestore.instance
          .collection('calls')
          .doc(conversationId)
          .snapshots()
          .listen(
            (snapshot) {
              if (!snapshot.exists) {
                // Call document deleted, dismiss dialog
                if (context.mounted) {
                  _dismissCurrentCallDialog(context);
                }
                return;
              }

              final data = snapshot.data() as Map<String, dynamic>;
              final status = data['status'] ?? 'ended';

              // If call is no longer ringing, dismiss the dialog
              if (status != 'ringing') {
                if (context.mounted) {
                  _dismissCurrentCallDialog(context);
                }
              }

              // Update isVideoCall status if it has changed
              final updatedIsVideoCall = data['isVideoCall'] ?? isVideoCall;
              if (updatedIsVideoCall != isVideoCall && context.mounted) {
                // Log the call type change
                print(
                  'Call type changed from ${isVideoCall ? "video" : "voice"} to ${updatedIsVideoCall ? "video" : "voice"}',
                );
              }
            },
            onError: (error) {
              print('Active call subscription error: $error');
              if (context.mounted) {
                _dismissCurrentCallDialog(context);
              }
            },
          );

      // Check context again before showing dialog
      if (!context.mounted) {
        _cleanupCallState();
        return;
      }

      // Show the dialog with call type information
      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) {
          return WillPopScope(
            onWillPop: () async => false, // Prevent back button from dismissing
            child: AlertDialog(
              title: Text('Incoming ${isVideoCall ? "Video" : "Voice"} Call'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (callerPhotoUrl != null && callerPhotoUrl != 'null')
                    CircleAvatar(
                      radius: 30,
                      backgroundImage: NetworkImage(callerPhotoUrl),
                    )
                  else
                    CircleAvatar(
                      radius: 30,
                      backgroundColor: Colors.blueGrey,
                      child: Text(
                        callerName.isNotEmpty
                            ? callerName[0].toUpperCase()
                            : '?',
                        style: TextStyle(fontSize: 24, color: Colors.white),
                      ),
                    ),
                  const SizedBox(height: 10),
                  Text('$callerName is calling you'),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    _cancelCallTimeout();
                    _stopRingtone();
                    FirebaseFirestore.instance
                        .collection('calls')
                        .doc(conversationId)
                        .update({'status': 'declined'})
                        .catchError((error) {
                          print('Error declining call: $error');
                        });
                    Navigator.of(ctx).pop();
                  },
                  child: const Text('Decline'),
                ),
                TextButton(
                  onPressed: () {
                    _cancelCallTimeout();
                    _stopRingtone();
                    // Accept the call
                    FirebaseFirestore.instance
                        .collection('calls')
                        .doc(conversationId)
                        .update({'status': 'accepted'})
                        .catchError((error) {
                          print('Error accepting call: $error');
                        });
                    Navigator.of(ctx).pop();

                    // Always get the latest call data to ensure we have the correct call type
                    FirebaseFirestore.instance
                        .collection('calls')
                        .doc(conversationId)
                        .get()
                        .then((callDoc) {
                          if (!callDoc.exists) {
                            print('Call document no longer exists');
                            return;
                          }

                          final callData =
                              callDoc.data();
                          if (callData == null) {
                            print('Call data is null');
                            return;
                          }

                          // IMPORTANT: Always respect the caller's choice for video call
                          final updatedIsVideoCall =
                              callData['isVideoCall'] ?? isVideoCall;

                          if (context.mounted) {
                            // Log the call type being used
                            print(
                              'Starting call with isVideoCall=${updatedIsVideoCall}',
                            );

                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder:
                                    (_) => CallScreen(
                                      conversationId: conversationId,
                                      callerId: callerId,
                                      receiverId: currentUserId,
                                      isVideoCall: updatedIsVideoCall, 

                                    ),
                              ),
                            ).then((_) {
                              // Reset state when returning from call screen
                              resetServiceState();
                            });
                          }
                        })
                        .catchError((error) {
                          print('Error getting updated call data: $error');
                          // Fallback to the original value if there's an error
                          if (context.mounted) {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder:
                                    (_) => CallScreen(
                                      conversationId: conversationId,
                                      callerId: callerId,
                                      receiverId: currentUserId,
                                      isVideoCall: isVideoCall, 

                                    ),
                              ),
                            ).then((_) {
                              // Reset state when returning from call screen
                              resetServiceState();
                            });
                          }
                        });
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('Accept'),
                ),
              ],
            ),
          );
        },
      ).then((_) {
        // Clean up when dialog is dismissed
        _cleanupCallState();
      });
    } catch (e) {
      print('Error showing incoming call dialog: $e');
      _cleanupCallState();
    }
  }

  // Helper method to clean up call state
  static void _cleanupCallState() {
    _stopRingtone();
    _activeCallSubscription?.cancel();
    _activeCallSubscription = null;
    _isDialogShowing = false;
    _cancelCallTimeout();
  }

  // Helper method to dismiss the current call dialog
  static void _dismissCurrentCallDialog(BuildContext context) {
    _stopRingtone();

    // Only pop if there's a dialog and context is still valid
    if (context.mounted && Navigator.of(context).canPop()) {
      try {
        Navigator.of(context, rootNavigator: true).pop();
      } catch (e) {
        print('Error dismissing call dialog: $e');
      }
    }
    
    _cleanupCallState();
  }
  
}
