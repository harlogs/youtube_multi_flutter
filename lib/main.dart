import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'SplashScreen.dart';
import 'MultiVideoPickerUploadPage.dart';
// import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'dart:io' show Platform;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // if (!kIsWeb) {
  //   await MobileAds.instance.initialize();
  // }
  runApp(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        scaffoldBackgroundColor: Colors.black,
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
        ),
      ),
      home: SplashScreen(nextScreen: MyApp()),
    ),
  );
}
String get clientIdd {
  if (kIsWeb) {
    return '419479685978-a2i54r2v2bjvkvm5mpd1i4ks5r3f68tt.apps.googleusercontent.com'; // Web Client ID
  } else if (Platform.isAndroid) {
    return '419479685978-o1lqlg3fq8lcn5leht17t50cp9l3ltj8.apps.googleusercontent.com'; // Android Client ID
  } else if (Platform.isIOS) {
    return '419479685978-k31nq590lglod4c2sm3tsounmc5ovu5d.apps.googleusercontent.com'; // iOS Client ID
  } else {
    throw UnsupportedError('Unsupported platform');
  }
}

final GoogleSignIn _googleSignIn = GoogleSignIn(
  clientId: clientIdd,
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

  // late BannerAd _bannerAd;
  // bool _isBannerAdReady = false;

  @override
  void initState() {
    super.initState();
    _initLoginState();

    _googleSignIn.onCurrentUserChanged.listen((account) async {
      setState(() => _currentUser = account);
      if (account != null) await _getAccessToken(account);
    });

    // _bannerAd = BannerAd(
    //   adUnitId: 'ca-app-pub-2342650808451846/1952398384', // Replace with real Ad Unit ID
    //   request: AdRequest(),
    //   size: AdSize.banner,
    //   listener: BannerAdListener(
    //     onAdLoaded: (_) {
    //       setState(() {
    //         _isBannerAdReady = true;
    //       });
    //     },
    //     onAdFailedToLoad: (ad, error) {
    //       ad.dispose();
    //       print('Ad load failed: $error');
    //     },
    //   ),
    // )..load();
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
      return const Scaffold(
        body: Center(child: CircularProgressIndicator(color: Colors.green)),
      );
    }

    if (_currentUser == null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('YouTube Multi Uploader', style: TextStyle(color: Colors.white)),
          backgroundColor: Colors.black,
        ),
        drawer: Drawer(
          child: ListView(
            padding: EdgeInsets.zero,
            children: const [
              DrawerHeader(
                decoration: BoxDecoration(color: Colors.black),
                child: Text('Menu', style: TextStyle(color: Colors.white, fontSize: 24)),
              ),
              ListTile(
                leading: Icon(Icons.info),
                title: Text('About'),
              ),
              ListTile(
                leading: Icon(Icons.settings),
                title: Text('Settings'),
              ),
            ],
          ),
        ),
        body: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        'Steps to Multi Upload Videos to YouTube',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.grey[900],
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Text.rich(
                          TextSpan(
                            style: TextStyle(color: Colors.white, fontSize: 15, height: 1.6),
                            children: [
                              TextSpan(
                                text: '1. ',
                                style: TextStyle(fontWeight: FontWeight.bold, color: Colors.lightBlue),
                              ),
                              TextSpan(text: 'Open the '),
                              TextSpan(
                                  text: 'YouTube app',
                                  style: TextStyle(fontWeight: FontWeight.bold, color: Colors.orange)),
                              TextSpan(text: ' on your mobile device or visit '),
                              TextSpan(
                                  text: 'youtube.com',
                                  style: TextStyle(fontWeight: FontWeight.bold, color: Colors.orange)),
                              TextSpan(text: ' on your computer\n\n'),

                              TextSpan(
                                text: '2. ',
                                style: TextStyle(fontWeight: FontWeight.bold, color: Colors.lightBlue),
                              ),
                              TextSpan(text: 'Create a '),
                              TextSpan(
                                  text: 'YouTube Channel',
                                  style: TextStyle(fontWeight: FontWeight.bold, color: Colors.orange)),
                              TextSpan(
                                  text: '\n   (If you already have one, skip this step)\n\n',
                                  style: TextStyle(color: Colors.grey)),

                              TextSpan(
                                text: '3. ',
                                style: TextStyle(fontWeight: FontWeight.bold, color: Colors.lightBlue),
                              ),
                              TextSpan(text: 'Go to '),
                              TextSpan(
                                  text: 'Settings > Upload defaults > Visibility → Private',
                                  style: TextStyle(fontWeight: FontWeight.bold, color: Colors.orange)),
                              TextSpan(
                                  text: '\n   (Only if you want to keep uploaded videos hidden from public)\n\n',
                                  style: TextStyle(color: Colors.grey)),

                              TextSpan(
                                text: '4. ',
                                style: TextStyle(fontWeight: FontWeight.bold, color: Colors.lightBlue),
                              ),
                              TextSpan(text: 'Click on the '),
                              TextSpan(
                                  text: 'Sign in with Google ',
                                  style: TextStyle(fontWeight: FontWeight.bold, color: Colors.green)),
                              TextSpan(text: 'button below\n\n'),

                              TextSpan(
                                text: '5. ',
                                style: TextStyle(fontWeight: FontWeight.bold, color: Colors.lightBlue),
                              ),
                              TextSpan(text: 'Choose your channel and allow required permissions\n\n'),

                              TextSpan(
                                text: '6. ',
                                style: TextStyle(fontWeight: FontWeight.bold, color: Colors.lightBlue),
                              ),
                              TextSpan(text: 'Select multiple videos to upload\n\n'),

                              TextSpan(
                                text: '7. ',
                                style: TextStyle(fontWeight: FontWeight.bold, color: Colors.lightBlue),
                              ),
                              TextSpan(text: 'Have Fun 🎉'),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      // if (_isBannerAdReady)
                      //   Container(
                      //     alignment: Alignment.center,
                      //     width: _bannerAd.size.width.toDouble(),
                      //     height: _bannerAd.size.height.toDouble(),
                      //     child: AdWidget(ad: _bannerAd),
                      //   ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                child: ElevatedButton(
                  onPressed: _handleSignIn,
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size.fromHeight(50),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  child: const Text(
                    'Sign in with Google',
                    style: TextStyle(color: Colors.white, fontSize: 16),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return MultiVideoPickerUploadPage(accessToken: _accessToken);
  }

  // @override
  // void dispose() {
  //   _bannerAd.dispose();
  //   super.dispose();
  // }
}
