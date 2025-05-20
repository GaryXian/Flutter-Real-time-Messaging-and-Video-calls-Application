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
  static StreamSubscription<DocumentSnapshot>? _activeCallSubscription; // Track active call dialog
  static bool _isDialogShowing = false; // Flag to prevent multiple dialogs

  static void startGlobalListening(BuildContext context, String currentUserId) {
    _globalSubscription?.cancel();

    _globalSubscription = FirebaseFirestore.instance
        .collection('calls')
        .where('receiverId', isEqualTo: currentUserId)
        .snapshots() // Listen to all incoming calls
        .listen((querySnapshot) async {
      for (var doc in querySnapshot.docs) {
        final data = doc.data();
        final callerId = data['callerId'];
        final conversationId = doc.id;
        final isVideoCall = data['isVideoCall'] ?? false;
        final callStatus = data['status'] ?? 'ended';

        // Skip if user is the caller
        if (callerId == currentUserId) continue;

        // Reset handled status when call is cancelled or ended
        if (callStatus == 'cancelled' || callStatus == 'ended' || callStatus == 'declined') {
          _handledCallIds.remove(conversationId);
          if (_isDialogShowing) {
            _dismissCurrentCallDialog(context);
          }
          continue;
        }

        // Process only ringing calls that haven't been handled
        if (callStatus == 'ringing' && !_handledCallIds.contains(conversationId) && !_isDialogShowing) {
          await _showIncomingCallDialog(
            context,
            conversationId,
            callerId,
            currentUserId,
            isVideoCall,
          );
        }
      }
    }, onError: (error) {
      print('Global call listener error: $error');
      // Attempt to restart listening after error
      Future.delayed(const Duration(seconds: 5), () {
        if (context.mounted) {
          startGlobalListening(context, currentUserId);
        }
      });
    });
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
  }

  static void startListening(
    BuildContext context,
    String conversationId,
    String currentUserId,
  ) {
    final callDocRef =
        FirebaseFirestore.instance.collection('calls').doc(conversationId);

    _subscription?.cancel();
    _subscription = callDocRef.snapshots().listen((doc) async {
      if (!doc.exists) return;

      final data = doc.data() as Map<String, dynamic>;
      final callerId = data['callerId'];
      final isVideoCall = data['isVideoCall'] ?? false;
      final callStatus = data['status'] ?? 'ended';

      // Reset handled status when call is cancelled or ended
      if (callStatus == 'cancelled' || callStatus == 'ended' || callStatus == 'declined') {
        _handledCallIds.remove(conversationId);
        if (_isDialogShowing) {
          _dismissCurrentCallDialog(context);
        }
        return;
      }

      if (callStatus != 'ringing') return;
      if (callerId == currentUserId) return;
      if (_handledCallIds.contains(conversationId)) return; // Prevent duplicate
      if (_isDialogShowing) return; // Prevent multiple dialogs

      await _showIncomingCallDialog(
        context,
        conversationId,
        callerId,
        currentUserId,
        isVideoCall,
      );
    }, onError: (error) {
      print('Call listener error: $error');
      // Attempt to restart listening
      Future.delayed(const Duration(seconds: 5), () {
        if (context.mounted) {
          startListening(context, conversationId, currentUserId);
        }
      });
    });
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
    _handledCallIds.add(conversationId); // Mark this call as handled

    try {
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(callerId)
          .get();
      
      if (!context.mounted) {
        _isDialogShowing = false;
        return;
      }
      
      final callerName = userDoc.exists
          ? (userDoc.data() != null
              ? (userDoc.data()!['displayName'] ?? 'Unknown')
              : 'Unknown')
          : 'Unknown';
      final callerPhotoUrl = userDoc.exists
          ? (userDoc.data() != null
              ? userDoc.data()!['photoUrl']
              : null)
          : null;

      await _playRingtone();

      // Cancel any active call subscription before creating a new one
      _activeCallSubscription?.cancel();
      
      // Setup a subscription to monitor this specific call for status changes
      _activeCallSubscription = FirebaseFirestore.instance
          .collection('calls')
          .doc(conversationId)
          .snapshots()
          .listen((snapshot) {
            if (!snapshot.exists) {
              // Call document deleted, dismiss dialog
              _dismissCurrentCallDialog(context);
              return;
            }
            
            final data = snapshot.data() as Map<String, dynamic>;
            final status = data['status'] ?? 'ended';
            
            // If call is no longer ringing, dismiss the dialog
            if (status != 'ringing') {
              _dismissCurrentCallDialog(context);
            }
          }, onError: (error) {
            print('Active call subscription error: $error');
            _dismissCurrentCallDialog(context);
          });

      if (!context.mounted) {
        _stopRingtone();
        _activeCallSubscription?.cancel();
        _isDialogShowing = false;
        return;
      }

      showDialog(
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
                    ),
                  const SizedBox(height: 10),
                  Text('$callerName is calling you'),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    _stopRingtone();
                    FirebaseFirestore.instance
                        .collection('calls')
                        .doc(conversationId)
                        .update({'status': 'declined'});
                    Navigator.of(ctx).pop();
                  },
                  child: const Text('Decline'),
                ),
                TextButton(
                  onPressed: () {
                    _stopRingtone();
                    FirebaseFirestore.instance
                        .collection('calls')
                        .doc(conversationId)
                        .update({'status': 'accepted'});
                    Navigator.of(ctx).pop();
                    
                    // Ensure the video call parameter is properly passed
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => CallScreen(
                          conversationId: conversationId,
                          callerId: callerId,
                          receiverId: currentUserId,
                          isVideoCall: isVideoCall,
                        ),
                      ),
                    );
                  },
                  child: const Text('Accept'),
                ),
              ],
            ),
          );
        },
      ).then((_) {
        // Clean up when dialog is dismissed
        _stopRingtone();
        _activeCallSubscription?.cancel();
        _activeCallSubscription = null;
        _isDialogShowing = false;
      });
    } catch (e) {
      print('Error showing incoming call dialog: $e');
      _stopRingtone();
      _activeCallSubscription?.cancel();
      _isDialogShowing = false;
    }
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
    
    _activeCallSubscription?.cancel();
    _activeCallSubscription = null;
    _isDialogShowing = false;
  }
}