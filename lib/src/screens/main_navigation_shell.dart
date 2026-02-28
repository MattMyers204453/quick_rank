import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/auth_service.dart';
import '../services/match_service.dart';
import 'opponent_search_screen.dart';
import 'rankings_screen.dart';
import 'profile_screen.dart';

class MainNavigationShell extends StatefulWidget {
  const MainNavigationShell({super.key});

  @override
  State<MainNavigationShell> createState() => _MainNavigationShellState();
}

class _MainNavigationShellState extends State<MainNavigationShell> {
  final AuthService _authService = AuthService();
  final MatchService _matchService = MatchService();
  int _selectedIndex = 0;

  final _rankingsKey = GlobalKey<RankingsScreenState>();
  final _profileKey = GlobalKey<ProfileScreenState>();

  late final List<Widget> _screens = [
    const OpponentSearchScreen(),
    RankingsScreen(key: _rankingsKey),
    ProfileScreen(key: _profileKey),
  ];

  void _onItemTapped(int index) {
    setState(() => _selectedIndex = index);

    // Reload data when switching to Rankings or Profile tabs
    if (index == 1) _rankingsKey.currentState?.reload();
    if (index == 2) _profileKey.currentState?.reload();
  }

  Future<void> _handleLogout() async {
    _matchService.disconnect();
    await _authService.logout();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('SmashRank',
            style: GoogleFonts.spaceMono(
                fontWeight: FontWeight.bold, fontSize: 24)),
        backgroundColor: const Color(0xFFBD0910),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Row(
              children: [
                Text(_authService.username ?? '',
                    style:
                        const TextStyle(fontSize: 14, color: Colors.white70)),
                IconButton(
                  icon: const Icon(Icons.logout, size: 20),
                  tooltip: 'Sign Out',
                  onPressed: _handleLogout,
                ),
              ],
            ),
          ),
        ],
      ),
      body: IndexedStack(
        index: _selectedIndex,
        children: _screens,
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: _onItemTapped,
        selectedItemColor: const Color(0xFFBD0910),
        unselectedItemColor: Colors.grey,
        items: const [
          BottomNavigationBarItem(
              icon: Icon(Icons.search), label: 'Find Match'),
          BottomNavigationBarItem(
              icon: Icon(Icons.leaderboard), label: 'Rankings'),
          BottomNavigationBarItem(icon: Icon(Icons.person), label: 'Profile'),
        ],
      ),
    );
  }
}
