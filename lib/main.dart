import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;
import 'package:photo_manager/photo_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'SplashScreen.dart';
import 'video_page.dart';

void main() {
  runApp(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      home: SplashScreen(nextScreen: MyApp()),
    ),
  );
}

final GoogleSignIn _googleSignIn = GoogleSignIn(
  clientId: kIsWeb
      ? '419479685978-a2i54r2v2bjvkvm5mpd1i4ks5r3f68tt.apps.googleusercontent.com'
      : '419479685978-k31nq590lglod4c2sm3tsounmc5ovu5d.apps.googleusercontent.com',
  scopes: [
    'email',
    'https://www.googleapis.com/auth/youtube.upload',
    'https://www.googleapis.com/auth/userinfo.email',
    'https://www.googleapis.com/auth/userinfo.profile',
  ],
);

class MyApp extends StatefulWidget {
  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  GoogleSignInAccount? _currentUser;
  String? _accessToken;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _initLoginState();
    _googleSignIn.onCurrentUserChanged.listen((account) async {
      setState(() => _currentUser = account);
      if (account != null) await _getAccessToken(account);
    });
  }

  Future<void> _initLoginState() async {
    try {
      final account = await _googleSignIn.signInSilently();
      if (account != null) {
        setState(() => _currentUser = account);
        await _getAccessToken(account);
      }
    } catch (e) {
      print('Silent sign-in failed: $e');
    }
    setState(() => _loading = false);
  }

  Future<void> _getAccessToken(GoogleSignInAccount account) async {
    final auth = await account.authentication;
    setState(() {
      _accessToken = auth.accessToken;
    });
  }

  Future<void> _handleSignIn() async {
    try {
      await _googleSignIn.signIn();
    } catch (error) {
      print('Sign in failed: $error');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: CircularProgressIndicator(color: Colors.green),
        ),
      );
    }

    if (_currentUser == null) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            onPressed: _handleSignIn,
            child: Text('Sign in with Google', style: TextStyle(color: Colors.white)),
          ),
        ),
      );
    }

    return MultiVideoPickerUploadPage(accessToken: _accessToken);
  }
}
