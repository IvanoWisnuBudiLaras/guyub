// Firebase production configuration is supplied at build/run time. These values
// are public client configuration, not service-account credentials, but are kept
// out of source control under the project's SEC-06 policy.
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static const _apiKey = String.fromEnvironment('FIREBASE_API_KEY');
  static const _appId = String.fromEnvironment('FIREBASE_APP_ID');
  static const _senderId = String.fromEnvironment(
    'FIREBASE_MESSAGING_SENDER_ID',
  );
  static const _projectId = String.fromEnvironment('FIREBASE_PROJECT_ID');

  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      throw UnsupportedError('Guyub.id MVP currently targets Android.');
    }
    if (defaultTargetPlatform == TargetPlatform.android) return android;
    if (defaultTargetPlatform == TargetPlatform.iOS) return ios;
    throw UnsupportedError('Firebase is not configured for this platform.');
  }

  static FirebaseOptions get android => FirebaseOptions(
    apiKey: _required(_apiKey, 'FIREBASE_API_KEY'),
    appId: _required(_appId, 'FIREBASE_APP_ID'),
    messagingSenderId: _required(_senderId, 'FIREBASE_MESSAGING_SENDER_ID'),
    projectId: _required(_projectId, 'FIREBASE_PROJECT_ID'),
  );

  static FirebaseOptions get ios => FirebaseOptions(
    apiKey: _required(_apiKey, 'FIREBASE_API_KEY'),
    appId: _required(_appId, 'FIREBASE_APP_ID'),
    messagingSenderId: _required(_senderId, 'FIREBASE_MESSAGING_SENDER_ID'),
    projectId: _required(_projectId, 'FIREBASE_PROJECT_ID'),
    iosBundleId: 'com.guyub.guyub',
  );

  static String _required(String value, String name) {
    if (value.isEmpty) {
      throw StateError(
        'Firebase configuration is missing. Supply --dart-define=$name=... .',
      );
    }
    return value;
  }
}
