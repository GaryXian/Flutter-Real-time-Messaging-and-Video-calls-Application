import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'login_screen.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final emailController = TextEditingController();
  final phoneController = TextEditingController();
  final passwordController = TextEditingController();
  final confirmPasswordController = TextEditingController();
  final displayNameController = TextEditingController();

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  bool _isRegistering = false;

  void _showMessage(String message, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: error ? Colors.red : null),
    );
  }

  bool _validateForm() {
    final isValid = _formKey.currentState?.validate() ?? false;
    if (passwordController.text != confirmPasswordController.text) {
      _showMessage("Passwords do not match", error: true);
      return false;
    }
    return isValid;
  }

  Future<void> _createUserStructures(User user, String phone, String displayName) async {
    final batch = _firestore.batch();
    final userRef = _firestore.collection('users').doc(user.uid);

    batch.set(userRef, {
      'uid': user.uid,
      'email': user.email ?? '',
      'phone': phone,
      'displayName': displayName,
      'photoURL': '',
      'createdAt': FieldValue.serverTimestamp(),
      'lastActive': FieldValue.serverTimestamp(),
      'status': 'offline',
      'fcmToken': '',
      'friendsCount': 0,
      'pendingRequestsCount': 0,
    });

    batch.set(userRef.collection('settings').doc('privacy'), {
      'allowFriendRequests': true,
      'allowConversations': true,
      'showOnlineStatus': true,
      'lastUpdated': FieldValue.serverTimestamp(),
    });
    batch.set(userRef.collection('settings').doc('notifications'), {
      'messageNotifications': true,
      'friendRequestNotifications': true,
      'lastUpdated': FieldValue.serverTimestamp(),
    });
    batch.set(userRef.collection('friends').doc(user.uid), {
      'uid': user.uid,
      'displayName': displayName,
      'email': user.email ?? '',
      'photoURL': '',
    });

    await batch.commit();
  }

  Future<void> _registerUser() async {
    if (!_validateForm()) return;

    setState(() => _isRegistering = true);

    final email = emailController.text.trim();
    final phone = phoneController.text.trim();
    final password = passwordController.text.trim();
    final displayName = displayNameController.text.trim();

    try {
      final userCredential = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      final user = userCredential.user!;
      await user.updateDisplayName(displayName);

      await _createUserStructures(user, phone, displayName);

      _showMessage("Registration Successful!");
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const LoginScreen()),
      );
    } on FirebaseAuthException catch (e) {
      _showMessage("Registration failed: ${e.message}", error: true);
    } catch (e) {
      _showMessage("Error: $e", error: true);
    } finally {
      if (mounted) setState(() => _isRegistering = false);
    }
  }

  InputDecoration _inputDecoration(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon),
      border: const OutlineInputBorder(),
    );
  }

  @override
  void dispose() {
    emailController.dispose();
    phoneController.dispose();
    passwordController.dispose();
    confirmPasswordController.dispose();
    displayNameController.dispose();
    super.dispose();
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Register")),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              TextFormField(
                controller: emailController,
                decoration: _inputDecoration("Email", Icons.email),
                keyboardType: TextInputType.emailAddress,
                validator: (value) {
                  if (value == null || value.isEmpty) return 'Enter your email';
                  final emailRegex = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');
                  if (!emailRegex.hasMatch(value)) return 'Enter a valid email';
                  return null;
                },
              ),
              const SizedBox(height: 10),

              TextFormField(
                controller: phoneController,
                decoration: _inputDecoration("Phone Number", Icons.phone),
                keyboardType: TextInputType.phone,
                validator: (value) {
                  if (value == null || value.isEmpty) return 'Enter your phone number';
                  final phoneRegex = RegExp(r'^\+?\d{7,15}$');
                  if (!phoneRegex.hasMatch(value)) return 'Enter a valid phone number';
                  return null;
                },
              ),
              const SizedBox(height: 10),

              TextFormField(
                controller: displayNameController,
                decoration: _inputDecoration("Display Name", Icons.person),
                validator: (value) {
                  if (value == null || value.isEmpty) return 'Enter a display name';
                  if (value.length < 3) return 'Name must be at least 3 characters';
                  return null;
                },
              ),
              const SizedBox(height: 10),

              TextFormField(
                controller: passwordController,
                decoration: _inputDecoration("Password", Icons.lock),
                obscureText: true,
                validator: (value) {
                  if (value == null || value.isEmpty) return 'Enter a password';
                  if (value.length < 6) return 'Password must be at least 6 characters';
                  return null;
                },
              ),
              const SizedBox(height: 10),

              TextFormField(
                controller: confirmPasswordController,
                decoration: _inputDecoration("Confirm Password", Icons.lock_outline),
                obscureText: true,
                validator: (value) {
                  if (value == null || value.isEmpty) return 'Confirm your password';
                  return null;
                },
              ),
              const SizedBox(height: 20),

              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: _isRegistering ? null : _registerUser,
                  child: _isRegistering
                      ? const CircularProgressIndicator(color: Colors.white)
                      : const Text("Register"),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
