import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'dart:io' show Platform;

import 'SplashScreen.dart';
import 'services/account_manager.dart';
import 'services/upload_scheduler.dart';
import 'services/background_service.dart';
import 'pages/upload_queue_page.dart';
import 'pages/youtube_browser_page.dart';
import 'pages/stats_page.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeBackgroundService();
  runApp(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        scaffoldBackgroundColor: Colors.black,
        appBarTheme: AppBarTheme(backgroundColor: Colors.grey[900], elevation: 0, foregroundColor: Colors.white, centerTitle: false),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
        ),
      ),
      home: SplashScreen(nextScreen: MainShell()),
    ),
  );
}

String get clientIdd {
  if (kIsWeb) {
    return '419479685978-a2i54r2v2bjvkvm5mpd1i4ks5r3f68tt.apps.googleusercontent.com';
  } else if (Platform.isAndroid) {
    return '419479685978-o1lqlg3fq8lcn5leht17t50cp9l3ltj8.apps.googleusercontent.com';
  } else if (Platform.isIOS) {
    return '419479685978-k31nq590lglod4c2sm3tsounmc5ovu5d.apps.googleusercontent.com';
  } else {
    throw UnsupportedError('Unsupported platform');
  }
}

final GoogleSignIn googleSignIn = GoogleSignIn(
  clientId: clientIdd,
  scopes: [
    'email',
    'https://www.googleapis.com/auth/youtube.upload',
    'https://www.googleapis.com/auth/youtube.readonly',
    'https://www.googleapis.com/auth/userinfo.email',
    'https://www.googleapis.com/auth/userinfo.profile',
  ],
);

class MainShell extends StatefulWidget {
  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  late final AccountManager _accountManager;
  late final UploadScheduler _scheduler;
  bool _initialized = false;
  int _currentTab = 0;

  @override
  void initState() {
    super.initState();
    _accountManager = AccountManager(googleSignIn: googleSignIn);
    _scheduler = UploadScheduler();
    _init();
  }

  Future<void> _init() async {
    await _scheduler.init();
    await _accountManager.init();
    _accountManager.addListener(_onAccountChanged);
    _scheduler.addListener(_onSchedulerChanged);
    if (mounted) setState(() => _initialized = true);
  }

  void _onAccountChanged() {
    if (mounted) setState(() {});
  }

  void _onSchedulerChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _accountManager.removeListener(_onAccountChanged);
    _scheduler.removeListener(_onSchedulerChanged);
    _scheduler.dispose();
    super.dispose();
  }

  Set<String> _buildLocalTitles() {
    final titles = <String>{};
    for (final job in _scheduler.jobs) {
      titles.add(job.title.trim());
    }
    return titles;
  }

  @override
  Widget build(BuildContext context) {
    if (!_initialized) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator(color: Colors.green)),
      );
    }

    if (!_accountManager.isSignedIn) {
      return _buildSignInScreen();
    }

    return _buildMainApp();
  }

  Widget _buildSignInScreen() {
    return Scaffold(
      appBar: AppBar(
        title: const Text('YouTube Multi Uploader', style: TextStyle(color: Colors.white)),
        backgroundColor: Colors.black,
      ),
      backgroundColor: Colors.black,
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
                      'Backup your iPhone videos to YouTube',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Upload queue • Scheduling • Multi-channel • 15/day limit',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey[400], fontSize: 13),
                    ),
                    const SizedBox(height: 24),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.grey[900],
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _step('1', 'Tap Sign in with Google below'),
                          _step('2', 'Choose your YouTube channel'),
                          _step('3', 'Select videos from your gallery'),
                          _step('4', 'They auto-upload with 15/day scheduling'),
                          _step('5', 'Free up iPhone space safely'),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: ElevatedButton(
                onPressed: _accountManager.loading ? null : () => _accountManager.signIn(),
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size.fromHeight(50),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                child: _accountManager.loading
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Sign in with Google', style: TextStyle(color: Colors.white, fontSize: 16)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _step(String num, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Container(
            width: 24, height: 24,
            decoration: BoxDecoration(color: Colors.green, borderRadius: BorderRadius.circular(12)),
            child: Center(child: Text(num, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold))),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(text, style: TextStyle(color: Colors.grey[300], fontSize: 14))),
        ],
      ),
    );
  }

  Widget _buildMainApp() {
    final pages = <Widget>[
      UploadQueuePage(
        scheduler: _scheduler,
        accountManager: _accountManager,
        accessToken: _accountManager.accessToken,
      ),
      YoutubeBrowserPage(
        accountManager: _accountManager,
        localVideoTitles: _buildLocalTitles(),
      ),
      StatsPage(
        scheduler: _scheduler,
        accountManager: _accountManager,
        onSignOut: () async {
          await _accountManager.signOut();
          if (!mounted) return;
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => MainShell()),
            (_) => false,
          );
        },
      ),
    ];

    return Scaffold(
      drawer: _buildDrawer(),
      body: IndexedStack(index: _currentTab, children: pages),
      bottomNavigationBar: Theme(
        data: Theme.of(context).copyWith(canvasColor: Colors.grey[900]),
        child: BottomNavigationBar(
          currentIndex: _currentTab,
          onTap: (i) => setState(() => _currentTab = i),
          selectedItemColor: Colors.green,
          unselectedItemColor: Colors.grey[600],
          items: const [
            BottomNavigationBarItem(icon: Icon(Icons.cloud_upload_outlined), activeIcon: Icon(Icons.cloud_upload), label: 'Upload'),
            BottomNavigationBarItem(icon: Icon(Icons.video_library_outlined), activeIcon: Icon(Icons.video_library), label: 'Browse'),
            BottomNavigationBarItem(icon: Icon(Icons.person_outline), activeIcon: Icon(Icons.person), label: 'Account'),
          ],
        ),
      ),
    );
  }

  Widget _buildDrawer() {
    final acct = _accountManager.currentAccount;
    final ch = _accountManager.selectedChannel;
    return Drawer(
      child: Column(
        children: [
          UserAccountsDrawerHeader(
            decoration: const BoxDecoration(color: Colors.black87),
            accountName: Text(
              acct?.displayName ?? 'User',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            accountEmail: Text(acct?.email ?? ''),
            currentAccountPicture: CircleAvatar(
              backgroundImage: acct?.photoUrl != null ? NetworkImage(acct!.photoUrl!) : null,
              child: acct?.photoUrl == null ? const Icon(Icons.person, size: 40) : null,
            ),
          ),

          // Today's count
          ListTile(
            leading: const Icon(Icons.today),
            title: const Text("Today's Uploads"),
            trailing: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(color: Colors.green, borderRadius: BorderRadius.circular(12)),
              child: Text(
                '${_scheduler.todayUploadedCount}',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
            ),
          ),

          // Total uploads
          ListTile(
            leading: const Icon(Icons.cloud_upload),
            title: const Text('Total Uploads'),
            trailing: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(color: Colors.blueGrey, borderRadius: BorderRadius.circular(12)),
              child: Text(
                '${_scheduler.completedCount}',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
            ),
          ),

          // Channel selector
          if (_accountManager.channels.length > 1) ...[
            const Divider(color: Colors.grey, height: 1),
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Text('Upload Channel', style: TextStyle(color: Colors.grey, fontSize: 12)),
            ),
            ..._accountManager.channels.map((c) => RadioListTile<ChannelInfo>(
              dense: true,
              title: Text(c.title, style: const TextStyle(color: Colors.white, fontSize: 13)),
              value: c,
              groupValue: ch,
              activeColor: Colors.green,
              onChanged: (v) {
                if (v != null) {
                  _accountManager.selectChannel(v);
                  Navigator.pop(context);
                }
              },
            )),
          ],

          const Spacer(),

          // Logout
          ListTile(
            leading: const Icon(Icons.logout),
            title: const Text('Logout'),
            onTap: () async {
              await _accountManager.signOut();
              if (!context.mounted) return;
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(builder: (_) => MainShell()),
                (_) => false,
              );
            },
          ),

          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('Version 0.0.1', style: TextStyle(color: Colors.grey, fontSize: 12)),
          ),
        ],
      ),
    );
  }
}
