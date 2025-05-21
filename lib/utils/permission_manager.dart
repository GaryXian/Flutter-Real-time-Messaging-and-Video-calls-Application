import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PermissionManager {
  // Keys for storing permission preferences
  static const String _cameraPermKey = 'camera_permission_preference';
  static const String _microphonePermKey = 'microphone_permission_preference';
  
  // Permission modes
  static const String alwaysAsk = 'always_ask';
  static const String rememberChoice = 'remember_choice';

  // Get current mode for a permission
  static Future<String> getPermissionMode(PermissionType type) async {
    final prefs = await SharedPreferences.getInstance();
    final key = _getPreferenceKey(type);
    return prefs.getString(key) ?? alwaysAsk;
  }

  // Set mode for a permission
  static Future<void> setPermissionMode(PermissionType type, String mode) async {
    final prefs = await SharedPreferences.getInstance();
    final key = _getPreferenceKey(type);
    await prefs.setString(key, mode);
  }

  // Get preference key based on permission type
  static String _getPreferenceKey(PermissionType type) {
    switch (type) {
      case PermissionType.camera:
        return _cameraPermKey;
      case PermissionType.microphone:
        return _microphonePermKey;
      }
  }

  // Check permission and request if needed based on saved preference
  static Future<bool> checkAndRequestPermission(
    BuildContext context,
    PermissionType type,
  ) async {
    final permission = _getPermission(type);
    final status = await permission.status;

    // If already granted, return true
    if (status.isGranted) {
      return true;
    }

    // If denied but not permanently, check the mode
    if (!status.isPermanentlyDenied) {
      final mode = await getPermissionMode(type);
      
      // If mode is alwaysAsk, show dialog before requesting
      if (mode == alwaysAsk) {
        final shouldRequest = await _showPermissionDialog(context, type);
        if (!shouldRequest) {
          return false;
        }
      }
      
      // Request permission
      final result = await permission.request();
      return result.isGranted;
    } else {
      // Permission permanently denied, show settings dialog
      await _showSettingsDialog(context, type);
      return false;
    }
  }

  // Show dialog asking if user wants to grant permission
  static Future<bool> _showPermissionDialog(
    BuildContext context,
    PermissionType type,
  ) async {
    final result = await showDialog<PermissionDialogResult>(
      context: context,
      barrierDismissible: false,
      builder: (context) => PermissionRequestDialog(type: type),
    );

    // Update permission mode if user chose to remember
    if (result?.rememberChoice == true) {
      await setPermissionMode(type, rememberChoice);
    }

    return result?.granted ?? false;
  }

  // Show dialog to open settings when permission is permanently denied
  static Future<void> _showSettingsDialog(
    BuildContext context,
    PermissionType type,
  ) async {
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Permission Required'),
        content: Text('${_getPermissionName(type)} permission has been permanently denied. '
            'Please enable it in app settings.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              openAppSettings();
            },
            child: const Text('Open Settings'),
          ),
        ],
      ),
    );
  }

  // Get permission instance based on type
  static Permission _getPermission(PermissionType type) {
    switch (type) {
      case PermissionType.camera:
        return Permission.camera;
      case PermissionType.microphone:
        return Permission.microphone;
      }
  }

  // Get permission name for UI
  static String _getPermissionName(PermissionType type) {
    switch (type) {
      case PermissionType.camera:
        return 'Camera';
      case PermissionType.microphone:
        return 'Microphone';
      }
  }
}

// Permission types supported by the app
enum PermissionType {
  camera,
  microphone,
}

// Result from permission dialog
class PermissionDialogResult {
  final bool granted;
  final bool rememberChoice;

  PermissionDialogResult({
    required this.granted,
    required this.rememberChoice,
  });
}

// Dialog for requesting permission
class PermissionRequestDialog extends StatefulWidget {
  final PermissionType type;

  const PermissionRequestDialog({
    Key? key,
    required this.type,
  }) : super(key: key);

  @override
  State<PermissionRequestDialog> createState() => _PermissionRequestDialogState();
}

class _PermissionRequestDialogState extends State<PermissionRequestDialog> {
  bool _rememberChoice = false;

  @override
  Widget build(BuildContext context) {
    final permissionName = _getPermissionName(widget.type);
    final permissionDescription = _getPermissionDescription(widget.type);
    final permissionIcon = _getPermissionIcon(widget.type);

    return AlertDialog(
      title: Text('$permissionName Access'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            permissionIcon,
            size: 48,
            color: Theme.of(context).primaryColor,
          ),
          const SizedBox(height: 16),
          Text(permissionDescription),
          const SizedBox(height: 12),
          CheckboxListTile(
            title: const Text('Remember my choice'),
            value: _rememberChoice,
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: EdgeInsets.zero,
            onChanged: (value) {
              setState(() {
                _rememberChoice = value ?? false;
              });
            },
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () {
            Navigator.pop(
              context,
              PermissionDialogResult(
                granted: false,
                rememberChoice: _rememberChoice,
              ),
            );
          },
          child: const Text('Deny'),
        ),
        ElevatedButton(
          onPressed: () {
            Navigator.pop(
              context,
              PermissionDialogResult(
                granted: true,
                rememberChoice: _rememberChoice,
              ),
            );
          },
          child: const Text('Allow'),
        ),
      ],
    );
  }

  String _getPermissionName(PermissionType type) {
    switch (type) {
      case PermissionType.camera:
        return 'Camera';
      case PermissionType.microphone:
        return 'Microphone';
      }
  }

  String _getPermissionDescription(PermissionType type) {
    switch (type) {
      case PermissionType.camera:
        return 'We need access to your camera to make video calls. This permission is required for video communication with other users.';
      case PermissionType.microphone:
        return 'We need access to your microphone to make voice and video calls. This permission is required for audio communication with other users.';
      }
  }

  IconData _getPermissionIcon(PermissionType type) {
    switch (type) {
      case PermissionType.camera:
        return Icons.camera_alt;
      case PermissionType.microphone:
        return Icons.mic;
      }
  }
}

