// ─────────────────────────────────────────────────────────────────────────────
// FIREBASE OPTIONS — Golf Bet Master
// Generado a partir de google-services.json (Android) y config web
// ─────────────────────────────────────────────────────────────────────────────
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) return web;
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      default:
        return web;
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyA14D84j0aJOW81FghwjuTkctw6ITbsPMs',
    authDomain: 'golf-bet-master.firebaseapp.com',
    projectId: 'golf-bet-master',
    storageBucket: 'golf-bet-master.firebasestorage.app',
    messagingSenderId: '925063159265',
    appId: '1:925063159265:web:eb11edf320bbc76122c6a0',
  );

  /// OAuth 2.0 Web Client ID — requerido para Google Sign-In
  static const String googleWebClientId =
      '925063159265-fku9som1aja54kbqc0t7r8q9jd5691g7.apps.googleusercontent.com';

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyABMK5NmOXr3tOuYh7JVI4sfuA0-4vQsEU',
    appId: '1:925063159265:android:efbc4030cd5fb53b22c6a0',
    messagingSenderId: '925063159265',
    projectId: 'golf-bet-master',
    storageBucket: 'golf-bet-master.firebasestorage.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyA14D84j0aJOW81FghwjuTkctw6ITbsPMs',
    appId: '1:925063159265:ios:000000000000000022c6a0',
    messagingSenderId: '925063159265',
    projectId: 'golf-bet-master',
    storageBucket: 'golf-bet-master.firebasestorage.app',
    iosBundleId: 'com.golfbetmaster.bet',
  );
}
