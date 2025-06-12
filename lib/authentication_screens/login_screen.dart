import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:flutter_facebook_auth/flutter_facebook_auth.dart';
import 'package:realtime_message_calling/authentication_screens/reset_password_screen.dart';
import 'package:realtime_message_calling/home/home.dart';
import 'register_screen.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:permission_handler/permission_handler.dart';
//import 'reset_password_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final emailController = TextEditingController();
  final passwordController = TextEditingController();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Future<void> login() async {
  try {
    final userCredential = await FirebaseAuth.instance.signInWithEmailAndPassword(
      email: emailController.text.trim(),
      password: passwordController.text.trim(),
    );

    final user = userCredential.user;
    if (user != null) {
      await _initializeUserData(user);  // Initialize user data
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const HomePage()),
      );
    }
  } on FirebaseAuthException catch (e) {
    String message;
    switch (e.code) {
      case 'invalid-email':
        message = 'Invalid email address.';
        break;
      case 'user-disabled':
        message = 'This account has been banned.';
        break;
      case 'user-not-found':
        message = 'Email address or password is incorrect. Please try again.';
        break;
      case 'wrong-password':
        message = 'Email address or password is incorrect. Please try again.';
        break;
      default:
        message = 'Email address or password is incorrect. Please try again.';
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  } catch (e) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("An unexpected error occurred: $e")),
    );
  }
}
Future<void> handleLogin(String email, String password) async {
  try {
    final credential = await FirebaseAuth.instance.signInWithEmailAndPassword(
      email: email,
      password: password,
    );

    // Request necessary permissions (Android/iOS)
    await requestPermissions();

    // Get FCM token after permissions granted
    String? token = await FirebaseMessaging.instance.getToken();
    print("FCM Token: $token");

    // Store this token in Firestore under user profile (or wherever appropriate)
    await FirebaseFirestore.instance.collection('users').doc(credential.user!.uid).update({
       'fcmToken': token,
     });

    // Optionally: listen to foreground messages
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      print('Foreground Notification: ${message.notification?.title}');
      // Show custom dialog/snackbar here if needed
    });

  } catch (e) {
    print("Login error: $e");
    // Show login error to user
  }
}
Future<void> requestPermissions() async {
  // For notification permission
  final messaging = FirebaseMessaging.instance;

  await messaging.requestPermission(
    alert: true,
    announcement: false,
    badge: true,
    carPlay: false,
    criticalAlert: false,
    provisional: false,
    sound: true,
  );

  // Android-specific permissions (optional but recommended)
  if (await Permission.notification.isDenied) {
    await Permission.notification.request();
  }

  // (Optional) Also request microphone, camera if you're doing calls:
  await Permission.microphone.request();
  await Permission.camera.request();
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

    Future<void> _initializeUserData(User user) async {
    final userRef = _firestore.collection('users').doc(user.uid);
    final userDoc = await userRef.get();

    if (!userDoc.exists) {
      await _createUserStructures(user);
    } else {
      await _updateUserStructures(user);
    }
  }
  Future<void> _createUserStructures(User user) async {
    final userRef = _firestore.collection('users').doc(user.uid);
    await userRef.set({
      'uid': user.uid,
      'displayName': user.displayName ?? 'User${user.uid.substring(0, 6)}',
      'email': user.email ?? '',
      'phone': user.phoneNumber ?? '',
      'photoURL': user.photoURL ?? '',
      'createdAt': FieldValue.serverTimestamp(),
      'lastActive': FieldValue.serverTimestamp(),
      'status': 'online',
      'fcmToken': '',
      'friendsCount': 0,
      'pendingRequestsCount': 0,
    });

    await _initializeSubcollections(user);
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

  Future<void> createUserStructures(User user) async {
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
  }

  Future<void> loginWithGoogle() async {
  try {
    final GoogleSignInAccount? googleUser = await GoogleSignIn().signIn();
    if (googleUser == null) return;

    final GoogleSignInAuthentication googleAuth = await googleUser.authentication;

    final AuthCredential credential = GoogleAuthProvider.credential(
      accessToken: googleAuth.accessToken,
      idToken: googleAuth.idToken,
    );

    final userCredential = await FirebaseAuth.instance.signInWithCredential(credential);
    final user = userCredential.user;
    if (user != null) {
      await _initializeUserData(user);
    }

    Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const HomePage()));
  } catch (e) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("Google Sign-In Failed: $e")),
    );
  }
}


Future<void> loginWithFacebook() async {
  try {
    final LoginResult result = await FacebookAuth.instance.login();
    if (result.status != LoginStatus.success || result.accessToken == null) return;

    final OAuthCredential credential = FacebookAuthProvider.credential(result.accessToken!.tokenString);

    final userCredential = await FirebaseAuth.instance.signInWithCredential(credential);
    final user = userCredential.user;
    if (user != null) {
      await _initializeUserData(user);
    }

    Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const HomePage()));
  } catch (e) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("Facebook Sign-In Failed: $e")),
    );
  }
}


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 100,
        title: const Text(
          "Welcome!",
          style: TextStyle(
            fontSize: 30,
            fontWeight: FontWeight.bold
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            const SizedBox(height: 20),
            // Optional: add a logo or image here
            // Image.asset('assets/logo.png', height: 100),

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
              keyboardType: TextInputType.visiblePassword,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.lock),
                labelText: 'Password',
                hintText: 'Enter your password',
                counterText: '',
              ),
              onFieldSubmitted: (_) => login(),
            ),
            const SizedBox(height: 5),
            InkWell(
              onTap: () {
                Navigator.push(context, MaterialPageRoute(builder: (context) => ResetPasswordScreen()));
              },
              child: const Text(
                'Forgot Password?',
                style: TextStyle(
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
            const SizedBox(height: 30),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                minimumSize: Size.fromHeight(55),
                backgroundColor: Colors.blue,
              ),
              onPressed: login,
              child: const Text(
                'Sign In',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold
                ),
              ),
            ),
            const SizedBox(height: 10),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                minimumSize: Size.fromHeight(55),
              ),
              onPressed: goToRegister,
              child: const Text(
                'Create Account',
                style: TextStyle(
                  color: Colors.blue,
                  fontSize: 18,
                  fontWeight: FontWeight.bold
                ),
              ),
            ),
            SizedBox(height: 20,),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SizedBox(height: 20),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    minimumSize: Size(150, 70), // Adjust size for better layout
                    backgroundColor: Colors.white,
                    side: const BorderSide(color: Colors.grey), // Adds border for visibility
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(5), // Ensures sharp corners for a square button
                    ),
                  ),
                  onPressed: loginWithGoogle,
                  icon: Image.asset('assets/images/google_icon.png', height: 40),
                  label: Text(' Google', style: TextStyle(
                    color: Colors.blueAccent
                  ),), // Ensure correct file path
                ),
                const SizedBox(width: 10), // Adds spacing
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    minimumSize: Size(50, 70),
                    backgroundColor: Colors.blue[800],
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(5), // Ensures sharp corners for a square button
                    ),
                  ),
                  onPressed: loginWithFacebook,
                  icon: const Icon(Icons.facebook, color: Colors.white, size: 36,),
                  label: Text(' Facebook', style: TextStyle(
                    color: Colors.white
                  ),),
                ),
              ],
            ),
          ],
        ),
      ),
    );
    }
  }

//git pull origin main