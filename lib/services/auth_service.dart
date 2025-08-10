import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/services.dart';
import 'package:google_sign_in/google_sign_in.dart';

/// Custom exception class for authentication errors with user-friendly messages
class AuthException implements Exception {
  final String message;
  AuthException(this.message);

  @override
  String toString() => message;
}

class AuthService {
  static final FirebaseAuth _auth = FirebaseAuth.instance;
  static final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: ['email', 'profile'],
  );

  static Future<User?> signInWithGoogle() async {
    try {
      // Return existing user if already signed in
      final existing = _auth.currentUser;
      if (existing != null) return existing;

      // Native Google Sign-In (Play Services), no browser redirect
      GoogleSignInAccount? googleUser = await _googleSignIn.signInSilently();
      googleUser ??= await _googleSignIn.signIn();
      if (googleUser == null) return null; // user cancelled

      final GoogleSignInAuthentication googleAuth =
          await googleUser.authentication;

      final OAuthCredential credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      final UserCredential cred = await _auth.signInWithCredential(credential);
      return cred.user;
    } on PlatformException catch (e) {
      print('Google Sign-In Platform Exception: ${e.code} - ${e.message}');
      // Handle specific platform errors with user-friendly messages
      switch (e.code) {
        case 'SIGN_IN_CANCELLED':
          return null; // User cancelled - no error to show
        case 'SIGN_IN_REQUIRED':
          throw AuthException('Sign in is required. Please try again.');
        case 'NETWORK_ERROR':
        case 'network_error':
          throw AuthException(
              'Network connection error. Please check your internet connection and try again.');
        case 'SIGN_IN_FAILED':
          throw AuthException('Sign in failed. Please try again.');
        case 'SIGN_IN_CURRENTLY_IN_PROGRESS':
          throw AuthException('Sign in is already in progress. Please wait.');
        case 'DEVELOPER_ERROR':
          throw AuthException(
              'App configuration error. Please contact support.');
        case 'INVALID_ACCOUNT':
          throw AuthException(
              'Invalid account. Please check your Google account settings.');
        case 'PLAY_SERVICES_NOT_AVAILABLE':
          throw AuthException(
              'Google Play Services not available. Please update or install Google Play Services.');
        case 'SIGN_IN_REQUIRED':
          throw AuthException('Sign in required. Please try again.');
        case 'INTERNAL_ERROR':
          throw AuthException(
              'Internal error occurred. Please try again later.');
        case 'TIMEOUT':
          throw AuthException(
              'Sign in timed out. Please check your connection and try again.');
        default:
          // Handle unknown error codes with a generic but helpful message
          if (e.message != null && e.message!.contains('ApiException')) {
            // Handle specific Google Play Services API exceptions
            if (e.message!.contains('ApiException: 7')) {
              throw AuthException(
                  'Google Sign-In service temporarily unavailable. Please try again in a moment.');
            } else if (e.message!.contains('ApiException: 8')) {
              throw AuthException(
                  'Google Sign-In service error. Please check your internet connection and try again.');
            } else if (e.message!.contains('ApiException: 16')) {
              throw AuthException(
                  'Google Sign-In service error. Please try again later.');
            }
            throw AuthException(
                'Google Sign-In service error. Please try again later.');
          }
          throw AuthException(
              'Sign in failed: ${e.message ?? 'Unknown error'}. Please try again.');
      }
    } on FirebaseAuthException catch (e) {
      print('Firebase Auth Exception: ${e.code} - ${e.message}');
      switch (e.code) {
        case 'network-request-failed':
          throw AuthException(
              'Network error. Please check your internet connection and try again.');
        case 'too-many-requests':
          throw AuthException(
              'Too many sign-in attempts. Please wait a moment and try again.');
        case 'user-disabled':
          throw AuthException(
              'This account has been disabled. Please contact support.');
        case 'invalid-credential':
          throw AuthException(
              'Invalid credentials. Please try signing in again.');
        case 'operation-not-allowed':
          throw AuthException(
              'Google Sign-In is not enabled. Please contact support.');
        case 'weak-password':
          throw AuthException(
              'Password is too weak. Please use a stronger password.');
        case 'email-already-in-use':
          throw AuthException(
              'This email is already in use. Please sign in with the correct account.');
        case 'user-not-found':
          throw AuthException(
              'Account not found. Please check your email address.');
        case 'wrong-password':
          throw AuthException('Incorrect password. Please try again.');
        case 'account-exists-with-different-credential':
          throw AuthException(
              'An account already exists with this email. Please sign in with the correct method.');
        default:
          throw AuthException(
              'Authentication failed: ${e.message ?? 'Unknown error'}. Please try again.');
      }
    } catch (e) {
      print('Google Sign-In Error: $e');
      // Handle other types of errors
      if (e.toString().contains('network') ||
          e.toString().contains('connection')) {
        throw AuthException(
            'Network connection error. Please check your internet connection and try again.');
      } else if (e.toString().contains('timeout')) {
        throw AuthException(
            'Request timed out. Please check your connection and try again.');
      } else if (e.toString().contains('cancelled')) {
        return null; // User cancelled - no error to show
      } else {
        throw AuthException('Authentication failed. Please try again later.');
      }
    }
  }

  static Future<void> signOut() async {
    try {
      await _googleSignIn.signOut();
      await _auth.signOut();
    } catch (e) {
      print('Sign out error: $e');
      // Continue even if there's an error
    }
  }

  static User? get currentUser => _auth.currentUser;
}
