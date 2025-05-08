import 'dart:io';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../authentication_screens/login_screen.dart';
import '../sub_screens/settings_screen.dart';

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
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    setState(() => _isLoading = true);
    _currentUser = _auth.currentUser;
    
    if (_currentUser != null) {
      final userDoc = await _firestore.collection('users').doc(_currentUser!.uid).get();
      if (userDoc.exists) {
        setState(() {
          _userData = userDoc.data()!;
          _isLoading = false;
        });
      } else {
        await _createUserDocument();
      }
    }
    setState(() => _isLoading = false);
  }

  Future<void> _createUserDocument() async {
    if (_currentUser == null) return;

    await _firestore.collection('users').doc(_currentUser!.uid).set({
      'uid': _currentUser!.uid,
      'email': _currentUser!.email,
      'displayName': _currentUser!.displayName ?? 'New User',
      'photoURL': _currentUser!.photoURL ?? '',
      'createdAt': FieldValue.serverTimestamp(),
      'lastActive': FieldValue.serverTimestamp(),
      'status': 'offline',
      'fcmToken': '',
      'bio': '',
    });

    await _loadUserData();
  }

  Future<void> _updateProfilePicture() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);

    if (pickedFile != null && _currentUser != null) {
      try {
        // Upload to Firebase Storage
        final ref = FirebaseStorage.instance
            .ref()
            .child('profile_pictures')
            .child('${_currentUser!.uid}.jpg');

        await ref.putFile(File(pickedFile.path));
        final photoURL = await ref.getDownloadURL();

        // Update Firebase Auth
        await _currentUser!.updatePhotoURL(photoURL);

        // Update Firestore
        await _firestore.collection('users').doc(_currentUser!.uid).update({
          'photoURL': photoURL,
        });

        await _loadUserData();
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update photo: ${e.toString()}')),
        );
      }
    }
  }

  Future<void> _updateBio(BuildContext context) async {
    final newBio = await showDialog<String>(
      context: context,
      builder: (context) {
        final bioController = TextEditingController(text: _userData['bio'] ?? '');
        return AlertDialog(
          title: const Text('Edit Bio'),
          content: TextField(
            controller: bioController,
            maxLength: 100,
            decoration: const InputDecoration(hintText: 'Tell us about yourself'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, bioController.text),
              child: const Text('Save'),
            ),
          ],
        );
      },
    );

    if (newBio != null && _currentUser != null) {
      try {
        await _firestore.collection('users').doc(_currentUser!.uid).update({
          'bio': newBio,
        });
        await _loadUserData();
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update bio: ${e.toString()}')),
        );
      }
    }
  }

  Future<void> _changeEmail() async {
    final newEmail = await showDialog<String>(
      context: context,
      builder: (context) {
        final emailController = TextEditingController(text: _userData['email'] ?? '');
        return AlertDialog(
          title: const Text('Change Email'),
          content: TextField(
            controller: emailController,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(hintText: 'Enter new email'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, emailController.text),
              child: const Text('Update'),
            ),
          ],
        );
      },
    );

    if (newEmail != null && newEmail.isNotEmpty && _currentUser != null) {
      try {
        await _currentUser!.updateEmail(newEmail);
        await _firestore.collection('users').doc(_currentUser!.uid).update({
          'email': newEmail,
        });
        await _loadUserData();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Email updated successfully')),
        );
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update email: ${e.toString()}')),
        );
      }
    }
  }

  Future<void> _changePassword() async {
    final newPassword = await showDialog<String>(
      context: context,
      builder: (context) {
        final passController = TextEditingController();
        return AlertDialog(
          title: const Text('Change Password'),
          content: TextField(
            controller: passController,
            obscureText: true,
            decoration: const InputDecoration(hintText: 'Enter new password'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, passController.text),
              child: const Text('Update'),
            ),
          ],
        );
      },
    );

    if (newPassword != null && newPassword.isNotEmpty && _currentUser != null) {
      try {
        await _currentUser!.updatePassword(newPassword);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Password updated successfully')),
        );
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update password: ${e.toString()}')),
        );
      }
    }
  }
  Future<void> _changeUsername(BuildContext context) async {
  final nameController = TextEditingController(text: _userData['displayName'] ?? '');
  final newName = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Change Username'),
      content: TextField(
        controller: nameController,
        decoration: const InputDecoration(hintText: 'Enter new username'),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        TextButton(onPressed: () => Navigator.pop(context, nameController.text), child: const Text('Save')),
      ],
    ),
  );

  if (newName != null && newName.isNotEmpty) {
    try {
      await _firestore.collection('users').doc(_currentUser!.uid).update({
        'displayName': newName,
      });
      await _loadUserData();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Username updated successfully')));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to update username: ${e.toString()}')));
    }
  }
}
  Future<void> _updateUserStatus() async {
    if (_currentUser != null) {
      await _firestore.collection('users').doc(_currentUser!.uid).update({
        'status': 'online',
        'lastActive': FieldValue.serverTimestamp(),
      });
    }
  }

  void _logout(BuildContext context) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Logout"),
        content: const Text("Are you sure you want to logout?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("Cancel"),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("Logout"),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        // Update user status before logging out
        if (_currentUser != null) {
          await _firestore.collection('users').doc(_currentUser!.uid).update({
            'status': 'offline',
            'lastActive': FieldValue.serverTimestamp(),
          });
        }

        await _auth.signOut();
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (context) => const LoginScreen()),
          (Route<dynamic> route) => false,
        );
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Logout failed: ${e.toString()}')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        automaticallyImplyLeading: false,
        actions: [
          IconButton(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SettingsScreen()),
              );
            },
            icon: const Icon(Icons.settings),
          ),
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
      padding: const EdgeInsets.all(16.0),
      child: Row(
        children: [
          GestureDetector(
            onTap: _updateProfilePicture,
            child: CircleAvatar(
              radius: 30,
              backgroundImage: _userData['photoURL'] != null &&
                      _userData['photoURL'].isNotEmpty
                  ? NetworkImage(_userData['photoURL'])
                  : null,
              child: _userData['photoURL'] == null ||
                      _userData['photoURL'].isEmpty
                  ? const Icon(Icons.person, size: 30)
                  : null,
            ),
          ),
          const SizedBox(width: 20),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _userData['displayName'] ?? 'No Name',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              InkWell(
                onTap: () => _updateBio(context),
                child: Text(
                  _userData['bio']?.isNotEmpty == true
                      ? _userData['bio']
                      : 'Add a bio',
                  style: TextStyle(
                    color: _userData['bio']?.isNotEmpty == true
                        ? Colors.black87
                        : Colors.blue,
                    decoration: _userData['bio']?.isNotEmpty == true
                        ? TextDecoration.none
                        : TextDecoration.underline,
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
          onTap: () => _showPersonalInfo(context),
        ),
        const Divider(),
        ListTile(
          leading: const Icon(Icons.security),
          title: const Text('Account Security'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _showAccountSecurity(context),
        ),
        const Divider(),
        ListTile(
          leading: const Icon(Icons.help),
          title: const Text('Help & Support'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _showHelpSupport(context),
        ),
        const Divider(),
        ListTile(
          leading: const Icon(Icons.exit_to_app),
          title: const Text('Logout'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _logout(context),
        ),
      ],
    );
  }

  void _showPersonalInfo(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (_) => Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Personal Information', 
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            _buildInfoRow('Name', _userData['displayName'] ?? 'Not set'),
            _buildInfoRow('Email', _userData['email'] ?? 'Not set'),
            _buildInfoRow(
              'Account Created',
              _userData['createdAt'] != null
                  ? DateFormat.yMMMd().format((_userData['createdAt'] as Timestamp).toDate())
                  : 'Unknown',
            ),
            _buildInfoRow('Status', _userData['status'] ?? 'invisible'),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => Navigator.pop(context), 
              child: const Text('Close')),
          ],
        ),
      ),
    );
  }

  void _showAccountSecurity(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (_) => Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Account Security', 
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            ListTile(
              leading: const Icon(Icons.email),
              title: const Text('Change Email'),
              onTap: () {
                Navigator.pop(context);
                _changeEmail();
              },
            ),
            ListTile(
              leading: const Icon(Icons.lock),
              title: const Text('Change Password'),
              onTap: () {
                Navigator.pop(context);
                _changePassword();
              },
            ),
            ListTile(
              leading: const Icon(Icons.person),
              title: const Text('Change Username'),
              onTap: () {
                Navigator.pop(context);
                _changeUsername(context);
              },
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => Navigator.pop(context), 
              child: const Text('Close')),
          ],
        ),
      ),
    );
  }

  void _showHelpSupport(BuildContext context) {
    showModalBottomSheet(
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

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        children: [
          Text('$label: ', style: const TextStyle(fontWeight: FontWeight.bold)),
          Text(value),
        ],
      ),
    );
  }
}