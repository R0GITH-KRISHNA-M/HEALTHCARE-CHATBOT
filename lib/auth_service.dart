import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Get current user
  User? get currentUser => _auth.currentUser;

  // Stream to listen to auth state changes (for future use)
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  // Email/Password Signup
  Future<void> signUpWithEmail({
    required String email,
    required String password,
    required String name,
  }) async {
    try {
      final UserCredential userCredential =
      await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      // Update display name for consistency with Google Sign-In
      await userCredential.user!.updateDisplayName(name);

      // Save user data to Firestore
      await _firestore.collection('users').doc(userCredential.user!.uid).set({
        'name': name,
        'email': email,
        'createdAt': FieldValue.serverTimestamp(),
      });
    } on FirebaseAuthException catch (e) {
      throw FirebaseAuthException(code: e.code, message: e.message);
    }
  }

  // Email/Password Login
  Future<void> loginWithEmail({
    required String email,
    required String password,
  }) async {
    try {
      await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
    } on FirebaseAuthException catch (e) {
      throw FirebaseAuthException(code: e.code, message: e.message);
    }
  }

  // Google Sign-In
  Future<UserCredential?> signInWithGoogle() async {
    try {
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
      if (googleUser == null) return null;

      final GoogleSignInAuthentication googleAuth =
      await googleUser.authentication;

      final OAuthCredential credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      final UserCredential userCredential =
      await _auth.signInWithCredential(credential);

      // Save Google user to Firestore if new
      if (userCredential.additionalUserInfo!.isNewUser) {
        await _firestore.collection('users').doc(userCredential.user!.uid).set({
          'name': userCredential.user!.displayName,
          'email': userCredential.user!.email,
          'createdAt': FieldValue.serverTimestamp(),
        });
      }

      return userCredential;
    } catch (e) {
      throw FirebaseAuthException(
        code: 'google_signin_failed',
        message: e.toString(),
      );
    }
  }

  // Sign Out
  Future<void> signOut() async {
    await _googleSignIn.signOut();
    await _auth.signOut();
  }

  // Save chat message to Firestore
  Future<void> saveChatMessage({
    required String userId,
    required String message,
    required String response,
  }) async {
    try {
      await _firestore
          .collection('users')
          .doc(userId)
          .collection('chatHistory')
          .add({
        'userMessage': message,
        'botResponse': response,
        'timestamp': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      print('Error saving chat message: $e');
    }
  }

  // Save hospital search to Firestore
  Future<void> saveHospitalSearch({
    required String userId,
    required Map<String, dynamic> hospital,
    required LatLng location,
  }) async {
    try {
      await _firestore
          .collection('users')
          .doc(userId)
          .collection('hospitalSearches')
          .add({
        'hospital': hospital,
        'userEmail': _auth.currentUser?.email ?? 'unknown',
        'location': {
          'latitude': location.latitude,
          'longitude': location.longitude,
        },
        'timestamp': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      print('Error saving hospital search: $e');
    }
  }
}