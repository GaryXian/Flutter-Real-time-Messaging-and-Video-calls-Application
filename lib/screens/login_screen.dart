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
  final phoneController = TextEditingController();
  final smsCodeController = TextEditingController();

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  bool _isLoading = false;
  bool _isPhoneLogin = false; // Toggle Email/Phone login
  String? _verificationId; // For phone OTP

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _initializeUserData(User user) async {
    final userRef = _firestore.collection('users').doc(user.uid);
    final userDoc = await userRef.get();

    if (!userDoc.exists) {
      await _createUserStructures(user);
    } else {
      await _updateUserStructures(user);
    }
  }

  Future<void> _updateUserStructures(User user) async {
    final userRef = _firestore.collection('users').doc(user.uid);
    final userDoc = await userRef.get();

    if (!userDoc.exists) return;

    final currentData = userDoc.data() ?? {};
    final updates = {
      if (currentData['displayName'] == null || currentData['displayName'].isEmpty)
        'displayName': user.displayName ?? 'User${user.uid.substring(0, 6)}',
      if (currentData['email'] == null || currentData['email'].isEmpty)
        'email': user.email ?? '',
      if (currentData['phone'] == null || currentData['phone'].isEmpty)
        'phone': user.phoneNumber ?? '',
      if (currentData['photoURL'] == null || currentData['photoURL'].isEmpty)
        'photoURL': user.photoURL ?? '',
      if (currentData['createdAt'] == null)
        'createdAt': FieldValue.serverTimestamp(),
      if (currentData['lastActive'] == null)
        'lastActive': FieldValue.serverTimestamp(),
      if (currentData['status'] == null || currentData['status'].isEmpty)
        'status': 'online',
      if (currentData['fcmToken'] == null)
        'fcmToken': '',
      if (currentData['friendsCount'] == null)
        'friendsCount': 0,
      if (currentData['pendingRequestsCount'] == null)
        'pendingRequestsCount': 0,
    };

    if (updates.isNotEmpty) {
      await userRef.set(updates, SetOptions(merge: true));
    }

    await _initializeSubcollections(user);
  }

  Future<void> _initializeSubcollections(User user) async {
    final userRef = _firestore.collection('users').doc(user.uid);

    // Check friends collection
    final friendsSnapshot = await userRef.collection('friends').limit(1).get();
    if (friendsSnapshot.docs.isEmpty) {
      await userRef.collection('friends').doc(user.uid).set({
        'uid': user.uid,
        'displayName': user.displayName ?? 'User${user.uid.substring(0, 6)}',
        'email': user.email ?? '',
        'photoURL': user.photoURL ?? '',
      });
    }

    // Check settings
    final privacySnapshot =
        await userRef.collection('settings').doc('privacy').get();
    if (!privacySnapshot.exists) {
      await userRef.collection('settings').doc('privacy').set({
        'allowFriendRequests': true,
        'allowConversations': true,
        'showOnlineStatus': true,
        'lastUpdated': FieldValue.serverTimestamp(),
      });
    }

    final notificationsSnapshot =
        await userRef.collection('settings').doc('notifications').get();
    if (!notificationsSnapshot.exists) {
      await userRef.collection('settings').doc('notifications').set({
        'message': true,
        'call': true,
        'friendRequest': true,
        'lastUpdated': FieldValue.serverTimestamp(),
      });
    }
  }

  Future<void> _createUserStructures(User user) async {
    final batch = _firestore.batch();
    final userRef = _firestore.collection('users').doc(user.uid);

    batch.set(userRef, {
      'uid': user.uid,
      'email': user.email ?? '',
      'phone': user.phoneNumber ?? '',
      'displayName': user.displayName ?? 'User${user.uid.substring(0, 6)}',
      'photoURL': user.photoURL ?? '',
      'createdAt': FieldValue.serverTimestamp(),
      'lastActive': FieldValue.serverTimestamp(),
      'status': 'online',
      'fcmToken': '',
      'friendsCount': 0,
      'pendingRequestsCount': 0,
    }, SetOptions(merge: true));

    final privacyRef = userRef.collection('settings').doc('privacy');
    batch.set(privacyRef, {
      'allowFriendRequests': true,
      'allowConversations': true,
      'showOnlineStatus': true,
      'lastUpdated': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    final notificationsRef = userRef
        .collection('settings')
        .doc('notifications');
    batch.set(notificationsRef, {
      'message': true,
      'call': true,
      'friendRequest': true,
      'lastUpdated': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    
    final friendsRef = userRef.collection('friends').doc(user.uid);
    batch.set(friendsRef, {
      'uid': user.uid,
      'displayName': user.displayName ?? 'User${user.uid.substring(0, 6)}',
      'email': user.email ?? '',
      'photoURL': user.photoURL ?? '',
    }, SetOptions(merge: true));

    await batch.commit();
  }

  Future<void> _navigateToHome() async {
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const HomePage()),
    );
  }

  Future<void> loginWithEmail() async {
    setState(() => _isLoading = true);
    try {
      final userCredential = await _auth.signInWithEmailAndPassword(
        email: emailController.text.trim(),
        password: passwordController.text.trim(),
      );

      await _initializeUserData(userCredential.user!);
      await _navigateToHome();
    } catch (e) {
      _showError("Login Failed: $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> sendPhoneOTP() async {
    final phone = phoneController.text.trim();
    if (phone.isEmpty) {
      _showError("Please enter phone number");
      return;
    }

    setState(() => _isLoading = true);

    await _auth.verifyPhoneNumber(
      phoneNumber: phone,
      verificationCompleted: (PhoneAuthCredential credential) async {
        // Auto sign-in if possible
        await _auth.signInWithCredential(credential);
        await _initializeUserData(_auth.currentUser!);
        await _navigateToHome();
      },
      verificationFailed: (FirebaseAuthException e) {
        _showError('Phone verification failed: ${e.message}');
        setState(() => _isLoading = false);
      },
      codeSent: (String verificationId, int? resendToken) {
        _verificationId = verificationId;
        setState(() => _isLoading = false);
        _showSMSCodeDialog();
      },
      codeAutoRetrievalTimeout: (String verificationId) {
        _verificationId = verificationId;
      },
    );
  }

  Future<void> verifySMSCode() async {
    final smsCode = smsCodeController.text.trim();
    if (_verificationId == null || smsCode.isEmpty) {
      _showError('Enter the verification code');
      return;
    }

    setState(() => _isLoading = true);

    try {
      final credential = PhoneAuthProvider.credential(
        verificationId: _verificationId!,
        smsCode: smsCode,
      );

      final userCredential = await _auth.signInWithCredential(credential);
      await _initializeUserData(userCredential.user!);
      await _navigateToHome();
    } catch (e) {
      _showError('Invalid code: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showSMSCodeDialog() {
    showDialog(
      context: context,
      builder:
          (_) => AlertDialog(
            title: const Text("Enter SMS Code"),
            content: TextField(
              controller: smsCodeController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                hintText: 'Enter the 6-digit code',
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(context);
                  verifySMSCode();
                },
                child: const Text('Verify'),
              ),
            ],
          ),
    );
  }

  void goToRegister() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const RegisterScreen()),
    );
  }

  @override
  void dispose() {
    emailController.dispose();
    passwordController.dispose();
    phoneController.dispose();
    smsCodeController.dispose();
    super.dispose();
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
            SwitchListTile(
              title: Text(
                _isPhoneLogin ? "Login with Phone" : "Login with Email",
              ),
              value: _isPhoneLogin,
              onChanged: (value) => setState(() => _isPhoneLogin = value),
            ),
            const SizedBox(height: 20),

            if (_isPhoneLogin) ...[
              TextFormField(
                controller: phoneController,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.phone),
                  labelText: 'Phone Number',
                  hintText: '+84xxxxxxxxx',
                ),
              ),
              const SizedBox(height: 10),
              _isLoading
                  ? const CircularProgressIndicator()
                  : ElevatedButton(
                    onPressed: sendPhoneOTP,
                    child: const Text('Send OTP'),
                  ),
            ] else ...[
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
                obscureText: true,
                maxLength: 16,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.lock),
                  labelText: 'Password',
                  hintText: 'Enter your password',
                ),
                onFieldSubmitted: (_) => loginWithEmail(),
              ),
              const SizedBox(height: 10),

              _isLoading
                  ? const CircularProgressIndicator()
                  : ElevatedButton(
                    onPressed: loginWithEmail,
                    child: const Text('Login'),
                  ),
            ],

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
}
