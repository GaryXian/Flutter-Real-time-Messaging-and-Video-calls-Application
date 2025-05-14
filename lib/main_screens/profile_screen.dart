import 'dart:io';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:mime/mime.dart';
import '../authentication_screens/login_screen.dart';
import '../sub_screens/settings_screen.dart';
import 'package:image_cropper/image_cropper.dart';

import '../widgets/helper.dart';


class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  User? _currentUser;
  Map<String, dynamic> _userData = {};
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _initializeUser();
  }

  Future<void> _initializeUser() async {
    _currentUser = _auth.currentUser;
    if (_currentUser != null) {
      final userDoc = await _firestore.collection('users').doc(_currentUser!.uid).get();
      if (userDoc.exists) {
        _userData = userDoc.data()!;
      } else {
        await _createUserDocument();
      }
      await _updateUserStatus('online');
    }
    setState(() => _isLoading = false);
  }

  Future<void> _createUserDocument() async {
    if (_currentUser == null) return;
    await _firestore.collection('users').doc(_currentUser!.uid).set({
      'uid': _currentUser!.uid,
      'email': _currentUser!.email,
      'phone': _currentUser!.phoneNumber,
      'displayName': _currentUser!.displayName ?? 'New User',
      'photoURL': _currentUser!.photoURL ?? '',
      'createdAt': FieldValue.serverTimestamp(),
      'lastActive': FieldValue.serverTimestamp(),
      'status': 'offline',
      'fcmToken': '',
      'bio': '',
    });
    _userData = (await _firestore.collection('users').doc(_currentUser!.uid).get()).data()!;
  }

  Future<void> _updateUserStatus(String status) async {
    if (_currentUser != null) {
      await _firestore.collection('users').doc(_currentUser!.uid).update({
        'status': status,
        'lastActive': FieldValue.serverTimestamp(),
      });
    }
  }

  void _showSnackBar(String message, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: error ? Colors.red : null),
    );
  }

Future<void> _updateProfilePicture() async {
  if (_currentUser == null) {
    _showSnackBar('User not logged in.', error: true);
    return;
  }

  try {
    // Pick image from gallery
    final XFile? pickedFile = await ImagePicker().pickImage(source: ImageSource.gallery);

    if (pickedFile == null) {
      _showSnackBar('No image selected.', error: true);
      return;
    }

    // Crop the image
    final CroppedFile? croppedFile = await ImageCropper().cropImage(
      sourcePath: pickedFile.path,
      aspectRatio: const CropAspectRatio(ratioX: 1, ratioY: 1),
      compressQuality: 75,
      uiSettings: [
        AndroidUiSettings(
          toolbarTitle: 'Crop Image',
          toolbarColor: Theme.of(context).primaryColor,
          toolbarWidgetColor: Colors.white,
          lockAspectRatio: true,
        ),
        IOSUiSettings(
          title: 'Crop Image',
          aspectRatioLockEnabled: true,
        ),
      ],
    );

    if (croppedFile == null) {
      _showSnackBar('Image cropping canceled.', error: true);
      return;
    }

    // Validate MIME type
    final mimeType = lookupMimeType(croppedFile.path);
    if (mimeType == null || !mimeType.startsWith('image')) {
      _showSnackBar('Please select a valid image file.', error: true);
      return;
    }

    final File imageFile = File(croppedFile.path); // ✅ Proper conversion

    // Show loading dialog
    UIHelper.showLoadingDialog(context, 'Uploading image...');

    // Upload to Firebase Storage
    final ref = FirebaseStorage.instance.ref('profile_pictures/${_currentUser!.uid}.jpg');
    await ref.putFile(imageFile);
    final photoURL = await ref.getDownloadURL();

    // Update photo URL
    await _currentUser!.updatePhotoURL(photoURL);
    await _firestore.collection('users').doc(_currentUser!.uid).update({'photoURL': photoURL});

    Navigator.pop(context); // Close loading dialog
    setState(() => _userData['photoURL'] = photoURL);
    _showSnackBar('Profile picture updated!');
  } catch (e) {
    if (Navigator.canPop(context)) Navigator.pop(context); // Avoid popping if already closed
    _showSnackBar('Failed to update photo: ${e.toString()}', error: true);
  }
}



  Future<void> _updateField(String title, String field, {bool isPassword = false, TextInputType? inputType}) async {
    final controller = TextEditingController(text: _userData[field] ?? '');
    final result = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          obscureText: isPassword,
          keyboardType: inputType,
          decoration: InputDecoration(hintText: 'Enter new ${field.toLowerCase()}'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, controller.text.trim()), child: const Text('Save')),
        ],
      ),
    );

    if (result != null && result.isNotEmpty && _currentUser != null) {
      try {
        if (field == 'email') {
          await _currentUser!.updateEmail(result);
        } else if (isPassword) {
          await _currentUser!.updatePassword(result);
        }

        if (!isPassword) {
          await _firestore.collection('users').doc(_currentUser!.uid).update({field: result});
          setState(() => _userData[field] = result);
        }

        _showSnackBar('$title updated successfully!');
      } catch (e) {
        _showSnackBar('Failed to update $field: ${e.toString()}', error: true);
      }
    }
  }

  Future<void> _changePhone() async {
    final controller = TextEditingController(text: _userData['phone'] ?? '');
    final newPhone = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Change Phone Number'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.phone,
          decoration: const InputDecoration(hintText: '+1234567890'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, controller.text.trim()), child: const Text('Verify')),
        ],
      ),
    );

    if (newPhone != null && newPhone.isNotEmpty && _currentUser != null) {
      try {
        await _auth.verifyPhoneNumber(
          phoneNumber: newPhone,
          verificationCompleted: (credential) async {
            await _currentUser!.updatePhoneNumber(credential);
            await _updateFirestorePhone(newPhone);
          },
          verificationFailed: (e) {
            _showSnackBar('Verification failed: ${e.message}', error: true);
          },
          codeSent: (verificationId, _) => _showOtpDialog(verificationId, newPhone),
          codeAutoRetrievalTimeout: (_) {},
        );
      } catch (e) {
        _showSnackBar('Error: ${e.toString()}', error: true);
      }
    }
  }

  void _showOtpDialog(String verificationId, String newPhone) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Enter SMS Code'),
        content: TextField(controller: controller, keyboardType: TextInputType.number, decoration: const InputDecoration(hintText: '6-digit code')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(
            onPressed: () async {
              final code = controller.text.trim();
              if (code.isNotEmpty) {
                final credential = PhoneAuthProvider.credential(verificationId: verificationId, smsCode: code);
                await _currentUser!.updatePhoneNumber(credential);
                await _updateFirestorePhone(newPhone);
                Navigator.pop(context);
              }
            },
            child: const Text('Submit'),
          ),
        ],
      ),
    );
  }

  Future<void> _updateFirestorePhone(String newPhone) async {
    await _firestore.collection('users').doc(_currentUser!.uid).update({'phone': newPhone});
    setState(() => _userData['phone'] = newPhone);
    _showSnackBar('Phone number updated successfully!');
  }

  Future<void> _logout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Log out"),
        content: const Text("Are you sure you want to log out?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("Cancel"),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("Log out"),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await _updateUserStatus('offline');
      await _auth.signOut();
      Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const LoginScreen()), (route) => false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        automaticallyImplyLeading: false,
        actions: [
          IconButton(icon: const Icon(Icons.settings), onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen()))),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              children: [
                _buildProfileHeader(),
                _buildMenuItems(),
              ],
            ),
    );
  }

  Widget _buildProfileHeader() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          GestureDetector(
            onTap: _updateProfilePicture,
            child: CircleAvatar(
              radius: 30,
              backgroundImage: (_userData['photoURL']?.isNotEmpty ?? false) ? NetworkImage(_userData['photoURL']) : null,
              child: (_userData['photoURL']?.isEmpty ?? true) ? const Icon(Icons.person, size: 30) : null,
            ),
          ),
          const SizedBox(width: 20),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_userData['displayName'] ?? 'No Name', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              InkWell(
                onTap: () => _updateField('Edit Bio', 'bio'),
                child: Text(
                  (_userData['bio']?.isNotEmpty ?? false) ? _userData['bio'] : 'Add a bio',
                  style: TextStyle(
                    color: (_userData['bio']?.isNotEmpty ?? false) ? Colors.black87 : Colors.blue,
                    decoration: (_userData['bio']?.isNotEmpty ?? false) ? TextDecoration.none : TextDecoration.underline,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMenuItems() {
    return Column(
      children: [
        ListTile(
          leading: const Icon(Icons.person),
          title: const Text('Personal Information'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _showPersonalInfo(),
        ),
        const Divider(),
        ListTile(
          leading: const Icon(Icons.security),
          title: const Text('Account Security'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _showAccountSecurity(),
        ),
        const Divider(),
        ListTile(
          leading: const Icon(Icons.help),
          title: const Text('Help & Support'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _showHelpSupport(),
        ),
        const Divider(),
        ListTile(
          leading: const Icon(Icons.exit_to_app),
          title: const Text('Log Out'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _logout(),
        ),
      ],
    );
  }

  ListTile _buildMenuTile(IconData icon, String title, Function() onTap) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }

  void _showPersonalInfo() {
    showModalBottomSheet(
      context: context,
      builder: (_) => _buildBottomSheetContent(
        title: 'Personal Information',
        children: [
          _buildInfoRow('Name', _userData['displayName']),
          _buildInfoRow('Email', _userData['email']),
          _buildInfoRow('Account Created', _userData['createdAt'] != null ? DateFormat.yMMMd().format((_userData['createdAt'] as Timestamp).toDate()) : 'Unknown'),
          _buildInfoRow('Status', _userData['status']),
        ],
      ),
    );
  }

  void _showAccountSecurity() {
    showModalBottomSheet(
      context: context,
      builder: (_) => _buildBottomSheetContent(
        title: 'Account Security',
        children: [
          _buildMenuTile(Icons.email, 'Change Email', () => _updateField('Change Email', 'email', inputType: TextInputType.emailAddress)),
          //_buildMenuTile(Icons.phone, 'Change Phone Number', _changePhone),
          _buildMenuTile(Icons.lock, 'Change Password', () => _updateField('Change Password', 'password', isPassword: true)),
          _buildMenuTile(Icons.person, 'Change Username', () => _updateField('Change Username', 'displayName')),
        ],
      ),
    );
  }

  void _showHelpSupport() {
    showDialog(
      context: context,
      builder: (_) => Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Help & Support', 
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            const Text('Contact us at 521K0008@student.tdtu.edu.vn'),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => Navigator.pop(context), 
              child: const Text('Close')),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomSheetContent({required String title, required List<Widget> children}) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(height: 16),
        ...children,
        const SizedBox(height: 16),
        ElevatedButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
      ]),
    );
  }

  Widget _buildInfoRow(String label, String? value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Text('$label: ', style: const TextStyle(fontWeight: FontWeight.bold)),
          Flexible(child: Text(value ?? 'Not set')),
        ],
      ),
    );
  }
}
