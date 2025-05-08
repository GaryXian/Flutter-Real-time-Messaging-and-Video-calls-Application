import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:realtime_message_calling/home/home.dart';
import 'register_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final emailController = TextEditingController();
  final passwordController = TextEditingController();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  bool _isLoading = false;

  Future<void> login() async {
    setState(() => _isLoading = true);
    try {
      final userCredential = await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: emailController.text.trim(),
        password: passwordController.text.trim(),
      );

      // Check and initialize user data structures
      await _initializeUserData(userCredential.user!);

      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const HomePage()),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Login Failed: $e")),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _initializeUserData(User user) async {
    final userRef = _firestore.collection('users').doc(user.uid);
    final userDoc = await userRef.get();

    // If user document doesn't exist or is missing required fields
    if (!userDoc.exists || !_hasRequiredData(userDoc.data()!)) {
      await _createUserStructures(user);
    }
  }

  bool _hasRequiredData(Map<String, dynamic>? userData) {
    if (userData == null) return false;
    
    final requiredFields = [
      'uid', 'email', 'displayName', 'createdAt', 
      'lastActive', 'status', 'friendsCount'
    ];
    
    return requiredFields.every((field) => userData.containsKey(field));
  }

  Future<void> _createUserStructures(User user) async {
    final batch = _firestore.batch();
    final userRef = _firestore.collection('users').doc(user.uid);

    // 1. Create/update main user document
    batch.set(userRef, {
      'uid': user.uid,
      'email': user.email,
      'displayName': user.displayName ?? 'User${user.uid.substring(0, 6)}',
      'photoURL': user.photoURL ?? '',
      'createdAt': FieldValue.serverTimestamp(),
      'lastActive': FieldValue.serverTimestamp(),
      'status': 'online',
      'fcmToken': '',
      'friendsCount': 0,
      'pendingRequestsCount': 0,
    }, SetOptions(merge: true));

    // 2. Ensure friends subcollection exists (no need to add documents)
    final friendsRef = userRef.collection('friends');
    
    // 3. Ensure friend_requests subcollection exists
    final requestsRef = userRef.collection('friend_requests');
    
    // 4. Set default privacy settings if they don't exist
    final privacyRef = userRef.collection('settings').doc('privacy');
    batch.set(privacyRef, {
      'allowFriendRequests': true,
      'allowConversations': true,
      'showOnlineStatus': true,
      'lastUpdated': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    await batch.commit();
  }

  Future<void> resetPassword() async {
    if (emailController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please enter your email to reset password")),
      );
      return;
    }

    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(
        email: emailController.text.trim(),
      );
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Password reset email sent")),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error: $e")),
      );
    }
  }

  void goToRegister() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const RegisterScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Login")),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const SizedBox(height: 20),
            
            TextFormField(
              controller: emailController,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.email),
                labelText: 'Email',
                hintText: 'Enter your email',
              ),
            ),
            const SizedBox(height: 10),
            
            TextFormField(
              controller: passwordController,
              maxLength: 16,
              obscureText: true,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.lock),
                labelText: 'Password',
                hintText: 'Enter your password',
              ),
              onFieldSubmitted: (_) => login(),
            ),
            const SizedBox(height: 10),

            _isLoading
                ? const CircularProgressIndicator()
                : ElevatedButton(
                    onPressed: login,
                    child: const Text('Login'),
                  ),
            
            TextButton(
              onPressed: resetPassword,
              child: const Text("Forgot password?"),
            ),
            
            const SizedBox(height: 10),
            
            ElevatedButton(
              onPressed: goToRegister,
              child: const Text('Create Account'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    emailController.dispose();
    passwordController.dispose();
    super.dispose();
  }
}