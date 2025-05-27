import 'dart:io' as io;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;
import 'package:file_picker/file_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'SplashScreen.dart';

const String kAccessTokenKey = 'access_token';

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
      : null,
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
  bool _loading = true; // loading state while checking prefs

  List<PlatformFile> _selectedFiles = [];
  Map<String, String> _uploadStatus = {}; // filename -> status

  @override
  void initState() {
    super.initState();

    _initLoginState();

    _googleSignIn.onCurrentUserChanged.listen((account) async {
      setState(() => _currentUser = account);
      if (account != null) {
        await _getAccessToken(account);
      } else {
        await _clearAccessToken();
      }
    });
  }

  Future<void> _initLoginState() async {
    // Try silent sign-in
    final account = await _googleSignIn.signInSilently();
    if (account != null) {
      setState(() {
        _currentUser = account;
      });
      await _getAccessToken(account);
    } else {
      // If silent sign-in fails, check stored token
      final prefs = await SharedPreferences.getInstance();
      final storedToken = prefs.getString(kAccessTokenKey);
      if (storedToken != null && storedToken.isNotEmpty) {
        setState(() {
          _accessToken = storedToken;
        });
      }
    }
    setState(() {
      _loading = false;
    });
  }

  Future<void> _getAccessToken(GoogleSignInAccount account) async {
    try {
      final auth = await account.authentication;
      setState(() {
        _accessToken = auth.accessToken;
      });
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(kAccessTokenKey, auth.accessToken ?? '');
    } catch (e) {
      print('Failed to get access token: $e');
    }
  }

  Future<void> _clearAccessToken() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(kAccessTokenKey);
    setState(() {
      _accessToken = null;
    });
  }

  Future<void> _handleSignIn() async {
    try {
      await _googleSignIn.signIn();
    } catch (error) {
      print('Sign in failed: $error');
    }
  }

  Future<void> _pickAndUploadVideos() async {
    if (_accessToken == null) {
      await _handleSignIn();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Please sign in first')),
      );
      return;
    }

    // Refresh token before upload
    if (_currentUser != null) {
      await _getAccessToken(_currentUser!);
    }

    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      withData: kIsWeb,
    );
    if (result == null) return;

    setState(() {
      _selectedFiles = result.files;
      _uploadStatus = {
        for (var file in _selectedFiles) file.name: 'Pending',
      };
    });

    for (final file in _selectedFiles) {
      setState(() {
        _uploadStatus[file.name] = 'Uploading...';
      });

      final uri = Uri.parse('http://localhost:3000/upload');
      final request = http.MultipartRequest('POST', uri);
      request.headers['Authorization'] = 'Bearer $_accessToken';
      request.fields['title'] = file.name;

      try {
        if (kIsWeb) {
          if (file.bytes == null) continue;
          request.files.add(http.MultipartFile.fromBytes(
            'video',
            file.bytes!,
            filename: file.name,
          ));
        } else {
          if (file.path == null) continue;
          request.files.add(await http.MultipartFile.fromPath('video', file.path!));
        }

        final streamedResponse = await request.send();
        final response = await http.Response.fromStream(streamedResponse);

        if (response.statusCode == 200) {
          setState(() {
            _uploadStatus[file.name] = 'Success';
          });
        } else {
          setState(() {
            _uploadStatus[file.name] = 'Failed (${response.statusCode})';
          });
        }
      } catch (e) {
        setState(() {
          _uploadStatus[file.name] = 'Failed (Exception)';
        });
        print('Upload failed for ${file.name}: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return MaterialApp(
        home: Scaffold(
          backgroundColor: Colors.black,
          body: Center(
            child: CircularProgressIndicator(color: Colors.green),
          ),
        ),
      );
    }

    return MaterialApp(
      title: 'Youtube Multi',
      home: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Color(0xFF34495E), // a nice dark muted blue-grey
          title: Text('Youtube Multi'),
        ),
        drawer: Drawer(
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              DrawerHeader(
                decoration: BoxDecoration(color: Color(0xFF34495E)),
                child: Text(
                  _currentUser != null
                      ? 'Signed in as\n${_currentUser!.email}'
                      : 'Not Signed In',
                  style: TextStyle(color: Colors.white, fontSize: 18),
                ),
              ),
              ListTile(
                title: Text('Home'),
                onTap: () {
                  Navigator.pop(context);
                },
              ),
              ListTile(
                title: Text('Sign Out'),
                onTap: () async {
                  await _googleSignIn.signOut();
                  await _clearAccessToken();
                  setState(() {
                    _currentUser = null;
                    _selectedFiles.clear();
                    _uploadStatus.clear();
                  });
                  Navigator.pop(context);
                },
              ),
            ],
          ),
        ),
        body: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: _currentUser == null && (_accessToken == null || _accessToken!.isEmpty)
              ? Column(
                  mainAxisAlignment: MainAxisAlignment.start,
                  children: [
                    SizedBox(height: 24),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        minimumSize: Size(double.infinity, 50),
                        backgroundColor: Colors.green,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(4), // minimal rounding
                        ),
                      ),
                      onPressed: _handleSignIn,
                      child: Text(
                        'Sign in with Google',
                        style: TextStyle(color: Colors.white, fontSize: 16),
                      ),
                    ),
                    SizedBox(height: 8),
                    Text(
                      'Please sign in with Google to upload videos',
                      style: TextStyle(color: Colors.white70),
                    ),
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ElevatedButton(
                      onPressed: _pickAndUploadVideos,
                      style: ElevatedButton.styleFrom(
                        minimumSize: Size(double.infinity, 50),
                        backgroundColor: Colors.green,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(4), // minimal rounding
                        ),
                      ),
                      child: Text('Pick & Upload Videos'),
                    ),
                    SizedBox(height: 12),
                    if (_selectedFiles.isNotEmpty)
                      Expanded(
                        child: SingleChildScrollView(
                          child: Table(
                            border: TableBorder.all(color: Colors.white54),
                            columnWidths: const {
                              0: FixedColumnWidth(40), // Serial no
                              1: FlexColumnWidth(3),
                              2: FlexColumnWidth(2),
                            },
                            children: [
                              TableRow(
                                decoration: BoxDecoration(color: Colors.grey[800]),
                                children: [
                                  Padding(
                                    padding: const EdgeInsets.all(8.0),
                                    child: Text(
                                      '#',
                                      style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          color: Colors.white),
                                      textAlign: TextAlign.center,
                                    ),
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.all(8.0),
                                    child: Text(
                                      'Filename',
                                      style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          color: Colors.white),
                                    ),
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.all(8.0),
                                    child: Text(
                                      'Status',
                                      style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          color: Colors.white),
                                    ),
                                  ),
                                ],
                              ),
                              ..._selectedFiles.asMap().entries.map((entry) {
                                final idx = entry.key + 1;
                                final file = entry.value;
                                final status = _uploadStatus[file.name] ?? 'Pending';
                                return TableRow(
                                  children: [
                                    Padding(
                                      padding: const EdgeInsets.all(8.0),
                                      child: Text(
                                        '$idx',
                                        style: TextStyle(color: Colors.white),
                                        textAlign: TextAlign.center,
                                      ),
                                    ),
                                    Padding(
                                      padding: const EdgeInsets.all(8.0),
                                      child: Text(
                                        file.name,
                                        style: TextStyle(color: Colors.white),
                                      ),
                                    ),
                                    Padding(
                                      padding: const EdgeInsets.all(8.0),
                                      child: Text(
                                        status,
                                        style: TextStyle(
                                          color: status.startsWith('Success')
                                              ? Colors.greenAccent
                                              : status.startsWith('Failed')
                                                  ? Colors.redAccent
                                                  : Colors.white,
                                        ),
                                      ),
                                    ),
                                  ],
                                );
                              }),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
        ),
      ),
    );
  }
}
